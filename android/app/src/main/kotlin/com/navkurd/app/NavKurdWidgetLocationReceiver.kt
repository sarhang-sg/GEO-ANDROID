package com.navkurd.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.location.Location
import android.location.LocationManager
import android.os.Build

class NavKurdWidgetLocationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != NavKurdWidgetLocation.ACTION || !NavKurdWidgetLocation.enabled(context)) return
        @Suppress("DEPRECATION")
        val location = if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(LocationManager.KEY_LOCATION_CHANGED, Location::class.java)
            else intent.getParcelableExtra<Location>(LocationManager.KEY_LOCATION_CHANGED)
        if (location == null || !NavKurdWidgetLocation.valid(location) || System.currentTimeMillis() - location.time !in 0..15L * 60L * 1000L) return
        // The worker reads the OS-owned last fix; extras never become an authority.
        NavKurdWeatherJob.schedule(context, force = true)
    }
}
