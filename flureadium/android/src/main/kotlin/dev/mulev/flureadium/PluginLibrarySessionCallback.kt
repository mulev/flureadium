package dev.mulev.flureadium

import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService.LibraryParams
import androidx.media3.session.MediaLibraryService.MediaLibrarySession
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.FutureCallback
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import dev.mulev.flureadium.car.CarContentSource
import dev.mulev.flureadium.car.NodeBrowseTree
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import org.readium.r2.shared.publication.Publication

private const val CUSTOM_COMMAND_REWIND_ACTION_ID = "REWIND_CUSTOM"
private const val CUSTOM_COMMAND_FORWARD_ACTION_ID = "FORWARD_CUSTOM"
private const val CUSTOM_COMMAND_BOOKMARK_ACTION_ID = "BOOKMARK_CUSTOM"

@UnstableApi
enum class NotificationPlayerCustomCommandButton(
    val customAction: String,
    val commandButton: CommandButton,
) {
    REWIND(
        customAction = CUSTOM_COMMAND_REWIND_ACTION_ID,
        commandButton = CommandButton.Builder(CommandButton.ICON_SKIP_BACK)
            .setDisplayName("Rewind")
            .setSlots(CommandButton.SLOT_BACK)
            .setSessionCommand(SessionCommand(CUSTOM_COMMAND_REWIND_ACTION_ID, Bundle()))
            .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_skip_back)
            .build(),
    ),
    FORWARD(
        customAction = CUSTOM_COMMAND_FORWARD_ACTION_ID,
        commandButton = CommandButton.Builder(CommandButton.ICON_SKIP_FORWARD)
            .setDisplayName("Forward")
            .setSlots(CommandButton.SLOT_FORWARD)
            .setSessionCommand(SessionCommand(CUSTOM_COMMAND_FORWARD_ACTION_ID, Bundle()))
            .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_skip_forward)
            .build(),
    ),
    BOOKMARK(
        customAction = CUSTOM_COMMAND_BOOKMARK_ACTION_ID,
        commandButton = CommandButton.Builder(CommandButton.ICON_BOOKMARK_FILLED)
            .setDisplayName("Bookmark")
            .setSlots(CommandButton.SLOT_OVERFLOW)
            .setSessionCommand(SessionCommand(CUSTOM_COMMAND_BOOKMARK_ACTION_ID, Bundle()))
            .setCustomIconResId(androidx.media3.session.R.drawable.media3_icon_bookmark_filled)
            .build(),
    );
}

/**
 * The [MediaLibrarySession.Callback] for [PluginMediaService]: it registers the
 * notification's rewind/forward buttons, routes their custom commands to the
 * reader, and serves the Android Auto browse tree and search.
 *
 * Browse and search come from [sourceProvider] — the host's registered
 * `CarContentProvider`, reached over the car engine — so the tree is the host's
 * whole library (tabs, containers, books), not just the open publication. Rows
 * map to media3 items via [NodeBrowseTree]. [publicationProvider] is used only
 * for the now-playing audiobook: picking one of its chapters seeks the loaded
 * timeline instead of replacing the playlist.
 */
