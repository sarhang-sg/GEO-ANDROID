package com.navkurd.app

import android.Manifest
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import android.os.Build
import androidx.core.content.ContextCompat
import androidx.core.location.LocationManagerCompat
import androidx.core.os.CancellationSignal
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** Optional widget location. No polling loop, foreground service or permission bypass. */
object NavKurdWidgetLocation {
    const val ACTION = "com.navkurd.app.WIDGET_LOCATION"
    private const val KEY = "automatic_widget_location"
    @Volatile var foreground = false

    private fun granted(context: Context): Boolean {
        val foregroundPermission = ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        return foregroundPermission && (Build.VERSION.SDK_INT < 29 ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED)
    }

    fun enabled(context: Context): Boolean = granted(context) &&
        context.getSharedPreferences(NavKurdWidgetProvider.PREFERENCES, Context.MODE_PRIVATE).getBoolean(KEY, false)

    fun setEnabled(context: Context, value: Boolean): Boolean {
        val enabled = value && granted(context)
        context.getSharedPreferences(NavKurdWidgetProvider.PREFERENCES, Context.MODE_PRIVATE).edit().putBoolean(KEY, enabled).apply()
        configure(context)
        if (enabled && NavKurdWidgetProvider.hasWidgets(context)) NavKurdWeatherJob.schedule(context, force = true)
        return enabled
    }

    fun configure(context: Context) {
        val manager = context.getSystemService(LocationManager::class.java)
        // LocationManager fills in the location extra. The mutable intent is explicit.
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or if (Build.VERSION.SDK_INT >= 31) PendingIntent.FLAG_MUTABLE else 0
        val intent = PendingIntent.getBroadcast(context, 901033,
            Intent(context, NavKurdWidgetLocationReceiver::class.java).setAction(ACTION), flags)
        runCatching {
            manager.removeUpdates(intent)
            if (enabled(context) && NavKurdWidgetProvider.hasWidgets(context)) {
                manager.requestLocationUpdates(LocationManager.PASSIVE_PROVIDER, 15L * 60L * 1000L, 1000f, intent)
            }
        }.onFailure {
            NavKurdDiagnostics.record(context, "warning", "widget.location", "Automatic widget location is unavailable: ${it.javaClass.simpleName}")
        }
    }

    fun latest(context: Context): Location? {
        if (!foreground && !enabled(context)) return null
        val manager = context.getSystemService(LocationManager::class.java)
        val now = System.currentTimeMillis()
        return manager.allProviders.mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .filter { valid(it) && now - it.time in 0..15L * 60L * 1000L }
            .maxByOrNull { it.time }
    }

    // Called only on the weather worker, with explicit background-location consent.
    fun current(context: Context): Location? {
        latest(context)?.let { return it }
        if (!enabled(context) || !NavKurdWidgetProvider.hasWidgets(context)) return null
        val manager = context.getSystemService(LocationManager::class.java)
        val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER)
            .firstOrNull { runCatching { manager.isProviderEnabled(it) }.getOrDefault(false) } ?: return null
        val signal = CancellationSignal()
        val latch = CountDownLatch(1)
        val result = AtomicReference<Location?>(null)
        try {
            LocationManagerCompat.getCurrentLocation(manager, provider, signal, Executor { it.run() }) { location ->
                if (location != null && valid(location)) result.set(location)
                latch.countDown()
            }
            latch.await(8, TimeUnit.SECONDS)
            return result.get()?.takeIf { System.currentTimeMillis() - it.time in 0..15L * 60L * 1000L }
        } catch (_: SecurityException) {
            return null
        } finally { signal.cancel() }
    }

    fun valid(location: Location): Boolean = location.latitude.isFinite() && location.longitude.isFinite() &&
        location.latitude in -90.0..90.0 && location.longitude in -180.0..180.0 &&
        (!location.hasAccuracy() || (location.accuracy.isFinite() && location.accuracy in 0f..10_000f))
}
