package dev.mulev.flureadium

import android.os.Build
import android.os.Looper
import androidx.media3.common.DeviceInfo
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.TrackSelectionParameters
import androidx.media3.common.VideoSize
import androidx.media3.common.util.Size
import androidx.media3.common.util.UnstableApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.mockito.Mockito.`when`
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Covers the media3 adaptation in [PluginSimpleBasePlayer]: remapping head-unit
 * next/previous to forward/backward seeks, and the [allowExternalSeeking]
 * command stripping in the rebuilt player state.
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
internal class PluginSimpleBasePlayerTest {

    /** Exposes the protected hooks under test. */
    private class Probe(
        player: Player,
        preferences: FlutterAudioPreferences,
    ) : PluginSimpleBasePlayer(player, preferences) {
        fun seek(command: Int) = handleSeek(0, 0L, command)
        fun stateForTest() = getState()
    }

    private fun playerMock(): Player {
        val player = mock(Player::class.java)
        `when`(player.applicationLooper).thenReturn(Looper.getMainLooper())
        return player
    }

    private fun probe(
        player: Player,
        allowExternalSeeking: Boolean = true,
    ) = Probe(player, FlutterAudioPreferences(allowExternalSeeking = allowExternalSeeking))

    @Test
    fun handleSeek_next_isRemappedToSeekForward() {
        val player = playerMock()

        probe(player).seek(Player.COMMAND_SEEK_TO_NEXT)

        verify(player).seekForward()
        verify(player, never()).seekToNext()
    }

    @Test
    fun handleSeek_previous_isRemappedToSeekBack() {
        val player = playerMock()

        probe(player).seek(Player.COMMAND_SEEK_TO_PREVIOUS)

        verify(player).seekBack()
        verify(player, never()).seekToPrevious()
    }

    @Test
    fun handleSeek_otherCommand_passesThrough() {
        val player = playerMock()

        probe(player).seek(Player.COMMAND_SEEK_FORWARD)

        verify(player).seekForward()
    }

    private fun stubStateGetters(player: Player, commands: Player.Commands) {
        `when`(player.availableCommands).thenReturn(commands)
        `when`(player.isCommandAvailable(org.mockito.ArgumentMatchers.anyInt()))
            .thenAnswer { commands.contains(it.getArgument<Int>(0)) }
        `when`(player.deviceInfo).thenReturn(DeviceInfo.UNKNOWN)
        `when`(player.playbackParameters).thenReturn(PlaybackParameters.DEFAULT)
        `when`(player.playbackState).thenReturn(Player.STATE_IDLE)
        `when`(player.currentTimeline).thenReturn(Timeline.EMPTY)
        `when`(player.surfaceSize).thenReturn(Size.UNKNOWN)
        `when`(player.videoSize).thenReturn(VideoSize.UNKNOWN)
        `when`(player.trackSelectionParameters)
            .thenReturn(TrackSelectionParameters.DEFAULT)
        `when`(player.seekBackIncrement).thenReturn(5000L)
        `when`(player.seekForwardIncrement).thenReturn(5000L)
    }

    @Test
    fun getState_whenExternalSeekingAllowed_keepsSeekInCurrentItemCommand() {
        val player = playerMock()
        val commands = Player.Commands.Builder()
            .add(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
            .build()
        stubStateGetters(player, commands)

        val state = probe(player, allowExternalSeeking = true).stateForTest()

        assertTrue(state.availableCommands.contains(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM))
    }

    @Test
    fun getState_whenExternalSeekingDisallowed_stripsSeekInCurrentItemCommand() {
        val player = playerMock()
        val commands = Player.Commands.Builder()
            .add(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)
            .build()
        stubStateGetters(player, commands)

        val state = probe(player, allowExternalSeeking = false).stateForTest()

        assertFalse(state.availableCommands.contains(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM))
    }
}
