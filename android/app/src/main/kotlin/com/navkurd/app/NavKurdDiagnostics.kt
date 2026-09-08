package com.navkurd.app

import android.Manifest
import android.app.ActivityManager
import android.app.NotificationManager
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.PowerManager
import android.os.StatFs
import android.webkit.WebView
import androidx.core.content.ContextCompat
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** Stores sanitized, real device/runtime failures for the in-app report panel. */
object NavKurdDiagnostics {
    private const val PREFERENCES = "nav_kurd_native_diagnostics"
    private const val KEY_EVENTS = "events"
    private const val MAX_EVENTS = 40

    @Synchronized
    fun record(
        context: Context,
        level: String,
        source: String,
        message: String,
        stack: String? = null,
    ) {
        val safeLevel = when (level.lowercase(Locale.US)) {
            "error" -> "error"
            "warning", "warn" -> "warning"
            else -> "info"
        }
        val entry = JSONObject().apply {
            put("at", isoNow())
            put("level", safeLevel)
            put("source", sanitize(source, 100))
            put("message", sanitize(message, 1800))
            stack?.takeIf { it.isNotBlank() }?.let {
                put("stack", sanitize(it, 3000))
            }
        }
        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val events = runCatching {
            JSONArray(preferences.getString(KEY_EVENTS, "[]") ?: "[]")
        }.getOrElse { JSONArray() }
        val trimmed = JSONArray()
        val start = (events.length() - (MAX_EVENTS - 1)).coerceAtLeast(0)
        for (index in start until events.length()) trimmed.put(events.opt(index))
        trimmed.put(entry)
        preferences.edit().putString(KEY_EVENTS, trimmed.toString()).apply()
    }

    @Synchronized
    fun report(context: Context): String {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            packageInfo.versionCode.toLong()
        }
        val lines = mutableListOf(
            "[META] Native Android diagnostics",
            "[META] Captured: ${isoNow()}",
            "[META] App: ${packageInfo.versionName ?: "unknown"} ($versionCode) · ${context.packageName}",
            "[META] Android: ${Build.VERSION.RELEASE} / SDK ${Build.VERSION.SDK_INT} · ${sanitize(Build.MANUFACTURER, 80)} ${sanitize(Build.MODEL, 120)}",
            "[META] ABI: ${Build.SUPPORTED_ABIS.joinToString(", ")}",
            webViewLine(),
            networkLine(context),
            memoryLine(context),
            batteryLine(context),
            storageLine("Internal app data", context.filesDir),
            storageLine("External app data", context.getExternalFilesDir(null)),
            "[META] Storage model: scoped app storage + MediaStore/DownloadManager exports",
            permissionLine(context),
            widgetLine(context),
        )

