package dev.mulev.flureadium.navigators

/**
 * Reading-order index of the track before [currentHref], or null when [currentHref] is the first
 * track, unknown, or null.
 */
fun previousTrackIndex(trackHrefs: List<String>, currentHref: String?): Int? =
    neighbourTrackIndex(trackHrefs, currentHref, -1)

/**
 * Reading-order index of the track after [currentHref], or null when [currentHref] is the last
 * track, unknown, or null.
 */
fun nextTrackIndex(trackHrefs: List<String>, currentHref: String?): Int? =
    neighbourTrackIndex(trackHrefs, currentHref, 1)

private fun neighbourTrackIndex(trackHrefs: List<String>, currentHref: String?, delta: Int): Int? {
    if (currentHref == null) return null
    val index = trackHrefs.indexOf(currentHref)
    if (index == -1) return null
    val target = index + delta
    return target.takeIf { it in trackHrefs.indices }
}
