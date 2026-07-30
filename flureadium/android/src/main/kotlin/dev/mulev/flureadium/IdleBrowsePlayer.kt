package dev.mulev.flureadium

import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.SimpleBasePlayer
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/**
 * The placeholder media3 [Player] that backs the browse-only session before
 * playback starts, so Android Auto can browse the host library without a real
 * playback engine. When a book starts, [PluginMediaService] swaps in the
 * navigator-backed player; on stop it swaps this one back so the browse surface
 * stays alive.
 *
 * It reports an idle, empty state (no phantom "now playing"). It does advertise
 * the commands a head unit uses to start playback from a browse row
 * (set/change media items, prepare, play), because that path
 * ([PluginLibrarySessionCallback.onSetMediaItems] -> `source.play`) is only
 * reachable when the connected controller is allowed to issue those commands.
 * The placeholder itself does not load anything: real playback is driven by
 * `source.play(mediaId)` and the player swap, so these handlers are no-ops and
 * the placeholder stays idle until it is replaced.
 */
@UnstableApi
class IdleBrowsePlayer(looper: Looper) : SimpleBasePlayer(looper) {

    override fun getState(): State =
        State.Builder()
            .setAvailableCommands(BROWSE_PICK_COMMANDS)
            .setPlaybackState(Player.STATE_IDLE)
            .build()

    override fun handleSetMediaItems(
        mediaItems: List<MediaItem>,
        startIndex: Int,
        startPositionMs: Long,
    ): ListenableFuture<*> = Futures.immediateVoidFuture()

    override fun handlePrepare(): ListenableFuture<*> = Futures.immediateVoidFuture()

    override fun handleSetPlayWhenReady(playWhenReady: Boolean): ListenableFuture<*> =
        Futures.immediateVoidFuture()

    private companion object {
        /** Just enough to let a head unit's row tap reach `onSetMediaItems`. */
        val BROWSE_PICK_COMMANDS: Player.Commands =
            Player.Commands.Builder()
                .addAll(
                    Player.COMMAND_SET_MEDIA_ITEM,
                    Player.COMMAND_CHANGE_MEDIA_ITEMS,
                    Player.COMMAND_PREPARE,
                    Player.COMMAND_PLAY_PAUSE,
                )
                .build()
    }
}
