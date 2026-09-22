@file:OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)

package dev.mulev.flureadium.navigators

import android.os.Build
import android.os.Bundle
import dev.mulev.flureadium.PublicationError
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Href
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.mediatype.MediaType
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.time.Duration

private fun link(href: String, duration: Double? = null) =
    Link(href = Href(Url(href)!!), mediaType = MediaType.MP3, duration = duration)

private fun locator(href: String, position: Int? = null) = Locator(
    href = Url(href)!!,
    mediaType = MediaType.MP3,
    locations = Locator.Locations(position = position),
)

/** Captures what the navigator hands the listener. */
private class RecordingListener : TimebasedNavigator.TimebasedListener {
    var locator: Locator? = null
    var link: Link? = null
    var calls = 0

    override fun onTimebasedPlaybackStateChanged(timebasedState: TimebasedNavigator.TimebasedState) = Unit
    override fun onTimebasedBufferChanged(buffer: Duration?) = Unit
    override fun onTimebasedPlaybackFailure(error: PublicationError) = Unit
    override fun onTimebasedLocationChanged(locator: Locator) = Unit
    override fun onTimebasedCurrentLocatorChanges(locator: Locator, currentReadingOrderLink: Link?) {
        this.locator = locator
        this.link = currentReadingOrderLink
        calls++
    }
}

/**
 * The smallest concrete TimebasedNavigator: everything abstract is a no-op, and
 * [probed] stands in for what AudiobookNavigator's resolvedTrackDurations answers.
 * An empty [probed] is the TTS case — the inherited null for every index.
 */
private class FakeTimebasedNavigator(
    publication: Publication,
    listener: TimebasedNavigator.TimebasedListener,
    private val probed: List<Double?> = emptyList(),
) : TimebasedNavigator<MediaNavigator.Playback>(publication, listener, null) {
    override fun trackDuration(index: Int): Double? = probed.getOrNull(index)
    override suspend fun initNavigator() = Unit
    override fun setupNavigatorListeners() = Unit
    override fun storeState(): Bundle = Bundle()
    override suspend fun play(fromLocator: Locator?) = Unit
    override suspend fun pause() = Unit
    override suspend fun resume() = Unit
    override suspend fun goBack() = Unit
    override suspend fun goForward() = Unit
    override suspend fun goToLocator(locator: Locator) = Unit
    override suspend fun seekTo(offset: Double) = Unit
}

/**
 * What `onCurrentLocatorChanges` hands the listener is the duration the navigator
 * plays with, not the one the manifest declared. A streamed audiobook declares no
 * durations, so reading them back off `publication.readingOrder` reports null however
 * well the probe did — the frozen `0:00` scrubber this seam exists to fix.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
internal class TimebasedNavigatorTrackDurationTest {

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun publicationOf(vararg links: Link): Publication {
        val publication = mock(Publication::class.java)
        `when`(publication.readingOrder).thenReturn(links.toList())
        return publication
    }

    @Test
    fun probedDurationReachesTheListener() {
        val listener = RecordingListener()
        val navigator = FakeTimebasedNavigator(
            publicationOf(link("t1.mp3")),
            listener,
            probed = listOf(434.085),
        )

        navigator.onCurrentLocatorChanges(locator("t1.mp3"))

        assertEquals(434.085, listener.link?.duration)
    }

    @Test
    fun declaredDurationSurvivesWhenNothingWasProbed() {
        val listener = RecordingListener()
        val navigator = FakeTimebasedNavigator(
            publicationOf(link("t1.mp3", duration = 120.0)),
            listener,
        )

        navigator.onCurrentLocatorChanges(locator("t1.mp3"))

        assertEquals(120.0, listener.link?.duration)
    }

    @Test
    fun anUnknownDurationStillDeliversTheLink() {
        val listener = RecordingListener()
        val navigator = FakeTimebasedNavigator(publicationOf(link("t1.mp3")), listener)

        navigator.onCurrentLocatorChanges(locator("t1.mp3"))

        assertNotNull(listener.link, "an unknown duration cost the listener its link")
        assertNull(listener.link?.duration)
    }

    @Test
    fun missingPositionIsFilledFromTheReadingOrderIndex() {
        val listener = RecordingListener()
        val navigator = FakeTimebasedNavigator(
            publicationOf(link("t1.mp3"), link("t2.mp3")),
            listener,
        )

        navigator.onCurrentLocatorChanges(locator("t2.mp3"))

        assertEquals(2, listener.locator?.locations?.position)
    }

    @Test
    fun anUnknownHrefDeliversANullLinkAndTheLocatorUnchanged() {
        val listener = RecordingListener()
        val navigator = FakeTimebasedNavigator(publicationOf(link("t1.mp3")), listener)

        navigator.onCurrentLocatorChanges(locator("t9.mp3"))

        assertNull(listener.link)
        assertNull(listener.locator?.locations?.position)
        assertEquals(1, listener.calls)
    }
}
