package dev.mulev.flureadium

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.util.Log
import android.view.ViewGroup
import androidx.fragment.app.FragmentManager
import androidx.savedstate.SavedStateRegistry
import androidx.savedstate.SavedStateRegistryOwner
import dev.mulev.flureadium.events.EpubIsReadyEventChannel
import dev.mulev.flureadium.events.ErrorEventChannel
import dev.mulev.flureadium.events.ReaderStatusEventChannel
import dev.mulev.flureadium.events.TextLocatorEventChannel
import dev.mulev.flureadium.events.TimedBasedStateEventChannel
import dev.mulev.flureadium.models.ReadiumTimebasedState
import dev.mulev.flureadium.navigators.AudiobookNavigator
import dev.mulev.flureadium.navigators.EpubNavigator
import dev.mulev.flureadium.navigators.ImageNavigator
import dev.mulev.flureadium.navigators.PdfNavigator
import dev.mulev.flureadium.navigators.SyncAudiobookNavigator
import dev.mulev.flureadium.navigators.TTSNavigator
import dev.mulev.flureadium.navigators.TimebasedNavigator
import io.flutter.plugin.common.BinaryMessenger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.readium.navigator.media.tts.android.AndroidTtsEngine
import org.readium.r2.navigator.Decoration
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.publication.allAreHtml
import org.readium.r2.shared.util.AbsoluteUrl
import org.readium.r2.shared.util.DebugError
import org.readium.r2.shared.util.ThrowableError
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Try.Companion.failure
import org.readium.r2.shared.util.Url
import org.readium.r2.shared.util.asset.Asset
import org.readium.r2.shared.util.asset.AssetRetriever
import org.readium.r2.shared.util.getOrElse
import org.readium.r2.shared.util.http.DefaultHttpClient
import org.readium.r2.shared.util.http.HttpRequest
import org.readium.r2.shared.util.http.HttpTry
import org.readium.r2.shared.util.resource.Resource
import org.readium.r2.shared.util.resource.TransformingContainer
import org.readium.adapter.pdfium.document.PdfiumDocumentFactory
import org.readium.r2.streamer.PublicationOpener
import org.readium.r2.streamer.PublicationOpener.OpenError
import org.readium.r2.streamer.parser.DefaultPublicationParser
import java.lang.ref.WeakReference
import kotlin.time.Duration
import kotlin.time.Duration.Companion.milliseconds

private const val TAG = "ReadiumReader"

private const val stateKey = "dev.mulev.flureadium.ReadiumReaderState"

private const val currentPublicationUrlKey = "currentPublicationUrl"
private const val ttsEnabledKey = "ttsEnabled"
private const val audioEnabledKey = "audioEnabled"
private const val syncAudioEnabledKey = "syncAudioEnabled"

private const val epubEnabledKey = "epubEnabled"
private const val ttsNavigatorStateKey = "ttsState"
private const val audioNavigatorStateKey = "audioState"
private const val syncAudioNavigatorStateKey = "syncAudioState"
private const val epubNavigatorStateKey = "epubState"
private const val imageEnabledKey = "imageEnabled"
private const val imageNavigatorStateKey = "imageState"
private const val pdfEnabledKey = "pdfEnabled"
private const val pdfNavigatorStateKey = "pdfState"
private const val decorationStyleKey = "decorationStyle"

// Content files are fetched with defaultHttpHeaders only; per-publication
// authentication headers are not supported.

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
object ReadiumReader : TimebasedNavigator.TimebasedListener, EpubNavigator.VisualListener, ImageNavigator.VisualListener, PdfNavigator.VisualListener {
    private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val jobs = mutableListOf<Job>()

    private var appRef: WeakReference<Application>? = null

    private var timedBasedStateEventChannel: TimedBasedStateEventChannel? = null
    private var readerStatusEventChannel: ReaderStatusEventChannel? = null
    private var errorEventChannel: ErrorEventChannel? = null
    private var textLocatorEventChannel: TextLocatorEventChannel? = null

    private var readerViewRef: WeakReference<ReadiumReaderWidget>? = null

    private var savedStateRef: WeakReference<SavedStateRegistry>? = null

    // in-memory cached state
    private val state = mutableMapOf<String, Any?>()

    private val currentTimebasedState = MutableStateFlow<TimebasedNavigator.TimebasedState?>(null)

    private val currentTimebasedDuration = MutableStateFlow<Double?>(null)

    private val currentTimebasedOffset = MutableStateFlow<Double?>(null)

    private val currentTimebasedBuffer = MutableStateFlow<Long?>(null)

    private val currentTimebasedLocator = MutableStateFlow<Locator?>(null)

    private var defaultHttpHeaders = mutableMapOf<String, String>()

    var ttsErrorType: String? = null

    var decorationStyle: FlutterDecorationPreferences
        get() = state[decorationStyleKey] as? FlutterDecorationPreferences ?: FlutterDecorationPreferences()
        set(value) {
            state[decorationStyleKey] = value
        }

