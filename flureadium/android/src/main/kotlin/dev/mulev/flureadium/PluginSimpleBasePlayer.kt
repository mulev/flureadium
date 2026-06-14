package dev.mulev.flureadium

import androidx.media3.common.ForwardingSimpleBasePlayer
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import com.google.common.util.concurrent.ListenableFuture

/**
 * A [ForwardingSimpleBasePlayer] that adapts the Readium audio/TTS player for
 * media3 sessions: it remaps next/previous seeks to forward/backward seeks and
 * rebuilds player state to tolerate the empty playlists the Readium TTS player
 * briefly reports.
 */
@UnstableApi
open class PluginSimpleBasePlayer(player: Player, val preferences: FlutterAudioPreferences) : ForwardingSimpleBasePlayer(player) {

    override fun handleSeek(
        mediaItemIndex: Int,
        positionMs: Long,
        seekCommand: Int
    ): ListenableFuture<*> {
        // NOTE: Maps seek to next/previous track, to seek forward/backward in current track.
        if (seekCommand == COMMAND_SEEK_TO_NEXT) {
            return super.handleSeek(mediaItemIndex, positionMs, COMMAND_SEEK_FORWARD)
        } else if (seekCommand == COMMAND_SEEK_TO_PREVIOUS) {
            return super.handleSeek(mediaItemIndex, positionMs, COMMAND_SEEK_BACK)
        }
        return super.handleSeek(mediaItemIndex, positionMs, seekCommand)
    }

    // FIX: Hacky way to fix missing COMMAND_GET_TIMELINE from TtsSessionAdapter
    override fun getState(): State {
        // This is a copy & override of the super implementation, due to assert on empty playlist,
        // which Readium TTSPlayer sometimes provides during active states.
        // See https://github.com/readium/kotlin-toolkit/pull/716

        // Ordered alphabetically by State.Builder setters.
        val state = State.Builder()
//      val positionSuppliers = livePositionSuppliers
        if (player.isCommandAvailable(COMMAND_GET_AUDIO_ATTRIBUTES)) {
            state.setAudioAttributes(player.audioAttributes)
        }

        if (preferences.allowExternalSeeking) {
            state.setAvailableCommands(player.availableCommands)
        } else {
            val commandsWithoutSeeking = player.availableCommands
                .buildUpon()
                .remove(COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
                .build()
            state.setAvailableCommands(commandsWithoutSeeking)
        }

        if (player.isCommandAvailable(COMMAND_GET_CURRENT_MEDIA_ITEM)) {
            state.setContentPositionMs { player.contentPosition }
            state.setContentBufferedPositionMs { player.contentBufferedPosition }
//          state.setContentBufferedPositionMs(positionSuppliers.contentBufferedPositionSupplier)
//          state.setContentPositionMs(positionSuppliers.contentPositionSupplier)
        }
        if (player.isCommandAvailable(COMMAND_GET_TEXT)) {
            state.setCurrentCues(player.currentCues)
        }
        //if (player.isCommandAvailable(COMMAND_GET_TIMELINE)) {
        state.setCurrentMediaItemIndex(player.currentMediaItemIndex)
        //}
        state.setDeviceInfo(player.getDeviceInfo())
        if (player.isCommandAvailable(COMMAND_GET_DEVICE_VOLUME)) {
            state.setDeviceVolume(player.deviceVolume)
            state.setIsDeviceMuted(player.isDeviceMuted)
        }
        state.setIsLoading(player.isLoading)
        state.setMaxSeekToPreviousPositionMs(player.maxSeekToPreviousPosition)
        state.setPlaybackParameters(player.playbackParameters)
        state.setPlaybackState(player.playbackState)
        state.setPlaybackSuppressionReason(player.playbackSuppressionReason)
        state.setPlayerError(player.playerError)
        //if (player.isCommandAvailable(COMMAND_GET_TIMELINE)) {
        val tracks =
            if (player.isCommandAvailable(COMMAND_GET_TRACKS))
                player.currentTracks
            else
                Tracks.EMPTY
        val mediaMetadata =
            if (player.isCommandAvailable(COMMAND_GET_METADATA)) player.mediaMetadata else null
        state.setPlaylist(player.currentTimeline, tracks, mediaMetadata)
        //}
        if (player.isCommandAvailable(COMMAND_GET_METADATA)) {
            state.setPlaylistMetadata(player.playlistMetadata)
        }
        state.setPlayWhenReady(player.playWhenReady, PLAY_WHEN_READY_CHANGE_REASON_END_OF_MEDIA_ITEM)
        state.setRepeatMode(player.repeatMode)
        state.setSeekBackIncrementMs(player.seekBackIncrement)
        state.setSeekForwardIncrementMs(player.seekForwardIncrement)
        state.setShuffleModeEnabled(player.shuffleModeEnabled)
        state.setSurfaceSize(player.surfaceSize)
        //state.setTimedMetadata(lastTimedMetadata)
        if (player.isCommandAvailable(COMMAND_GET_CURRENT_MEDIA_ITEM)) {
            state.setTotalBufferedDurationMs { player.totalBufferedDuration }
        }
        state.setTrackSelectionParameters(player.trackSelectionParameters)
        state.setVideoSize(player.videoSize)
        if (player.isCommandAvailable(COMMAND_GET_VOLUME)) {
            state.setVolume(player.volume)
        }
        return state.build()
    }
}
