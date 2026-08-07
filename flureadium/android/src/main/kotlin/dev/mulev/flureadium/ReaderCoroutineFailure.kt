package dev.mulev.flureadium

import android.util.Log
import kotlinx.coroutines.CoroutineExceptionHandler

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
 */
internal fun readerCoroutineExceptionHandler(tag: String): CoroutineExceptionHandler =
    CoroutineExceptionHandler { _, throwable ->
        Log.e(tag, "Uncaught coroutine failure", throwable)
        ReadiumReader.sendReaderStatus("error")
        ReadiumReader.sendError(
            throwable.message ?: throwable.toString(),
            code = readerFailureErrorCode,
            data = throwable.stackTraceToString(),
        )
    }
