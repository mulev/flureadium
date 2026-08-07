@file:OptIn(ExperimentalReadiumApi::class)

package dev.mulev.flureadium

import android.speech.tts.TextToSpeech
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import org.json.JSONObject
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.fromLegacyHref
import org.readium.r2.shared.util.getOrElse
import kotlin.time.Duration

private const val TAG = "PublicationChannel"

/**
 * Runs a method-channel [block] and maps its outcome onto this result.
 *
 * [CancellationException] is re-thrown rather than reported: a coroutine torn
 * down mid-call — e.g. a `play` still suspended on a [kotlinx.coroutines.Deferred]
 * when the publication closes — must unwind normally, not surface to Dart as a
 * spurious `PlatformException(JobCancellationException ...)`.
 */
@OptIn(InternalReadiumApi::class)
internal suspend fun MethodChannel.Result.dispatchGuarded(
    method: String,
    block: suspend () -> Try<Any?, PublicationError>
) {
    try {
        val res = block().getOrElse { error ->
            publicationError(method, error)
            return
        }
        if (res is Unit) success(null) else success(res)
    } catch (e: CancellationException) {
        throw e
    } catch (_: NotImplementedError) {
        notImplemented()
    } catch (e: Exception) {
        Log.e(TAG, "Exception: $e")
        error(e.javaClass.toString(), e.toString(), e.stackTraceToString())
    }
}

internal const val publicationChannelName = "dev.mulev.flureadium/main"

