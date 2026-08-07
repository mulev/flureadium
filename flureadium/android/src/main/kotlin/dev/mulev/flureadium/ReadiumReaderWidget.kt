package dev.mulev.flureadium

import android.content.Context
import android.content.ContextWrapper
import android.graphics.Color
import android.util.AttributeSet
import android.util.Log
import android.view.View
import android.view.ViewGroup
import android.widget.LinearLayout
import android.widget.LinearLayout.generateViewId
import androidx.fragment.app.FragmentActivity
import androidx.fragment.app.commitNow
import dev.mulev.flureadium.fragments.EpubReaderFragment
import dev.mulev.flureadium.navigators.EpubNavigator
import dev.mulev.flureadium.navigators.PdfNavigator
import org.readium.r2.shared.publication.Publication
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancelChildren
import kotlinx.coroutines.launch
import org.json.JSONObject
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.html.cssSelector
import org.readium.r2.shared.publication.html.domRange
import org.readium.r2.shared.util.AbsoluteUrl
import kotlin.math.abs

private const val TAG = "ReadiumReaderView"
internal const val viewTypeChannelName = "dev.mulev.flureadium/ReadiumReaderWidget"

@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class)
class ReadiumReaderWidget(
    private val context: Context,
    id: Int,
    creationParams: Map<String?, Any?>,
    messenger: BinaryMessenger,
    attrs: AttributeSet? = null
) : PlatformView, MethodChannel.MethodCallHandler,
    EpubReaderFragment.Listener, EpubNavigator.VisualListener, PdfNavigator.VisualListener {

    private val channel: ReadiumReaderChannel
    private val layout: ViewGroup

    private val activity
        get() = (context as ContextWrapper).baseContext as FragmentActivity
    private val fragmentManager
        get() = activity.supportFragmentManager

    private val mainScope = CoroutineScope(
        SupervisorJob() + Dispatchers.Main.immediate + readerCoroutineExceptionHandler(TAG)
    )

    // Fixed for this widget's lifetime. As a getter over the mutable
    // ReadiumReader.currentPublication, a publication swap under a live
    // platform view would flip this widget's kind and send dispose() down the
    // wrong teardown path — leaking the navigator and is-ready channel it
    // actually enabled.
    private val readerKind: PublicationReaderKind =
        ReadiumReader.currentPublication?.readerKind() ?: PublicationReaderKind.EPUB

    private val isPdf: Boolean = readerKind == PublicationReaderKind.PDF
    private val isImage: Boolean = readerKind == PublicationReaderKind.IMAGE
    private val isAudio: Boolean = readerKind == PublicationReaderKind.AUDIO
    private val isEpub: Boolean = readerKind == PublicationReaderKind.EPUB

    private var storedNavigationConfig: FlutterNavigationConfig? = null

    override fun getView(): View {
        //Log.d(TAG, "::getView")
        return layout
    }

    override fun dispose() {
        Log.d(TAG, "::dispose")
        // Flutter creates the replacement platform view before disposing the one
        // it replaces — the new element's initState runs during buildScope, the
        // old element unmounts later in finalizeTree — so a stale widget's
        // dispose() routinely arrives after a newer widget has already
        // registered itself. Only the widget that still owns the registration
        // may tear down anything shared.
        if (ReadiumReader.currentReaderWidget === this) {
            ReadiumReader.sendReaderStatus("closed")
            ReadiumReader.currentReaderWidget = null
            when (readerKind) {
                PublicationReaderKind.PDF -> ReadiumReader.pdfClose()
                PublicationReaderKind.IMAGE -> ReadiumReader.imageClose()
                PublicationReaderKind.EPUB -> ReadiumReader.epubClose()
                // AUDIO enables no navigator and no is-ready channel, so
                // clearing the registration above is its whole teardown.
                PublicationReaderKind.AUDIO -> Unit
            }
        }

        channel.setMethodCallHandler(null)
        mainScope.coroutineContext.cancelChildren()
        layout.removeAllViews()
    }

    override fun onFlutterViewAttached(flutterView: View) {
        // Seems to never be called, so can't use this. Flutter bug?
        Log.d(TAG, "::onFlutterViewAttached")
        super.onFlutterViewAttached(flutterView)
    }

    override fun onFlutterViewDetached() {
        // Seems to never be called, so can't use this. Flutter bug?
        Log.d(TAG, "::onFlutterViewDetached")
        super.onFlutterViewDetached()
    }

    init {
        Log.d(TAG, "::init")

        @Suppress("UNCHECKED_CAST")
        val initPrefsMap = creationParams["preferences"] as Map<String, String>?
        val publication = ReadiumReader.currentPublication
        val locatorString = creationParams["initialLocator"] as String?
        val allowScreenReaderNavigation = creationParams["allowScreenReaderNavigation"] as Boolean?
        var initialLocator =
            if (locatorString == null) null else Locator.fromJSON(jsonDecode(locatorString) as JSONObject)
        val initialPreferences =
            if (initPrefsMap == null) EpubPreferences() else epubPreferencesFromMap(
                initPrefsMap,
                null
            )
        Log.d(TAG, "publication = $publication")

        layout = LinearLayout(context, attrs)
        layout.id = generateViewId()
        layout.setBackgroundColor(Color.TRANSPARENT)
        layout.setPadding(0, 0, 0, 0)

        ReadiumReader.currentReaderWidget = this

        channel = ReadiumReaderChannel(messenger, "$viewTypeChannelName:$id")
        channel.setMethodCallHandler(this)

        ReadiumReader.sendReaderStatus("loading")

        // By default reader contents are hidden from screen-readers, as not to trap them within it.
        // This can be toggled back on via the 'allowScreenReaderNavigation' creation param.
        if (allowScreenReaderNavigation != true) {
            layout.importantForAccessibility =
                View.IMPORTANT_FOR_ACCESSIBILITY_NO_HIDE_DESCENDANTS
        }

        // Remove existing fragment if any (this is to avoid crashing on restore).
        fragmentManager.findFragmentByTag(NAVIGATOR_FRAGMENT_TAG)?.let { fragment ->
            Log.d(TAG, "::init - remove existing fragment")

            fragmentManager.commitNow {
                remove(fragment)
            }
        }

        mainScope.launch {
            if (isPdf) {
                val pdfPreferences = if (initPrefsMap == null) {
                    FlutterPdfPreferences()
                } else {
                    FlutterPdfPreferences.fromMap(initPrefsMap)
                }
                ReadiumReader.pdfEnable(
                    initialLocator,
                    pdfPreferences,
                    messenger,
                    fragmentManager,
                    layout,
                    this@ReadiumReaderWidget,
                )
            } else if (isImage) {
                ReadiumReader.imageEnable(
                    initialLocator,
                    messenger,
                    fragmentManager,
                    layout,
                    this@ReadiumReaderWidget,
                )
            } else if (isAudio) {
                // An audio-only publication has no visual navigator to enable.
                // The widget is a live but empty host, so nothing else will
                // report readiness — onVisualReaderIsReady() never fires
                // without a navigator. Reuse the existing "ready" status:
                // method_channel_flureadium.dart:80 maps statuses with
                // firstWhere and no orElse, so an unknown string would throw
                // StateError in every host app.
                ReadiumReader.sendReaderStatus("ready")
            } else {
                ReadiumReader.epubEnable(
                    initialLocator,
                    initialPreferences,
                    messenger,
                    fragmentManager,
                    layout,
                    this@ReadiumReaderWidget,
                )
            }
        }
    }

    override fun onPageLoaded() {
        Log.d(TAG, "::onPageLoaded")
    }

    // To avoid duplicate onPageChanged events forwarded to Flutter.
    private var lastForwardedLocatorKey: String? = null
    private var lastStableEpubLocator: Locator? = null
    private var isRestoringInitialEpubLocator = false
    private var restoreStartedAtMs: Long = 0L
    private var restoreTargetHref: String? = null
    private var restoreTargetProgression: Double? = null
    private var restoreSettledAtMs: Long = 0L
    private var restoreGracePeriodMs: Long = 5000L  // 5 seconds grace period after restore

    private fun locatorForwardKey(locator: Locator): String {
        val progression = locator.locations.progression?.toString() ?: "null"
        val position = locator.locations.position?.toString() ?: "null"
        val cssSelector = locator.locations.cssSelector ?: ""
        return "${locator.href}|$progression|$position|$cssSelector"
    }

    private fun locatorDebugSummary(locator: Locator): String {
        val locations = locator.locations
        return "href=${locator.href}, progression=${locations.progression}, position=${locations.position}, totalProgression=${locations.totalProgression}, cssSelector=${locations.cssSelector}, fragments=${locations.fragments}"
    }

    private fun forwardLocatorIfChanged(locator: Locator, source: String = "unknown") {
        val normalizedLocator = if (isEpub) normalizeEpubLocator(locator) else locator
        if (isEpub && isStableEpubLocator(normalizedLocator)) {
            lastStableEpubLocator = normalizedLocator
        }

        val currentKey = locatorForwardKey(normalizedLocator)
        if (lastForwardedLocatorKey == currentKey) {
            Log.d(TAG, "forwardLocatorIfChanged[$source]: skip duplicate ${locatorDebugSummary(normalizedLocator)}")
            return
        }
        lastForwardedLocatorKey = currentKey
        Log.d(TAG, "forwardLocatorIfChanged[$source]: emit ${locatorDebugSummary(normalizedLocator)}")
        mainScope.launch { emitOnPageChanged(normalizedLocator) }
    }

    private fun markInitialEpubRestoreStarted(locator: Locator) {
        isRestoringInitialEpubLocator = true
        restoreStartedAtMs = System.currentTimeMillis()
        restoreTargetHref = locator.href.toString()
        restoreTargetProgression = locator.locations.progression
        Log.d(TAG, "restore: started for ${locator.href}, progression=${restoreTargetProgression}")

        // Safety timeout: force settle after 3 seconds
        mainScope.launch {
            kotlinx.coroutines.delay(3000)
            if (isRestoringInitialEpubLocator) {
                Log.w(TAG, "restore: timeout after 3000ms, force settling")
                isRestoringInitialEpubLocator = false
                restoreTargetHref = null
                restoreTargetProgression = null
            }
        }
    }

    private fun markInitialEpubRestoreSettled(locator: Locator) {
        val elapsedMs = System.currentTimeMillis() - restoreStartedAtMs
        Log.d(
            TAG,
            "restore: settled after ${elapsedMs}ms (target=$restoreTargetHref @ $restoreTargetProgression, current=${locator.href} @ ${locator.locations.progression})"
        )
        isRestoringInitialEpubLocator = false
        restoreSettledAtMs = System.currentTimeMillis()
        // Keep restoreTargetHref and restoreTargetProgression for grace period validation

        // Clear grace period after timeout
        mainScope.launch {
            kotlinx.coroutines.delay(restoreGracePeriodMs)
            Log.d(TAG, "restore: grace period ended")
            restoreTargetHref = null
            restoreTargetProgression = null
        }
    }

    override fun onPageChanged(pageIndex: Int, totalPages: Int, locator: Locator) {
        Log.d(
            TAG,
            "::onPageChanged $pageIndex/$totalPages ${locator.href} ${locator.locations.progression} ${locator.locations}"
        )

        if (isEpub) {
            if (isRestoringInitialEpubLocator) {
                Log.d(TAG, "::onPageChanged - ignore EPUB pagination event during restore window")
            } else {
                Log.d(TAG, "::onPageChanged - ignore EPUB pagination event; using visual locator flow")
            }
            return
        }

        forwardLocatorIfChanged(locator, "pageChanged")
    }

    override fun onExternalLinkActivated(url: AbsoluteUrl) {
        Log.d(TAG, "::onExternalLinkActivated $url")
        mainScope.launch { emitOnExternalLinkActivated(url) }
    }

    override fun onVisualCurrentLocationChanged(locator: Locator) {
        Log.d(TAG, "::onVisualCurrentLocationChanged ${locatorDebugSummary(locator)}")

        if (isPdf) return

        if (isImage) {
            forwardLocatorIfChanged(locator, "visualLocator")
            return
        }

        if (isRestoringInitialEpubLocator) {
            val targetHref = restoreTargetHref
            val locatorHref = locator.href.toString()
            val elapsed = System.currentTimeMillis() - restoreStartedAtMs

            if (targetHref != null && locatorHref == targetHref && elapsed > 50) {
                markInitialEpubRestoreSettled(locator)
                forwardLocatorIfChanged(locator, "visualLocator")
            } else {
                Log.d(TAG, "::onVisualCurrentLocationChanged - suppress during restore " +
                    "(targetHref=$targetHref, locatorHref=$locatorHref, elapsed=${elapsed}ms)")
            }
            return
        }

        // Grace period validation: check if we're still within grace period after restore
        val targetHref = restoreTargetHref
        val targetProgression = restoreTargetProgression
        if (targetHref != null && restoreSettledAtMs > 0) {
            val elapsedSinceSettle = System.currentTimeMillis() - restoreSettledAtMs
            if (elapsedSinceSettle < restoreGracePeriodMs) {
                val locatorHref = locator.href.toString()
                val locatorProgression = locator.locations.progression

                // If href matches but progression is far off, suppress
                if (locatorHref == targetHref && targetProgression != null && locatorProgression != null) {
                    val progressionDelta = kotlin.math.abs(locatorProgression - targetProgression)
                    if (progressionDelta > 0.2) {  // More than 20% difference
                        Log.w(TAG, "::onVisualCurrentLocationChanged - SUPPRESS late jump during grace period! " +
                            "target=$targetProgression, current=$locatorProgression, delta=$progressionDelta, " +
                            "elapsed=${elapsedSinceSettle}ms")
                        return
                    }
                }
            }
        }

        forwardLocatorIfChanged(locator, "visualLocator")
    }

    override fun onVisualReaderIsReady() {
        Log.d(TAG, "::onVisualReaderIsReady")
        ReadiumReader.sendReaderStatus("ready")
    }

    suspend fun getFirstVisibleLocator(): Locator? = withScope(mainScope) { ReadiumReader.getFirstVisibleLocator() }

    @Throws(IllegalArgumentException::class)
    private fun setPreferencesFromMap(prefMap: Map<String, String>) {
        Log.d(TAG, "::setPreferencesFromMap")
        val newPreferences = epubPreferencesFromMap(prefMap, null)
        updatePreferences(newPreferences)
    }

    private suspend fun emitOnPageChanged(locator: Locator) {
        try {
            if (isPdf || isImage) {
                channel.onPageChanged(locator)
                ReadiumReader.sendTextLocatorEvent(locator)
            } else {
                val locatorWithFragments = ReadiumReader.getEpubLocatorFragments(locator)
                val finalLocator = if (locatorWithFragments != null) {
                    normalizeEpubLocator(locatorWithFragments)
                } else {
                    Log.e(TAG, "emitOnPageChanged: getVisibleRange failed, using base locator")
                    normalizeEpubLocator(locator)
                }
                channel.onPageChanged(finalLocator)
                ReadiumReader.sendTextLocatorEvent(finalLocator)
            }
        } catch (e: Exception) {
            Log.e(TAG, "emitOnPageChanged: ${readerKind.name} failed! $e")
        }
    }

    private fun emitOnExternalLinkActivated(url: AbsoluteUrl) {
        channel.onExternalLinkActivated(url)
    }

    private suspend fun setLocation(
        locator: Locator,
        isAudioBookWithText: Boolean
    ) {
        val json = locator.toJSON().toString()
        Log.d(TAG, "::scrollToLocations: Go to locations $json")
        evaluateJavascript("window.epubPage.setLocation($json, $isAudioBookWithText);")
    }

    private fun canApplyJsSetLocation(locator: Locator): Boolean {
        val cssSelector = locator.locations.cssSelector
        if (!cssSelector.isNullOrBlank()) {
            return true
        }

        val domRangeStartSelector = locator.locations.domRange?.start?.cssSelector
        return !domRangeStartSelector.isNullOrBlank()
    }

    private fun normalizeCssSelector(cssSelector: String?): String? {
        if (cssSelector.isNullOrBlank()) {
            return cssSelector
        }

        return cssSelector.replaceFirst(":root > :nth-child(2)", "body")
    }

    private fun normalizeEpubFragments(fragments: List<String>): List<String> {
        if (fragments.isEmpty()) {
            return fragments
        }

        val passthrough = mutableListOf<String>()
        var pageFragment: String? = null
        var totalPagesFragment: String? = null
        var tocFragment: String? = null
        var physicalPageFragment: String? = null

        for (fragment in fragments) {
            when {
                fragment.startsWith("page=") -> pageFragment = fragment
                fragment.startsWith("totalPages=") -> totalPagesFragment = fragment
                fragment.startsWith("toc=") -> tocFragment = fragment
                fragment.startsWith("physicalPage=") -> physicalPageFragment = fragment
                passthrough.contains(fragment).not() -> passthrough.add(fragment)
            }
        }

        val normalized = mutableListOf<String>()
        normalized.addAll(passthrough)
        pageFragment?.let(normalized::add)
        totalPagesFragment?.let(normalized::add)
        tocFragment?.let(normalized::add)
        physicalPageFragment?.let(normalized::add)

        return normalized
    }

    private fun normalizeEpubLocator(locator: Locator): Locator {
        val locations = locator.locations
        val normalizedFragments = normalizeEpubFragments(locations.fragments)
        val normalizedCssSelector = normalizeCssSelector(locations.cssSelector)

        if (normalizedFragments == locations.fragments && normalizedCssSelector == locations.cssSelector) {
            return locator
        }

        Log.d(
            TAG,
            "normalizeEpubLocator: before=${locatorDebugSummary(locator)}, afterCss=$normalizedCssSelector, afterFragments=$normalizedFragments"
        )

        val normalizedOtherLocations = locations.otherLocations.toMutableMap().apply {
            if (normalizedCssSelector.isNullOrBlank()) {
                remove("cssSelector")
            } else {
                this["cssSelector"] = normalizedCssSelector
            }
        }

        return locator.copy(
            locations = locations.copy(
                fragments = normalizedFragments,
                otherLocations = normalizedOtherLocations
            )
        )
    }

    private fun isStableEpubLocator(locator: Locator): Boolean {
        return locator.locations.progression != null || locator.locations.position != null
    }

    private fun scoreEpubLocator(locator: Locator): Int {
        val locations = locator.locations
        var score = 0

        if (locations.progression != null) {
            score += 4
        }

        if (locations.position != null) {
            score += 3
        }

        val cssSelector = locations.cssSelector
        if (!cssSelector.isNullOrBlank() && !cssSelector.startsWith(":root")) {
            score += 2
        }

        if (locations.fragments.any { it.startsWith("page=") }) {
            score += 1
        }

        if (!hasConsistentPageFragments(locator)) {
            score -= 3
        }

        return score
    }

    private fun fragmentInt(fragments: List<String>, key: String): Int? {
        val prefix = "$key="
        val value = fragments.firstOrNull { it.startsWith(prefix) }?.substringAfter(prefix)
        return value?.toIntOrNull()
    }

    private fun progressionFromPageFragments(locator: Locator): Double? {
        val page = fragmentInt(locator.locations.fragments, "page") ?: return null
        val totalPages = fragmentInt(locator.locations.fragments, "totalPages") ?: return null
        if (totalPages <= 1) {
            return 0.0
        }

        val clampedPage = page.coerceIn(1, totalPages)
        return (clampedPage - 1).toDouble() / (totalPages - 1).toDouble()
    }

    private fun hasConsistentPageFragments(locator: Locator): Boolean {
        val progression = locator.locations.progression ?: return true
        val progressionFromFragments = progressionFromPageFragments(locator) ?: return true
        val delta = abs(progressionFromFragments - progression)
        return delta <= 0.25
    }

    private fun pickConsistentEpubLocator(
        baseLocator: Locator,
        candidateLocator: Locator
    ): Locator {
        if (hasConsistentPageFragments(candidateLocator)) {
            return candidateLocator
        }

        val candidateProgression = candidateLocator.locations.progression
        val candidateFragmentsProgression = progressionFromPageFragments(candidateLocator)
        val delta = if (candidateProgression != null && candidateFragmentsProgression != null) {
            abs(candidateProgression - candidateFragmentsProgression)
        } else {
            null
        }

        Log.w(
            TAG,
            "emitOnPageChanged: inconsistent candidate locator; falling back to base locator. candidate=${locatorDebugSummary(candidateLocator)}, delta=$delta, base=${locatorDebugSummary(baseLocator)}"
        )

        return baseLocator
    }

    private suspend fun getBestEpubCurrentLocator(): Locator? {
        val candidates = mutableListOf<Pair<String, Locator>>()

        val firstVisibleLocator = ReadiumReader.getFirstVisibleLocator()
        if (firstVisibleLocator != null) {
            try {
                val enrichedVisibleLocator = ReadiumReader.getEpubLocatorFragments(firstVisibleLocator)
                val bestVisibleLocator = enrichedVisibleLocator ?: firstVisibleLocator
                candidates += "firstVisible" to normalizeEpubLocator(bestVisibleLocator)
                Log.d(
                    TAG,
                    "getCurrentLocator: firstVisible candidate ${locatorDebugSummary(candidates.last().second)}"
                )
            } catch (e: Exception) {
                Log.w(TAG, "getCurrentLocator: Error enriching first visible locator, falling back", e)
            }
        }

        ReadiumReader.epubCurrentLocator?.let { currentLocator ->
            try {
                val enrichedLocator = ReadiumReader.getEpubLocatorFragments(currentLocator)
                val bestCurrentLocator = enrichedLocator ?: currentLocator
                candidates += "current" to normalizeEpubLocator(bestCurrentLocator)
                Log.d(
                    TAG,
                    "getCurrentLocator: current candidate ${locatorDebugSummary(candidates.last().second)}"
                )
            } catch (e: Exception) {
                Log.w(TAG, "getCurrentLocator: Error enriching EPUB current locator, using fallback locator", e)
                candidates += "current-fallback" to normalizeEpubLocator(currentLocator)
                Log.d(
                    TAG,
                    "getCurrentLocator: current-fallback candidate ${locatorDebugSummary(candidates.last().second)}"
                )
            }
        }

        val selected = candidates.maxByOrNull { (_, locator) -> scoreEpubLocator(locator) }

        if (selected == null) {
            Log.d(
                TAG,
                "getCurrentLocator: no candidates, returning lastStable=${lastStableEpubLocator?.let(::locatorDebugSummary)}"
            )
            return lastStableEpubLocator
        }

        val (source, locator) = selected
        val score = scoreEpubLocator(locator)
        Log.d(TAG, "getCurrentLocator: selected $source (score=$score) $locator")

        // Guard: if selected href differs from stable, prefer stable if score comparable
        val stable = lastStableEpubLocator
        if (stable != null && locator.href != stable.href) {
            val stableScore = scoreEpubLocator(stable)
            if (stableScore >= score) {
                Log.w(TAG, "getCurrentLocator: selected href differs from stable, preferring stable")
                return stable
            }
        }

        if (isStableEpubLocator(locator)) {
            lastStableEpubLocator = locator
            return locator
        }

        Log.d(
            TAG,
            "getCurrentLocator: selected locator not stable, using lastStable=${lastStableEpubLocator?.let(::locatorDebugSummary)}"
        )
        return lastStableEpubLocator ?: locator
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        // TODO: To be safe we're doing everything on the Main thread right now.
        // Could probably optimize by using .IO and then change to Main
        // when affecting readerView or returning a result.
        mainScope.launch {
            Log.d(TAG, "::onMethodCall ${call.method}")
            when (call.method) {
                "setPreferences" -> {
                    @Suppress("UNCHECKED_CAST")
                    val prefsMap = call.arguments as Map<String, String>
                    try {
                        if (isPdf) {
                            val pdfPrefs = FlutterPdfPreferences.fromMap(prefsMap)
                            ReadiumReader.pdfUpdatePreferences(pdfPrefs)
                        } else if (isImage) {
                            result.success(null)
                            return@launch
                        } else {
                            setPreferencesFromMap(prefsMap)
                            val isScrollMode = prefsMap["verticalScroll"]?.toBoolean() == true
                            ReadiumReader.epubSetScrollMode(isScrollMode)
                        }
                        result.success(null)
                    } catch (ex: Exception) {
                        result.error("Flureadium", "Failed to set preferences", ex.message)
                    }
                }

                "setNavigationConfig" -> {
                    @Suppress("UNCHECKED_CAST")
                    val args = call.arguments as? Map<*, *>
                    val config = FlutterNavigationConfig.fromMap(args)
                    applyNavigationConfig(config)
                    result.success(null)
                }

                "go" -> {
                    val args = call.arguments as List<*>
                    val locatorJson = JSONObject(args[0] as String)
                    val animated = args[1] as Boolean
                    val isAudioBookWithText = args[2] as Boolean
                    val isLikelyInitialRestore = !isAudioBookWithText && !animated
                    if (locatorJson.optString("type") == "") {
                        locatorJson.put("type", " ")
                        Log.e(
                            TAG,
                            "Got locator with empty type! This shouldn't happen. $locatorJson"
                        )
                    }
                    val locator = Locator.fromJSON(locatorJson)!!
                    if (isPdf) {
                        ReadiumReader.pdfGoToLocator(locator, animated)
                    } else if (isImage) {
                        ReadiumReader.imageGoToLocator(locator, animated)
                    } else {
                        if (!isAudioBookWithText) {
                            // Avoid stale startup pending-scroll overriding an explicit go() call.
                            ReadiumReader.epubClearPendingScrollTarget()
                        }
                        if (isLikelyInitialRestore) {
                            markInitialEpubRestoreStarted(locator)
                        }
                        ReadiumReader.epubGoToLocator(locator, animated)
                        if (isAudioBookWithText && canApplyJsSetLocation(locator)) {
                            try {
                                setLocation(locator, isAudioBookWithText)
                            } catch (e: Exception) {
                                Log.w(
                                    TAG,
                                    "go: JS setLocation failed after native locator navigation, keeping native result",
                                    e
                                )
                            }
                        } else {
                            Log.d(
                                TAG,
                                "go: Skipping JS setLocation for non-audiobook restore or locator without cssSelector/domRange.start"
                            )
                        }
                    }
                    result.success(null)
                }

                "goLeft" -> {
                    val animated = call.arguments as Boolean
                    if (isPdf) {
                        ReadiumReader.pdfGoLeft(animated)
                    } else if (isImage) {
                        ReadiumReader.imageGoLeft(animated)
                    } else {
                        goLeft(animated)
                    }
                    result.success(null)
                }

                "goRight" -> {
                    val animated = call.arguments as Boolean
                    if (isPdf) {
                        ReadiumReader.pdfGoRight(animated)
                    } else if (isImage) {
                        ReadiumReader.imageGoRight(animated)
                    } else {
                        goRight(animated)
                    }
                    result.success(null)
                }

                "setLocation" -> {
                    val args = call.arguments as List<*>
                    val locatorJson = JSONObject(args[0] as String)
                    val isAudioBookWithText = args[1] as Boolean
                    val locator = Locator.fromJSON(locatorJson)!!
                    setLocation(locator, isAudioBookWithText)
                    result.success(null)
                }

                "isLocatorVisible" -> {
                    if (!isEpub) {
                        result.success(false)
                        return@launch
                    }
                    val args = call.arguments as String
                    val locatorJson = JSONObject(args)
                    val locator = Locator.fromJSON(locatorJson)!!
                    var visible = locator.href == ReadiumReader.epubCurrentLocator?.href
                    if (visible) {
                        val jsonRes =
                            evaluateJavascript("window.epubPage.isLocatorVisible($args);")
                                ?: "false"
                        try {
                            visible = jsonDecode(jsonRes) as Boolean
                        } catch (e: Error) {
                            Log.e(TAG, "::isLocatorVisible - invalid response:$jsonRes - e:$e")
                            visible = false
                        }
                    }
                    result.success(visible)
                }

                "isReaderReady" -> {
                    try {
                        result.success(if (isEpub) ReadiumReader.epubIsReaderReady() else true)
                    } catch (e: Error) {
                        Log.e(TAG, "::isReaderReady - error getting state - $e")
                        result.success(false)
                    }
                }

                "getLocatorFragments" -> {
                    val args = call.arguments as String?
                    if (!isEpub) {
                        result.success(args)
                        return@launch
                    }
                    Log.d(TAG, "::====== $args")
                    val locatorJson = JSONObject(args!!)
                    Log.d(TAG, "::====== $locatorJson")

                    val locator =
                        ReadiumReader.epubGetLocatorFragments(Locator.fromJSON(locatorJson)!!)
                    Log.d(TAG, "::====== $locator")

                    result.success(jsonEncode(locator?.toJSON()))
                }

                "applyDecorations" -> {
                    val args = call.arguments as List<*>
                    val groupId = args[0] as String

                    @Suppress("UNCHECKED_CAST")
                    val decorationListStr = args[1] as List<Map<String, String>>
                    val decorations = decorationListStr.mapNotNull { decorationFromMap(it) }

                    ReadiumReader.applyDecorations(decorations, groupId)
                    result.success(null)
                }

                "dispose" -> {
                    dispose()
                    result.success(null)
                }

                "getCurrentLocator" -> {
                    val locator =
                        when {
                            isPdf -> ReadiumReader.pdfCurrentLocator
                            isImage -> ReadiumReader.imageCurrentLocator
                            else -> getBestEpubCurrentLocator()
                        }
                    Log.d(
                        TAG,
                        "getCurrentLocator: result=${locator?.let(::locatorDebugSummary)}"
                    )
                    result.success(locator?.let { jsonEncode(it.toJSON()) })
                }

                else -> {
                    Log.e(TAG, "Unhandled call ${call.method}")
                    result.notImplemented()
                }
            }
        }
    }

    fun go(locator: Locator, animated: Boolean) {
        Log.d(TAG, "::go ${locator.href}")
        mainScope.launch {
            when {
                isPdf -> ReadiumReader.pdfGoToLocator(locator, animated)
                isImage -> ReadiumReader.imageGoToLocator(locator, animated)
                else -> ReadiumReader.epubGoToLocator(locator, animated)
            }
        }
    }

    private fun applyNavigationConfig(config: FlutterNavigationConfig) {
        storedNavigationConfig = config
        if (isPdf) {
            ReadiumReader.pdfSetNavigationConfig(config)
        } else if (isImage) {
            ReadiumReader.imageSetNavigationConfig(config)
        } else {
            ReadiumReader.epubSetNavigationConfig(config)
        }
    }

    private fun goLeft(animated: Boolean) {
        Log.d(TAG, "::goLeft")
        ReadiumReader.epubGoLeft(animated)
    }

    private fun goRight(animated: Boolean) {
        ReadiumReader.epubGoRight(animated)
    }

    private suspend fun evaluateJavascript(script: String): String? {
        val ret = ReadiumReader.epubEvaluateJavascript(script)
        if (ret == null || ret == "null" || ret == "undefined") {
            // Hopefully can't happen.
            Log.e(TAG, "::evaluateJavascript($script) returned null $ret")

            return null
        }

        return ret
    }

    private fun updatePreferences(preferences: EpubPreferences) {
        ReadiumReader.epubUpdatePreferences(preferences)
    }

    companion object {
        const val NAVIGATOR_FRAGMENT_TAG = "NAVIGATOR_READER_FRAGMENT"
    }
}
