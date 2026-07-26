package dev.mulev.flureadium.car

/**
 * The kind of a car browse row, mirroring the Dart `CarNodeKind`. Entry names
 * match the wire strings the transport sends (`CarNodeKind.name` on the Dart
 * side), so [fromName] can decode them directly.
 */
enum class CarNodeKind {
    tab,
    container,
    audiobook,
    ttsBook,
    chapter,
    siri;

    companion object {
        /** The kind whose name equals [name], or null when unknown/absent. */
        fun fromName(name: String?): CarNodeKind? =
            entries.firstOrNull { it.name == name }
    }
}

/**
 * One browsable or playable row the host's `CarContentProvider` returns over the
 * `dev.mulev.flureadium/car` channel, decoded from its serialized map.
 *
 * A plain value type with no Android or reader dependencies so it is
 * JVM-unit-testable. [fromMap] returns null for a payload missing a required
 * field (id/title/kind) rather than throwing, so a malformed row is dropped from
 * a list instead of failing the whole browse response — matching the iOS
 * bridge's lenient decode.
 */
data class CarBrowseNode(
    val id: String,
    val title: String,
    val subtitle: String?,
    val artworkPath: String?,
    val kind: CarNodeKind,
    val isPlayable: Boolean,
    val progress: Double?,
    val isNowPlaying: Boolean,
) {
    companion object {
        /** Decodes a node from its transport map, or null when it is invalid. */
        fun fromMap(map: Map<*, *>): CarBrowseNode? {
            val id = (map["id"] as? String)?.takeIf { it.isNotEmpty() } ?: return null
            val title = (map["title"] as? String)?.takeIf { it.isNotEmpty() } ?: return null
            val kind = CarNodeKind.fromName(map["kind"] as? String) ?: return null
            return CarBrowseNode(
                id = id,
                title = title,
                subtitle = map["subtitle"] as? String,
                artworkPath = map["artworkPath"] as? String,
                kind = kind,
                isPlayable = (map["isPlayable"] as? Boolean) ?: false,
                progress = (map["progress"] as? Number)?.toDouble(),
                isNowPlaying = (map["isNowPlaying"] as? Boolean) ?: false,
            )
        }
    }
}
