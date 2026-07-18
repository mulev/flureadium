package dev.mulev.flureadium

import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import org.readium.r2.shared.publication.Publication

private const val CUSTOM_COMMAND_REWIND_ACTION_ID = "REWIND_CUSTOM"
private const val CUSTOM_COMMAND_FORWARD_ACTION_ID = "FORWARD_CUSTOM"

@UnstableApi
enum class NotificationPlayerCustomCommandButton(
    val customAction: String,
    val commandButton: CommandButton,
) {
    REWIND(
        customAction = CUSTOM_COMMAND_REWIND_ACTION_ID,
        commandButton = CommandButton.Builder(CommandButton.ICON_SKIP_BACK)
            .setDisplayName("Rewind")
            .setSlots(CommandButton.SLOT_BACK)
            .setSessionCommand(SessionCommand(CUSTOM_COMMAND_REWIND_ACTION_ID, Bundle()))
            .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_skip_back)
            .build(),
    ),
    FORWARD(
        customAction = CUSTOM_COMMAND_FORWARD_ACTION_ID,
        commandButton = CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD)
            .setDisplayName("Forward")
            .setSlots(CommandButton.SLOT_FORWARD)
            .setSessionCommand(SessionCommand(CUSTOM_COMMAND_FORWARD_ACTION_ID, Bundle()))
            .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_skip_forward)
            .build(),
    );
}

/**
 * The [MediaLibrarySession.Callback] for [PluginMediaService]: it registers the
 * notification's rewind/forward buttons, routes their custom commands to the
 * reader, and serves the Android Auto browse tree.
 *
 * The browse tree is built lazily from [publicationProvider] so the callback
 * stays decoupled from the service's session state.
 */
@UnstableApi
class PluginLibrarySessionCallback(
    private val publicationProvider: () -> Publication?,
) : MediaLibrarySession.Callback {

    val commandButtons: List<CommandButton> =
        NotificationPlayerCustomCommandButton.entries.map { it.commandButton }

    override fun onConnect(
        session: MediaSession,
        controller: MediaSession.ControllerInfo
    ): MediaSession.ConnectionResult {
        val connectionResult = super.onConnect(session, controller)
        val availableSessionCommands = connectionResult.availableSessionCommands.buildUpon()

        /* Registering custom player command buttons for player notification. */
        commandButtons.forEach { commandButton ->
            commandButton.sessionCommand?.let(availableSessionCommands::add)
        }

        return MediaSession.ConnectionResult.accept(
            availableSessionCommands.build(),
            connectionResult.availablePlayerCommands,
        )
    }

    override fun onPostConnect(session: MediaSession, controller: MediaSession.ControllerInfo) {
        super.onPostConnect(session, controller)
        if (commandButtons.isNotEmpty()) {
            /* Setting custom player command buttons to mediaLibrarySession for player notification. */
            /* Set media-button preferences, so that skip buttons are replaces with seek */
            session.setCustomLayout(commandButtons)
            session.setMediaButtonPreferences(commandButtons)
        }
    }

    override fun onCustomCommand(
        session: MediaSession,
        controller: MediaSession.ControllerInfo,
        customCommand: SessionCommand,
        args: Bundle
    ): ListenableFuture<SessionResult> {
        /* Handle custom command buttons from player notification. */
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.REWIND.customAction) {
            CoroutineScope(Dispatchers.Main).async {
                ReadiumReader.previous()
            }
        }
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.FORWARD.customAction) {
            CoroutineScope(Dispatchers.Main).async {
                ReadiumReader.next()
            }
        }
        return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
    }

    /* --- Android Auto browse tree --- */

    /**
     * The browse tree for the currently open audiobook, or null when nothing
     * browsable is playing (e.g. a TTS session, or no session at all).
     */
    private fun browseTree(): AudiobookBrowseTree? =
        publicationProvider()?.let { AudiobookBrowseTree(it) }

    override fun onGetLibraryRoot(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        params: LibraryParams?
    ): ListenableFuture<LibraryResult<MediaItem>> {
        val root = browseTree()?.rootItem() ?: emptyLibraryRoot
        return Futures.immediateFuture(LibraryResult.ofItem(root, params))
    }

    override fun onGetChildren(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        parentId: String,
        page: Int,
        pageSize: Int,
        params: LibraryParams?
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        val children = if (parentId == AudiobookBrowseTree.ROOT_ID) {
            browseTree()?.children().orEmpty()
        } else {
            emptyList()
        }
        return Futures.immediateFuture(
            LibraryResult.ofItemList(ImmutableList.copyOf(children), params)
        )
    }

    override fun onGetItem(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        mediaId: String
    ): ListenableFuture<LibraryResult<MediaItem>> {
        val item = browseTree()?.mediaItemForId(mediaId)
            ?: return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE))
        return Futures.immediateFuture(LibraryResult.ofItem(item, null))
    }

    /**
     * A head unit plays a chapter by "setting" its browse item. The audiobook is
     * already loaded as a single timeline, so instead of replacing the playlist
     * we keep the current items and seek to the picked chapter's index.
     */
    override fun onSetMediaItems(
        mediaSession: MediaSession,
        controller: MediaSession.ControllerInfo,
        mediaItems: MutableList<MediaItem>,
        startIndex: Int,
        startPositionMs: Long
    ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
        val tree = browseTree()
        val chapterIndex = tree?.let {
            mediaItems.firstNotNullOfOrNull { item -> it.chapterIndexForId(item.mediaId) }
        }
        if (chapterIndex == null) {
            return super.onSetMediaItems(
                mediaSession, controller, mediaItems, startIndex, startPositionMs
            )
        }
        val player = mediaSession.player
        val currentItems = (0 until player.mediaItemCount).map { player.getMediaItemAt(it) }
        return Futures.immediateFuture(
            MediaSession.MediaItemsWithStartPosition(currentItems, chapterIndex, 0L)
        )
    }

    /** Fallback browsable root shown when no audiobook is open. */
    private val emptyLibraryRoot: MediaItem by lazy {
        MediaItem.Builder()
            .setMediaId(AudiobookBrowseTree.ROOT_ID)
            .setMediaMetadata(
                MediaMetadata.Builder()
                    .setIsBrowsable(true)
                    .setIsPlayable(false)
                    .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_AUDIO_BOOKS)
                    .build()
            )
            .build()
    }
}
