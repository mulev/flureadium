package dev.mulev.flureadium.car

import com.google.common.util.concurrent.ListenableFuture

/**
 * The mechanism-neutral seam the Android Auto browse callback pulls car content
 * from. It mirrors the iOS `CarPlayContentBridging` protocol: the callback maps
 * whatever this returns into media3 items, without knowing whether the answer
 * came over a method channel, a cache, or a test stub.
 *
 * List calls return [ListenableFuture]s so the media3 callbacks can hand them
 * back directly and complete when the host answers — the cold-launch path from
 * the ADR (headless engine + channel that may still be starting).
 */
interface CarContentSource {
    /** The root tabs (Continue / Library / Search). */
    fun rootTabs(): ListenableFuture<List<CarTab>>

    /** The rows nested under [nodeId] (a tab id or a container node id). */
    fun children(nodeId: String): ListenableFuture<List<CarBrowseNode>>

    /** The rows matching [query] across the host's library. */
    fun search(query: String): ListenableFuture<List<CarBrowseNode>>

    /** The host's localized status strings, or null when none are registered. */
    fun strings(): ListenableFuture<CarContentStrings?>

    /** Forwards a playable-row selection to the host (→ provider `play`). */
    fun play(nodeId: String)
}
