package com.navkurd.app

import android.Manifest
import android.app.DownloadManager
import android.app.PendingIntent
import android.content.ComponentCallbacks2
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.util.Base64
import android.view.WindowManager
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.Locale

class MainActivity : FlutterActivity(), EventChannel.StreamHandler {
    companion object {
        private const val METHOD_CHANNEL = "navkurd/native"
        private const val DEEP_LINK_CHANNEL = "navkurd/deep_links"
        private const val DOWNLOAD_FOLDER = "NAV KURD"
    }

    private var deepLinkSink: EventChannel.EventSink? = null
    private var pendingDeepLink: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyImmersiveMode()
        NavKurdNotificationScheduler.schedule(this)
        NavKurdNotificationScheduler.checkForUpdateSoon(this)
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) applyImmersiveMode()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        NavKurdNotifications.createChannels(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler(::handleMethodCall)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, DEEP_LINK_CHANNEL)
            .setStreamHandler(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.dataString?.let { value ->
            val sink = deepLinkSink
            if (sink == null) pendingDeepLink = value else sink.success(value)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        deepLinkSink = events
        pendingDeepLink?.let { value ->
            events?.success(value)
            pendingDeepLink = null
        }
    }

    override fun onCancel(arguments: Any?) {
        deepLinkSink = null
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getInitialDeepLink" -> result.success(intent?.dataString)
                "getSdkInt" -> result.success(Build.VERSION.SDK_INT)
                "getRuntimeInfo" -> result.success(NavKurdRuntimeInfo.collect(this))
                "clearTransientCache" -> result.success(clearTransientCache())
                "setLanguage" -> {
                    NavKurdWidgetProvider.setLanguage(
                        this,
                        call.argument<String>("language") ?: "ku",
                    )
                    NavKurdNotifications.createChannels(this)
                    result.success(null)
                }
                "scheduleNotifications" -> {
                    NavKurdNotificationScheduler.schedule(this)
                    NavKurdNotificationScheduler.checkForUpdateSoon(this)
                    result.success(null)
                }
                "enterImmersiveMode" -> {
                    applyImmersiveMode()
                    result.success(null)
                }
                "recordDiagnostic" -> {
                    NavKurdDiagnostics.record(
                        this,
                        call.argument<String>("level") ?: "warning",
                        call.argument<String>("source") ?: "flutter.runtime",
                        call.argument<String>("message") ?: "Unknown runtime issue",
                        call.argument<String>("stack"),
                    )
                    result.success(null)
                }
                "getDiagnosticReport" -> result.success(NavKurdDiagnostics.report(this))
                "enqueueDownload" -> result.success(enqueueDownload(call))
                "saveBase64Download" -> result.success(saveBase64Download(call))
                "showNotification" -> {
                    showNotification(
                        call.argument<String>("title") ?: getString(R.string.app_name),
                        call.argument<String>("body") ?: "",
                    )
                    result.success(null)
                }
                "updateWidget" -> {
                    updateWidget(
                        call.argument<String>("status") ?: "ONLINE",
                        call.argument<String>("detail") ?: "Kurdistan Atlas",
                    )
                    result.success(null)
                }
                "updateWidgetLocation" -> {
                    val latitude = call.argument<Number>("latitude")?.toDouble()
                        ?: error("Missing latitude")
                    val longitude = call.argument<Number>("longitude")?.toDouble()
                        ?: error("Missing longitude")
                    val accuracy = call.argument<Number>("accuracy")?.toDouble() ?: 0.0
                    require(latitude in -90.0..90.0 && longitude in -180.0..180.0) {
                        "Invalid widget location"
                    }
                    NavKurdWidgetProvider.storeLocationAndRefresh(
                        this,
                        latitude,
                        longitude,
                        accuracy,
                    )
                    result.success(null)
                }
                "refreshWidgetWeather" -> {
                    NavKurdWidgetProvider.refreshWeather(this, force = false)
                    result.success(null)
                }
                "openDownloads" -> {
                    openDownloads()
                    result.success(null)
                }
                "openAppSettings" -> {
                    openAppSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Exception) {
            NavKurdDiagnostics.record(
                this,
                "error",
                "native.${call.method}",
                error.message ?: error.javaClass.simpleName,
                error.stackTraceToString(),
            )
            result.error("NAV_KURD_NATIVE", error.message ?: "Native operation failed", null)
        }
    }

    override fun onLowMemory() {
        NavKurdDiagnostics.record(
            this,
            "warning",
            "android.memory",
            "Android reported a low-memory condition.",
        )
        super.onLowMemory()
    }

    override fun onTrimMemory(level: Int) {
        // TRIM_MEMORY_UI_HIDDEN is level 20. It is a normal lifecycle signal
        // when NAV KURD goes into the background (for example while the user
        // opens the widget picker), not evidence of low memory.
        val isRealMemoryPressure =
            level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW ||
                level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL ||
                level == ComponentCallbacks2.TRIM_MEMORY_MODERATE ||
                level == ComponentCallbacks2.TRIM_MEMORY_COMPLETE
        if (isRealMemoryPressure) {
            NavKurdDiagnostics.record(
                this,
                "warning",
                "android.memory",
                "Android requested memory trimming (level $level).",
            )
        }
        super.onTrimMemory(level)
    }

    private fun applyImmersiveMode() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes = window.attributes.apply {
                layoutInDisplayCutoutMode =
                    WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        WindowCompat.getInsetsController(window, window.decorView).apply {
            systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            hide(WindowInsetsCompat.Type.systemBars())
        }
    }

    private fun enqueueDownload(call: MethodCall): Long {
        val rawUrl = call.argument<String>("url")?.trim().orEmpty()
        val uri = Uri.parse(rawUrl)
        require(uri.scheme.equals("https", ignoreCase = true)) {
            "Only secure HTTPS downloads are supported"
        }

        val mimeType = call.argument<String>("mimeType")?.trim()?.ifEmpty { null }
        val contentDisposition = call.argument<String>("contentDisposition")
        val requestedName = call.argument<String>("fileName")
        val guessedName = URLUtil.guessFileName(rawUrl, contentDisposition, mimeType)
        val fileName = sanitizeFileName(requestedName ?: guessedName, mimeType)
        val request = DownloadManager.Request(uri)
            .setTitle(fileName)
            .setDescription(getString(R.string.download_in_progress))
            .setAllowedOverMetered(true)
            .setAllowedOverRoaming(true)
            .setNotificationVisibility(
                DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED,
            )
            .setDestinationInExternalPublicDir(
                Environment.DIRECTORY_DOWNLOADS,
                "$DOWNLOAD_FOLDER/$fileName",
            )

        if (!mimeType.isNullOrBlank()) request.setMimeType(mimeType)
        call.argument<String>("userAgent")
            ?.takeIf { it.isNotBlank() }
            ?.let { request.addRequestHeader("User-Agent", it) }
        call.argument<String>("cookies")
            ?.takeIf { it.isNotBlank() }
            ?.let { request.addRequestHeader("Cookie", it) }

        val manager = getSystemService(DOWNLOAD_SERVICE) as DownloadManager
        return manager.enqueue(request)
    }

    private fun saveBase64Download(call: MethodCall): String {
        val fileName = sanitizeFileName(
            call.argument<String>("fileName") ?: "nav-kurd-file",
            call.argument<String>("mimeType"),
        )
        val mimeType = call.argument<String>("mimeType")
            ?.takeIf { it.isNotBlank() }
            ?: "application/octet-stream"
        val encoded = call.argument<String>("base64Data")
            ?: error("Missing base64 payload")
        require(encoded.length <= 70 * 1024 * 1024) {
            "The blob download exceeds the native bridge limit"
        }
        val payload = encoded.substringAfter(',', encoded)
        val bytes = Base64.decode(payload, Base64.DEFAULT)

        val destination = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            saveWithMediaStore(fileName, mimeType, bytes)
        } else {
            saveLegacy(fileName, bytes)
        }
        showNotification(
            getString(R.string.download_complete),
            getString(R.string.download_saved, fileName),
        )
        return destination.toString()
    }

    private fun saveWithMediaStore(
        fileName: String,
        mimeType: String,
        bytes: ByteArray,
    ): Uri {
        val values = ContentValues().apply {
            put(MediaStore.Downloads.DISPLAY_NAME, fileName)
            put(MediaStore.Downloads.MIME_TYPE, mimeType)
            put(
                MediaStore.Downloads.RELATIVE_PATH,
                "${Environment.DIRECTORY_DOWNLOADS}/$DOWNLOAD_FOLDER",
            )
            put(MediaStore.Downloads.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = contentResolver.insert(collection, values)
            ?: error("Could not create the download")
        try {
            contentResolver.openOutputStream(uri, "w")?.use { stream ->
                stream.write(bytes)
                stream.flush()
            } ?: error("Could not open the download destination")
            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
            return uri
        } catch (error: Exception) {
            contentResolver.delete(uri, null, null)
            throw error
        }
    }

    @Suppress("DEPRECATION")
    private fun saveLegacy(fileName: String, bytes: ByteArray): Uri {
        val downloads = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS,
        )
        val directory = File(downloads, DOWNLOAD_FOLDER).apply { mkdirs() }
        val destination = uniqueFile(directory, fileName)
        FileOutputStream(destination).use { stream ->
            stream.write(bytes)
            stream.flush()
        }
        return Uri.fromFile(destination)
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        val requested = File(directory, fileName)
        if (!requested.exists()) return requested
        val dot = fileName.lastIndexOf('.')
        val stem = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var index = 2
        while (true) {
            val candidate = File(directory, "$stem ($index)$extension")
            if (!candidate.exists()) return candidate
            index += 1
        }
    }

    private fun sanitizeFileName(value: String, mimeType: String?): String {
        var cleaned = value
            .trim()
            .replace(Regex("[\\\\/:*?\"<>|\\u0000-\\u001F]"), "_")
            .replace(Regex("\\s+"), " ")
            .trim('.', ' ')
        if (cleaned.isBlank()) cleaned = "nav-kurd-file"

        if (!cleaned.contains('.') && !mimeType.isNullOrBlank()) {
            val extension = MimeTypeMap.getSingleton()
                .getExtensionFromMimeType(mimeType.lowercase(Locale.US))
            if (!extension.isNullOrBlank()) cleaned += ".$extension"
        }
        if (cleaned.length > 120) {
            val dot = cleaned.lastIndexOf('.')
            val extension = if (dot > 0 && cleaned.length - dot <= 12) {
                cleaned.substring(dot)
            } else {
                ""
            }
            cleaned = cleaned.take(120 - extension.length) + extension
        }
        return cleaned
    }

    private fun clearTransientCache(): Map<String, Boolean> {
        var cleared = true
        cacheDir.listFiles()?.forEach { entry ->
            if (!entry.deleteRecursively()) cleared = false
        }
        return mapOf("cleared" to cleared)
    }

    private fun showNotification(title: String, body: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse("navkurd://open")
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            1001,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, NavKurdNotifications.CHANNEL_GENERAL)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(this).notify(
            (System.currentTimeMillis() and 0x0FFFFFFF).toInt(),
            notification,
        )
    }

    private fun updateWidget(status: String, detail: String) {
        NavKurdWidgetProvider.updateStatus(this, status, detail)
    }

    private fun openDownloads() {
        val intent = Intent(DownloadManager.ACTION_VIEW_DOWNLOADS)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }

    private fun openAppSettings() {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:$packageName"),
        ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
    }
}
