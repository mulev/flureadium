package dev.mulev.flureadium

import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.ExperimentalCoroutinesApi

/** Code carried by every error event raised from an uncaught reader coroutine failure. */
internal const val readerFailureErrorCode = "ReaderFailure"

/**
 * Handler for the root coroutines of a reader scope.
 *
 * Every reader scope is built on a SupervisorJob, and a supervisor's direct
 * children are treated as root coroutines, so kotlinx.coroutines hands their
 * failures to the CoroutineExceptionHandler in the coroutine's context. With no
 * handler installed it falls through to the thread's uncaught handler, which on
 * Android kills the process — that is how a failed navigator enable used to take
 * the app down with nothing reaching Dart. Reporting the failure keeps the
 * process alive and tells the host app what happened, the way iOS already does
 * for a reader failure.
 *
 * Cancellation never arrives here: a coroutine cancelled by dispose() or
 * detach() completes with a CancellationException, which is not handed to a
 * handler, so teardown stays silent.
 *
 * [shouldReport] decides whether this failure still describes the session the
 * host app is looking at. A reader widget passes its own identity check here:
 * Flutter builds a replacement platform view before unmounting the one it
 * replaces, so a stale widget's enable can fail while a newer widget already
 * owns the reader — and reporting then would flip a healthy reader to "error"
 * over a failure that belongs to a session the host has already dropped. The
 * log line is written either way, because a swallowed failure still has to be
 * findable.
 *
 * A scope whose own failure would travel through the reporting path must use
 * [channelCoroutineExceptionHandler] instead — see the note there.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal fun readerCoroutineExceptionHandler(
    tag: String,
    shouldReport: () -> Boolean = { true },
): CoroutineExceptionHandler =
    CoroutineExceptionHandler { _, throwable ->
        Log.e(tag, "Uncaught coroutine failure", throwable)
        if (!shouldReport()) return@CoroutineExceptionHandler
        ReadiumReader.sendReaderStatus("error")
        ReadiumReader.sendError(
            throwable.message ?: throwable.toString(),
            code = readerFailureErrorCode,
            data = throwable.stackTraceToString(),
        )
    }

/**
 * Handler for the scopes the report itself runs through.
 *
 * Reporting a failure means sending on the reader-status and error channels, and
 * those sends run in the channel's own scope. A channel that reported its own
 * failure would send again, fail again, and never stop — and because the send is
 * dispatched rather than nested, the loop spins forever instead of overflowing
 * the stack. There is no flag that fixes that; the cycle has to not exist.
 *
 * So a channel failure is logged and goes no further. The process stays alive,
 * which is the point, and logcat still has the throwable. Anything a host app
 * needs to know about a broken channel it will learn from the missing events.
 */
internal fun channelCoroutineExceptionHandler(tag: String): CoroutineExceptionHandler =
    CoroutineExceptionHandler { _, throwable ->
        Log.e(tag, "Uncaught event channel failure", throwable)
    }
