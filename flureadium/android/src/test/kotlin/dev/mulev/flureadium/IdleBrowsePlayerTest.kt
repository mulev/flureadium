package dev.mulev.flureadium

import android.os.Build
import android.os.Looper
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Covers the browse placeholder's observable contract: it reports an idle, empty
 * state (no phantom "now playing"), yet still accepts the browse-row play
 * commands so a head unit's row tap can reach
 * [PluginLibrarySessionCallback.onSetMediaItems]. The placeholder itself starts
 * no playback — that is driven by `source.play` and the player swap.
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
internal class IdleBrowsePlayerTest {

    private fun player() = IdleBrowsePlayer(Looper.getMainLooper())

    @Test
    fun reportsIdlePlaybackState() {
        assertEquals(Player.STATE_IDLE, player().playbackState)
    }

    @Test
    fun hasNoMediaItems() {
        assertEquals(0, player().mediaItemCount)
    }

    @Test
    fun acceptsBrowsePickCommands_withoutStartingPlayback() {
        val player = player()

        // The head unit "plays" a browse row by setting it as the media items,
        // then preparing and playing. The placeholder must accept these (the same
        // list shape onSetMediaItems handles) without loading anything itself.
        player.setMediaItems(listOf(MediaItem.fromUri("flureadium://browse-pick")), 0, 0L)
        player.prepare()
        player.play()

        assertEquals(Player.STATE_IDLE, player.playbackState)
        assertEquals(0, player.mediaItemCount)
    }
}
