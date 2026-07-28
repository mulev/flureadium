package dev.mulev.flureadium.car

/**
 * Host-supplied, already-localized status strings the car browse tree shows
 * verbatim; flureadium owns none of this copy. Decoded from the transport
 * `strings` map. [fromMap] returns null when any field is missing or blank, so a
 * caller falls back to a plain placeholder rather than showing an empty label.
 */
data class CarContentStrings(
    val emptyRootTitle: String,
    val emptyRootSubtitle: String,
    val voiceUnavailable: String,
    val offline: String,
) {
    companion object {
        /** Decodes the strings from their transport map, or null when incomplete. */
        fun fromMap(map: Map<*, *>): CarContentStrings? {
            val emptyRootTitle = nonEmpty(map, "emptyRootTitle") ?: return null
            val emptyRootSubtitle = nonEmpty(map, "emptyRootSubtitle") ?: return null
            val voiceUnavailable = nonEmpty(map, "voiceUnavailable") ?: return null
            val offline = nonEmpty(map, "offline") ?: return null
            return CarContentStrings(
                emptyRootTitle = emptyRootTitle,
                emptyRootSubtitle = emptyRootSubtitle,
                voiceUnavailable = voiceUnavailable,
                offline = offline,
            )
        }

        private fun nonEmpty(map: Map<*, *>, key: String): String? =
            (map[key] as? String)?.takeIf { it.isNotEmpty() }
    }
}
