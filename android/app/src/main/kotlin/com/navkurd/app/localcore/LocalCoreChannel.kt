package com.navkurd.app.localcore

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CompletionException

/** The installer is the single owner of required assets and removable map files. */
class LocalCoreChannel(context: Context, messenger: BinaryMessenger) {
    private val installer = CorePackInstaller(context.applicationContext)
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "navkurd/local_core")
    private val events = EventChannel(messenger, "navkurd/local_core_events")
    private var sink: EventChannel.EventSink? = null
    private var closed = false
    init {
        events.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
            override fun onCancel(arguments: Any?) { sink = null }
        })
        installer.onMapSnapshot = { snapshot -> main.post { if (!closed) sink?.success(snapshot) } }
        channel.setMethodCallHandler { call, result ->
            val operation: CompletableFuture<*> = when (call.method) {
                "install" -> installer.ensureInstalled().thenApply { installed ->
                    mapOf("packDirectory" to installed.packDirectory, "userDatabase" to installed.userDatabase,
                        "packId" to installed.packId, "mapArchives" to installed.mapArchives,
                        "mapSnapshot" to installed.mapSnapshot)
                }
                "mapSnapshot" -> installer.snapshotMaps()
                "mapArchives" -> if (call.argument<Boolean>("bundled") == true) installer.bundledMapArchives() else installer.currentMapArchives()
                "downloadMaps" -> installer.downloadMaps()
                "pauseMaps" -> installer.pauseMaps()
                "deleteMaps" -> installer.deleteMaps()
                else -> { result.notImplemented(); return@setMethodCallHandler }
            }
            operation.whenComplete { value, error ->
                main.post {
                    if (closed) result.error("local_core_closed", "The Android engine was disposed.", null)
                    else if (error != null) {
                        val cause = if (error is CompletionException) error.cause ?: error else error
                        result.error((cause as? LocalCoreException)?.code ?: "core_install", cause.message, null)
                    } else result.success(value)
                }
            }
        }
    }
    fun close() {
        closed = true
        installer.pauseMaps()
        installer.onMapSnapshot = null
        sink = null
        events.setStreamHandler(null)
        channel.setMethodCallHandler(null)
    }
}
