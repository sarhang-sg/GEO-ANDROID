package com.navkurd.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL

class NavKurdNotificationReceiver : BroadcastReceiver() {
    companion object {
        private const val RELEASE_URL = "https://geo-map-kappa.vercel.app/releases/latest.json"
        private const val RELEASE_PREFERENCES = "nav_kurd_release_notifications"
        private const val KEY_NOTIFIED_VERSION = "notified_version"
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                NavKurdNotificationScheduler.schedule(context, resetClock = true)
                NavKurdWidgetProvider.scheduleRefresh(context)
                if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
                    NavKurdNotificationScheduler.checkForUpdateSoon(context)
                }
            }
            NavKurdNotificationScheduler.ACTION_DAILY_WEATHER -> {
                NavKurdWeatherJob.schedule(context, force = true, daily = true)
            }
            NavKurdNotificationScheduler.ACTION_UPDATE_CHECK -> {
                NavKurdReleaseJob.schedule(context)
            }
        }
    }

    fun checkForUpdate(context: Context) {
        val connection = URL(RELEASE_URL).openConnection() as HttpURLConnection
        connection.connectTimeout = 10_000
        connection.readTimeout = 10_000
        connection.requestMethod = "GET"
        connection.setRequestProperty("Accept", "application/json")
        connection.setRequestProperty("User-Agent", "NAV-KURD-Android/${currentVersion(context)}")
        try {
            require(connection.responseCode in 200..299) {
                "Release service returned HTTP ${connection.responseCode}"
            }
            val text = connection.inputStream.bufferedReader().use { reader ->
                val buffer = CharArray(65537)
                var count = 0
                while (count < buffer.size) {
                    val n = reader.read(buffer, count, buffer.size - count)
                    if (n < 0) break
                    count += n
                }
                require(count <= 65536) { "Release response exceeds size limit" }
                String(buffer, 0, count)
            }
            val release = JSONObject(text)
            if (release.optString("packageName") != context.packageName) return
            val latestVersion = release.optString("version").trim()
            val latestCode = release.optLong("versionCode", -1L)
            if (!latestVersion.matches(Regex("\\d+\\.\\d+\\.\\d+")) || latestCode <= currentVersionCode(context)) return
            // A web version announcement is not proof that its APK exists.
            if (!release.optBoolean("directApkAvailable")) return

            val preferences = context.getSharedPreferences(RELEASE_PREFERENCES, Context.MODE_PRIVATE)
            if (preferences.getString(KEY_NOTIFIED_VERSION, null) == latestVersion) return
            val rawUrl = release.optString("directApkUrl").trim()
            val fileName = "NAV-KURD-$latestVersion.apk"
            val githubUrl = "https://github.com/sarhang-sg/GEO-ANDROID/releases/download/v$latestVersion/$fileName"
            val appUrl = "https://geo-map-kappa.vercel.app/downloads/$fileName"
            val downloadUrl = when (rawUrl) {
                githubUrl, appUrl -> rawUrl
                "/downloads/$fileName" -> appUrl
                else -> return
            }
            if (NavKurdNotifications.showUpdate(context, latestVersion, downloadUrl)) {
                preferences.edit().putString(KEY_NOTIFIED_VERSION, latestVersion).apply()
            }
        } finally {
            connection.disconnect()
        }
    }

    private fun currentVersion(context: Context): String = context.packageManager
        .getPackageInfo(context.packageName, 0)
        .versionName
        ?: "unknown"

    @Suppress("DEPRECATION")
    private fun currentVersionCode(context: Context): Long {
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            packageInfo.longVersionCode
        } else {
            packageInfo.versionCode.toLong()
        }
    }
}
