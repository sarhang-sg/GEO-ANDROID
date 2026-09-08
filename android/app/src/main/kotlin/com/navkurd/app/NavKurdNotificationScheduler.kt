package com.navkurd.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import java.util.Calendar

object NavKurdNotificationScheduler {
    const val ACTION_DAILY_WEATHER = "com.navkurd.app.DAILY_WEATHER"
    const val ACTION_UPDATE_CHECK = "com.navkurd.app.UPDATE_CHECK"

    private const val DAY_MILLIS = 24L * 60L * 60L * 1000L
    private const val UPDATE_INTERVAL_MILLIS = 12L * 60L * 60L * 1000L

    fun schedule(context: Context) {
        NavKurdNotifications.createChannels(context)
        val manager = context.getSystemService(AlarmManager::class.java)
        manager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextDailyWeatherTime(),
            DAY_MILLIS,
            pending(context, ACTION_DAILY_WEATHER, 900003),
        )
        manager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 15L * 60L * 1000L,
            UPDATE_INTERVAL_MILLIS,
            pending(context, ACTION_UPDATE_CHECK, 900004),
        )
    }

    fun checkForUpdateSoon(context: Context) {
        val manager = context.getSystemService(AlarmManager::class.java)
        manager.set(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + 20_000L,
            pending(context, ACTION_UPDATE_CHECK, 900005),
        )
    }

    private fun nextDailyWeatherTime(): Long {
        val now = Calendar.getInstance()
        val next = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 8)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= now.timeInMillis) add(Calendar.DAY_OF_YEAR, 1)
        }
        return next.timeInMillis
    }

    private fun pending(context: Context, action: String, requestCode: Int): PendingIntent {
        val intent = Intent(context, NavKurdNotificationReceiver::class.java).apply {
            this.action = action
        }
        return PendingIntent.getBroadcast(
            context,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
