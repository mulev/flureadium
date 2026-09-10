package dev.mulev.flureadium

import dev.mulev.flureadium.navigators.AudiobookNavigator
import dev.mulev.flureadium.navigators.SyncAudiobookNavigator
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runTest
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Guards the `/main` `audiobookTrackDurations` route: it reports what the open audio
 * navigator resolved — either navigator kind — with `null` entries preserved, and an
 * empty list when no audiobook is open.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
@RunWith(RobolectricTestRunner::class)
internal class PublicationChannelAudioDurationsTest {

    // ReadiumReader is an object that outlives this class, so every field seeded
    // here is cleared again — see ReadiumReaderFields.kt's own doc comment.
    @AfterTest
    fun tearDown() {
        setReaderField("audiobookNavigator", null)
        setReaderField("syncAudiobookNavigator", null)
    }

    @Test
    fun reportsTheAudioNavigatorsResolvedDurations_keepingNulls() = runTest {
        val navigator = mock(AudiobookNavigator::class.java)
        `when`(navigator.resolvedTrackDurations).thenReturn(listOf(12.5, null, 30.0))
        setReaderField("audiobookNavigator", navigator)

        val result = PublicationMethodCallHandler()
            .handleMethodCallsQueue("audiobookTrackDurations", null)

        assertTrue(result.isSuccess)
        assertEquals(
            listOf(12.5, null, 30.0),
            result.getOrNull(),
            "a duration that could not be resolved must stay null: Readium reads 0.0 " +
                "as missing and rejects a publication that declares it",
        )
    }

    @Test
    fun fallsBackToTheSyncNavigatorWhenThatIsTheOpenOne() = runTest {
        val navigator = mock(SyncAudiobookNavigator::class.java)
        `when`(navigator.resolvedTrackDurations).thenReturn(listOf(60.0))
        setReaderField("syncAudiobookNavigator", navigator)

        val result = PublicationMethodCallHandler()
            .handleMethodCallsQueue("audiobookTrackDurations", null)

        assertTrue(result.isSuccess)
        assertEquals(listOf(60.0), result.getOrNull())
    }

    @Test
    fun reportsAnEmptyListWhenNoAudiobookIsOpen() = runTest {
        val result = PublicationMethodCallHandler()
            .handleMethodCallsQueue("audiobookTrackDurations", null)

        assertTrue(result.isSuccess, "an empty answer is legitimate, not an error")
        assertEquals(emptyList<Double?>(), result.getOrNull())
    }
}
