package dev.mulev.flureadium

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import java.io.File

/**
 * Guards the [PluginMediaService] intent-filter contract in the shipped source manifest.
 *
 * Android Auto connects as a platform `MediaBrowser` client and enumerates media apps by the
 * presence of the legacy `android.media.browse.MediaBrowserService` action. Without it the app
 * is never listed, even though media3's `MediaLibraryService` already bridges to the legacy
 * `MediaBrowserServiceCompat` interface at runtime. This reads the raw source manifest (not a
 * merged/Robolectric manifest) so it asserts what actually ships to consumers.
 */
internal class PluginMediaServiceManifestTest {

    private val manifest = File("src/main/AndroidManifest.xml").readText()

    @Test
    fun advertisesLegacyMediaBrowserServiceForAndroidAuto() {
        assertTrue(
            manifest.contains("android.media.browse.MediaBrowserService"),
            "PluginMediaService must advertise android.media.browse.MediaBrowserService " +
                "so Android Auto can discover it as a browsable media app",
        )
    }

    @Test
    fun dropsNonStandardMediaSessionServiceAction() {
        assertFalse(
            manifest.contains("android.media.session.MediaSessionService"),
            "android.media.session.MediaSessionService is not a real platform action " +
                "(a browse/session typo) and must not be declared",
        )
    }
}
