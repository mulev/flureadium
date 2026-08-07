/*
 * Copyright 2022 Readium Foundation. All rights reserved.
 * Use of this source code is governed by the BSD-style license
 * available in the top-level LICENSE file of the project.
 */

package dev.mulev.flureadium

import android.app.Application
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.readium.navigator.media.common.Media3Adapter
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.InternalReadiumApi
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.CoroutineQueue

private const val TAG = "PluginMediaServiceFacade"

/**
 * Enables to try to close a session without starting the [PluginMediaService] if it is not started.
 */
@ExperimentalCoroutinesApi
@OptIn(ExperimentalReadiumApi::class, InternalReadiumApi::class)
class PluginMediaServiceFacade(
    private val application: Application,
) {
    private val coroutineScope: CoroutineScope =
        MainScope() + readerCoroutineExceptionHandler(TAG)

    private val coroutineQueue: CoroutineQueue =
        CoroutineQueue()

    private var binder: PluginMediaService.Binder? =
        null

    private var bindingJob: Job? =
        null

    private val sessionMutable: MutableStateFlow<PluginMediaService.Session?> =
        MutableStateFlow(null)

    val session: StateFlow<PluginMediaService.Session?> =
        sessionMutable.asStateFlow()

    /**
     * Throws an IllegalStateException if binding to the MyMediaService fails.
     */
    suspend fun <N> openSession(
        navigator: N,
        publication: Publication? = null,
    ) where N : AnyMediaNavigator, N : Media3Adapter {
        coroutineQueue.await {
            // Already bound with a live session for this navigator — reuse it
            // instead of rebinding and relaunching a session collector. Read the
            // binder's own session (set synchronously by openSession), not the
            // mirrored `sessionMutable` the async collector lags behind.
            if (sessionActionFor(binder?.session?.value?.navigator, navigator) == SessionAction.REUSE) {
                return@await
            }
            PluginMediaService.start(application)
            binder = try {
                PluginMediaService.bind(application)
            } catch (e: Exception) {
                // Failed to bind to the service.
                PluginMediaService.stop(application)
                throw e
            }

            bindingJob = binder!!.session
                .onEach { sessionMutable.value = it }
                .launchIn(coroutineScope)
            binder!!.openSession(navigator, publication)
        }
    }

    fun closeSession() {
        coroutineQueue.launch {
            bindingJob?.cancelAndJoin()
            binder?.closeSession()
            binder?.stop()
            sessionMutable.value = null
            binder = null
        }
    }
}
