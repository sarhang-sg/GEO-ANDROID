package com.navkurd.app.location

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import androidx.core.content.ContextCompat
import com.navkurd.app.NavKurdWidgetProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.hypot
import kotlin.math.cos

/** One foreground device location owner. GPS with precise permission works
 * without network; approximate permission uses the device's coarse provider.
 * Provider/permission failures are explicit, not fabricated coordinates. */
class NativeLocationService(context: Context, messenger: BinaryMessenger) : LocationListener, EventChannel.StreamHandler {
    private val app = context.applicationContext
    private val manager = app.getSystemService(Context.LOCATION_SERVICE) as LocationManager
    private val methods = MethodChannel(messenger, "navkurd/location")
    private val events = EventChannel(messenger, "navkurd/location_events")
    private var sink: EventChannel.EventSink? = null
    private var wanted = false
    private var foreground = false
    private var registered = false
    private var selectedProvider: String? = null
    private var recent: Location? = null
    private var widgetFix: Location? = null
    private var widgetAt = 0L
    init {
        events.setStreamHandler(this)
        methods.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "status" -> result.success(status())
                    "start" -> {
                        if (permission() == "denied") result.error("permission_denied", "Location permission is not granted.", null)
                        else {
                            wanted = true; reconcile()
                            result.success(null)
                        }
                    }
                    "stop" -> { wanted = false; unregister(); result.success(null) }
                    else -> result.notImplemented()
                }
            } catch (error: SecurityException) { unregister(); result.error("permission_denied", error.message, null) }
            catch (error: IllegalArgumentException) { unregister(); result.error("provider_unavailable", error.message, null) }
        }
    }
    fun resume() { foreground = true; reconcile() }
    fun pause() { foreground = false; unregister() }
    fun close() { wanted = false; unregister(); methods.setMethodCallHandler(null); events.setStreamHandler(null); sink = null }
    private fun permission(): String = when {
        ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED -> "precise"
        ContextCompat.checkSelfPermission(app, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED -> "approximate"
        else -> "denied"
    }
    private fun provider(): String? {
        val candidate = if (permission() == "precise") LocationManager.GPS_PROVIDER else LocationManager.NETWORK_PROVIDER
        return candidate.takeIf { manager.allProviders.contains(it) }
    }
    private fun snapshot(location: Location): Map<String, Any?> = mapOf(
        "latitude" to location.latitude, "longitude" to location.longitude, "accuracy" to location.accuracy.toDouble(),
        "heading" to if (location.hasBearing()) location.bearing.toDouble() else null,
        "speed" to if (location.hasSpeed()) location.speed.toDouble() else null,
        "altitude" to if (location.hasAltitude()) location.altitude else null, "timestamp" to location.time,
        "ageMillis" to ((SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1_000_000).coerceAtLeast(0),
        "provider" to location.provider, "permission" to permission())
    private fun cached(): Location? {
        if (permission() == "denied") return null
        val selected = provider()
        val local = recent?.takeIf { it.provider == selected } ?: selected?.let { manager.getLastKnownLocation(it) }
        return local?.takeIf { SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos in 0..300_000_000_000L }
    }
    private fun status(): Map<String, Any?> {
        val selected = provider()
        return mapOf("permission" to permission(), "provider" to selected,
            "enabled" to (selected != null && manager.isProviderEnabled(selected)), "watching" to registered,
            "foreground" to foreground, "recent" to cached()?.let(::snapshot))
    }
    private fun reconcile() {
        if (!wanted || !foreground || sink == null) { unregister(); return }
        if (permission() == "denied") { unregister(); emitError("permission_denied", "Location permission is not granted."); return }
        val selected = provider()
        if (selected == null) { unregister(); emitError("provider_unavailable", "No permitted location provider is available."); return }
        if (registered && selectedProvider == selected) return
        unregister()
        try {
            selectedProvider = selected
            manager.requestLocationUpdates(selected, 1000L, 0f, this, Looper.getMainLooper())
            registered = true; cached()?.let(::emitPosition)
            if (!manager.isProviderEnabled(selected)) emitError("location_disabled", "Device location is disabled.")
        } catch (error: SecurityException) { unregister(); emitError("permission_denied", error.message ?: "Location permission was revoked.") }
        catch (error: IllegalArgumentException) { unregister(); emitError("provider_unavailable", error.message ?: "Location provider is unavailable.") }
    }
    private fun unregister() { if (registered) manager.removeUpdates(this); registered = false; selectedProvider = null }
    private fun emitError(code: String, message: String) { sink?.success(mapOf("type" to "error", "code" to code, "message" to message)) }
    private fun emitPosition(location: Location) { sink?.success(mapOf("type" to "position", "position" to snapshot(location))) }
    override fun onLocationChanged(location: Location) {
        if (!registered || !foreground || !wanted) return
        if (permission() == "denied" || provider() != selectedProvider) { reconcile(); return }
        if (location.latitude !in -90.0..90.0 || location.longitude !in -180.0..180.0 ||
            !location.hasAccuracy() || !location.accuracy.isFinite() || location.accuracy < 0f) {
            emitError("invalid_fix", "Android delivered an invalid location fix."); return
        }
        recent = Location(location); emitPosition(location)
        val now = SystemClock.elapsedRealtime()
        val moved = widgetFix?.let { hypot(location.latitude - it.latitude, (location.longitude - it.longitude) * cos(location.latitude * Math.PI / 180)) >= 0.008 } ?: true
        if (moved || now - widgetAt >= 30_000) {
            widgetFix = Location(location); widgetAt = now
            NavKurdWidgetProvider.storeLocationAndRefresh(app, location.latitude, location.longitude, location.accuracy.toDouble())
        }
    }
    override fun onProviderDisabled(provider: String) { if (provider == selectedProvider) emitError("location_disabled", "Device location is disabled.") }
    override fun onProviderEnabled(provider: String) {
        if (provider != selectedProvider) return
        try { sink?.success(mapOf("type" to "status", "status" to status())) }
        catch (error: SecurityException) { unregister(); emitError("permission_denied", error.message ?: "Location permission was revoked.") }
    }
    @Deprecated("Required on supported Android APIs")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) = Unit
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events; reconcile() }
    override fun onCancel(arguments: Any?) { sink = null; unregister() }
}
