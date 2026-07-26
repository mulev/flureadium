package dev.mulev.flureadium

/*
 * Modified version of kotlin-toolkit's example app MediaService.
 * See https://github.com/search?q=repo%3Areadium%2Fkotlin-toolkit%20mediaServiceFacade&type=code
 * and https://github.com/readium/kotlin-toolkit/blob/develop/docs/guides/navigator/media-navigator.md
 */

/*
 * Copyright 2022 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.sample
import org.readium.navigator.media.common.Media3Adapter
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication
import dev.mulev.flureadium.car.FlureadiumCarEngine

@OptIn(ExperimentalReadiumApi::class)
typealias AnyMediaNavigator = MediaNavigator<*, *, *>

private const val TAG = "Flutter_Readium.MediaService"

private const val STARTUP_NOTIFICATION_CHANNEL_NAME = "Media playback"
private const val STARTUP_NOTIFICATION_TITLE = "Flureadium playback"
private const val STARTUP_NOTIFICATION_TEXT = "Preparing playback"

/**
 * The lifecycle action to take when opening a media session for [an incoming
 * navigator] while [a navigator] already owns the live session (or none does).
 */
internal enum class SessionAction {
    /** No live session — build a new one. */
    FRESH,

    /** The live session already belongs to this navigator — keep it. */
    REUSE,

    /** A different navigator owns the live session — release it, then build. */
    REPLACE,
}

/**
 * Decides how [PluginMediaService.Binder.openSession] should treat a request for
 * [incoming] given the [current] navigator of the live session (`null` when none
 * is open). Reusing the same navigator's session is what keeps `play(locator)`
 * from rebuilding a duplicate session on a chapter jump.
 */
@OptIn(ExperimentalReadiumApi::class)
internal fun sessionActionFor(
    current: AnyMediaNavigator?,
    incoming: AnyMediaNavigator,
): SessionAction = when {
    current == null -> SessionAction.FRESH
    current === incoming -> SessionAction.REUSE
    else -> SessionAction.REPLACE
}

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
@androidx.annotation.OptIn(UnstableApi::class)
class PluginMediaService : MediaLibraryService() {

    class Session(
        val navigator: AnyMediaNavigator,
        val mediaSession: MediaLibrarySession,
        val publication: Publication?,
    ) {
        val coroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    }

    private val libraryCallback by lazy {
        PluginLibrarySessionCallback(
            sourceProvider = { FlureadiumCarEngine.source },
            publicationProvider = { binder.session.value?.publication },
        )
    }

    /**
     * The service interface to be used by the app.
     */
    inner class Binder : android.os.Binder() {

        private val sessionMutable: MutableStateFlow<Session?> =
            MutableStateFlow(null)

        val session: StateFlow<Session?> =
            sessionMutable.asStateFlow()

        fun closeSession() {
            Log.d(TAG, "closeSession")
            session.value?.let { session ->
                session.mediaSession.release()
                session.coroutineScope.cancel()
                session.navigator.close()
                sessionMutable.value = null
            }
        }

        @OptIn(FlowPreview::class)
        fun <N> openSession(
            navigator: N,
            publication: Publication? = null,
        ) where N : AnyMediaNavigator, N : Media3Adapter {
            Log.d(TAG, "openSession")

            when (sessionActionFor(sessionMutable.value?.navigator, navigator)) {
                SessionAction.REUSE -> {
                    Log.d(TAG, "openSession: reusing live session for the same navigator")
                    return
                }
                SessionAction.REPLACE -> closeSession()
                SessionAction.FRESH -> {}
            }

            val activityIntent = createSessionActivityIntent()
            val player = navigator.asMedia3Player()
            // Create our SimpleBasePlayer override to override some media-button mapping.
            val pluginForwardingPlayer = PluginSimpleBasePlayer(player, ReadiumReader.audioPreferences)

            val mediaSession = MediaLibrarySession.Builder(
                this@PluginMediaService,
                pluginForwardingPlayer,
                libraryCallback
            )
                .setSessionActivity(activityIntent)
                .setCustomLayout(libraryCallback.commandButtons)
                .build()

            addSession(mediaSession)

            val session = Session(
                navigator,
                mediaSession,
                publication
            )

            sessionMutable.value = session

            /*
             * Launch a job for saving progression even when playback is going on in the background
             * with no ReaderActivity opened.
             */
            navigator.currentLocator
                .sample(5000)
                .onEach { locator ->
                    Log.d(TAG, "Progression update: $locator")
                    // TODO: Submit on the plugin audio-locator stream?
                    //app.bookRepository.saveProgression(locator, bookId)
                }.launchIn(session.coroutineScope)
        }

        private fun createSessionActivityIntent(): PendingIntent {
            // This intent will be triggered when the notification is clicked.
            var flags = PendingIntent.FLAG_UPDATE_CURRENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                flags = flags or PendingIntent.FLAG_IMMUTABLE
            }

            val intent = application.packageManager.getLaunchIntentForPackage(
                application.packageName
            )

            return PendingIntent.getActivity(applicationContext, 0, intent, flags)
        }