@UnstableApi
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class PluginLibrarySessionCallback(
    private val sourceProvider: () -> CarContentSource?,
    private val publicationProvider: () -> Publication?,
) : MediaLibrarySession.Callback {

    val commandButtons: List<CommandButton> =
        NotificationPlayerCustomCommandButton.entries.map { it.commandButton }

    override fun onConnect(
        session: MediaSession,
        controller: MediaSession.ControllerInfo
    ): MediaSession.ConnectionResult {
        val connectionResult = super.onConnect(session, controller)
        val availableSessionCommands = connectionResult.availableSessionCommands.buildUpon()

        /* Registering custom player command buttons for player notification. */
        commandButtons.forEach { commandButton ->
            commandButton.sessionCommand?.let(availableSessionCommands::add)
        }

        return MediaSession.ConnectionResult.accept(
            availableSessionCommands.build(),
            connectionResult.availablePlayerCommands,
        )
    }

    override fun onPostConnect(session: MediaSession, controller: MediaSession.ControllerInfo) {
        super.onPostConnect(session, controller)
        if (commandButtons.isNotEmpty()) {
            /* Setting custom player command buttons to mediaLibrarySession for player notification. */
            /* Set media-button preferences, so that skip buttons are replaces with seek */
            session.setCustomLayout(commandButtons)
            session.setMediaButtonPreferences(commandButtons)
        }
    }

    override fun onCustomCommand(
        session: MediaSession,
        controller: MediaSession.ControllerInfo,
        customCommand: SessionCommand,
        args: Bundle
    ): ListenableFuture<SessionResult> {
        /* Handle custom command buttons from player notification. */
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.REWIND.customAction) {
            CoroutineScope(Dispatchers.Main).async {
                ReadiumReader.previous()
            }
        }
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.FORWARD.customAction) {
            CoroutineScope(Dispatchers.Main).async {
                ReadiumReader.next()
            }
        }
        if (customCommand.customAction == NotificationPlayerCustomCommandButton.BOOKMARK.customAction) {
            sourceProvider()?.addBookmark()
        }
        return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
    }

    /* --- Android Auto browse tree + search --- */

    override fun onGetLibraryRoot(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        params: LibraryParams?
    ): ListenableFuture<LibraryResult<MediaItem>> =
        Futures.immediateFuture(LibraryResult.ofItem(NodeBrowseTree.rootItem(null), params))

    override fun onGetChildren(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        parentId: String,
        page: Int,
        pageSize: Int,
        params: LibraryParams?
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        val source = sourceProvider() ?: return immediateItemList(emptyList(), params)
        return if (parentId == NodeBrowseTree.ROOT_ID) {
            rootChildren(source, params)
        } else {
            Futures.transform(
                source.children(parentId),
                { nodes -> itemListResult(NodeBrowseTree.nodeItems(nodes), params) },
                MoreExecutors.directExecutor(),
            )
        }
    }

    /**
     * The root's children are the provider's tabs. An empty tree shows a single
     * non-selectable status row from the host's strings (so the head unit shows
     * "nothing here" copy, not a blank screen), or nothing when no strings are
     * registered.
     */
    private fun rootChildren(
        source: CarContentSource,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
        Futures.transformAsync(
            source.rootTabs(),
            { tabs ->
                if (!tabs.isNullOrEmpty()) {
                    Futures.immediateFuture(itemListResult(NodeBrowseTree.tabItems(tabs), params))
                } else {
                    Futures.transform(
                        source.strings(),
                        { strings ->
                            val items = strings?.let {
                                listOf(NodeBrowseTree.statusItem(it.emptyRootTitle, it.emptyRootSubtitle))
                            } ?: emptyList()
                            itemListResult(items, params)
                        },
                        MoreExecutors.directExecutor(),
                    )
                }
            },
            MoreExecutors.directExecutor(),
        )

    override fun onSearch(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        query: String,
        params: LibraryParams?
    ): ListenableFuture<LibraryResult<Void>> {
        val source = sourceProvider() ?: return Futures.immediateFuture(LibraryResult.ofVoid())
        return Futures.transform(
            source.search(query),
            { nodes ->
                session.notifySearchResultChanged(browser, query, nodes.size, params)
                LibraryResult.ofVoid()
            },
            MoreExecutors.directExecutor(),
        )
    }

    override fun onGetSearchResult(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        query: String,
        page: Int,
        pageSize: Int,
        params: LibraryParams?
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
        val source = sourceProvider() ?: return immediateItemList(emptyList(), params)
        return Futures.transform(
            source.search(query),
            { nodes -> itemListResult(NodeBrowseTree.nodeItems(nodes), params) },
            MoreExecutors.directExecutor(),
        )
    }

    /* --- Browse refresh: track subscribers, re-notify on refreshCarContent --- */

    private data class Subscription(
        val controller: MediaSession.ControllerInfo,
        val parentId: String,
        val params: LibraryParams?,
    )

    private val subscriptionsLock = Any()
    private val subscriptions = mutableSetOf<Subscription>()

    override fun onSubscribe(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        parentId: String,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<Void>> {
        synchronized(subscriptionsLock) {
            // Last write wins per (controller, parentId): a re-subscribe replaces
            // its params instead of accumulating a duplicate record.
            subscriptions.removeAll { it.controller == browser && it.parentId == parentId }
            subscriptions.add(Subscription(browser, parentId, params))
        }
        return super.onSubscribe(session, browser, parentId, params)
    }

    override fun onUnsubscribe(
        session: MediaLibrarySession,
        browser: MediaSession.ControllerInfo,
        parentId: String,
    ): ListenableFuture<LibraryResult<Void>> {
        synchronized(subscriptionsLock) {
            subscriptions.removeAll { it.controller == browser && it.parentId == parentId }
        }
        return super.onUnsubscribe(session, browser, parentId)
    }

    override fun onDisconnected(session: MediaSession, controller: MediaSession.ControllerInfo) {
        // A controller can drop without unsubscribing — drop its records so a
        // later refresh neither leaks nor notifies a gone controller.
        synchronized(subscriptionsLock) {
            subscriptions.removeAll { it.controller == controller }
        }
        super.onDisconnected(session, controller)
    }

    /**
     * Re-notifies each subscribed controller so Android Auto re-queries its
     * parent. Invoked on `refreshCarContent`. The child count is taken from
     * [onGetChildren] itself, so the notified count matches exactly what a
     * re-query returns — including the empty-state status row and the dropped
     * `siri` nodes. Each subscription is notified when its own count resolves,
     * via the per-controller `notifyChildrenChanged` overload so every
     * subscriber keeps its own [LibraryParams]. [isActive] is re-checked when each
     * deferred count resolves, so a session released mid-refresh is not notified.
     * Must run on the session's application (main) looper;
     * [PluginMediaService.refreshBrowse] posts it there.
     */
    fun notifySubscribedParents(session: MediaLibrarySession, isActive: () -> Boolean) {
        if (sourceProvider() == null) return
        val current = synchronized(subscriptionsLock) { subscriptions.toList() }
        current.forEach { sub ->
            val countFuture: ListenableFuture<Int> =
                Futures.transform(
                    onGetChildren(session, sub.controller, sub.parentId, 0, Int.MAX_VALUE, sub.params),
                    { it?.value?.size ?: 0 },
                    MoreExecutors.directExecutor(),
                )
            Futures.addCallback(
                countFuture,
                object : FutureCallback<Int> {
                    override fun onSuccess(result: Int) {
                        // The count fetch is async; if the session was released while it
                        // was in flight, isActive() is false, so skip rather than touch a
                        // dead session. Both run on the main looper, so this is race-free.
                        if (isActive()) {
                            session.notifyChildrenChanged(sub.controller, sub.parentId, result, sub.params)
                        }
                    }

                    override fun onFailure(t: Throwable) {
                        // Skip this parent when its children can't be fetched.
                    }
                },
                MoreExecutors.directExecutor(),
            )
        }
    }

    /**
     * A head unit "plays" a browse row by setting it as the media items. For a
     * chapter of the now-playing audiobook, keep the loaded timeline and seek to
     * its index (the same navigator the in-app controls drive). Any other row is
     * a library node — forward it to the provider to start playback.
     */
    override fun onSetMediaItems(
        mediaSession: MediaSession,
        controller: MediaSession.ControllerInfo,
        mediaItems: MutableList<MediaItem>,
        startIndex: Int,
        startPositionMs: Long
    ): ListenableFuture<MediaSession.MediaItemsWithStartPosition> {
        val tree = publicationProvider()?.let { AudiobookBrowseTree(it) }
        val chapterIndex = tree?.let { t ->
            mediaItems.firstNotNullOfOrNull { t.chapterIndexForId(it.mediaId) }
        }
        if (chapterIndex != null) {
            val player = mediaSession.player
            val currentItems = (0 until player.mediaItemCount).map { player.getMediaItemAt(it) }
            return Futures.immediateFuture(
                MediaSession.MediaItemsWithStartPosition(currentItems, chapterIndex, 0L)
            )
        }
        sourceProvider()?.let { source ->
            mediaItems.firstOrNull()?.let { source.play(it.mediaId) }
        }
        return Futures.immediateFuture(
            MediaSession.MediaItemsWithStartPosition(mediaItems, startIndex, startPositionMs)
        )
    }

    private fun itemListResult(
        items: List<MediaItem>,
        params: LibraryParams?,
    ): LibraryResult<ImmutableList<MediaItem>> =
        LibraryResult.ofItemList(ImmutableList.copyOf(items), params)

    private fun immediateItemList(
        items: List<MediaItem>,
        params: LibraryParams?,
    ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
        Futures.immediateFuture(itemListResult(items, params))
}
