package dev.mulev.flureadium

import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Parcel
import dev.mulev.flureadium.navigators.ImageNavigator
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import org.json.JSONObject
import org.junit.runner.RunWith
import org.readium.r2.navigator.Decoration
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.mockito.Mockito.mock

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.P], manifest = Config.NONE)
@OptIn(ExperimentalCoroutinesApi::class)
internal class ReadiumReaderSavedStateTest {

    @AfterTest
    fun tearDown() {
        ReadiumReader.currentPublicationUrl = null
        ReadiumReader.decorationStyle = FlutterDecorationPreferences()
        setReaderField("imageNavigator", null)
    }

    @Test
    fun storeState_persistsDecorationStyleAsBundle() {
        ReadiumReader.currentPublicationUrl = "https://example.com/book.epub"
        ReadiumReader.decorationStyle = FlutterDecorationPreferences(
            utteranceStyle = Decoration.Style.Underline(tint = Color.GREEN),
            currentRangeStyle = Decoration.Style.Highlight(tint = Color.BLUE)
        )

        val parcel = Parcel.obtain()

        try {
            val savedState = invokeStoreState()
            parcel.writeBundle(savedState)
            parcel.setDataPosition(0)

            val restoredState = parcel.readBundle(javaClass.classLoader)
            val decorationStyleBundle = restoredState?.getBundle("decorationStyle")
            val restoredPreferences = FlutterDecorationPreferences.fromBundle(decorationStyleBundle)

            assertNotNull(decorationStyleBundle)
            assertEquals(
                Color.GREEN,
                assertIs<Decoration.Style.Underline>(restoredPreferences.utteranceStyle).tint
            )
            assertEquals(
                Color.BLUE,
                assertIs<Decoration.Style.Highlight>(restoredPreferences.currentRangeStyle).tint
            )
        } finally {
            parcel.recycle()
        }
    }

    @Test
    fun storeState_persistsImageNavigatorStateAsBundle() {
        ReadiumReader.currentPublicationUrl = "https://example.com/book.cbz"
        val navigator = ImageNavigator(
            mock(Publication::class.java),
            null,
            mock(ImageNavigator.VisualListener::class.java)
        )
        val locator = Locator.fromJSON(
            JSONObject(
                """
                {
                  "href": "images/page-9.jpg",
                  "type": "image/jpeg",
                  "locations": {
                    "progression": 0.9,
                    "position": 9
                  }
                }
                """.trimIndent()
            )
        )!!
        navigator.onJumpToLocator(locator)
        setReaderField("imageNavigator", navigator)

        val savedState = invokeStoreState()
        val imageState = savedState.getBundle("imageState")

        assertEquals(true, savedState.getBoolean("imageEnabled"))
        assertNotNull(imageState)
        assertEquals(locator.toJSON().toString(), imageState.getString("currentVisualCurrentLocator"))
    }

    private fun invokeStoreState(): Bundle {
        val storeState = ReadiumReader::class.java.getDeclaredMethod("storeState")
        storeState.isAccessible = true
        return storeState.invoke(ReadiumReader) as Bundle
    }
}
