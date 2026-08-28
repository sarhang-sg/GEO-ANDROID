package com.navkurd.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat

object NavKurdNotifications {
    const val CHANNEL_DAILY_WEATHER = "nav_kurd_daily_weather"
    const val CHANNEL_APP_UPDATES = "nav_kurd_app_updates"
    const val CHANNEL_GENERAL = "nav_kurd_general"

    private const val NOTIFICATION_DAILY = 800041
    private const val NOTIFICATION_UPDATE = 800042

    fun createChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
        val language = language(context)
        val weatherName = when (language) {
            "en" -> "Daily weather"
            "ar" -> "الطقس اليومي"
            else -> "کەش‌وهەوای ڕۆژانە"
        }
        val updateName = when (language) {
            "en" -> "App updates"
            "ar" -> "تحديثات التطبيق"
            else -> "نوێکردنەوەی ئەپ"
        }
        val generalName = when (language) {
            "en" -> "NAV KURD activity"
            "ar" -> "نشاط NAV KURD"
            else -> "چالاکییەکانی NAV KURD"
        }
        manager.createNotificationChannels(
            listOf(
                NotificationChannel(CHANNEL_DAILY_WEATHER, weatherName, NotificationManager.IMPORTANCE_DEFAULT).apply {
                    description = when (language) {
                        "en" -> "A concise daily weather summary for your current area"
                        "ar" -> "ملخص يومي موجز للطقس في منطقتك الحالية"
                        else -> "پوختەیەکی ڕۆژانەی کەش‌وهەوای ناوچەکەت"
                    }
                },
                NotificationChannel(CHANNEL_APP_UPDATES, updateName, NotificationManager.IMPORTANCE_HIGH).apply {
                    description = when (language) {
                        "en" -> "Only notifies when a newer NAV KURD version is available"
                        "ar" -> "إشعار فقط عند توفر إصدار أحدث من NAV KURD"
                        else -> "تەنها کاتێک ڤێرژنی نوێتر بەردەست بێت ئاگادارت دەکاتەوە"
                    }
                },
                NotificationChannel(CHANNEL_GENERAL, generalName, NotificationManager.IMPORTANCE_DEFAULT),
            ),
        )
    }

    fun showDailyWeather(context: Context) {
        if (!canNotify(context)) return
        val summary = NavKurdWidgetProvider.dailyWeatherSummary(context) ?: return
        val notification = NotificationCompat.Builder(context, CHANNEL_DAILY_WEATHER)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(summary.first)
            .setContentText(summary.second)
            .setStyle(NotificationCompat.BigTextStyle().bigText(summary.second))
            .setContentIntent(openAppIntent(context, "navkurd://locate?action=locate", NOTIFICATION_DAILY))
            .setAutoCancel(true)
            .setOnlyAlertOnce(false)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(NOTIFICATION_DAILY, notification)
    }

    fun showUpdate(context: Context, latestVersion: String, downloadUrl: String) {
        if (!canNotify(context)) return
        val language = language(context)
        val title = when (language) {
            "en" -> "NAV KURD $latestVersion is available"
            "ar" -> "يتوفر NAV KURD $latestVersion"
            else -> "NAV KURD $latestVersion بەردەستە"
        }
        val body = when (language) {
            "en" -> "Update now for the latest map, GPS, widget, and reliability improvements."
            "ar" -> "حدّث الآن للحصول على أحدث تحسينات الخريطة وGPS والودجت والاستقرار."
            else -> "ئێستا نوێی بکەرەوە بۆ تازەترین چاکسازیی خەریتە، GPS، ویجێت و جێگیری."
        }
        val target = Uri.parse(downloadUrl)
        val launchIntent = Intent(Intent.ACTION_VIEW, target).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        val pendingIntent = PendingIntent.getActivity(
            context,
            NOTIFICATION_UPDATE,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(context, CHANNEL_APP_UPDATES)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .build()
        NotificationManagerCompat.from(context).notify(NOTIFICATION_UPDATE, notification)
    }

    private fun openAppIntent(context: Context, uri: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            data = Uri.parse(uri)
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        return PendingIntent.getActivity(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun canNotify(context: Context): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun language(context: Context): String = context
        .getSharedPreferences(NavKurdWidgetProvider.PREFERENCES, Context.MODE_PRIVATE)
        .getString(NavKurdWidgetProvider.KEY_LANGUAGE, "ku")
        ?: "ku"
}
