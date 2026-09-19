package dev.mulev.flureadium.navigators

import android.util.Log
import dev.mulev.flureadium.PublicationError
import org.readium.navigator.media.common.MediaNavigator
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import kotlin.time.Duration

private const val TAG = "TimebasedNavigator"

/**
 * Base class for time-based navigators, such as audiobook or TTS navigators.
 */
@OptIn(ExperimentalReadiumApi::class)
abstract class TimebasedNavigator<P : MediaNavigator.Playback>(
    publication: Publication,

    /**
     * Listener for time-based navigator events.
     */
    protected val timebaseListener: TimebasedListener,
    initialLocator: Locator?
) : BaseNavigator(publication, initialLocator) {

    /**
     * Listener interface for time-based navigator events.
     */
    interface TimebasedListener {
        /**
         * Called when the playback state changes.
         */
        fun onTimebasedPlaybackStateChanged(timebasedState: TimebasedState)

        /**
         * Called when the time-based buffer changes.
         */
        fun onTimebasedBufferChanged(buffer: Duration?)

        /**
         * Called when there is a playback error.
         */
        fun onTimebasedPlaybackFailure(error: PublicationError)

        /**
         * Called when the current locator changes.
         */
        fun onTimebasedCurrentLocatorChanges(locator: Locator, currentReadingOrderLink: Link?)

        /**
         * Called when there is a time-based location change, this is used to highlight text while reading.
         */
        fun onTimebasedLocationChanged(locator: Locator)
    }

    // Possible states for a time-based navigator.
    enum class TimebasedState {
        Playing,

        Paused,

        Loading,

        Failure,

        Ended,
    }

    /**
     * Called when the playback state changes.
     */
    open fun onPlaybackStateChanged(pb: P) {
        var timebasedState: TimebasedState
        when (pb.state) {
            is MediaNavigator.State.Ready -> {
                timebasedState = if (pb.playWhenReady) TimebasedState.Playing else TimebasedState.Paused
            }

            is MediaNavigator.State.Buffering -> {
                timebasedState = TimebasedState.Loading
            }

            is MediaNavigator.State.Failure -> {
                timebasedState = TimebasedState.Failure
            }

            is MediaNavigator.State.Ended -> {
                timebasedState = TimebasedState.Ended
            }
        }

        Log.d(
            TAG,
            ": onPlaybackStateChanged: state=${pb.state} playWhenReady={${pb.playWhenReady}}, playbackState=$timebasedState, index=${pb.index}"
        )

        timebaseListener.onTimebasedPlaybackStateChanged(timebasedState)
    }

    override fun onCurrentLocatorChanges(locator: Locator) {
        val index = publication.readingOrder.indexOfFirst { link ->
            link.href.toString() == locator.href.toString()
        }
        val readingOrderLink = publication.readingOrder.getOrNull(index)?.let { link ->
            trackDuration(index)?.let { link.copy(duration = it) } ?: link
        }

        val newLocator =
            if (locator.locations.position == null && index != -1) {
                locator.copy(locations = locator.locations.copy(position = index + 1))
            } else {
                locator
            }

        timebaseListener.onTimebasedCurrentLocatorChanges(newLocator, readingOrderLink)
    }

    /**
     * Effective duration in seconds of reading-order track [index] — the value this
     * navigator actually plays with, which is not always the one the manifest declares.
     * Null when the navigator has no duration of its own; every navigator but the
     * audiobook one inherits that default.
     *
     * The manifest is not the source because it is not what plays: `AudiobookNavigator`
     * resolves the missing durations up front and hands the *resolved* reading order to
     * Readium's `createNavigator`, leaving `publication.readingOrder` untouched. Reading
     * the duration back off the manifest therefore reports null for a streamed book that
     * declares none, however well the probe did — the frozen `0:00` scrubber this seam
     * exists to fix.
     */
    protected open fun trackDuration(index: Int): Double? = null

    /**
     * Start playing
     */
    open suspend fun play() {
        play(null)
    }

    /**
     * Start playing. If fromLocator is provided from that position.
     */
    abstract suspend fun play(fromLocator: Locator?)

    /**
     * Pause playback.
     */
    abstract suspend fun pause()

    /**
     * Resume playback
     */
    abstract suspend fun resume()

    /**
     * Go back in the playback.
     */
    abstract suspend fun goBack()

    /**
     * Go forward in the playback.
     */
    abstract suspend fun goForward()

    /**
     * Seek to a specific position in the playback.
     */
    abstract suspend fun goToLocator(locator: Locator)

    /**
     * Seek to a specific offset in seconds from the current position. Can be negative or positive.
     */
    abstract suspend fun seekTo(offset: Double)
}
