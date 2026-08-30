package com.navkurd.app

import android.app.Activity
import android.app.ActivityManager
import android.app.usage.StorageStatsManager
import android.content.Context
import android.graphics.Rect
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.GLES20
import android.os.Build
import android.os.Process
import android.os.StatFs
import android.os.storage.StorageManager
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.ViewCompat
import java.io.File
import kotlin.math.roundToInt

/** Reads real Android capabilities. Values that Android cannot expose remain null. */
object NavKurdRuntimeInfo {
    fun collect(activity: Activity): Map<String, Any?> {
        val memory = activity.getSystemService(ActivityManager::class.java)
        val memoryInfo = ActivityManager.MemoryInfo().also(memory::getMemoryInfo)
        val display = displayInfo(activity)
        val gpu = readGpu()
        val storage = storageInfo(activity)
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
            "cacheBytes" to directoryBytes(activity.cacheDir),
            "appStorageBytes" to storage["appStorageBytes"],
            "storage" to storage,
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

    private fun storageInfo(context: Context): Map<String, Any?> {
        val stat = StatFs(context.filesDir.absolutePath)
        val appStorage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            runCatching {
                val manager = context.getSystemService(StorageStatsManager::class.java)
                val stats = manager.queryStatsForUid(StorageManager.UUID_DEFAULT, Process.myUid())
                stats.appBytes + stats.dataBytes + stats.cacheBytes
            }.getOrNull()
        } else {
            null
        }
        return mapOf(
            "totalBytes" to stat.totalBytes,
            "availableBytes" to stat.availableBytes,
            "appStorageBytes" to appStorage,
            "filesBytes" to directoryBytes(context.filesDir),
            "cacheBytes" to directoryBytes(context.cacheDir),
        )
    }

    private fun directoryBytes(root: File): Long {
        if (!root.exists()) return 0L
        return runCatching {
            root.walkTopDown()
                .filter(File::isFile)
                .fold(0L) { total, file -> total + file.length() }
        }.getOrDefault(0L)
    }

    private fun readGpu(): Map<String, Any?> {
        var display = EGL14.EGL_NO_DISPLAY
        var surface = EGL14.EGL_NO_SURFACE
        var context = EGL14.EGL_NO_CONTEXT
        return try {
            display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
            if (display == EGL14.EGL_NO_DISPLAY) return unavailableGpu()
            val versions = IntArray(2)
            if (!EGL14.eglInitialize(display, versions, 0, versions, 1)) return unavailableGpu()
            val attributes = intArrayOf(
                EGL14.EGL_RED_SIZE, 8,
                EGL14.EGL_GREEN_SIZE, 8,
                EGL14.EGL_BLUE_SIZE, 8,
                EGL14.EGL_ALPHA_SIZE, 8,
                EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
                EGL14.EGL_NONE,
            )
            val configs = arrayOfNulls<EGLConfig>(1)
            val count = IntArray(1)
            if (!EGL14.eglChooseConfig(display, attributes, 0, configs, 0, 1, count, 0) || count[0] == 0) {
                return unavailableGpu()
            }
            val config = configs[0] ?: return unavailableGpu()
            context = EGL14.eglCreateContext(
                display,
                config,
                EGL14.EGL_NO_CONTEXT,
                intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
                0,
            )
            surface = EGL14.eglCreatePbufferSurface(
                display,
                config,
                intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
                0,
            )
            if (context == EGL14.EGL_NO_CONTEXT || surface == EGL14.EGL_NO_SURFACE ||
                !EGL14.eglMakeCurrent(display, surface, surface, context)
            ) {
                return unavailableGpu()
            }
            val textureSize = IntArray(1)
            GLES20.glGetIntegerv(GLES20.GL_MAX_TEXTURE_SIZE, textureSize, 0)
            mapOf(
                "vendor" to GLES20.glGetString(GLES20.GL_VENDOR),
                "renderer" to GLES20.glGetString(GLES20.GL_RENDERER),
                "version" to GLES20.glGetString(GLES20.GL_VERSION),
                "shadingLanguageVersion" to GLES20.glGetString(GLES20.GL_SHADING_LANGUAGE_VERSION),
                "maxTextureSize" to textureSize[0].takeIf { it > 0 },
            )
        } catch (_: Exception) {
            unavailableGpu()
        } finally {
            if (display != EGL14.EGL_NO_DISPLAY) {
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
                if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
                EGL14.eglTerminate(display)
            }
        }
    }

    private fun unavailableGpu(): Map<String, Any?> = mapOf(
        "vendor" to null,
        "renderer" to null,
        "version" to null,
        "shadingLanguageVersion" to null,
        "maxTextureSize" to null,
    )
}