    fun createCurrentTimebasedReaderState(): Flow<ReadiumTimebasedState?> {
        return combine(
            currentTimebasedLocator.throttleLatest(100.milliseconds).distinctUntilChanged(),
            currentTimebasedState.throttleLatest(100.milliseconds).distinctUntilChanged(),
            currentTimebasedOffset.throttleLatest(100.milliseconds).distinctUntilChanged(),
            currentTimebasedBuffer.throttleLatest(250.milliseconds).distinctUntilChanged(),
            currentTimebasedDuration.throttleLatest(100.milliseconds).distinctUntilChanged(),
        ) { locator, state, offset, buffer, duration ->
            if (state == null) {
                return@combine null
            }

            ReadiumTimebasedState(
                locator, state, offset, buffer, duration ?: 0.0,
                ttsErrorType = ttsErrorType
            )
        }.throttleLatest(100.milliseconds).distinctUntilChanged()
    }

    private val httpClient by lazy {
        DefaultHttpClient(callback = object : DefaultHttpClient.Callback {
            override suspend fun onStartRequest(request: HttpRequest): HttpTry<HttpRequest> {
                val requestWithHeaders = request.copy {
                    defaultHttpHeaders.toMap().forEach { (key, value) ->
                        setHeader(key, value)
                    }
                }
                return Try.success(requestWithHeaders)
            }
        })
    }

    private var _assetRetriever: AssetRetriever? = null

    private val assetRetriever: AssetRetriever
        get() {
            if (_assetRetriever == null) {
                _assetRetriever = AssetRetriever(context.contentResolver, httpClient)
            }

            return _assetRetriever!!
        }

    private var _publicationOpener: PublicationOpener? = null

    private var ttsNavigator: TTSNavigator? = null

    private var audiobookNavigator: AudiobookNavigator? = null
    private var syncAudiobookNavigator: SyncAudiobookNavigator? = null

    private var epubNavigator: EpubNavigator? = null

    val epubCurrentLocator: Locator?
        get() = epubNavigator?.currentLocator?.value

    private var imageNavigator: ImageNavigator? = null

    val imageCurrentLocator: Locator?
        get() = imageNavigator?.currentLocator?.value

    private var pdfNavigator: PdfNavigator? = null

    val pdfCurrentLocator: Locator?
        get() = pdfNavigator?.currentLocator?.value

    private var _pdfPreferences: FlutterPdfPreferences = FlutterPdfPreferences()

    /** Current PDF preferences (defaults if PDF hasn't been enabled yet). */
    val pdfPreferences: FlutterPdfPreferences
        get() = _pdfPreferences

    private var _audioPreferences: FlutterAudioPreferences = FlutterAudioPreferences()

    /** Current audio preferences (defaults if audio hasn't been enabled yet). */
    val audioPreferences: FlutterAudioPreferences
        get() = _audioPreferences

    /**
     * The PublicationFactory is used to open publications.
     */
    private val publicationOpener: PublicationOpener
        get() {
            if (_publicationOpener == null) {
                _publicationOpener = PublicationOpener(
                    publicationParser = DefaultPublicationParser(
                        context,
                        assetRetriever = assetRetriever,
                        httpClient = httpClient,
                        // PDF support via PDFium adapter
                        pdfFactory = PdfiumDocumentFactory(context)
                    ),
                )
            }

            return _publicationOpener!!
        }

    /**
     * Seeds the process-wide [Application] reference.
     *
     * Called at engine attach, so a UI-less engine — the Android Auto car
     * engine, a background isolate — reaches application-only APIs without an
     * Activity. [attach] still covers everything the reader widget needs from
     * an Activity.
     */
    fun attachApplication(context: Context) {
        unwrapToApplication(context)?.let { appRef = WeakReference(it) }
    }