@ExperimentalCoroutinesApi
internal class PublicationMethodCallHandler(
    private val refreshCarContent: () -> Unit = { PluginMediaService.instance?.refreshBrowse() },
) :
    MethodChannel.MethodCallHandler {

    @OptIn(InternalReadiumApi::class, ExperimentalReadiumApi::class)
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // no-handler: the body is one dispatchGuarded call, which catches every
        // exception and answers with result.error, so nothing escapes this
        // coroutine to the thread's uncaught handler.
        CoroutineScope(Dispatchers.IO).launch {
            result.dispatchGuarded(call.method) {
                handleMethodCallsQueue(call.method, call.arguments)
            }
        }
    }

    /**
     * This function can be used to handle method calls sequentially if needed.
     */
    internal suspend fun handleMethodCallsQueue(
        method: String,
        arguments: Any?
    ): Try<Any?, PublicationError> {
        when (method) {
            "setCustomHeaders" -> {
                @Suppress("UNCHECKED_CAST")
                val args = arguments as? Map<String, Map<String, String>> ?: emptyMap()
                val httpHeaders = args["httpHeaders"] ?: emptyMap()

                ReadiumReader.setDefaultHttpHeaders(httpHeaders)
                return Try.success(null)
            }

            "refreshCarContent" -> {
                refreshCarContent()
                return Try.success(null)
            }

            "loadPublication" -> {
                val args = arguments as List<Any?>
                val pubUrlStr = args[0] as String
                return loadPublication(pubUrlStr)
            }

            "openPublication" -> {
                val args = arguments as List<Any?>
                val pubUrlStr = args[0] as String

                return openPublication(pubUrlStr)
            }

            "closePublication" -> {
                Log.d(TAG, "Close publication")

                ReadiumReader.closePublication()
                return Try.success(null)
            }

            "ttsEnable" -> {
                val args = arguments as List<*>
                val ttsPrefs = FlutterTtsPreferences.fromMap(args[0] as Map<*, *>?)
                val locator = (args[1] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }
                return ttsEnable(locator, ttsPrefs)
            }

            "ttsSetPreferences" -> {
                val args = arguments as Map<*, *>?
                val ttsPrefs = FlutterTtsPreferences.fromMap(args)

                return ttsSetPreferences(ttsPrefs)
            }

            "setDecorationStyle" -> {
                val args = arguments as List<*>
                val uttDecoMap = args[0] as Map<*, *>?
                val rangeDecoMap = args[1] as Map<*, *>?
                val decorationPreferences = FlutterDecorationPreferences.fromMap(uttDecoMap, rangeDecoMap)

                return setDecorationStyle(decorationPreferences)
            }

            "ttsCanSpeak" -> {
                return Try.success(ReadiumReader.ttsCanSpeak())
            }

            "ttsRequestInstallVoice" -> {
                ReadiumReader.ttsRequestInstallVoice()
                return Try.success(null)
            }

            "ttsGetAvailableVoices" -> {
                return Try.success(ttsGetAvailableVoices())
            }

            "ttsGetSystemVoices" -> {
                return Try.success(ttsGetSystemVoices())
            }

            "ttsSetVoice" -> {
                val args = arguments as List<*>
                val voiceId = args[0] as String?
                val language = args[1] as String?

                ReadiumReader.ttsSetPreferredVoice(voiceId, language)

                return Try.success(null)
            }

            "play" -> {
                val args = arguments as List<*>
                val fromLocator = (args[0] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }

                ReadiumReader.play(fromLocator)

                return Try.success(null)
            }

            "pause" -> {
                ReadiumReader.pause()

                return Try.success(null)
            }

            "resume" -> {
                ReadiumReader.resume()

                return Try.success(null)
            }

            "stop" -> {
                ReadiumReader.stop()

                return Try.success(null)
            }

            "next" -> {
                ReadiumReader.next()

                return Try.success(null)
            }

            "previous" -> {
                ReadiumReader.previous()

                return Try.success(null)
            }

            "goToLocator" -> {
                val args = arguments as List<*>
                val locator = (args[0] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }

                if (locator == null) {
                    throw Exception("goToLocator: failed to go to locator. Missing locator: ${args[0]} ")
                }

                val navigated = ReadiumReader.goToLocator(locator)

                return Try.success(navigated)
            }

            "getLinkContent" -> {
                val args = arguments as List<Any?>
                val linkStr = args[0] as String
                val asString = args[1] as? Boolean ?: true
                val link = Link.fromJSON(JSONObject(linkStr))

                if (link == null) {
                    throw Exception("getLinkContent: failed to get resource. Missing link: $link")
                }

                return getLinkContent(link, asString)
            }

            "audioEnable" -> {
                val args = arguments as List<*>
                // 0 is AudioPreferences
                val prefs = args[0] as Map<*, *>?

                val preferences = prefs?.let { FlutterAudioPreferences.fromMap(it) }
                    ?: FlutterAudioPreferences()

                val locator = (args[1] as? Map<*, *>)?.let {
                    Locator.fromJSON(JSONObject(it))
                }

                return audioEnable(locator, preferences)
            }

            "audioSetPreferences" -> {
                val prefs = arguments as Map<*, *>?
                val preferences =
                    prefs?.let { FlutterAudioPreferences.fromMap(it) }
                        ?: FlutterAudioPreferences()

                ReadiumReader.audioUpdatePreferences(preferences)

                return Try.success(null)
            }

            "audioSeekBy" -> {
                val seekOffsetSeconds = arguments as Int
                ReadiumReader.audioSeek(seekOffsetSeconds.toDouble())
                return Try.success(null)
            }

            "renderFirstPage" -> {
                val args = arguments as List<Any?>
                val pubUrlStr = args[0] as String
                val maxWidth = args[1] as Int
                val maxHeight = args[2] as Int
                return renderFirstPage(pubUrlStr, maxWidth, maxHeight)
            }

            "extractPageThumbnail" -> {
                val args = arguments as List<Any?>
                val href = args[0] as String
                val maxHeight = args[1] as Int
                val quality = args[2] as Int
                return extractPageThumbnail(href, maxHeight, quality)
            }

            else -> {
                throw NotImplementedError()
            }
        }
    }

    /**
     * Load and return the publication manifest from a URL without opening it.
     */
    private suspend fun loadPublication(pubUrlStr: String): Try<String, PublicationError> {
        val publication =
            ReadiumReader.loadPublicationFromUrl(pubUrlStr).getOrElse { error ->
                return Try.failure(error)
            }

        val pubJsonManifest =
            publication.manifest.toJSON().toString().replace("\\/", "/")

        // Close the publication to avoid leaks.
        publication.close()
        return Try.success(pubJsonManifest)
    }

    /**
     * Open a publication from a URL. If another publication is already opened, it will be closed first.
     *
     * There can be only one... opened publication at a time.
     */
    private suspend fun openPublication(pubUrlStr: String): Try<String, PublicationError> {
        val publication =
            ReadiumReader.openPublicationFromUrl(pubUrlStr).getOrElse { error ->
                return Try.failure(error)
            }

        val pubJsonManifest =
            publication.manifest.toJSON().toString().replace("\\/", "/")

        return Try.success(pubJsonManifest)
    }

    /**
     * Enable TTS reading with the provided preferences.
     */
    private suspend fun ttsEnable(
        locator: Locator?,
        prefs: FlutterTtsPreferences
    ): Try<Any?, PublicationError> {
        val publication = ReadiumReader.currentPublication
        if (publication == null) {
            return Try.failure(
                PublicationError.Unavailable()
            )
        }

        ReadiumReader.ttsEnable(locator, prefs)
        return Try.success(null)
    }

    /**
     * Update the TTS preferences. The TTS must be enabled first.
     */
    private suspend fun ttsSetPreferences(ttsPrefs: FlutterTtsPreferences): Try<Any?, PublicationError> {
        val publication = ReadiumReader.currentPublication
        if (publication == null) {
            return Try.failure(
                PublicationError.Unavailable()
            )
        }

        ReadiumReader.ttsSetPreferences(ttsPrefs)
        return Try.success(null)
    }

    suspend fun setDecorationStyle(
        decorationPreferences: FlutterDecorationPreferences
    ): Try<Any?, PublicationError> {
        try {
            ReadiumReader.setDecorationStyle(decorationPreferences)
            return Try.success(null)
        } catch (_: Error) {
            return Try.failure(PublicationError.Unknown("Failed to set decoration style"))
        }
    }

    /**
     * Get the list of available TTS voices on the device.
     */
    fun ttsGetAvailableVoices(): List<String> {
        val androidVoices = ReadiumReader.ttsGetAvailableVoices()
        if (androidVoices == null) {
            return listOf()
        }

        val voicesJson = androidVoices.map {
            JSONObject().apply {
                put("identifier", it.id.value)
                put(
                    "name",
                    it.id.value
                ) // ID should be mapped to a readable name on Flutter side.
                put("quality", it.quality.name.lowercase())
                put("requiresNetwork", it.requiresNetwork)
                put("language", it.language.code)
            }.toString()
        }

        return voicesJson
    }

    /**
     * Get the list of TTS voices from the OS without requiring a TTS navigator.
     */
    private suspend fun ttsGetSystemVoices(): List<String> {
        val context = ReadiumReader.application.applicationContext
        return suspendCancellableCoroutine { cont ->
            var tts: TextToSpeech? = null
            tts = TextToSpeech(context) { status ->
                if (status == TextToSpeech.SUCCESS) {
                    val voices = tts?.voices ?: emptySet()
                    val json = voices.map { voice ->
                        JSONObject().apply {
                            put("identifier", voice.name)
                            put("name", voice.name)
                            put("quality", if (voice.quality >= android.speech.tts.Voice.QUALITY_HIGH) "high" else "normal")
                            put("requiresNetwork", voice.isNetworkConnectionRequired)
                            put("language", voice.locale.toLanguageTag())
                        }.toString()
                    }
                    tts?.shutdown()
                    cont.resume(json)
                } else {
                    tts?.shutdown()
                    cont.resume(listOf())
                }
            }
            cont.invokeOnCancellation { tts?.shutdown() }
        }
    }

    /**
     * Get the content of a publication resource via a Link.
     * If asString is true the content is returned as a String, otherwise as ByteArray
     */
    private suspend fun getLinkContent(link: Link, asString: Boolean): Try<Any, PublicationError> {
        val publication = ReadiumReader.currentPublication
            ?: return Try.failure(
                PublicationError.Unavailable()
            )

        Log.d(TAG, "Use publication = $publication")

        val resource = publication.get(link) ?: run {
            throw Exception("getLinkContent: failed to find pub resource via link: pubId=${publication.metadata.identifier},link=$link")
        }
        val resourceBytes = resource.read().getOrElse {
            throw Exception("getLinkContent: failed to read resource. ${it.message}")
        }

        return Try.success(if (asString) String(resourceBytes) else resourceBytes)
    }

    /**
     * Enable audio (audiobook) reading with optional locator to start from and audio preferences.
     */
    private suspend fun audioEnable(
        locator: Locator?,
        preferences: FlutterAudioPreferences
    ): Try<Any?, PublicationError> {
        val publication = ReadiumReader.currentPublication
        if (publication == null) {
            return Try.failure(
                PublicationError.Unavailable()
            )
        }

        ReadiumReader.audioEnable(locator, preferences)
        return Try.success(null)
    }

    /**
     * Extract a downscaled JPEG thumbnail from the resource at [href] in the open publication.
     * Returns null if no publication is open, the resource is missing/unreadable, or decode fails.
     */
    private suspend fun extractPageThumbnail(
        href: String,
        maxHeight: Int,
        quality: Int,
    ): Try<ByteArray?, PublicationError> {
        val publication = ReadiumReader.currentPublication
            ?: return Try.success(null)
        // Use fromLegacyHref to match iOS AnyURL(legacyHREF:) — strips a
        // leading '/' the Dart Publication.fromJson normalizer adds and
        // percent-encodes the path before container lookup.
        val url = Url.fromLegacyHref(href) ?: return Try.success(null)
        val resource = publication.get(url) ?: return Try.success(null)
        val resourceBytes = resource.read().getOrElse { return Try.success(null) }
        return Try.success(PageThumbnailExtractor.extract(resourceBytes, maxHeight, quality))
    }

    /**
     * Render the first page of a PDF file as a JPEG image.
     * Uses Android's PdfRenderer (available since API 21).
     * Returns null if the file doesn't exist or rendering fails.
     */
    private fun renderFirstPage(
        pubUrlStr: String,
        maxWidth: Int,
        maxHeight: Int
    ): Try<ByteArray?, PublicationError> {
        val filePath = pubUrlStr.removePrefix("file://")
        val file = java.io.File(filePath)
        if (!file.exists()) {
            Log.w(TAG, "File not found for renderFirstPage: $filePath")
            return Try.success(null)
        }

        return try {
            val fd = android.os.ParcelFileDescriptor.open(
                file,
                android.os.ParcelFileDescriptor.MODE_READ_ONLY
            )
            val renderer = android.graphics.pdf.PdfRenderer(fd)
            val page = renderer.openPage(0)

            val scale = minOf(
                maxWidth.toFloat() / page.width,
                maxHeight.toFloat() / page.height,
                1f
            )
            val width = (page.width * scale).toInt()
            val height = (page.height * scale).toInt()

            val bitmap = android.graphics.Bitmap.createBitmap(
                width,
                height,
                android.graphics.Bitmap.Config.ARGB_8888
            )
            bitmap.eraseColor(android.graphics.Color.WHITE)
            page.render(
                bitmap,
                null,
                null,
                android.graphics.pdf.PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
            )

            page.close()
            renderer.close()
            fd.close()

            val stream = java.io.ByteArrayOutputStream()
            bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, stream)
            bitmap.recycle()

            Try.success(stream.toByteArray())
        } catch (e: Exception) {
            Log.e(TAG, "Failed to render first page: $e")
            Try.success(null)
        }
    }
}

/**
 * Send a PublicationError back to Flutter via MethodChannel.Result
 */
fun MethodChannel.Result.publicationError(method: String, error: PublicationError) {
    Log.e(
        TAG,
        "$method: PublicationError<${error.errorCode}>: ${error.message}, cause=${error.cause}"
    )

    this.error(
        error.errorCode.name,
        error.message,
        error.cause?.toString()
    )
}
