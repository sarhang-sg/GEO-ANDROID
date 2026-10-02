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

    fun schedule(context: Context, resetClock: Boolean = false) {
        NavKurdNotifications.createChannels(context)
        val manager = context.getSystemService(AlarmManager::class.java)
        val existing = PendingIntent.getBroadcast(context, 900003,
            Intent(context, NavKurdNotificationReceiver::class.java).setAction(ACTION_DAILY_WEATHER),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
        if (resetClock || existing == null) manager.setInexactRepeating(
            AlarmManager.RTC_WAKEUP,
            nextDailyWeatherTime(),
            DAY_MILLIS,
            pending(context, ACTION_DAILY_WEATHER, 900003),
        )
        // Remove the superseded alarm-driven HTTP path during upgrades.
        for (code in listOf(900004, 900005)) {
            val legacy = PendingIntent.getBroadcast(context, code,
                Intent(context, NavKurdNotificationReceiver::class.java).setAction(ACTION_UPDATE_CHECK),
                PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE)
            if (legacy != null) { manager.cancel(legacy); legacy.cancel() }
        }
        NavKurdReleaseJob.schedule(context, periodic = true)
    }

    fun checkForUpdateSoon(context: Context) {
        NavKurdReleaseJob.schedule(context)
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
