package dev.mulev.flureadium.navigators

import android.os.Bundle
import android.util.Log
import dev.mulev.flureadium.ControlPanelInfoType
import dev.mulev.flureadium.FlutterAudioPreferences
import dev.mulev.flureadium.PluginMediaServiceFacade
import dev.mulev.flureadium.PublicationError
import dev.mulev.flureadium.ReadiumReader
import dev.mulev.flureadium.throttleLatest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONObject
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.adapter.exoplayer.audio.ExoPlayerNavigatorFactory
import org.readium.adapter.exoplayer.audio.ExoPlayerPreferences
import org.readium.adapter.exoplayer.audio.ExoPlayerSettings
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.getOrElse
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

private const val TAG = "AudioNavigator"

const val currentTimebaseLocatorKey = "currentTimebaseLocator"

const val audioPreferencesKey = "audioPreferencesKey"

/**
 * Navigator for pure Audiobook publications using Readium's AudioNavigator.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
open class AudiobookNavigator(
    publication: Publication,
    timebasedListener: TimebasedListener,
    initialLocator: Locator?,
    private var preferences: FlutterAudioPreferences
) : TimebasedNavigator<AudioNavigator.Playback>(publication, timebasedListener, initialLocator) {
    /**
     * The AudioNavigator provided by Readium..
     */
    protected var audioNavigator: AudioNavigator<ExoPlayerSettings, ExoPlayerPreferences>? = null

    /**
     * The MediaServiceFacade to manage MediaSession interactions, notifications, etc.
     */
    protected var mediaServiceFacade: PluginMediaServiceFacade? = null

    override suspend fun initNavigator() {
        // Create AudioNavigatorFactory
        val navigatorFactory = ExoPlayerNavigatorFactory(
            publication,
            ExoPlayerEngineProvider(ReadiumReader.application, metadataProvider = { pub ->
                DatabaseMediaMetadataFactory(
                    publication = publication,
                    trackCount = pub.readingOrder.size,
                    controlPanelInfoType = preferences.controlPanelInfoType ?: ControlPanelInfoType.STANDARD
                )})
        )

        if (navigatorFactory == null) {
            // TODO: Better Error handling, if the book isn't an audiobook the factory is null.
            Log.e(TAG, ":initNavigator - Couldn't create AudioNavigatorFactory")
            throw Exception("Couldn't create AudioNavigatorFactory")
        }

        // Readium's createNavigator falls back to MediaMetadataRetriever for every
        // reading-order item without a duration, and that fallback blocks the calling
        // thread (runBlocking inside a MediaDataSource callback). For a streamed
        // audiobook that is one socket read per track. Resolve here, on IO, so the
        // main-thread hop below never probes anything.
        val resolvedReadingOrder = withContext(Dispatchers.IO) {
            resolveTrackDurations(publication, publication.readingOrder)
        }

        mainScope.async {
            audioNavigator = navigatorFactory.createNavigator(
                this@AudiobookNavigator.initialLocator,
                preferences.toExoPlayerPreferences(),
                resolvedReadingOrder,
            ).getOrElse { error ->
                Log.e(TAG, ":initNavigator - $error")
                throw Exception(PublicationError.invoke(error).message)
            }

            mediaServiceFacade = PluginMediaServiceFacade(ReadiumReader.application).apply {
                session
                    .flatMapLatest { it?.navigator?.playback ?: MutableStateFlow(null) }
                    .onEach { playback ->
                        when (val state = (playback?.state as? AudioNavigator.State)) {
                            null, AudioNavigator.State.Ready, AudioNavigator.State.Buffering -> {
                                // Do nothing
                            }

                            is AudioNavigator.State.Ended -> {
                                onAudioNavigatorEnded()
                            }

                            is AudioNavigator.State.Failure<*> -> {
                                Log.e(TAG, "AudioNavigator failure: ${state.error}")
                                //onPlaybackError(state.error)
                            }
                        }
                    }.launchIn(mainScope)
            }

            setupNavigatorListeners()
        }.await()
    }

    /**
     * Handles natural end-of-book. Forwards [TimebasedState.Ended] to the
     * listener BEFORE teardown, so the un-throttled closeSession()/
     * navigator.close() can't push a post-Ended state that the stacked
     * throttleLatest windows coalesce over Ended. Cancels forwarding jobs so
     * no late tick races the listener after Ended is delivered.
     */
    protected open fun onAudioNavigatorEnded() {
        timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Ended)
        jobs.forEach { it.cancel() }
        jobs.clear()
        mediaServiceFacade?.closeSession()
    }

    override suspend fun play(fromLocator: Locator?) {
        mainScope.async {
            if (fromLocator != null) {
                audioNavigator?.go(fromLocator)
            }

            try {
                Log.d(TAG, "Opening MediaSession")
                mediaServiceFacade?.openSession(audioNavigator!!, publication)
            } catch (e: Exception) {
                Log.e(TAG, "Error opening MediaSession: ${e.message}")
                mediaServiceFacade?.closeSession()
                audioNavigator?.close()
                return@async
            }

            audioNavigator?.play()
        }.await()
    }

    override suspend fun pause() {
        mainScope.async {
            audioNavigator?.pause()
        }.await()
    }

    override suspend fun resume() {
        mainScope.async {
            // TODO: Do we need to check if already playing?
            audioNavigator?.play()
        }.await()
    }

    override suspend fun goBack() {
        val nav = audioNavigator ?: return
        mainScope.async {
            goToTrack(nav, previousTrackIndex(trackHrefs(), nav.currentHref()))
        }.await()
    }

    override suspend fun goForward() {
        val nav = audioNavigator ?: return
        mainScope.async {
            goToTrack(nav, nextTrackIndex(trackHrefs(), nav.currentHref()))
        }.await()
    }

    private fun trackHrefs(): List<String> =
        publication.readingOrder.map { it.href.toString() }

    private fun AudioNavigator<*, *>.currentHref(): String =
        currentLocator.value.href.toString()

    private suspend fun goToTrack(nav: AudioNavigator<*, *>, index: Int?) {
        index ?: return
        publication.locatorFromLink(publication.readingOrder[index])?.let { nav.go(it) }
    }

    override suspend fun goToLocator(locator: Locator) {
        val navigator = audioNavigator ?: return
        mainScope.async {
            navigator.go(locator)
        }
    }

    override suspend fun seekTo(offset: Double) {
        mainScope.async {
            audioNavigator?.skip(offset.seconds)
        }.await()
    }

    /**
     * Updates Audio preferences, does not override current preferences if props are null
     */
    fun updatePreferences(prefs: FlutterAudioPreferences) {
        preferences = preferences + prefs

        mainScope.async {
            audioNavigator?.submitPreferences(preferences.toExoPlayerPreferences())
        }
    }

    override fun setupNavigatorListeners() {
        val navigator = audioNavigator
        if (navigator == null) {
            Log.e(TAG, ": setupNavigatorListeners - navigator is null")
            return
        }

        // Listen to state changes
        navigator.playback
            .throttleLatest(100.milliseconds)
            .distinctUntilChangedBy { pb ->
                "${pb.state}|${pb.playWhenReady}"
            }
            .onEach { pb ->
                onPlaybackStateChanged(pb)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Handle buffered changes
        navigator.playback
            .throttleLatest(250.milliseconds)
            .distinctUntilChangedBy { pb -> pb.buffered }
            .onEach { pb ->
                timebaseListener.onTimebasedBufferChanged(pb.buffered)
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        // Handle current locator changes
        navigator.currentLocator
            .throttleLatest(100.milliseconds)
            .distinctUntilChanged()
            .onEach { locator ->
                onCurrentLocatorChanges(locator)
                state[currentTimebaseLocatorKey] = locator
            }
            .launchIn(mainScope)
            .let { jobs.add(it) }

        mainScope.async {
            navigator.settings
                .collect { s ->
                    Log.d(TAG, ": AudioNavigator settings changed: $s")
                }
        }
    }

    override fun onPlaybackStateChanged(pb: AudioNavigator.Playback) {
        when (pb.state) {
            is AudioNavigator.State.Failure<*> -> {
                val audioState = pb.state as AudioNavigator.State.Failure<*>
                val error = audioState.error

                Log.e(
                    TAG,
                    ": onPlaybackStateChanged - audio error: Message=${error.message} cause=${error.cause}"
                )

                timebaseListener.onTimebasedPlaybackStateChanged(TimebasedState.Failure)
                timebaseListener.onTimebasedPlaybackFailure(
                    PublicationError.invoke(error)
                )
            }

            else -> {
                super.onPlaybackStateChanged(pb)
            }
        }
    }

    override fun storeState(): Bundle {
        return Bundle().apply {
            putString(
                currentTimebaseLocatorKey,
                (state[currentTimebaseLocatorKey] as? Locator)?.toJSON()?.toString()
            )

            putString(
                audioPreferencesKey,
                FlutterAudioPreferences.toJSON(preferences).toString()
            )
        }
    }

    override suspend fun release() {
        super.dispose()

        mediaServiceFacade?.closeSession()
        // ExoPlayer enforces thread affinity — release() must run on the
        // main thread. release() can be called from Dispatchers.IO (via
        // PublicationChannel), so we switch explicitly.
        withContext(Dispatchers.Main.immediate) {
            audioNavigator?.close()
        }
        audioNavigator = null
    }

    override fun dispose() {
        super.dispose()

        mainScope.launch {
            mediaServiceFacade?.closeSession()

            audioNavigator?.close()
            audioNavigator = null
        }
    }

    companion object {
        fun restoreState(
            publication: Publication,
            listener: TimebasedListener,
            state: Bundle
        ): AudiobookNavigator {
            val locator = state.getString(currentTimebaseLocatorKey)
                ?.let { json -> Locator.fromJSON(JSONObject(json)) }
            val preferences = state.getString(audioPreferencesKey)
                ?.let { json -> FlutterAudioPreferences.fromJSON(json) }
                ?: FlutterAudioPreferences()

            return AudiobookNavigator(publication, listener, locator, preferences)
        }
    }
}
