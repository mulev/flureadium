package dev.mulev.flureadium

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.setMain
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.test.AfterTest
import kotlin.test.BeforeTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Tests what the reader scopes report when a coroutine fails.
 *
 * The handler is the whole reason a failed enable no longer kills the process,
 * so what it sends is the host app's only account of what happened.
 */
@OptIn(ExperimentalCoroutinesApi::class)
internal class ReaderCoroutineFailureTest {

    private val testDispatcher = UnconfinedTestDispatcher()

    @BeforeTest
    fun setUp() {
        Dispatchers.setMain(testDispatcher)
        resetReaderState()
    }

    @AfterTest
    fun tearDown() {
        Dispatchers.resetMain()
        resetReaderState()
    }

    @Test
    fun reportsTheFailureMessageAndCode() {
        val errors = subscribeToErrorEvents()

        handleFailure(Exception("boom"))

        assertEquals(1, errors.size)
        val errorEvent = errors.single()
        assertEquals("boom", errorEvent["message"])
        assertEquals("ReaderFailure", errorEvent["code"])
        assertTrue(
            (errorEvent["data"] as String).isNotEmpty(),
            "the stack trace is what makes the report actionable"
        )
    }

    @Test
    fun reportsAnErrorReaderStatus() {
        val statuses = subscribeToReaderStatus()

        handleFailure(Exception("boom"))

        assertEquals(listOf("error"), statuses)
    }

    @Test
    fun fallsBackToTheThrowableStringWhenThereIsNoMessage() {
        val errors = subscribeToErrorEvents()
        val throwable = IllegalStateException()

        handleFailure(throwable)

        assertEquals(
            throwable.toString(),
            errors.single()["message"],
            "an empty message tells a host app nothing about what failed"
        )
    }

    private fun handleFailure(throwable: Throwable) {
        readerCoroutineExceptionHandler("TestTag")
            .handleException(EmptyCoroutineContext, throwable)
    }
}
