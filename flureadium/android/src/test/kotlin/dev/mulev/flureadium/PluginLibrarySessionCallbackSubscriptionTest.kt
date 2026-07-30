package dev.mulev.flureadium

import android.os.Build
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import dev.mulev.flureadium.car.CarBrowseNode
import dev.mulev.flureadium.car.CarContentSource
import dev.mulev.flureadium.car.CarContentStrings
import dev.mulev.flureadium.car.CarNodeKind
import dev.mulev.flureadium.car.CarTab
import dev.mulev.flureadium.car.NodeBrowseTree
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.mockito.Mockito.never
import org.mockito.Mockito.verify
import org.readium.r2.shared.ExperimentalReadiumApi
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import kotlin.test.Test

/**
 * Covers subscription tracking and the refresh notification in
 * [PluginLibrarySessionCallback]: `onSubscribe`/`onUnsubscribe`/`onDisconnected`
 * bookkeeping, and `notifySubscribedParents` re-notifying each subscribed
 * controller with a count that matches exactly what `onGetChildren` returns.
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@OptIn(ExperimentalReadiumApi::class, ExperimentalCoroutinesApi::class)
internal class PluginLibrarySessionCallbackSubscriptionTest {

    private class StubCarContentSource(
        val tabs: List<CarTab> = emptyList(),
        val childrenByParent: Map<String, List<CarBrowseNode>> = emptyMap(),
        val stringsValue: CarContentStrings? = null,
    ) : CarContentSource {
        override fun rootTabs(): ListenableFuture<List<CarTab>> = Futures.immediateFuture(tabs)

        override fun children(nodeId: String): ListenableFuture<List<CarBrowseNode>> =
            Futures.immediateFuture(childrenByParent[nodeId].orEmpty())

        override fun search(query: String): ListenableFuture<List<CarBrowseNode>> =
            Futures.immediateFuture(emptyList())

        override fun strings(): ListenableFuture<CarContentStrings?> =
            Futures.immediateFuture(stringsValue)

        override fun play(nodeId: String) {}

        override fun addBookmark() {}
    }

    private fun node(id: String, kind: CarNodeKind = CarNodeKind.audiobook) = CarBrowseNode(
        id = id,
        title = id,
        subtitle = null,
        artworkPath = null,
        kind = kind,
        isPlayable = true,
        progress = null,
        isNowPlaying = false,
    )

    private fun strings() = CarContentStrings(
        emptyRootTitle = "Nothing to play yet",
        emptyRootSubtitle = "Add books to see them here",
        voiceUnavailable = "This voice is not installed",
        offline = "This book needs a connection",
    )

    private fun callback(source: CarContentSource?) = PluginLibrarySessionCallback(
        sourceProvider = { source },
        publicationProvider = { null },
    )

    private val session = mock(MediaLibrarySession::class.java)
    private val browser = mock(MediaSession.ControllerInfo::class.java)

    @Test
    fun notifySubscribedParents_notifiesSubscribedContainer_withRefetchedCount() {
        val source = StubCarContentSource(
            childrenByParent = mapOf("genre:sci-fi" to listOf(node("book:dune"), node("book:foundation"))),
        )
        val cb = callback(source)
        val params = LibraryParams.Builder().build()
        cb.onSubscribe(session, browser, "genre:sci-fi", params)

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browser, "genre:sci-fi", 2, params)
    }

    @Test
    fun notifySubscribedParents_ofRoot_usesRootTabCount() {
        val source = StubCarContentSource(
            tabs = listOf(CarTab("continue", "Continue", null), CarTab("library", "Library", null)),
        )
        val cb = callback(source)
        cb.onSubscribe(session, browser, NodeBrowseTree.ROOT_ID, null)

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browser, NodeBrowseTree.ROOT_ID, 2, null)
    }

    @Test
    fun notifySubscribedParents_root_emptyTabsWithStrings_countIncludesStatusRow() {
        val source = StubCarContentSource(tabs = emptyList(), stringsValue = strings())
        val cb = callback(source)
        cb.onSubscribe(session, browser, NodeBrowseTree.ROOT_ID, null)

        cb.notifySubscribedParents(session) { true }

        // onGetChildren renders a single status row for an empty tree with strings,
        // so the refresh must announce one child, not zero.
        verify(session).notifyChildrenChanged(browser, NodeBrowseTree.ROOT_ID, 1, null)
    }

    @Test
    fun notifySubscribedParents_root_emptyTabsNoStrings_countIsZero() {
        val source = StubCarContentSource(tabs = emptyList(), stringsValue = null)
        val cb = callback(source)
        cb.onSubscribe(session, browser, NodeBrowseTree.ROOT_ID, null)

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browser, NodeBrowseTree.ROOT_ID, 0, null)
    }

    @Test
    fun notifySubscribedParents_container_excludesSiriNodesFromCount() {
        val source = StubCarContentSource(
            childrenByParent = mapOf("p1" to listOf(node("a"), node("siri", kind = CarNodeKind.siri))),
        )
        val cb = callback(source)
        cb.onSubscribe(session, browser, "p1", null)

        cb.notifySubscribedParents(session) { true }

        // The siri marker has no Android Auto browse row, so it is not counted.
        verify(session).notifyChildrenChanged(browser, "p1", 1, null)
    }

    @Test
    fun twoControllers_sameParent_differentParams_eachNotifiedWithOwnParams() {
        val source = StubCarContentSource(
            childrenByParent = mapOf("genre:sci-fi" to listOf(node("book:dune"))),
        )
        val cb = callback(source)
        val browserB = mock(MediaSession.ControllerInfo::class.java)
        val paramsA = LibraryParams.Builder().setRecent(true).build()
        val paramsB = LibraryParams.Builder().setSuggested(true).build()
        cb.onSubscribe(session, browser, "genre:sci-fi", paramsA)
        cb.onSubscribe(session, browserB, "genre:sci-fi", paramsB)

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browser, "genre:sci-fi", 1, paramsA)
        verify(session).notifyChildrenChanged(browserB, "genre:sci-fi", 1, paramsB)
    }

    @Test
    fun onUnsubscribe_removesOnlyThatControllerAndParent() {
        val source = StubCarContentSource(
            childrenByParent = mapOf("p1" to listOf(node("a")), "p2" to listOf(node("b"))),
        )
        val cb = callback(source)
        cb.onSubscribe(session, browser, "p1", null)
        cb.onSubscribe(session, browser, "p2", null)
        cb.onUnsubscribe(session, browser, "p1")

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browser, "p2", 1, null)
        verify(session, never()).notifyChildrenChanged(browser, "p1", 1, null)
    }

    @Test
    fun onDisconnected_removesAllRecordsForThatController() {
        val source = StubCarContentSource(childrenByParent = mapOf("p1" to listOf(node("a"))))
        val cb = callback(source)
        val browserB = mock(MediaSession.ControllerInfo::class.java)
        cb.onSubscribe(session, browser, "p1", null)
        cb.onSubscribe(session, browserB, "p1", null)
        cb.onDisconnected(session, browser)

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browserB, "p1", 1, null)
        verify(session, never()).notifyChildrenChanged(browser, "p1", 1, null)
    }

    @Test
    fun notifySubscribedParents_withNoSource_doesNotNotify() {
        val cb = callback(source = null)
        cb.onSubscribe(session, browser, "p1", null)

        cb.notifySubscribedParents(session) { true }

        verify(session, never()).notifyChildrenChanged(browser, "p1", 0, null)
    }

    @Test
    fun notifySubscribedParents_whenInactive_doesNotNotify() {
        val source = StubCarContentSource(childrenByParent = mapOf("p1" to listOf(node("a"))))
        val cb = callback(source)
        cb.onSubscribe(session, browser, "p1", null)

        // A session released mid-refresh reports inactive; the deferred notify is skipped.
        cb.notifySubscribedParents(session) { false }

        verify(session, never()).notifyChildrenChanged(browser, "p1", 1, null)
    }

    @Test
    fun onSubscribe_sameControllerAndParent_replacesParams() {
        val source = StubCarContentSource(childrenByParent = mapOf("p1" to listOf(node("a"))))
        val cb = callback(source)
        val oldParams = LibraryParams.Builder().setRecent(true).build()
        val newParams = LibraryParams.Builder().setSuggested(true).build()
        cb.onSubscribe(session, browser, "p1", oldParams)
        cb.onSubscribe(session, browser, "p1", newParams)

        cb.notifySubscribedParents(session) { true }

        verify(session).notifyChildrenChanged(browser, "p1", 1, newParams)
        verify(session, never()).notifyChildrenChanged(browser, "p1", 1, oldParams)
    }
}
