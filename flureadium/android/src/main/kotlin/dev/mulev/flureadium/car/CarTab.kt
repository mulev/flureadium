package dev.mulev.flureadium.car

/**
 * One root tab (Continue / Library / Search) the host's `CarContentProvider`
 * returns, decoded from its transport map. A blank id or title would render an
 * unusable row, so [fromMap] rejects those by returning null.
 */
data class CarTab(
    val id: String,
    val title: String,
    val iconName: String?,
) {
    companion object {
        /** Decodes a tab from its transport map, or null when id/title is blank. */
        fun fromMap(map: Map<*, *>): CarTab? {
            val id = (map["id"] as? String)?.takeIf { it.isNotEmpty() } ?: return null
            val title = (map["title"] as? String)?.takeIf { it.isNotEmpty() } ?: return null
            return CarTab(id = id, title = title, iconName = map["iconName"] as? String)
        }
    }
}
