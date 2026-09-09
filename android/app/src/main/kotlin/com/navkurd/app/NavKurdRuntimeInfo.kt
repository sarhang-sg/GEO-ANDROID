package com.navkurd.app

import android.app.Activity
import android.app.ActivityManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.graphics.Rect
import android.os.Build
import android.os.Process
import android.os.StatFs
import android.os.storage.StorageManager
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.ViewCompat
import kotlin.math.roundToInt

/** Reads real Android capabilities. Values that Android cannot expose remain null. */
object NavKurdRuntimeInfo {
    fun collect(activity: Activity): Map<String, Any?> {
        val memory = activity.getSystemService(ActivityManager::class.java)
        val memoryInfo = ActivityManager.MemoryInfo().also(memory::getMemoryInfo)
        val display = displayInfo(activity)
        // MapLibre owns the active EGL/WebGL context. Creating a second EGL
        // context on the Android UI thread during startup caused visible stalls.
        val gpu = unavailableGpu()
        val safeArea = safeArea(activity)
        val packageInfo = activity.packageManager.getPackageInfo(activity.packageName, 0)

        return mapOf(
            "version" to (packageInfo.versionName ?: "unknown"),
            "versionCode" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            },
            "sdkInt" to Build.VERSION.SDK_INT,
            "manufacturer" to Build.MANUFACTURER,
            "model" to Build.MODEL,
            "device" to Build.DEVICE,
            "hardware" to Build.HARDWARE,
            "board" to Build.BOARD,
            "product" to Build.PRODUCT,
            "socManufacturer" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MANUFACTURER else null,
            "socModel" to if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) Build.SOC_MODEL else null,
            "abis" to Build.SUPPORTED_ABIS.toList(),
            "logicalProcessors" to Runtime.getRuntime().availableProcessors(),
            "totalMemoryBytes" to memoryInfo.totalMem,
            "availableMemoryBytes" to memoryInfo.availMem,
            "memoryClassMb" to memory.memoryClass,
            "largeMemoryClassMb" to memory.largeMemoryClass,
            "lowMemory" to memoryInfo.lowMemory,
            "screen" to display,
            "gpu" to gpu,
            "safeArea" to safeArea,
        )
    }

    private fun displayInfo(activity: Activity): Map<String, Any?> {
        val bounds: Rect
        val refreshRate: Float?
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            bounds = activity.windowManager.currentWindowMetrics.bounds
            refreshRate = activity.display?.mode?.refreshRate
        } else {
            @Suppress("DEPRECATION")
            val metrics = android.util.DisplayMetrics().also {
                @Suppress("DEPRECATION")
                activity.windowManager.defaultDisplay.getRealMetrics(it)
            }
            bounds = Rect(0, 0, metrics.widthPixels, metrics.heightPixels)
            @Suppress("DEPRECATION")
            refreshRate = activity.windowManager.defaultDisplay.refreshRate
        }
        val metrics = activity.resources.displayMetrics
        return mapOf(
            "widthPixels" to bounds.width(),
            "heightPixels" to bounds.height(),
            "density" to metrics.density,
            "densityDpi" to metrics.densityDpi,
            "scaledDensity" to metrics.scaledDensity,
            "refreshRateHz" to refreshRate,
        )
    }

    private fun safeArea(activity: Activity): Map<String, Int> {
        val insets = ViewCompat.getRootWindowInsets(activity.window.decorView)
            ?.getInsets(WindowInsetsCompat.Type.systemBars() or WindowInsetsCompat.Type.displayCutout())
            ?: androidx.core.graphics.Insets.NONE
        // The Web UI consumes these values as CSS pixels. Android insets are
        // physical pixels, so passing them through unchanged applies the
        // device density twice and pushes controls far below the status area.
        val density = activity.resources.displayMetrics.density.coerceAtLeast(1f)
        fun cssPixels(value: Int): Int = (value / density).roundToInt().coerceAtLeast(0)
        return mapOf(
            "top" to cssPixels(insets.top),
            "right" to cssPixels(insets.right),
            "bottom" to cssPixels(insets.bottom),
            "left" to cssPixels(insets.left),
        )
    }

    /** StorageStatsManager may perform slow binder/disk work; call off the UI thread. */
    fun withStorage(context: Context, snapshot: Map<String, Any?>): Map<String, Any?> {
        val storage = storageInfo(context)
        return snapshot + mapOf(
            "cacheBytes" to storage["cacheBytes"],
            "appStorageBytes" to storage["appStorageBytes"],
            "storage" to storage,
        )
    }

    private fun storageInfo(context: Context): Map<String, Any?> {
        val stat = StatFs(context.filesDir.absolutePath)
        val appStorage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            runCatching {
                val manager = context.getSystemService(StorageStatsManager::class.java)
                val stats = manager.queryStatsForUid(StorageManager.UUID_DEFAULT, Process.myUid())
                mapOf("appStorageBytes" to (stats.appBytes + stats.dataBytes + stats.cacheBytes), "cacheBytes" to stats.cacheBytes)
            }.getOrNull()
        } else {
            null
        }
        return mapOf(
            "totalBytes" to stat.totalBytes,
            "availableBytes" to stat.availableBytes,
            "appStorageBytes" to appStorage?.get("appStorageBytes"),
            "filesBytes" to null,
            "cacheBytes" to appStorage?.get("cacheBytes"),
        )
    }

    private fun unavailableGpu(): Map<String, Any?> = mapOf(
        "vendor" to null,
        "renderer" to null,
        "version" to null,
        "shadingLanguageVersion" to null,
        "maxTextureSize" to null,
    )
}
