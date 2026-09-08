package com.navkurd.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

class NavKurdNotificationReceiver : BroadcastReceiver() {
    companion object {
        private const val RELEASE_URL = "https://geo-map-kappa.vercel.app/releases/latest.json"
        private const val RELEASE_PREFERENCES = "nav_kurd_release_notifications"
        private const val KEY_NOTIFIED_VERSION = "notified_version"
        private val executor = Executors.newSingleThreadExecutor()
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                NavKurdNotificationScheduler.schedule(context)
                NavKurdWidgetProvider.scheduleRefresh(context)
                if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
                    NavKurdNotificationScheduler.checkForUpdateSoon(context)
                }
            }
            NavKurdNotificationScheduler.ACTION_DAILY_WEATHER -> {
                val pending = goAsync()
                NavKurdWidgetProvider.refreshWeather(context, force = true) {
                    try {
                        NavKurdNotifications.showDailyWeather(context)
                    } finally {
                        pending.finish()
                    }
                }
            }
            NavKurdNotificationScheduler.ACTION_UPDATE_CHECK -> {
                val pending = goAsync()
                executor.execute {
                    try {
                        checkForUpdate(context.applicationContext)
                    } catch (error: Exception) {
                        NavKurdDiagnostics.record(
                            context,
                            "warning",
                            "notification.update-check",
                            error.message ?: "Update check failed",
                        )
                    } finally {
                        pending.finish()
                    }
                }
            }
        }
    }

    private fun checkForUpdate(context: Context) {
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
            val release = JSONObject(connection.inputStream.bufferedReader().use { it.readText() })
            if (release.optString("packageName") != context.packageName) return
            val latestVersion = release.optString("version").trim()
            val latestCode = release.optLong("versionCode", -1L)
            if (latestVersion.isBlank() || latestCode <= currentVersionCode(context)) return

            val preferences = context.getSharedPreferences(RELEASE_PREFERENCES, Context.MODE_PRIVATE)
            if (preferences.getString(KEY_NOTIFIED_VERSION, null) == latestVersion) return
            val rawUrl = release.optString("directApkUrl")
            val downloadUrl = if (rawUrl.startsWith("https://")) {
                rawUrl
            } else {
                "https://geo-map-kappa.vercel.app/${rawUrl.trimStart('/')}"
            }
            NavKurdNotifications.showUpdate(context, latestVersion, downloadUrl)
            preferences.edit().putString(KEY_NOTIFIED_VERSION, latestVersion).apply()
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
