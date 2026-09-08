package com.navkurd.app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextDirectionHeuristics
import android.text.TextPaint
import android.text.TextUtils
import android.widget.RemoteViews
import androidx.core.content.res.ResourcesCompat
import kotlin.math.ceil
import kotlin.math.roundToInt

/**
 * Render type inside our own process, then send pixels to the launcher.
 * RemoteViews cannot invoke setTypeface; relying only on fontFamily in an XML
 * inflated by another app is not sufficient on all OEM widget hosts.
 * StaticLayout preserves Kurdish/Arabic shaping, bidi order and ellipsis.
 * Native TextClock is deliberately retained so the clock still ticks live.
 */
object NavKurdWidgetTypography {
    enum class Alignment { START, CENTER, END }

    private const val SCALE = 2f
    private val typefaces = mutableMapOf<Int, Typeface>()

    @Synchronized
    private fun font(context: Context, latin: Boolean): Typeface {
        val resource = if (latin) R.font.red_hat_display_variable else R.font.uniqaidar_money_heist_002
        return typefaces.getOrPut(resource) {
            requireNotNull(ResourcesCompat.getFont(context, resource)) {
                "Bundled widget font could not be loaded: $resource"
            }
        }
    }

    fun bind(
        context: Context,
        views: RemoteViews,
        viewId: Int,
        text: String,
        language: String,
        sizeSp: Float,
        maxWidthDp: Float,
        color: String,
    ) {
        val latin = language == "en" || text.none {
            it in '\u0600'..'\u08ff' || it in '\ufb50'..'\ufdff' || it in '\ufe70'..'\ufeff'
        }
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = font(context, latin)
            textSize = sizeSp * context.resources.configuration.fontScale * SCALE
            this.color = Color.parseColor(color)
        }
        val safeText = text.replace('\n', ' ').take(180).ifEmpty { " " }
        val width = ceil(paint.measureText(safeText) + 4f * SCALE).toInt()
            .coerceIn(1, (maxWidthDp.coerceIn(16f, 480f) * SCALE).toInt())
        val layout = StaticLayout.Builder.obtain(safeText, 0, safeText.length, paint, width)
            .setAlignment(Layout.Alignment.ALIGN_NORMAL)
            .setTextDirection(if (latin) TextDirectionHeuristics.FIRSTSTRONG_LTR else TextDirectionHeuristics.FIRSTSTRONG_RTL)
            .setIncludePad(true)
            .setMaxLines(1)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setEllipsizedWidth(width)
            .build()
        val bitmap = Bitmap.createBitmap(width, layout.height.coerceAtLeast(1), Bitmap.Config.ARGB_8888)
        bitmap.density = (160 * SCALE).toInt()
        layout.draw(Canvas(bitmap))
        views.setImageViewBitmap(viewId, bitmap)
        // Preserve the label for TalkBack; this is not decorative image text.
        views.setContentDescription(viewId, text)
    }

    // Preserve the renderer already present in the installed R5 source.
    fun render(
        context: Context,
        text: String,
        language: String,
        widthDp: Float,
        heightDp: Float,
        sizeSp: Float,
        color: Int = Color.WHITE,
        alignment: Alignment = Alignment.START,
        bold: Boolean = true,
    ): Bitmap {
        val density = context.resources.displayMetrics.density.coerceIn(1f, 1.5f)
        val width = (widthDp * density).roundToInt().coerceAtLeast(1)
        val height = (heightDp * density).roundToInt().coerceAtLeast(1)
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val baseTypeface = ResourcesCompat.getFont(
            context,
            if (language == "en") R.font.red_hat_display_variable else R.font.uniqaidar_money_heist_002,
        ) ?: Typeface.DEFAULT
        val paint = TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            this.color = color
            textSize = sizeSp * density
            typeface = Typeface.create(baseTypeface, if (bold) Typeface.BOLD else Typeface.NORMAL)
        }
        val layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, width)
            .setAlignment(
                when (alignment) {
                    Alignment.CENTER -> Layout.Alignment.ALIGN_CENTER
                    Alignment.START -> Layout.Alignment.ALIGN_NORMAL
                    Alignment.END -> Layout.Alignment.ALIGN_OPPOSITE
                },
            )
            .setIncludePad(false)
            .setMaxLines(1)
            .setEllipsize(TextUtils.TruncateAt.END)
            .setTextDirection(
                if (language == "en") TextDirectionHeuristics.LTR else TextDirectionHeuristics.RTL,
            )
            .build()
        canvas.save()
        canvas.translate(0f, ((height - layout.height) / 2f).coerceAtLeast(0f))
        layout.draw(canvas)
        canvas.restore()
        return bitmap
    }
}
