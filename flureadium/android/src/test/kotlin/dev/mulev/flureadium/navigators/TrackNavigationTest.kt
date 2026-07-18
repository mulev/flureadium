package dev.mulev.flureadium.navigators

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

internal class TrackNavigationTest {

    private val tracks = listOf("track1", "track2", "track3")

    @Test
    fun nextTrackIndex_fromFirstTrack_returnsSecondIndex() {
        assertEquals(1, nextTrackIndex(tracks, "track1"))
    }

    @Test
    fun nextTrackIndex_fromMiddleTrack_returnsFollowingIndex() {
        assertEquals(2, nextTrackIndex(tracks, "track2"))
    }

    @Test
    fun nextTrackIndex_fromLastTrack_returnsNull() {
        assertNull(nextTrackIndex(tracks, "track3"))
    }

    @Test
    fun previousTrackIndex_fromMiddleTrack_returnsPrecedingIndex() {
        assertEquals(0, previousTrackIndex(tracks, "track2"))
    }

    @Test
    fun previousTrackIndex_fromLastTrack_returnsPrecedingIndex() {
        assertEquals(1, previousTrackIndex(tracks, "track3"))
    }

    @Test
    fun previousTrackIndex_fromFirstTrack_returnsNull() {
        assertNull(previousTrackIndex(tracks, "track1"))
    }

    @Test
    fun neighbourTrackIndex_withUnknownHref_returnsNullForBoth() {
        assertNull(nextTrackIndex(tracks, "ghost"))
        assertNull(previousTrackIndex(tracks, "ghost"))
    }

    @Test
    fun neighbourTrackIndex_withNullHref_returnsNullForBoth() {
        assertNull(nextTrackIndex(tracks, null))
        assertNull(previousTrackIndex(tracks, null))
    }
}