    // Initialize the reader session from the host Activity; a headless engine uses attachApplication.
    fun attach(activity: Activity, messenger: BinaryMessenger) {
        attachApplication(activity)

        timedBasedStateEventChannel?.dispose()
        timedBasedStateEventChannel = TimedBasedStateEventChannel(messenger)

        readerStatusEventChannel?.dispose()
        readerStatusEventChannel = ReaderStatusEventChannel(messenger)

        errorEventChannel?.dispose()
        errorEventChannel = ErrorEventChannel(messenger)

        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = TextLocatorEventChannel(messenger)

        // store weak ref only
        (activity as? SavedStateRegistryOwner)?.savedStateRegistry?.let {
            savedStateRef = WeakReference(it)
            it.registerSavedStateProvider(stateKey) {
                storeState()
            }

            restoreState(it.consumeRestoredStateForKey(stateKey))
        }

        createCurrentTimebasedReaderState().onEach {
            Log.d(
                TAG, "currentTimebasedReaderState: ${
                    jsonEncode(
                        it?.toJSON()
                    )
                }"
            )

            if (it != null) {
                timedBasedStateEventChannel?.sendEvent(it)
            }
        }.launchIn(mainScope).let { jobs.add(it) }
    }

    private fun storeState(): Bundle {
        if (currentPublicationUrl == null) {
            // No current publication, no state.
            return Bundle()
        }

        return Bundle().apply {
            putString(currentPublicationUrlKey, currentPublicationUrl)
            putBoolean(epubEnabledKey, epubNavigator != null)
            putBundle(epubNavigatorStateKey, epubNavigator?.storeState())
            putBoolean(imageEnabledKey, imageNavigator != null)
            putBundle(imageNavigatorStateKey, imageNavigator?.storeState())
            putBoolean(pdfEnabledKey, pdfNavigator != null)
            putBundle(pdfNavigatorStateKey, pdfNavigator?.storeState())
            putBoolean(ttsEnabledKey, ttsNavigator != null)
            putBundle(ttsNavigatorStateKey, ttsNavigator?.storeState())
            putBoolean(audioEnabledKey, audiobookNavigator != null)
            putBundle(audioNavigatorStateKey, audiobookNavigator?.storeState())
            putBoolean(syncAudioEnabledKey, syncAudiobookNavigator != null)
            putBundle(syncAudioNavigatorStateKey, syncAudiobookNavigator?.storeState())
            putBundle(decorationStyleKey, decorationStyle.toBundle())
        }
    }

    private fun restoreState(bundle: Bundle?) {
        if (bundle == null) {
            Log.d(TAG, ":restoreState nothing to restore")
            return
        }

        Log.d(TAG, ":restoreState $bundle")
        val pubUrl = bundle.getString(currentPublicationUrlKey)
        if (pubUrl == null) {
            Log.d(TAG, ":storeState - currentPublicationUrl - not restored")
            return
        }

        Log.d(TAG, ":restoreState - currentPublicationUrl - $pubUrl")
        mainScope.launch {
            val pub = openPublication(pubUrl).getOrElse {
                Log.d(TAG, ":restoreState - failed to restore publication")
                // Restore is best-effort: the reader stays closed and Dart is not notified.
                return@launch
            }

            decorationStyle = FlutterDecorationPreferences.fromBundle(bundle.getBundle(decorationStyleKey))

            if (bundle.getBoolean(epubEnabledKey)) {
                Log.d(TAG, ":storeState - restore epub navigator")
                bundle.getBundle(epubNavigatorStateKey)?.let { state ->
                    epubNavigator =
                        EpubNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - epubNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(imageEnabledKey)) {
                Log.d(TAG, ":storeState - restore image navigator")
                bundle.getBundle(imageNavigatorStateKey)?.let { state ->
                    imageNavigator =
                        ImageNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - imageNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(pdfEnabledKey)) {
                Log.d(TAG, ":storeState - restore pdf navigator")
                bundle.getBundle(pdfNavigatorStateKey)?.let { state ->
                    pdfNavigator =
                        PdfNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - pdfNavigator restored")
                        }
                }
            }

            if (bundle.getBoolean(ttsEnabledKey)) {
                // Restore TTS navigator
                Log.d(TAG, ":storeState - restore tts navigator")
                bundle.getBundle(ttsNavigatorStateKey)?.let { state ->
                    ttsNavigator = TTSNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                        initNavigator()
                        Log.d(TAG, ":storeState - ttsNavigator restored")
                    }
                }
            }

            if (bundle.getBoolean(audioEnabledKey)) {
                // Restore Audio navigator
                Log.d(TAG, ":storeState - restore audio navigator")
                bundle.getBundle(audioNavigatorStateKey)?.let { state ->
                    audiobookNavigator =
                        AudiobookNavigator.restoreState(pub, this@ReadiumReader, state).apply {
                            initNavigator()
                            Log.d(TAG, ":storeState - audioNavigator restored")
                        }
                }
            } else if (bundle.getBoolean(syncAudioEnabledKey)) {
                // Restore Sync Audio navigator
                Log.d(TAG, ":storeState - restore sync audio navigator")
                val (ap, mediaOverlays) = pub.makeSyncAudiobook()
                if (mediaOverlays != null) {
                    bundle.getBundle(syncAudioNavigatorStateKey)?.let { state ->
                        syncAudiobookNavigator =
                            SyncAudiobookNavigator.restoreState(
                                ap,
                                mediaOverlays,
                                this@ReadiumReader,
                                state
                            )
                                .apply {
                                    initNavigator()
                                    Log.d(TAG, ":storeState - syncAudioNavigator restored")
                                }
                    }
                } else {
                    Log.e(TAG, ":storeState - no media overlays for sync audio navigator")
                }
            }

            Log.d(TAG, "consumeRestoredStateForKey - 2 - $currentPublication")
        }
    }

    /**
     * Tears down the reader session.
     *
     * The [Application] reference deliberately survives this: it is
     * process-scoped and outlives every engine, so a second engine in the same
     * process (a host can run a UI engine and a car engine side by side) keeps
     * resolving it after this one tears down. Everything else here is still
     * shared across engines and still cleared.
     */
    fun detach() {
        mainScope.launch {
            closePublication()
        }

        savedStateRef?.clear()
        savedStateRef = null

        _assetRetriever = null
        _publicationOpener = null

        readerViewRef?.clear()
        readerViewRef = null

        timedBasedStateEventChannel?.dispose()
        timedBasedStateEventChannel = null

        readerStatusEventChannel?.dispose()
        readerStatusEventChannel = null

        errorEventChannel?.dispose()
        errorEventChannel = null

        textLocatorEventChannel?.dispose()
        textLocatorEventChannel = null

        jobs.forEach { it.cancel() }
        jobs.clear()
        mainScope.coroutineContext.cancelChildren()
    }

    fun sendReaderStatus(status: String) {
        readerStatusEventChannel?.sendEvent(status)
    }

    fun sendError(message: String, code: String? = null, data: Any? = null) {
        errorEventChannel?.sendEvent(
            mapOf("message" to message, "code" to code, "data" to data)
        )
    }

    fun sendTextLocatorEvent(locator: Locator) {
        textLocatorEventChannel?.sendEvent(locator)
    }

    // Safe getter — returns applicationContext or throws if not available.
    val application: Application
        get() = appRef?.get()
            ?: throw IllegalStateException(
                "Application not initialized. FlureadiumPlugin seeds it in onAttachedToEngine; " +
                    "call ReadiumReader.attachApplication(context) when driving the reader directly."
            )

    var currentReaderWidget: ReadiumReaderWidget?
        get() = readerViewRef?.get()
        set(value) {
            readerViewRef = value?.let { WeakReference(it) }
        }

    private val context: Context
        get() = application.applicationContext

    private var _currentPublication: Publication? = null
    val currentPublication: Publication?
        get() = _currentPublication
    var currentPublicationUrl
        get() = state[currentPublicationUrlKey] as String?
        set(value) {
            state[currentPublicationUrlKey] = value
        }

    // Serializes publication open/switch so concurrent openPublication calls
    // (e.g. a reader-screen open racing another open on the shared native reader)
    // cannot double-load or double-release navigators.
    private val openMutex = Mutex()

    /**
     * Sets the headers used in the HTTP requests for fetching publication resources, including
     * resources in already created `Publication` objects.
     *
     * @param headers a map of HTTP header key value pairs.
     */
    fun setDefaultHttpHeaders(headers: Map<String, String>) {
        defaultHttpHeaders.clear()
        defaultHttpHeaders.putAll(headers)
    }

    private var isReadyEventChannel: EpubIsReadyEventChannel? = null

    private suspend fun assetToPublication(
        asset: Asset
    ): Try<Publication, OpenError> {
        val publication: Publication =
            publicationOpener.open(asset, allowUserInteraction = true, onCreatePublication = {
                // Outermost, so it also contains anything the injecting transformer
                // surfaces from a container that closed underneath it.
                container = TransformingContainer(container) { _: Url, resource: Resource ->
                    resource.injectScriptsAndStyles().catchingClosedContainer()
                }
            }).getOrElse { err: OpenError ->
                Log.e(TAG, "Error opening publication: $err")
                asset.close()
                return failure(err)
            }
        Log.d(TAG, "Open publication success: $publication")
        return Try.success(publication)
    }

    /**
     * Load a publication from a String url.
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(
        pubUrl: String?
    ): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument")
                )
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { pubUrl -> loadPublication(pubUrl) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url")
            )
        )
    }

    /**
     * Load a publication from an AbsoluteUrl
     *
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublication(
        pubUrl: AbsoluteUrl
    ): Try<Publication, PublicationError> {
        return withContext(Dispatchers.IO) {
            try {
                // No media type hint is passed; the retriever sniffs the asset.
                val asset: Asset = assetRetriever.retrieve(pubUrl)
                    .getOrElse { error: AssetRetriever.RetrieveUrlError ->
                        Log.e(TAG, "Error retrieving asset: $error from url:$pubUrl")
                        return@withContext failure(PublicationError.invoke(error))
                    }
                val pub = assetToPublication(asset).getOrElse { error: OpenError ->
                    Log.e(TAG, "Error loading asset to Publication object: $error from url:$pubUrl")
                    return@withContext failure(PublicationError.invoke(error))
                }
                Log.d(TAG, "Opened publication = ${pub.metadata.identifier} from url:$pubUrl")
                return@withContext Try.success(pub)
            } catch (e: Throwable) {
                return@withContext failure(PublicationError.Unexpected(ThrowableError(e)))
            }
        }
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(
        pubUrl: String?
    ): Try<Publication, PublicationError> {
        if (pubUrl == null) {
            return failure(
                PublicationError.Unexpected(
                    DebugError("missing argument")
                )
            )
        }

        return AbsoluteUrl.invoke(pubUrl)?.let { pubUrl -> openPublication(pubUrl) } ?: failure(
            PublicationError.Unexpected(
                DebugError("Invalid Url")
            )
        )
    }

    /**
     * Open a publication and set it as the current publication.
     */
    suspend fun openPublication(
        pubUrl: AbsoluteUrl
    ): Try<Publication, PublicationError> = openMutex.withLock {
        // Fast path: if the same publication is already open, return it.
        _currentPublication?.let { cached ->
            if (currentPublicationUrl == pubUrl.toString()) return@withLock Try.success(cached)
        }

        val pub = loadPublication(pubUrl).getOrElse { e -> return@withLock failure(e) }

        // Release all active navigators before switching publications.
        // Awaits ExoPlayer/TTS/MediaSession cleanup to prevent resource contention.
        ttsNavigator?.release()
        ttsNavigator = null
        audiobookNavigator?.release()
        audiobookNavigator = null
        syncAudiobookNavigator?.release()
        syncAudiobookNavigator = null
        pdfNavigator?.release()
        pdfNavigator = null
        imageNavigator?.release()
        imageNavigator = null
        epubNavigator?.release()
        epubNavigator = null

        isReadyEventChannel?.dispose()
        isReadyEventChannel = null

        _currentPublication?.close()
        _currentPublication = pub
        currentPublicationUrl = pubUrl.toString()

        Try.success(pub)
    }

    /**
     * Load a publication from a URL
     * Note: Remember to close the publication to avoid leaks.
     */
    suspend fun loadPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl = resolvePubUrl(urlStr).getOrElse {
            return failure(PublicationError.InvalidPublicationUrl(urlStr))
        }

        Log.d(TAG, "loadPublicationFromUrl: $pubUrl")

        return loadPublication(pubUrl)
    }

    /**
     * Open a publication from a URL.
     *
     * Note: This sets the publication as the current publication.
     */
    suspend fun openPublicationFromUrl(urlStr: String): Try<Publication, PublicationError> {
        val pubUrl = resolvePubUrl(urlStr).getOrElse {
            return failure(PublicationError.InvalidPublicationUrl(urlStr))
        }

        Log.d(TAG, "openPublicationFromUrl: $pubUrl")

        return openPublication(pubUrl)
    }

    /**
     * Helper function for resolving a URL and make sure a file path is turned into a URL.
     */
    private fun resolvePubUrl(urlStr: String): Try<AbsoluteUrl, PublicationError> {
        var pubUrlStr = urlStr
        // If URL is neither http nor file, assume it is a local file reference.
        if (!pubUrlStr.startsWith("http") && !pubUrlStr.startsWith("file")) {
            pubUrlStr = "file://$pubUrlStr"
        }
        // Create AbsoluteUrl, return PublicationError.InvalidPublicationUrl if null
        val pubUrl = AbsoluteUrl(pubUrlStr)
        if (pubUrl == null) {
            return failure(PublicationError.InvalidPublicationUrl(pubUrlStr))
        }

        return Try.success(pubUrl)
    }

    suspend fun closePublication() {
        mainScope.async {
            ttsNavigator?.release()
            ttsNavigator = null
            audiobookNavigator?.release()
            audiobookNavigator = null
            syncAudiobookNavigator?.release()
            syncAudiobookNavigator = null
            pdfNavigator?.release()
            pdfNavigator = null
            imageNavigator?.release()
            imageNavigator = null
            epubNavigator?.release()
            epubNavigator = null

            _currentPublication?.close()
            _currentPublication = null

            _audioPreferences = FlutterAudioPreferences()
            _pdfPreferences = FlutterPdfPreferences()

            state.clear()
        }.await()
    }

    override fun onTimebasedPlaybackStateChanged(timebasedState: TimebasedNavigator.TimebasedState) {
        Log.d(TAG, ":onTimebasedPlaybackStateChanged $timebasedState")
        currentTimebasedState.value = timebasedState
    }

    override fun onTimebasedBufferChanged(buffer: Duration?) {
        Log.d(TAG, ":onTimebasedBufferChanged $buffer")
        currentTimebasedBuffer.value = buffer?.inWholeMilliseconds
    }

    override fun onTimebasedPlaybackFailure(error: PublicationError) {
        Log.d(TAG, ":onTimebasedPlaybackFailure $error")
        // Forward to onErrorEvent so a failed streaming load surfaces to the
        // client instead of stalling silently at 0:00. Mirrors the iOS audio
        // path, which reports timebased failures with code "TimebasedError".
        sendError(error.message, code = "TimebasedError", data = error.errorCode.name)
    }

    override fun onTimebasedCurrentLocatorChanges(
        locator: Locator, currentReadingOrderLink: Link?
    ) {
        val duration = currentReadingOrderLink?.duration
        val timeOffset =
            locator.locations.fragments.find { it.startsWith("t=") }?.substring(2)?.toDoubleOrNull()
                ?: (duration?.let { duration ->
                    locator.locations.progression?.let { prog -> duration * prog }
                })

        Log.d(TAG, ":onTimebasedCurrentLocatorChanges $locator, timeOffset=$timeOffset")

        currentTimebasedOffset.value = timeOffset?.let { it * 1000 }
        currentTimebasedDuration.value = duration?.let { it * 1000 }
        currentTimebasedLocator.value = locator
    }

    override fun onTimebasedLocationChanged(locator: Locator) {
        Log.d(TAG, ":onTimebasedLocationChanged $locator")

        currentReaderWidget?.go(locator, true)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun epubEnable(
        initialLocator: Locator?,
        initialPreferences: EpubPreferences,
        messenger: BinaryMessenger,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable epub")

        isReadyEventChannel?.dispose()
        isReadyEventChannel = EpubIsReadyEventChannel(messenger)
        currentReaderWidget = readerWidget

        val isEpub = pub.conformsTo(Publication.Profile.EPUB) || pub.readingOrder.allAreHtml
        if (!isEpub) {
            throw Exception("Publication is not an EPUB, cannot enable epub navigator")
        }

        withScope(mainScope) {
            epubNavigator?.let {
                attachEpubNavigator(fragmentManager, viewGroup)
                return@withScope
            } // Already enabled - assume from restored state.

            EpubNavigator(pub, initialLocator, this@ReadiumReader, initialPreferences).apply {
                initNavigator()
                epubNavigator = this
                attachEpubNavigator(fragmentManager, viewGroup)
                return@withScope
            }
        }
    }

    suspend fun attachEpubNavigator(fragmentManager: FragmentManager?, viewGroup: ViewGroup?) {
        if (fragmentManager == null || viewGroup == null) {
            Log.d(TAG, "attachEpubNavigator: Missing fragmentManager or viewGroup")
            return
        }

        mainScope.async {
            epubNavigator?.attachNavigator(fragmentManager, viewGroup)
        }.await()
    }

    fun epubClose() {
        currentReaderWidget = null
        epubNavigator?.dispose()
        epubNavigator = null

        isReadyEventChannel?.dispose()
        isReadyEventChannel = null
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun imageEnable(
        initialLocator: Locator?,
        messenger: BinaryMessenger,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable image navigator")

        isReadyEventChannel?.dispose()
        isReadyEventChannel = EpubIsReadyEventChannel(messenger)
        currentReaderWidget = readerWidget

        if (pub.readerKind() != PublicationReaderKind.IMAGE) {
            throw Exception("Publication is not image-based, cannot enable image navigator")
        }

        withScope(mainScope) {
            imageNavigator?.let {
                attachImageNavigator(fragmentManager, viewGroup)
                return@withScope
            }

            ImageNavigator(pub, initialLocator, this@ReadiumReader).apply {
                initNavigator()
                imageNavigator = this
                attachImageNavigator(fragmentManager, viewGroup)
                return@withScope
            }
        }
    }

    suspend fun attachImageNavigator(fragmentManager: FragmentManager?, viewGroup: ViewGroup?) {
        if (fragmentManager == null || viewGroup == null) {
            Log.d(TAG, "attachImageNavigator: Missing fragmentManager or viewGroup")
            return
        }

        mainScope.async {
            imageNavigator?.attachNavigator(fragmentManager, viewGroup)
        }.await()
    }

    fun imageClose() {
        currentReaderWidget = null
        imageNavigator?.dispose()
        imageNavigator = null

        isReadyEventChannel?.dispose()
        isReadyEventChannel = null
    }

    fun imageSetNavigationConfig(config: FlutterNavigationConfig) {
        imageNavigator?.setNavigationConfig(config)
    }

    fun imageGoLeft(animated: Boolean) {
        imageNavigator?.goLeft(animated)
    }

    fun imageGoRight(animated: Boolean) {
        imageNavigator?.goRight(animated)
    }

    suspend fun imageGoToLocator(locator: Locator, animated: Boolean) {
        imageNavigator?.goToLocator(locator, animated)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun pdfEnable(
        initialLocator: Locator?,
        initialPreferences: FlutterPdfPreferences,
        messenger: BinaryMessenger,
        fragmentManager: FragmentManager,
        viewGroup: ViewGroup,
        readerWidget: ReadiumReaderWidget
    ) {
        val pub = currentPublication ?: throw Exception("Publication not opened cannot enable pdf")

        isReadyEventChannel?.dispose()
        isReadyEventChannel = EpubIsReadyEventChannel(messenger)
        currentReaderWidget = readerWidget

        val isPdf = pub.conformsTo(Publication.Profile.PDF)
        if (!isPdf) {
            throw Exception("Publication is not a PDF, cannot enable pdf navigator")
        }

        _pdfPreferences = initialPreferences

        withScope(mainScope) {
            pdfNavigator?.let {
                attachPdfNavigator(fragmentManager, viewGroup)
                return@withScope
            } // Already enabled - assume from restored state.

            PdfNavigator(pub, initialLocator, this@ReadiumReader, initialPreferences).apply {
                initNavigator()
                pdfNavigator = this
                attachPdfNavigator(fragmentManager, viewGroup)
                return@withScope
            }
        }
    }

    suspend fun attachPdfNavigator(fragmentManager: FragmentManager?, viewGroup: ViewGroup?) {
        if (fragmentManager == null || viewGroup == null) {
            Log.d(TAG, "attachPdfNavigator: Missing fragmentManager or viewGroup")
            return
        }

        mainScope.async {
            pdfNavigator?.attachNavigator(fragmentManager, viewGroup)
        }.await()
    }

    fun pdfClose() {
        currentReaderWidget = null
        pdfNavigator?.dispose()
        pdfNavigator = null

        isReadyEventChannel?.dispose()
        isReadyEventChannel = null
    }

    /**
     * Update PDF navigator preferences.
     */
    fun pdfUpdatePreferences(preferences: FlutterPdfPreferences) {
        _pdfPreferences = preferences
        pdfNavigator?.updatePreferences(preferences)
    }

    /**
     * Go to a specific locator in the PDF navigator.
     */
    suspend fun pdfGo(locator: Locator, animated: Boolean) {
        pdfNavigator?.go(locator, animated)
    }

    /**
     * Apply a navigation config to the PDF navigator overlay.
     */
    fun pdfSetNavigationConfig(config: FlutterNavigationConfig) {
        pdfNavigator?.setNavigationConfig(config)
    }

    /**
     * Go left (previous page) in the PDF navigator.
     */
    fun pdfGoLeft(animated: Boolean) {
        pdfNavigator?.goLeft(animated)
    }

    /**
     * Go right (next page) in the PDF navigator.
     */
    fun pdfGoRight(animated: Boolean) {
        pdfNavigator?.goRight(animated)
    }

    /**
     * Go to a specific locator in the PDF navigator, scrolling to position if needed.
     */
    suspend fun pdfGoToLocator(locator: Locator, animated: Boolean) {
        pdfNavigator?.goToLocator(locator, animated)
    }

    suspend fun ttsEnable(initialLocator: Locator?, ttsPrefs: FlutterTtsPreferences) {
        currentPublication?.let {
            ttsNavigator = TTSNavigator(it, this@ReadiumReader, initialLocator, ttsPrefs).apply {
                initNavigator()
            }
        } ?: throw Exception("Publication not opened cannot enable tts")
    }

    suspend fun ttsSetPreferences(ttsPrefs: FlutterTtsPreferences) {
        ttsNavigator?.updatePreferences(ttsPrefs)
            ?: throw Exception("TTS is not enabled, can't set preferences")
    }

    suspend fun setDecorationStyle(style: FlutterDecorationPreferences) {
        decorationStyle = style

        ttsNavigator?.decorationsUpdated()
        syncAudiobookNavigator?.decorationsUpdated()
    }

    fun ttsGetAvailableVoices(): Set<AndroidTtsEngine.Voice>? {
        return ttsNavigator?.voices
    }

    suspend fun ttsSetPreferredVoice(voiceId: String?, language: String?) {
        if (voiceId == null) return

        ttsNavigator?.setPreferredVoice(voiceId, language)
    }

    fun ttsCanSpeak(): Boolean {
        val pub = currentPublication ?: return false
        return pub.conformsTo(Publication.Profile.EPUB) || pub.readingOrder.allAreHtml
    }

    fun ttsRequestInstallVoice() {
        val app = appRef?.get() ?: return
        AndroidTtsEngine.requestInstallVoice(app)
    }

    suspend fun play(locator: Locator?) {
        var fromLocator = locator

        // If using TTS and no fromLocator given, start from current visible locator.
        if (fromLocator == null && (ttsNavigator != null || syncAudiobookNavigator != null)) {
            fromLocator = currentReaderWidget?.getFirstVisibleLocator()
        }

        audiobookNavigator?.play(fromLocator)
        syncAudiobookNavigator?.play(fromLocator)
        ttsNavigator?.play(fromLocator)
    }

    suspend fun pause() {
        audiobookNavigator?.pause()
        syncAudiobookNavigator?.pause()
        ttsNavigator?.pause()
    }

    suspend fun resume() {
        audiobookNavigator?.resume()
        syncAudiobookNavigator?.resume()
        ttsNavigator?.resume()
    }

    suspend fun stop() {
        audiobookNavigator?.apply {
            pause()
            release()
            audiobookNavigator = null
        }

        syncAudiobookNavigator?.apply {
            pause()
            release()
            syncAudiobookNavigator = null
        }

        ttsNavigator?.apply {
            pause()
            release()
            ttsNavigator = null
            ttsErrorType = null
        }
    }

    /**
     * Skip backwards.
     */
    suspend fun previous() {
        audiobookNavigator?.goBack()
        syncAudiobookNavigator?.goBack()
        ttsNavigator?.goBack()
    }

    /**
     * Skip forwards.
     */
    suspend fun next() {
        audiobookNavigator?.goForward()
        syncAudiobookNavigator?.goForward()
        ttsNavigator?.goForward()
    }

    /**
     * Go to a specific locator. Returns true if at least one navigator was
     * available to dispatch to, false otherwise.
     */
    suspend fun goToLocator(locator: Locator): Boolean {
        val handled = audiobookNavigator != null
            || syncAudiobookNavigator != null
            || ttsNavigator != null
            || imageNavigator != null
            || pdfNavigator != null
            || epubNavigator != null
        audiobookNavigator?.goToLocator(locator)
        syncAudiobookNavigator?.goToLocator(locator)
        ttsNavigator?.goToLocator(locator)
        imageGoToLocator(locator, true)
        pdfGoToLocator(locator, true)
        epubGoToLocator(locator, true)
        return handled
    }

    suspend fun audioSeek(offsetSeconds: Double) {
        audiobookNavigator?.seekTo(offsetSeconds)
        syncAudiobookNavigator?.seekTo(offsetSeconds)
    }

    @OptIn(InternalReadiumApi::class)
    suspend fun audioEnable(initialLocator: Locator?, preferences: FlutterAudioPreferences) {
        _audioPreferences = preferences

        currentPublication?.let { publication ->
            // Handle karaoke books - by creating a pseudo audio publication from the media overlays.
            val (ap, overlays) = publication.makeSyncAudiobook()

            audiobookNavigator?.release()
            audiobookNavigator = null
            syncAudiobookNavigator?.release()
            syncAudiobookNavigator = null

            if (overlays == null) {
                audiobookNavigator = AudiobookNavigator(
                    ap, this@ReadiumReader, initialLocator, preferences
                ).apply {
                    initNavigator()
                }
            } else {
                val ail = initialLocator ?: epubNavigator?.currentLocator?.value
                syncAudiobookNavigator = SyncAudiobookNavigator(
                    ap, overlays, this@ReadiumReader, ail, preferences
                ).apply {
                    initNavigator()
                }

            }
        } ?: throw Exception("Publication not opened")
    }

    suspend fun audioUpdatePreferences(preferences: FlutterAudioPreferences) {
        _audioPreferences = preferences

        mainScope.async {
            audiobookNavigator?.updatePreferences(preferences)
                ?: syncAudiobookNavigator?.updatePreferences(preferences)
                ?: throw Exception("Audio not enabled, cannot update preferences")
        }.await()
    }

    suspend fun applyDecorations(
        decorations: List<Decoration>, group: String
    ) {
        epubNavigator?.applyDecorations(decorations, group)
    }

    override fun onPageLoaded() {
        currentReaderWidget?.onPageLoaded()
    }

    override fun onPageChanged(
        pageIndex: Int, totalPages: Int, locator: Locator
    ) {
        currentReaderWidget?.onPageChanged(pageIndex, totalPages, locator)
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        currentReaderWidget?.onExternalLinkActivated(url)
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        currentReaderWidget?.onVisualCurrentLocationChanged(locator)
    }

    override fun onVisualReaderIsReady() {
        currentReaderWidget?.onVisualReaderIsReady()
        isReadyEventChannel?.sendEvent(true)
    }

    suspend fun getFirstVisibleLocator(): Locator? {
        return epubNavigator?.firstVisibleElementLocator()
    }

    suspend fun getEpubLocatorFragments(locator: Locator): Locator? {
        return epubNavigator?.getLocatorFragments(locator)
    }

    suspend fun epubEvaluateJavascript(script: String): String? {
        return epubNavigator?.evaluateJavascript(script)
    }

    /**
     * Update EPUB navigator preferences.
     */
    fun epubUpdatePreferences(preferences: EpubPreferences) {
        epubNavigator?.updatePreferences(preferences)
    }

    /**
     * Check if the EPUB navigator is ready.
     */
    suspend fun epubIsReaderReady(): Boolean {
        return epubNavigator?.isReaderReady() ?: false
    }

    /**
     * Go to a specific locator in the EPUB navigator, without scrolling to the locator position.
     */
    suspend fun epubGo(locator: Locator, animated: Boolean) {
        epubNavigator?.go(locator, animated)
    }

    /**
     * Apply a navigation config to the EPUB navigator overlay.
     */
    fun epubSetNavigationConfig(config: FlutterNavigationConfig) {
        epubNavigator?.setNavigationConfig(config)
    }

    /**
     * Enable or disable EPUB overlay gestures for scroll mode.
     */
    fun epubSetScrollMode(isScrollMode: Boolean) {
        epubNavigator?.setScrollMode(isScrollMode)
    }

    /**
     * Go left (previous page) in the EPUB navigator.
     */
    fun epubGoLeft(animated: Boolean) {
        epubNavigator?.goLeft(animated)
    }

    /**
     * Go right (next page) in the EPUB navigator.
     */
    fun epubGoRight(animated: Boolean) {
        epubNavigator?.goRight(animated)
    }

    /**
     * Go to a specific locator in the EPUB navigator, this scrolls to the locator position if needed.
     */
    suspend fun epubGoToLocator(locator: Locator, animated: Boolean) {
        epubNavigator?.goToLocator(locator, animated)
    }

    /**
     * Clears deferred EPUB scroll targets queued before explicit restore/navigation calls.
     */
    fun epubClearPendingScrollTarget() {
        epubNavigator?.clearPendingScrollTarget()
    }

    /**
     * Get locator fragments from EPUB navigator.
     */
    suspend fun epubGetLocatorFragments(locator: Locator): Locator? {
        return epubNavigator?.getLocatorFragments(locator)
    }
}
