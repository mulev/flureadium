package dev.mulev.flureadium.car

import android.os.Build
import android.os.Looper
import io.flutter.plugin.common.MethodChannel
import org.junit.runner.RunWith
import org.mockito.ArgumentMatchers.any
import org.mockito.ArgumentMatchers.anyString
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito.doAnswer
import org.mockito.Mockito.mock
import org.mockito.Mockito.verify
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.time.Duration
import java.util.concurrent.atomic.AtomicInteger
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull

/**
 * Covers [MethodChannelCarContentSource]'s decode-and-retry over the method
 * channel: list replies decode to typed values, a not-yet-ready non-list reply
 * is retried and then recovers, an exhausted retry budget yields an empty list,
 * and `play` fires the channel call.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
internal class MethodChannelCarContentSourceTest {

    private val channel = mock(MethodChannel::class.java)
    private val source = MethodChannelCarContentSource(channel)

    /** Answers every result-bearing invokeMethod with [result]. */
    private fun answerWith(result: Any?) {
        doAnswer { invocation ->
            invocation.getArgument<MethodChannel.Result>(2).success(result)
            null
        }.`when`(channel).invokeMethod(anyString(), any(), any(MethodChannel.Result::class.java))
    }

    @Test
    fun rootTabs_decodesTabsFromListReply() {
        answerWith(
            listOf(
                mapOf("id" to "library", "title" to "Library", "iconName" to "books"),
            ),
        )

        assertEquals(
            listOf(CarTab("library", "Library", "books")),
            source.rootTabs().get(),
        )
    }

    @Test
    fun children_decodesNodesFromListReply() {
        answerWith(
            listOf(
                mapOf("id" to "book:1", "title" to "Dune", "kind" to "audiobook", "isPlayable" to true),
            ),
        )

        val nodes = source.children("library").get()

        assertEquals(1, nodes.size)
        assertEquals("book:1", nodes[0].id)
        assertEquals(CarNodeKind.audiobook, nodes[0].kind)
        assertEquals(true, nodes[0].isPlayable)
    }

    @Test
    fun search_decodesNodesFromListReply() {
        answerWith(
            listOf(mapOf("id" to "book:1", "title" to "Dune", "kind" to "audiobook")),
        )

        assertEquals(1, source.search("dune").get().size)
    }

    @Test
    fun children_dropsMalformedRows() {
        answerWith(
            listOf(
                mapOf("id" to "book:1", "title" to "Dune", "kind" to "audiobook"),
                mapOf("id" to "book:2", "kind" to "audiobook"), // missing title
                "garbage",
            ),
        )

        assertEquals(1, source.children("library").get().size)
    }

    @Test
    fun strings_decodesStringsMap() {
        answerWith(
            mapOf(
                "emptyRootTitle" to "Nothing to play yet",
                "emptyRootSubtitle" to "Add books to see them here",
                "voiceUnavailable" to "This voice is not installed",
                "offline" to "This book needs a connection",
            ),
        )

        val strings = source.strings().get()

        assertEquals("Nothing to play yet", strings?.emptyRootTitle)
    }

    @Test
    fun strings_isNull_whenReplyIsNotAMap() {
        answerWith(null)

        assertNull(source.strings().get())
    }

    @Test
    fun play_invokesPlayWithNodeId() {
        source.play("book:1")

        verify(channel).invokeMethod("play", mapOf("nodeId" to "book:1"))
    }

    @Test
    fun addBookmark_invokesAddBookmark() {
        source.addBookmark()

        verify(channel).invokeMethod("addBookmark", null)
    }

    @Test
    fun list_retriesUntilAnArrayArrives() {
        val calls = AtomicInteger(0)
        doAnswer { invocation ->
            val cb = invocation.getArgument<MethodChannel.Result>(2)
            if (calls.getAndIncrement() == 0) {
                cb.success("handler not ready")
            } else {
                cb.success(listOf(mapOf("id" to "library", "title" to "Library")))
            }
            null
        }.`when`(channel).invokeMethod(anyString(), any(), any(MethodChannel.Result::class.java))

        val future = source.rootTabs()
        assertFalse(future.isDone) // waiting on the retry

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500))

        assertEquals(listOf(CarTab("library", "Library", null)), future.get())
    }

    @Test
    fun list_givesUpWithEmptyAfterExhaustingRetries() {
        answerWith("never an array")

        val future = source.rootTabs()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(5))

        assertEquals(emptyList<CarTab>(), future.get())
    }

    @Test
    fun list_retriesOnNotImplemented_thenRecovers() {
        val calls = AtomicInteger(0)
        doAnswer { invocation ->
            val cb = invocation.getArgument<MethodChannel.Result>(2)
            if (calls.getAndIncrement() == 0) {
                cb.notImplemented() // cold engine: no handler installed yet
            } else {
                cb.success(listOf(mapOf("id" to "library", "title" to "Library")))
            }
            null
        }.`when`(channel).invokeMethod(anyString(), any(), any(MethodChannel.Result::class.java))

        val future = source.rootTabs()
        assertFalse(future.isDone)

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(500))

        assertEquals(listOf(CarTab("library", "Library", null)), future.get())
    }
}
