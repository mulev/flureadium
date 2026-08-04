package dev.mulev.flureadium

import java.lang.reflect.Field

/**
 * Reflective access to ReadiumReader's private state, shared by the JVM suite.
 *
 * ReadiumReader is an object with no test seam: its navigators, event channels
 * and current publication are private, and the only public way to populate them
 * is to open a real publication on a device. Seeding those fields directly is
 * what keeps the reader tests on Robolectric, and this file is the one place
 * that knows how.
 *
 * Anything seeded here must be cleared again in the test's teardown — the
 * fields belong to a singleton that outlives each test class.
 */
internal fun setReaderField(name: String, value: Any?) {
    readerField(name).set(ReadiumReader, value)
}

internal fun getReaderField(name: String): Any? = readerField(name).get(ReadiumReader)

private fun readerField(name: String): Field =
    ReadiumReader::class.java.getDeclaredField(name).apply { isAccessible = true }