        val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
        val events = runCatching {
            JSONArray(preferences.getString(KEY_EVENTS, "[]") ?: "[]")
        }.getOrElse { JSONArray() }
        val errors = (0 until events.length()).count {
            events.optJSONObject(it)?.optString("level") == "error"
        }
        val warnings = (0 until events.length()).count {
            events.optJSONObject(it)?.optString("level") == "warning"
        }
        lines += "[META] Native issue summary: errors=$errors warnings=$warnings total=${events.length()}"
        if (events.length() == 0) {
            lines += "[OK] No native Android, Flutter, or WebView failures captured in stored history."
        } else {
            lines += ""
            lines += "[META] Recent native issues (newest first):"
            val first = (events.length() - 8).coerceAtLeast(0)
            for (index in events.length() - 1 downTo first) {
                val event = events.optJSONObject(index) ?: continue
                val label = when (event.optString("level")) {
                    "error" -> "ERROR"
                    "warning" -> "WARN"
                    else -> "INFO"
                }
                lines += "[$label] ${event.optString("at")} · ${event.optString("source")} · ${event.optString("message").take(700)}"
            }
        }
        return lines.joinToString("\n")
    }

    private fun webViewLine(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return "[META] Android System WebView: package details unavailable below SDK 26"
        }
        return runCatching {
            val info = WebView.getCurrentWebViewPackage()
            "[META] Android System WebView: ${info?.packageName ?: "unavailable"} ${info?.versionName ?: "unknown"}"
        }.getOrElse { "[WARN] Android System WebView package could not be inspected" }
    }

    private fun networkLine(context: Context): String {
        return runCatching {
            val manager = context.getSystemService(ConnectivityManager::class.java)
            val network = manager.activeNetwork
            val capabilities = manager.getNetworkCapabilities(network)
            val transport = when {
                capabilities == null -> "offline"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
                capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN) -> "vpn"
                else -> "other"
            }
            val validated = capabilities?.hasCapability(
                NetworkCapabilities.NET_CAPABILITY_VALIDATED,
            ) == true
            "[META] Network: $transport · validated=$validated · metered=${manager.isActiveNetworkMetered}"
        }.getOrElse { "[WARN] Network state could not be inspected" }
    }

    private fun memoryLine(context: Context): String {
        return runCatching {
            val manager = context.getSystemService(ActivityManager::class.java)
            val info = ActivityManager.MemoryInfo()
            manager.getMemoryInfo(info)
            "[META] Memory: available=${humanBytes(info.availMem)} / total=${humanBytes(info.totalMem)} · low=${info.lowMemory}"
        }.getOrElse { "[WARN] Device memory could not be inspected" }
    }

    private fun batteryLine(context: Context): String {
        return runCatching {
            val manager = context.getSystemService(BatteryManager::class.java)
            val capacity = manager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
            val battery = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
            val status = battery?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
            val charging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
            val powerSave = context.getSystemService(PowerManager::class.java).isPowerSaveMode
            "[META] Battery: $capacity% · charging=$charging · powerSave=$powerSave"
        }.getOrElse { "[WARN] Battery state could not be inspected" }
    }

    private fun storageLine(label: String, directory: File?): String {
        if (directory == null) return "[WARN] $label: unavailable"
        return runCatching {
            val stats = StatFs(directory.absolutePath)
            "[META] $label: free=${humanBytes(stats.availableBytes)} / total=${humanBytes(stats.totalBytes)}"
        }.getOrElse { "[WARN] $label: could not be inspected" }
    }

    private fun permissionLine(context: Context): String {
        fun granted(permission: String): Boolean = ContextCompat.checkSelfPermission(
            context,
            permission,
        ) == PackageManager.PERMISSION_GRANTED
        val notifications = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            granted(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            context.getSystemService(NotificationManager::class.java).areNotificationsEnabled()
        }
        return "[META] Permissions: fineLocation=${granted(Manifest.permission.ACCESS_FINE_LOCATION)} " +
            "coarseLocation=${granted(Manifest.permission.ACCESS_COARSE_LOCATION)} " +
            "camera=${granted(Manifest.permission.CAMERA)} notifications=$notifications"
    }

    private fun widgetLine(context: Context): String {
        val preferences = context.getSharedPreferences(
            NavKurdWidgetProvider.PREFERENCES,
            Context.MODE_PRIVATE,
        )
        val city = sanitize(preferences.getString(NavKurdWidgetProvider.KEY_CITY, null) ?: "unknown", 100)
        val weatherAt = preferences.getLong(NavKurdWidgetProvider.KEY_WEATHER_AT, 0L)
        val age = if (weatherAt > 0L) ((System.currentTimeMillis() - weatherAt) / 60000L).coerceAtLeast(0) else -1
        val locationStored = preferences.contains(NavKurdWidgetProvider.KEY_LATITUDE) &&
            preferences.contains(NavKurdWidgetProvider.KEY_LONGITUDE)
        val widgetCount = runCatching {
            AppWidgetManager.getInstance(context).getAppWidgetIds(
                ComponentName(context, NavKurdWidgetProvider::class.java),
            ).size
        }.getOrDefault(-1)
        val lastRenderAt = preferences.getLong(NavKurdWidgetProvider.KEY_LAST_RENDER_AT, 0L)
        val renderAge = if (lastRenderAt > 0L) {
            ((System.currentTimeMillis() - lastRenderAt) / 60000L).coerceAtLeast(0)
        } else {
            -1
        }
        val renderError = sanitize(
            preferences.getString(NavKurdWidgetProvider.KEY_LAST_RENDER_ERROR, null) ?: "none",
            180,
        )
        val timezone = sanitize(
            preferences.getString(NavKurdWidgetProvider.KEY_TIMEZONE, null) ?: "unknown",
            80,
        )
        val phase = if (preferences.contains(NavKurdWidgetProvider.KEY_IS_DAY)) {
            if (preferences.getBoolean(NavKurdWidgetProvider.KEY_IS_DAY, true)) "day" else "night"
        } else {
            "unknown"
        }
        val weatherCode = preferences.getInt(NavKurdWidgetProvider.KEY_WEATHER_CODE, -1)
        val dust = preferences.getFloat(NavKurdWidgetProvider.KEY_DUST, Float.NaN)
        val dustValue = if (dust.isFinite()) String.format(Locale.US, "%.1f", dust) else "unknown"
        return "[META] Widget: installed=$widgetCount · city=$city · " +
            "locationStored=$locationStored · weatherAgeMinutes=$age · " +
            "timezone=$timezone · phase=$phase · weatherCode=$weatherCode · " +
            "dust=$dustValue · renderAgeMinutes=$renderAge · renderError=$renderError"
    }

    private fun humanBytes(value: Long): String {
        if (value < 1024L) return "$value B"
        val units = arrayOf("KiB", "MiB", "GiB", "TiB")
        var amount = value.toDouble()
        var unit = -1
        do {
            amount /= 1024.0
            unit += 1
        } while (amount >= 1024.0 && unit < units.lastIndex)
        return String.format(Locale.US, "%.1f %s", amount, units[unit])
    }

    private fun sanitize(value: String, limit: Int): String {
        return value
            .replace(Regex("Bearer\\s+[A-Za-z0-9._~-]+", RegexOption.IGNORE_CASE), "Bearer <redacted>")
            .replace(Regex("([?&](?:key|token|access_token|api_key|secret)=)[^&\\s]+", RegexOption.IGNORE_CASE), "\$1<redacted>")
            .replace(Regex("[A-Z0-9._%+-]+@[A-Z0-9.-]+\\.[A-Z]{2,}", RegexOption.IGNORE_CASE), "<email-redacted>")
            .replace(Regex("-?\\d{1,2}\\.\\d{4,}\\s*[,/]\\s*-?\\d{1,3}\\.\\d{4,}"), "<coordinates-redacted>")
            .replace(Regex("[\\r\\n\\t]+"), " ")
            .trim()
            .take(limit)
    }

    private fun isoNow(): String {
        val format = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        format.timeZone = TimeZone.getTimeZone("UTC")
        return format.format(Date())
    }
}