        fun stop() {
            closeSession()
            ServiceCompat.stopForeground(
                this@PluginMediaService,
                ServiceCompat.STOP_FOREGROUND_REMOVE
            )
            this@PluginMediaService.stopSelf()
        }
    }

    private val binder by lazy {
        Binder()
    }

    override fun onBind(intent: Intent?): IBinder? {
        Log.d(TAG, "onBind called with $intent")

        return if (intent?.action == SERVICE_INTERFACE) {
            super.onBind(intent)
            // Readium-aware client.
            Log.d(TAG, "Returning custom binder.")
            binder
        } else {
            // External controller.
            Log.d(TAG, "Returning MediaSessionService binder.")
            super.onBind(intent)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        enterForegroundForStartup()
        super.onStartCommand(intent, flags, startId)

        // TODO: Handle restoration properly when activated from a stale notification.
        // App and service can be started again from a stale notification using
        // PendingIntent.getForegroundService, so we need to call startForeground and then stop
        // the service.

        // Prevents the service from being automatically restarted after being killed;
        return START_NOT_STICKY
    }

    private fun enterForegroundForStartup() {
        ensureStartupNotificationChannel()

        val notification = NotificationCompat.Builder(
            this,
            DefaultMediaNotificationProvider.DEFAULT_CHANNEL_ID
        )
            .setSmallIcon(androidx.media3.session.R.drawable.media3_icon_play)
            .setContentTitle(STARTUP_NOTIFICATION_TITLE)
            .setContentText(STARTUP_NOTIFICATION_TEXT)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setSilent(true)
            .build()

        ServiceCompat.startForeground(
            this,
            DefaultMediaNotificationProvider.DEFAULT_NOTIFICATION_ID,
            notification,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
        )
    }

    private fun ensureStartupNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val notificationManager = getSystemService(NotificationManager::class.java)
        val channel = NotificationChannel(
            DefaultMediaNotificationProvider.DEFAULT_CHANNEL_ID,
            STARTUP_NOTIFICATION_CHANNEL_NAME,
            NotificationManager.IMPORTANCE_LOW
        )
        notificationManager.createNotificationChannel(channel)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? {
        return binder.session.value?.mediaSession
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        Log.d(TAG, "Task removed. Stopping session and service.")
        // Close the session to allow the service to be stopped.
        binder.closeSession()
        binder.stop()
    }

    override fun onDestroy() {
        Log.d(TAG, "Destroying MediaService.")
        binder.closeSession()
        // Ensure one more time that all notifications are gone and,
        // hopefully, pending intents cancelled.
        NotificationManagerCompat.from(this).cancelAll()
        super.onDestroy()
    }

    companion object {

        const val SERVICE_INTERFACE = "dev.mulev.flureadium.MediaService"

        fun start(application: Application) {
            val intent = intent(application)
            ContextCompat.startForegroundService(application, intent)
        }

        fun stop(application: Application) {
            val intent = intent(application)
            application.stopService(intent)
        }

        suspend fun bind(application: Application): Binder {
            val mediaServiceBinder: CompletableDeferred<Binder> =
                CompletableDeferred()

            val mediaServiceConnection = object : ServiceConnection {

                override fun onServiceConnected(name: ComponentName?, service: IBinder) {
                    Log.d(TAG, "MediaService bound.")
                    mediaServiceBinder.complete(service as Binder)
                }

                override fun onServiceDisconnected(name: ComponentName) {
                    Log.d(TAG, "MediaService disconnected.")
                }

                override fun onNullBinding(name: ComponentName) {
                    if (mediaServiceBinder.isCompleted) {
                        // This happens when the service has successfully connected and later
                        // stopped and disconnected.
                        return
                    }
                    val errorMessage = "Failed to bind to MediaService."
                    Log.e(TAG, errorMessage)
                    val exception = IllegalStateException(errorMessage)
                    mediaServiceBinder.completeExceptionally(exception)
                }
            }

            val intent = intent(application)
            application.bindService(intent, mediaServiceConnection, 0)

            return mediaServiceBinder.await()
        }

        private fun intent(application: Application) =
            Intent(SERVICE_INTERFACE)
                // MediaSessionService.onBind requires the intent to have a non-null action
                .apply { setClass(application, PluginMediaService::class.java) }
    }
}
