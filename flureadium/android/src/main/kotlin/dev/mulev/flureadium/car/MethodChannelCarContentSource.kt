package dev.mulev.flureadium.car

import android.os.Handler
import android.os.Looper
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.BinaryMessenger

/**
 * A [CarContentSource] backed by the `dev.mulev.flureadium/car` method channel,
 * bound to whichever binary messenger the host runs its Dart car entrypoint on.
 *
 * On a cold connect the car engine's Dart handler may not be installed yet. A
 * registered provider always answers a browse call with an array (empty when it
 * has nothing), so a *non-array* reply means "handler not ready": the source
 * retries those a bounded number of times before giving up with an empty list,
 * rather than mistaking the startup race for an empty library. This mirrors the
 * iOS `CarPlayContentBridge` retry.
 */
class MethodChannelCarContentSource(
    private val channel: MethodChannel,
    private val retryHandler: Handler = Handler(Looper.getMainLooper()),
) : CarContentSource {

    override fun rootTabs(): ListenableFuture<List<CarTab>> =
        invokeList("rootTabs", null, CarTab::fromMap)

    override fun children(nodeId: String): ListenableFuture<List<CarBrowseNode>> =
        invokeList("children", mapOf("nodeId" to nodeId), CarBrowseNode::fromMap)

    override fun search(query: String): ListenableFuture<List<CarBrowseNode>> =
        invokeList("search", mapOf("query" to query), CarBrowseNode::fromMap)

    override fun strings(): ListenableFuture<CarContentStrings?> {
        val future = SettableFuture.create<CarContentStrings?>()
        channel.invokeMethod(
            "strings",
            null,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    future.set((result as? Map<*, *>)?.let(CarContentStrings::fromMap))
                }

                override fun error(code: String, message: String?, details: Any?) {
                    future.set(null)
                }

                override fun notImplemented() {
                    future.set(null)
                }
            },
        )
        return future
    }

    override fun play(nodeId: String) {
        channel.invokeMethod("play", mapOf("nodeId" to nodeId))
    }

    override fun addBookmark() {
        channel.invokeMethod("addBookmark", null)
    }

    private fun <T> invokeList(
        method: String,
        arguments: Any?,
        decode: (Map<*, *>) -> T?,
    ): ListenableFuture<List<T>> {
        val future = SettableFuture.create<List<T>>()
        invokeListAttempt(method, arguments, 0, future, decode)
        return future
    }

    private fun <T> invokeListAttempt(
        method: String,
        arguments: Any?,
        attempt: Int,
        future: SettableFuture<List<T>>,
        decode: (Map<*, *>) -> T?,
    ) {
        // A not-yet-ready car engine has no handler on the channel, which replies
        // notImplemented (or error); treat every non-list outcome the same way and
        // retry, so the cold-start race isn't mistaken for an empty library.
        fun retryOrGiveUp() {
            if (attempt < READY_RETRY_LIMIT) {
                retryHandler.postDelayed(
                    { invokeListAttempt(method, arguments, attempt + 1, future, decode) },
                    READY_RETRY_DELAY_MS,
                )
            } else {
                future.set(emptyList())
            }
        }
        channel.invokeMethod(
            method,
            arguments,
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    val list = result as? List<*>
                    if (list != null) {
                        future.set(list.mapNotNull { (it as? Map<*, *>)?.let(decode) })
                    } else {
                        retryOrGiveUp()
                    }
                }

                override fun error(code: String, message: String?, details: Any?) {
                    retryOrGiveUp()
                }

                override fun notImplemented() {
                    retryOrGiveUp()
                }
            },
        )
    }

    companion object {
        const val CHANNEL_NAME = "dev.mulev.flureadium/car"
        const val READY_RETRY_LIMIT = 20
        const val READY_RETRY_DELAY_MS = 150L

        /** Builds a source bound to [messenger] on the car channel. */
        fun fromMessenger(messenger: BinaryMessenger): MethodChannelCarContentSource =
            MethodChannelCarContentSource(MethodChannel(messenger, CHANNEL_NAME))
    }
}
