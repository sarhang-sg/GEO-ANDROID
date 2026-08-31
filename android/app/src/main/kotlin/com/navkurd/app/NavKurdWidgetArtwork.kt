package com.navkurd.app

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RadialGradient
import android.graphics.RectF
import android.graphics.Shader
import java.util.Random

/**
 * Rich, launcher-safe widget artwork.
 *
 * Android RemoteViews cannot host Lottie, an animated SVG, or a continuously
 * running custom view.  We therefore render a lightweight bitmap frame whose
 * palette and particles advance on each scheduled refresh.  It reacts to the
 * real weather, local day phase, and astronomical season without using emoji.
 */
object NavKurdWidgetArtwork {
    private const val SCENE_WIDTH = 480
    private const val SCENE_HEIGHT = 220
    private const val ICON_SIZE = 128

    fun scene(
        kind: String,
        isDay: Boolean,
        phase: String,
        season: String,
        frame: Long,
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(SCENE_WIDTH, SCENE_HEIGHT, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val palette = palette(kind, isDay, phase, season)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(
            0f,
            0f,
            SCENE_WIDTH.toFloat(),
            SCENE_HEIGHT.toFloat(),
            palette.first,
            palette.second,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRoundRect(RectF(0f, 0f, SCENE_WIDTH.toFloat(), SCENE_HEIGHT.toFloat()), 34f, 34f, paint)
        paint.shader = null

        if (!isDay || phase == "evening" || phase == "dawn") drawStars(canvas, frame)
        drawHorizon(canvas, season, isDay)
        drawAmbientAtmosphere(canvas, kind, frame)

        paint.color = Color.argb(62, 255, 255, 255)
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.4f
        canvas.drawRoundRect(RectF(1f, 1f, SCENE_WIDTH - 1f, SCENE_HEIGHT - 1f), 34f, 34f, paint)
        paint.style = Paint.Style.FILL
        paint.shader = LinearGradient(
            0f,
            0f,
            0f,
            SCENE_HEIGHT.toFloat(),
            intArrayOf(Color.argb(20, 255, 255, 255), Color.TRANSPARENT, Color.argb(86, 3, 8, 24)),
            floatArrayOf(0f, 0.45f, 1f),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRoundRect(RectF(0f, 0f, SCENE_WIDTH.toFloat(), SCENE_HEIGHT.toFloat()), 34f, 34f, paint)
        return bitmap
    }

    fun weatherIcon(kind: String, isDay: Boolean, frame: Long): Bitmap {
        val bitmap = Bitmap.createBitmap(ICON_SIZE, ICON_SIZE, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val shift = ((frame % 5L) - 2L).toFloat()

        when (kind) {
            "CLEAR", "HOT", "COLD" -> {
                if (isDay) drawSun(canvas, 62f, 61f, if (kind == "HOT") 31f else 27f, paint)
                else drawMoon(canvas, 63f, 58f, 30f, paint)
                if (kind == "HOT") drawHeat(canvas, shift, paint)
                if (kind == "COLD") drawSnow(canvas, frame, 7, paint)
            }
            "PARTLY_CLOUDY", "CLOUDY" -> {
                if (isDay) drawSun(canvas, 43f, 41f, 19f, paint) else drawMoon(canvas, 43f, 39f, 21f, paint)
                drawCloud(canvas, 66f, 69f, kind == "CLOUDY", paint)
            }
            "FOG" -> {
                if (isDay) drawSun(canvas, 43f, 40f, 17f, paint) else drawMoon(canvas, 43f, 39f, 19f, paint)
                drawCloud(canvas, 67f, 60f, false, paint)
                drawFog(canvas, paint)
            }
            "DRIZZLE", "RAIN", "SHOWERS", "DUST_RAIN", "FREEZING_RAIN" -> {
                if (isDay && kind == "DRIZZLE") drawSun(canvas, 43f, 38f, 16f, paint)
                drawCloud(canvas, 64f, 53f, kind != "DRIZZLE", paint)
                drawRain(canvas, frame, if (kind == "DRIZZLE") 5 else 9, paint)
                if (kind == "FREEZING_RAIN") drawSnow(canvas, frame + 3L, 4, paint)
                if (kind == "DUST_RAIN") drawDust(canvas, frame, paint)
            }
            "SNOW" -> {
                drawCloud(canvas, 63f, 48f, true, paint)
                drawSnow(canvas, frame, 12, paint)
            }
            "THUNDERSTORM", "HAIL" -> {
                drawCloud(canvas, 63f, 46f, true, paint)
                drawLightning(canvas, paint)
                if (kind == "HAIL") drawHail(canvas, frame, paint) else drawRain(canvas, frame, 7, paint)
            }
            "DUST", "STRONG_WIND" -> {
                if (isDay) drawSun(canvas, 38f, 38f, 18f, paint) else drawMoon(canvas, 38f, 37f, 20f, paint)
                drawWind(canvas, shift, kind == "DUST", paint)
            }
            "TORNADO" -> drawTornado(canvas, paint)
            else -> drawCompass(canvas, paint)
        }
        return bitmap
    }

    private fun palette(kind: String, isDay: Boolean, phase: String, season: String): Pair<Int, Int> {
        if (kind in setOf("THUNDERSTORM", "HAIL", "TORNADO")) {
            return Color.rgb(20, 28, 58) to Color.rgb(48, 22, 69)
        }
        if (kind in setOf("DUST", "DUST_RAIN", "STRONG_WIND")) {
            return Color.rgb(103, 69, 55) to Color.rgb(35, 48, 70)
        }
        if (kind == "SNOW" || kind == "FREEZING_RAIN" || kind == "COLD") {
            return Color.rgb(55, 99, 139) to Color.rgb(25, 45, 78)
        }
        return when {
            !isDay || phase == "night" -> Color.rgb(9, 18, 50) to Color.rgb(34, 22, 72)
            phase == "dawn" -> Color.rgb(70, 76, 135) to Color.rgb(222, 126, 101)
            phase == "evening" -> Color.rgb(49, 53, 109) to Color.rgb(213, 89, 92)
            kind == "HOT" || season == "summer" -> Color.rgb(21, 119, 187) to Color.rgb(238, 135, 67)
            kind in setOf("RAIN", "SHOWERS", "DRIZZLE", "FOG", "CLOUDY") -> Color.rgb(42, 74, 107) to Color.rgb(31, 49, 75)
            season == "spring" -> Color.rgb(21, 132, 153) to Color.rgb(58, 84, 129)
            season == "autumn" -> Color.rgb(71, 82, 122) to Color.rgb(169, 89, 61)
            else -> Color.rgb(17, 116, 184) to Color.rgb(40, 70, 128)
        }
    }

    private fun drawStars(canvas: Canvas, frame: Long) {
        val random = Random(900L)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        repeat(24) { index ->
            val x = random.nextFloat() * SCENE_WIDTH
            val y = 12f + random.nextFloat() * 100f
            val alpha = if ((index + frame.toInt()) % 3 == 0) 235 else 115
            paint.color = Color.argb(alpha, 224, 239, 255)
            canvas.drawCircle(x, y, if (index % 5 == 0) 1.8f else 1f, paint)
        }
    }

    private fun drawHorizon(canvas: Canvas, season: String, isDay: Boolean) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val path = Path().apply {
            moveTo(0f, 158f)
            cubicTo(90f, 126f, 145f, 170f, 232f, 143f)
            cubicTo(320f, 116f, 379f, 162f, 480f, 132f)
            lineTo(480f, 220f)
            lineTo(0f, 220f)
            close()
        }
        val base = when (season) {
            "spring" -> Color.rgb(24, 91, 80)
            "summer" -> Color.rgb(37, 91, 80)
            "autumn" -> Color.rgb(94, 65, 57)
            else -> Color.rgb(59, 76, 99)
        }
        paint.color = if (isDay) Color.argb(175, Color.red(base), Color.green(base), Color.blue(base)) else Color.argb(190, 10, 25, 46)
        canvas.drawPath(path, paint)
    }

    /**
     * Background-only atmosphere. The foreground weather icon owns the single
     * sun/moon/cloud illustration so launchers never render duplicate weather.
     */
    private fun drawAmbientAtmosphere(canvas: Canvas, kind: String, frame: Long) {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        when (kind) {
            "FOG" -> repeat(4) { index ->
                paint.color = Color.argb(34 + index * 9, 225, 240, 248)
                paint.strokeWidth = 2.5f
                canvas.drawLine(100f + index * 28f, 105f + index * 18f, 470f, 105f + index * 18f, paint)
            }
            "DRIZZLE", "RAIN", "SHOWERS", "FREEZING_RAIN", "DUST_RAIN" -> drawSceneRain(canvas, frame, kind == "DRIZZLE", paint)
            "SNOW", "COLD" -> drawSceneSnow(canvas, frame, paint)
            "THUNDERSTORM", "HAIL" -> {
                drawSceneRain(canvas, frame, false, paint)
                paint.color = Color.argb(if (frame % 4L == 0L) 95 else 24, 219, 232, 255)
                canvas.drawRect(0f, 0f, SCENE_WIDTH.toFloat(), SCENE_HEIGHT.toFloat(), paint)
            }
            "DUST", "DUST_RAIN", "STRONG_WIND" -> drawSceneDust(canvas, frame, paint)
            "TORNADO" -> drawSceneDust(canvas, frame, paint)
            "HOT" -> drawHeatScene(canvas, frame, paint)
        }
    }

    private fun drawSun(canvas: Canvas, cx: Float, cy: Float, radius: Float, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 4f
        paint.color = Color.rgb(255, 219, 92)
        val rays = 12
        repeat(rays) { index ->
            val angle = Math.PI * 2 * index / rays
            val inner = radius + 6f
            val outer = radius + 14f
            canvas.drawLine(
                cx + (kotlin.math.cos(angle) * inner).toFloat(),
                cy + (kotlin.math.sin(angle) * inner).toFloat(),
                cx + (kotlin.math.cos(angle) * outer).toFloat(),
                cy + (kotlin.math.sin(angle) * outer).toFloat(),
                paint,
            )
        }
        paint.style = Paint.Style.FILL
        paint.shader = RadialGradient(cx - radius * 0.25f, cy - radius * 0.25f, radius * 1.25f, Color.rgb(255, 247, 175), Color.rgb(255, 168, 52), Shader.TileMode.CLAMP)
        canvas.drawCircle(cx, cy, radius, paint)
        paint.shader = null
    }

    private fun drawMoon(canvas: Canvas, cx: Float, cy: Float, radius: Float, paint: Paint) {
        paint.style = Paint.Style.FILL
        paint.color = Color.rgb(238, 244, 255)
        canvas.drawCircle(cx, cy, radius, paint)
        paint.color = Color.rgb(78, 86, 139)
        canvas.drawCircle(cx + radius * 0.45f, cy - radius * 0.18f, radius * 0.86f, paint)
        paint.color = Color.argb(85, 167, 190, 232)
        canvas.drawCircle(cx - radius * 0.28f, cy + radius * 0.3f, radius * 0.15f, paint)
    }

    private fun drawCloud(canvas: Canvas, cx: Float, cy: Float, dark: Boolean, paint: Paint, scale: Float = 1f) {
        paint.style = Paint.Style.FILL
        paint.shader = LinearGradient(0f, cy - 30f, 0f, cy + 35f, if (dark) Color.rgb(133, 151, 179) else Color.WHITE, if (dark) Color.rgb(63, 79, 109) else Color.rgb(184, 214, 232), Shader.TileMode.CLAMP)
        canvas.drawRoundRect(RectF(cx - 45f * scale, cy - 3f * scale, cx + 45f * scale, cy + 30f * scale), 18f * scale, 18f * scale, paint)
        canvas.drawCircle(cx - 23f * scale, cy, 25f * scale, paint)
        canvas.drawCircle(cx + 4f * scale, cy - 13f * scale, 34f * scale, paint)
        canvas.drawCircle(cx + 31f * scale, cy + 2f * scale, 23f * scale, paint)
        paint.shader = null
    }

    private fun drawRain(canvas: Canvas, frame: Long, count: Int, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 4f
        paint.color = Color.rgb(84, 205, 255)
        repeat(count) { index ->
            val x = 29f + index * (75f / count) + (frame % 3L) * 2f
            val y = 83f + (index % 3) * 11f
            canvas.drawLine(x, y, x - 6f, y + 16f, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawSceneRain(canvas: Canvas, frame: Long, light: Boolean, paint: Paint) {
        val random = Random(900L + frame)
        paint.color = Color.argb(if (light) 105 else 165, 102, 213, 255)
        paint.strokeWidth = if (light) 1.5f else 2.2f
        repeat(if (light) 30 else 58) {
            val x = random.nextFloat() * SCENE_WIDTH
            val y = 30f + random.nextFloat() * 170f
            canvas.drawLine(x, y, x - 5f, y + 13f, paint)
        }
    }

    private fun drawSnow(canvas: Canvas, frame: Long, count: Int, paint: Paint) {
        val random = Random(80L + frame)
        repeat(count) {
            val x = 20f + random.nextFloat() * 88f
            val y = 72f + random.nextFloat() * 47f
            drawSnowflake(canvas, x, y, 3.5f + random.nextFloat() * 2f, paint)
        }
    }

    private fun drawSceneSnow(canvas: Canvas, frame: Long, paint: Paint) {
        val random = Random(404L + frame)
        repeat(42) {
            drawSnowflake(canvas, random.nextFloat() * SCENE_WIDTH, 18f + random.nextFloat() * 182f, 1.5f + random.nextFloat() * 2.3f, paint)
        }
    }

    private fun drawSnowflake(canvas: Canvas, cx: Float, cy: Float, radius: Float, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = (radius / 4f).coerceAtLeast(1f)
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.rgb(225, 247, 255)
        repeat(3) { index ->
            val angle = Math.PI * index / 3
            val dx = (kotlin.math.cos(angle) * radius).toFloat()
            val dy = (kotlin.math.sin(angle) * radius).toFloat()
            canvas.drawLine(cx - dx, cy - dy, cx + dx, cy + dy, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawFog(canvas: Canvas, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 5f
        repeat(4) { index ->
            paint.color = Color.argb(215 - index * 25, 218, 237, 244)
            canvas.drawLine(22f + (index % 2) * 11f, 82f + index * 11f, 106f - (index % 2) * 9f, 82f + index * 11f, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawLightning(canvas: Canvas, paint: Paint) {
        val path = Path().apply {
            moveTo(68f, 69f)
            lineTo(47f, 95f)
            lineTo(63f, 95f)
            lineTo(50f, 124f)
            lineTo(88f, 86f)
            lineTo(69f, 86f)
            close()
        }
        paint.color = Color.rgb(255, 224, 82)
        paint.style = Paint.Style.FILL
        canvas.drawPath(path, paint)
    }

    private fun drawHail(canvas: Canvas, frame: Long, paint: Paint) {
        val random = Random(99L + frame)
        paint.style = Paint.Style.FILL
        repeat(8) {
            val x = 23f + random.nextFloat() * 84f
            val y = 80f + random.nextFloat() * 38f
            paint.color = Color.rgb(221, 246, 255)
            canvas.drawCircle(x, y, 4.5f, paint)
            paint.color = Color.argb(150, 114, 183, 226)
            canvas.drawCircle(x + 1.3f, y + 1.2f, 2.4f, paint)
        }
    }

    private fun drawWind(canvas: Canvas, shift: Float, dusty: Boolean, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 5f
        repeat(4) { index ->
            paint.color = if (dusty) Color.argb(220 - index * 25, 244, 193, 105) else Color.argb(220 - index * 25, 190, 238, 255)
            val y = 57f + index * 17f
            val path = Path().apply {
                moveTo(20f + shift, y)
                cubicTo(47f, y - 10f, 71f, y + 9f, 108f - index * 5f, y - 2f)
            }
            canvas.drawPath(path, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawDust(canvas: Canvas, frame: Long, paint: Paint) {
        val random = Random(108L + frame)
        paint.color = Color.rgb(244, 190, 96)
        repeat(11) { canvas.drawCircle(18f + random.nextFloat() * 98f, 70f + random.nextFloat() * 52f, 1.5f + random.nextFloat() * 2.2f, paint) }
    }

    private fun drawSceneDust(canvas: Canvas, frame: Long, paint: Paint) {
        val random = Random(208L + frame)
        repeat(34) {
            paint.color = Color.argb(80 + random.nextInt(90), 243, 185, 97)
            canvas.drawCircle(random.nextFloat() * SCENE_WIDTH, 42f + random.nextFloat() * 154f, 1f + random.nextFloat() * 3f, paint)
        }
    }

    private fun drawTornado(canvas: Canvas, paint: Paint) {
        drawCloud(canvas, 64f, 34f, true, paint)
        drawTornadoAt(canvas, 64f, 58f, 1f, paint)
    }

    private fun drawTornadoAt(canvas: Canvas, cx: Float, top: Float, scale: Float, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        repeat(6) { index ->
            paint.strokeWidth = (8f - index * 0.8f) * scale
            paint.color = Color.argb(230 - index * 18, 193, 209, 221)
            val width = (39f - index * 5.2f) * scale
            val y = top + index * 10f * scale
            canvas.drawArc(RectF(cx - width, y, cx + width, y + 12f * scale), 8f, 168f, false, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawHeat(canvas: Canvas, shift: Float, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 3f
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.rgb(255, 152, 64)
        repeat(3) { index ->
            val x = 38f + index * 25f + shift
            canvas.drawPath(Path().apply { moveTo(x, 104f); cubicTo(x - 7f, 94f, x + 8f, 86f, x, 76f) }, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawHeatScene(canvas: Canvas, frame: Long, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 2f
        paint.color = Color.argb(90, 255, 207, 110)
        repeat(14) { index ->
            val x = index * 38f + (frame % 4L) * 3f
            canvas.drawPath(Path().apply { moveTo(x, 204f); cubicTo(x - 9f, 185f, x + 10f, 167f, x, 147f) }, paint)
        }
        paint.style = Paint.Style.FILL
    }

    private fun drawCompass(canvas: Canvas, paint: Paint) {
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 5f
        paint.color = Color.rgb(161, 231, 247)
        canvas.drawCircle(64f, 64f, 39f, paint)
        paint.style = Paint.Style.FILL
        val path = Path().apply { moveTo(77f, 42f); lineTo(67f, 70f); lineTo(42f, 84f); lineTo(56f, 56f); close() }
        paint.color = Color.WHITE
        canvas.drawPath(path, paint)
        paint.color = Color.rgb(109, 222, 243)
        canvas.drawCircle(64f, 64f, 5f, paint)
    }
}
