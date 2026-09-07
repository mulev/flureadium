package dev.mulev.flureadium

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * An audio navigator must be assigned to its field before `initNavigator()` runs.
 *
 * `AudiobookNavigator.initNavigator` resolves missing track durations off the main
 * thread, so it suspends — for a 246-track streamed book, for as long as those
 * requests take. Anything arriving on the reader in that window runs against the
 * field as it is: `stop()`, `audioDisable()` and a second `audioEnable()` all call
 * `audiobookNavigator?.release()`.
 *
 * Written as `field = Navigator(...).apply { initNavigator() }`, the assignment
 * happens only after `initNavigator()` returns. The field stays null for the whole
 * suspension, so a concurrent teardown releases nothing and the init still in
 * flight then installs a live AudioNavigator, media service and MediaSession into a
 * reader that was already told to stop.
 *
 * Publishing the field is necessary but not sufficient, and the other half lives in
 * `AudiobookNavigator.initNavigator` rather than here: the duration probe runs
 * inside `mainScope`, so `dispose()`'s `cancelChildren()` reaches it. Probed on the
 * caller's coroutine it was outside that scope, and `cancelChildren()` does not
 * cancel the scope's own Job, so a release() arriving mid-probe cancelled nothing.
 *
 * This was all safe until durations moved off the main thread: `initNavigator()`
 * held the looper, so nothing could interleave. It is not safe now, and the shape
 * that caused it is invisible at a glance — hence this test.
 *
 * Only the audio navigators probe durations, so only they are checked here. EPUB,
 * PDF, image and TTS still use `.apply { initNavigator() }`; whether any of them
 * suspends before publishing is a separate question this test makes no claim about.
 */
internal class AudioNavigatorPublishOrderConventionTest {

    /** A call with no receiver, so it runs inside an `apply`/`run` scope. */
    private val bareInitNavigator = Regex("""(^|[^.\w])initNavigator\(\)""")

    @Test
    fun audioNavigatorsArePublishedBeforeInitNavigatorRuns() {
        val sourceRoot = mainSourceRoot()
        val sources = sourceRoot.walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue(sources.isNotEmpty(), "found no Kotlin sources under ${sourceRoot.absolutePath}")

        val offenders = sources.flatMap { file -> unpublishedAudioInitsIn(file) }

        assertTrue(
            offenders.isEmpty(),
            "audio navigators whose initNavigator() runs before the field is assigned — " +
                "assign the field, then call initNavigator() on it:\n" +
                offenders.joinToString("\n") { "  $it" },
        )
    }

    /**
     * Bare `initNavigator()` calls in [file] whose enclosing construction names an
     * audio navigator. `SyncAudiobookNavigator` contains `AudiobookNavigator`, so
     * one needle catches both.
     */
    private fun unpublishedAudioInitsIn(file: File): List<String> {
        val lines = file.readLines()
        return lines.indices
            .filter { bareInitNavigator.containsMatchIn(lines[it]) }
            .filter { index -> constructsAudioNavigatorAbove(lines, index) }
            .map { index -> "${file.name}:${index + 1}: ${lines[index].trim()}" }
    }

    /**
     * Whether the statement the call at [index] belongs to constructs an audio
     * navigator. The construction can wrap over several lines, so the search walks
     * back to the line that opened the expression.
     */
    private fun constructsAudioNavigatorAbove(lines: List<String>, index: Int): Boolean =
        (index - 1 downTo maxOf(0, index - LOOKBEHIND)).asSequence()
            .map { lines[it] }
            .takeWhile { "=" !in it || "AudiobookNavigator" in it }
            .any { "AudiobookNavigator" in it }

    private fun mainSourceRoot(): File {
        val start = File("").absoluteFile
        return generateSequence(start) { it.parentFile }
            .map { File(it, "src/main/kotlin") }
            .firstOrNull { it.isDirectory }
            ?: error("cannot locate src/main/kotlin from $start")
    }

    private companion object {
        /** Longest audio-navigator construction in the plugin spans 5 lines; 8 is slack. */
        const val LOOKBEHIND = 8
    }
}
