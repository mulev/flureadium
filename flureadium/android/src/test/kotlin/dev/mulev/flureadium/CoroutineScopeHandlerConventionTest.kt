package dev.mulev.flureadium

import java.io.File
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * Every coroutine scope in the plugin must say what happens when one of its
 * root coroutines throws.
 *
 * A scope built on a SupervisorJob treats its direct children as root
 * coroutines: a throw goes to the CoroutineExceptionHandler in the context, and
 * with none installed it reaches the thread's uncaught handler, which on Android
 * kills the process. That is the failure flureadium-2xw fixed for the three
 * reader scopes, and this test is what stops the fourth scope from being written
 * without one.
 *
 * A scope passes by carrying a handler, or by carrying a `// no-handler:` comment
 * that says why it does not need one. Both are visible at the construction site,
 * which is the only place a reader of that code will look.
 */
internal class CoroutineScopeHandlerConventionTest {

    private val scopeConstruction = Regex("""\b(?:CoroutineScope|MainScope)\(""")

    @Test
    fun everyCoroutineScopeReportsOrSaysWhyItDoesNot() {
        val sourceRoot = mainSourceRoot()
        val sources = sourceRoot.walkTopDown().filter { it.extension == "kt" }.toList()
        assertTrue(sources.isNotEmpty(), "found no Kotlin sources under ${sourceRoot.absolutePath}")

        val offenders = sources.flatMap { file -> bareScopesIn(file) }

        assertTrue(
            offenders.isEmpty(),
            "coroutine scopes with neither a CoroutineExceptionHandler nor a `// no-handler:` reason:\n" +
                offenders.joinToString("\n") { "  $it" },
        )
    }

    /** Scope constructions in [file] that neither install a handler nor explain themselves. */
    private fun bareScopesIn(file: File): List<String> {
        val lines = file.readLines()
        return lines.indices
            .filter { scopeConstruction.containsMatchIn(lines[it]) }
            .filterNot { index -> installsHandler(lines, index) }
            .filterNot { index -> waiverFor(lines, index) }
            .map { index -> "${file.name}:${index + 1}: ${lines[index].trim()}" }
    }

    /**
     * Whether the construction starting on [index] names a handler. The expression
     * can wrap over several lines, so the search runs until the parentheses opened
     * on that line balance again.
     */
    private fun installsHandler(lines: List<String>, index: Int): Boolean {
        var depth = 0
        for (line in lines.subList(index, lines.size)) {
            if ("ExceptionHandler" in line) return true
            depth += line.count { it == '(' } - line.count { it == ')' }
            if (depth <= 0) return false
        }
        return false
    }

    /** A `// no-handler:` reason on the construction line or in the comment block above it. */
    private fun waiverFor(lines: List<String>, index: Int): Boolean =
        "no-handler:" in lines[index] || commentBlockAbove(lines, index).any { "no-handler:" in it }

    /** The contiguous run of comment lines immediately above [index]. */
    private fun commentBlockAbove(lines: List<String>, index: Int): Sequence<String> =
        (index - 1 downTo 0).asSequence()
            .map { lines[it] }
            .takeWhile { it.trimStart().startsWith("//") }

    private fun mainSourceRoot(): File {
        val start = File("").absoluteFile
        return generateSequence(start) { it.parentFile }
            .map { File(it, "src/main/kotlin") }
            .firstOrNull { it.isDirectory }
            ?: error("cannot locate src/main/kotlin from $start")
    }
}
