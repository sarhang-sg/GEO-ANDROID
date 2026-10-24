package com.navkurd.app

import android.content.Context
import org.json.JSONObject

/** Shared WMO condition labels and descriptive temperature/wind context. */
internal object NavKurdWeatherDescriptions {
    @Volatile private var descriptions: JSONObject? = null

    private fun load(context: Context): JSONObject? = descriptions ?: synchronized(this) {
        descriptions ?: runCatching {
            context.assets.open("nav_kurd_weather_descriptions.json").bufferedReader().use { JSONObject(it.readText()) }
        }.getOrNull()?.also { descriptions = it }
    }

    fun label(context: Context, code: Int, isDay: Boolean, language: String): String? {
        val data = load(context) ?: return null
        val row = if (code == 0 && isDay) data.optJSONObject("clearDay")
            else data.optJSONObject("codes")?.optJSONObject(code.toString()) ?: data.optJSONObject("unavailable")
        return row?.optString(language)?.takeIf { it.isNotBlank() }
    }

    fun contextLabels(context: Context, temperature: Double?, wind: Double?, gusts: Double?, language: String): String {
        val data = load(context) ?: return ""
        val thresholds = data.optJSONObject("contextThresholds") ?: return ""
        val labels = data.optJSONObject("context") ?: return ""
        val keys = mutableListOf<String>()
        if (temperature != null && temperature.isFinite()) {
            when {
                temperature <= thresholds.optDouble("extremeColdC", -10.0) -> keys.add("extremeCold")
                temperature <= thresholds.optDouble("coldC", 5.0) -> keys.add("cold")
                temperature < thresholds.optDouble("coolC", 16.0) -> keys.add("cool")
                temperature >= thresholds.optDouble("extremeHeatC", 40.0) -> keys.add("extremeHeat")
                temperature >= thresholds.optDouble("hotC", 32.0) -> keys.add("hot")
            }
        }
        if (wind != null && wind.isFinite() && wind >= thresholds.optDouble("strongWindKmh", 40.0)) keys.add("strongWind")
        else if (gusts != null && gusts.isFinite() && gusts >= thresholds.optDouble("strongGustsKmh", 60.0)) keys.add("gusts")
        return keys.mapNotNull { labels.optJSONObject(it)?.optString(language)?.takeIf { value -> value.isNotBlank() } }.joinToString(" · ")
    }
}
