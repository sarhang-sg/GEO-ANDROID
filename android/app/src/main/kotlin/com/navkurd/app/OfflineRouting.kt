package com.navkurd.app

import android.app.ActivityManager
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import btools.router.NavKurdDirections
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.concurrent.Executors

internal class OfflineRouting(private val context: Context) {
    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    @Volatile private var current: NavKurdDirections? = null
    private var currentId = -1

    fun route(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("id")?.toInt()
        val mode = call.argument<String>("mode")
        val origin = coordinate(call.argument<List<*>>("origin"))
        val destination = coordinate(call.argument<List<*>>("destination"))
        if (id == null || mode !in setOf("car", "bicycle", "walking") || origin == null || destination == null) {
            result.error("invalid_route", "Invalid offline route request", null)
            return
        }
        if (listOf(origin, destination).any { it[0] !in 40.0..49.999999 || it[1] !in 30.0..39.999999 }) {
            result.success(mapOf("code" to "OutsideCoverage"))
            return
        }
        current?.cancel()
        val request = NavKurdDirections()
        current = request
        currentId = id
        io.execute {
            try {
                val files = installed(context)
                val heap = context.getSystemService(ActivityManager::class.java).memoryClass
                val response = request.calculate(File(files, "segments"), File(files, "profiles"), mode,
                    doubleArrayOf(origin[0], destination[0]), doubleArrayOf(origin[1], destination[1]), heap / 3)
                main.post { result.success(response) }
            } catch (e: Exception) {
                main.post { result.error("offline_route", "Could not read the installed road graph", null) }
            } finally {
                main.post { if (current === request) current = null }
            }
        }
    }

    fun cancel(id: Int?) { if (id == currentId) current?.cancel() }
    fun close() { current?.cancel(); io.shutdown() }

    private fun coordinate(raw: List<*>?): DoubleArray? {
        if (raw?.size != 2) return null
        val lon = (raw[0] as? Number)?.toDouble() ?: return null
        val lat = (raw[1] as? Number)?.toDouble() ?: return null
        return if (lon in -180.0..180.0 && lat in -90.0..90.0) doubleArrayOf(lon, lat) else null
    }

    companion object {
        private var ready: File? = null

        @Synchronized private fun installed(context: Context): File {
            ready?.let { return it }
            val manifest = context.assets.open("road-graph/manifest.json").bufferedReader().use { JSONObject(it.readText()) }
            val root = File(context.noBackupFilesDir, "offline-routes/" + manifest.getString("tag"))
            val segments = File(root, "segments").apply { mkdirs() }
            val profiles = File(root, "profiles").apply { mkdirs() }
            val files = manifest.getJSONObject("files")
            for (name in files.keys()) {
                val record = files.getJSONArray(name)
                val file = File(segments, name)
                if (!file.isFile || file.length() != record.getLong(0))
                    extract(context, "road-graph/$name", file, record.getString(1))
            }
            for (name in listOf("lookups.dat", "car-fast.brf", "trekking.brf", "hiking-mountain.brf"))
                extract(context, "routing-profiles/$name", File(profiles, name), null)
            ready = root
            return root
        }

        private fun extract(context: Context, asset: String, file: File, expected: String?) {
            val atomic = AtomicFile(file)
            val output = atomic.startWrite()
            try {
                val sha = MessageDigest.getInstance("SHA-256")
                DigestInputStream(context.assets.open(asset), sha).use { it.copyTo(output, 128 * 1024) }
                if (expected != null && sha.digest().joinToString("") { "%02x".format(it) } != expected)
                    throw IOException("Offline road data integrity check failed")
                atomic.finishWrite(output)
            } catch (e: Exception) {
                atomic.failWrite(output)
                throw e
            }
        }
    }
}
