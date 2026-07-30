package dev.mulev.flureadium

import android.os.Build
import android.os.Looper
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import dev.mulev.flureadium.car.CarBrowseNode
import dev.mulev.flureadium.car.CarContentSource
import dev.mulev.flureadium.car.CarContentStrings
import dev.mulev.flureadium.car.CarNodeKind
import dev.mulev.flureadium.car.CarTab
import dev.mulev.flureadium.car.FlureadiumCarEngine
import kotlinx.coroutines.ExperimentalCoroutinesApi
import org.junit.runner.RunWith
import org.mockito.Mockito.mock
import org.robolectric.Robolectric
import org.robolectric.Shadows.shadowOf
import org.robolectric.RobolectricTestRunner
import org.robolectric.android.controller.ServiceController
import org.robolectric.annotation.Config
import org.robolectric.annotation.LooperMode
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * Covers the Android refresh entry on [PluginMediaService]: the process-scoped
 * [PluginMediaService.instance] the `/main` router reaches, and `refreshBrowse()`
 * re-notifying subscribed browse parents through the persistent session's
 * callback (proven by the refetch it triggers on the registered source).
 */
@UnstableApi
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P])
@LooperMode(LooperMode.Mode.PAUSED)
@OptIn(ExperimentalCoroutinesApi::class)
internal class PluginMediaServiceRefreshTest {

    private class CountingCarContentSource(
        private val childrenByParent: Map<String, List<CarBrowseNode>> = emptyMap(),
    ) : CarContentSource {
        val childrenCalls = mutableListOf<String>()

        override fun rootTabs(): ListenableFuture<List<CarTab>> =
            Futures.immediateFuture(emptyList())

        override fun children(nodeId: String): ListenableFuture<List<CarBrowseNode>> {
            childrenCalls.add(nodeId)
            return Futures.immediateFuture(childrenByParent[nodeId].orEmpty())
        }

        override fun search(query: String): ListenableFuture<List<CarBrowseNode>> =
            Futures.immediateFuture(emptyList())

        override fun strings(): ListenableFuture<CarContentStrings?> =
            Futures.immediateFuture(null)

        override fun play(nodeId: String) {}

        override fun addBookmark() {}
    }

    private fun node(id: String) = CarBrowseNode(
        id = id,
        title = id,
        subtitle = null,
        artworkPath = null,
        kind = CarNodeKind.audiobook,
        isPlayable = true,
        progress = null,
        isNowPlaying = false,
    )

    private lateinit var controller: ServiceController<PluginMediaService>
    private var controllerDestroyed = false

    private fun service(): PluginMediaService {
        controller = Robolectric.buildService(PluginMediaService::class.java).create()
        return controller.get()
    }

    @AfterTest
    fun tearDown() {
        if (::controller.isInitialized && !controllerDestroyed) controller.destroy()
        FlureadiumCarEngine.source = null
    }

    @Test
    fun instance_isSetAfterCreate_andClearedAfterDestroy() {
        val service = service()

        assertSame(service, PluginMediaService.instance)

        controller.destroy()
        controllerDestroyed = true
        assertNull(PluginMediaService.instance)
    }

    @Test
    fun refreshBrowse_refetchesSubscribedParent_throughPersistentCallback() {
        val source = CountingCarContentSource(
            childrenByParent = mapOf(
                "genre:sci-fi" to listOf(node("book:dune"), node("book:foundation")),
            ),
        )
        FlureadiumCarEngine.source = source
        val service = service()
        // Record a subscription on the persistent session's real callback; the
        // controller is a mock, so the resulting notifyChildrenChanged is a no-op
        // on the real session, but the count refetch still runs.
        service.libraryCallback.onSubscribe(
            mock(MediaLibrarySession::class.java),
            mock(MediaSession.ControllerInfo::class.java),
            "genre:sci-fi",
            null,
        )

        service.refreshBrowse()

        // refreshBrowse marshals onto the main looper; nothing runs until it drains.
        assertTrue(source.childrenCalls.isEmpty())
        shadowOf(Looper.getMainLooper()).idle()

        // refreshBrowse -> callback.notifySubscribedParents -> source refetch per parent.
        assertEquals(listOf("genre:sci-fi"), source.childrenCalls)
    }

    @Test
    fun refreshBrowse_beforeSessionExists_isNoOp() {
        // No create() -> the persistent session is not initialized yet.
        val service = Robolectric.buildService(PluginMediaService::class.java).get()

        service.refreshBrowse()
    }
}
