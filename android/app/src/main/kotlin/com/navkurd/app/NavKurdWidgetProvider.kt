package com.navkurd.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.location.Geocoder
import android.location.Location
import android.net.Uri
import android.os.Bundle
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import java.text.SimpleDateFormat
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class NavKurdWidgetProvider : AppWidgetProvider() {
    companion object {
        const val PREFERENCES = "nav_kurd_widget"
        const val KEY_STATUS = "status"
        const val KEY_DETAIL = "detail"
        const val KEY_LANGUAGE = "language"
        const val KEY_LATITUDE = "latitude"
        const val KEY_LONGITUDE = "longitude"
        const val KEY_ACCURACY = "accuracy"
        const val KEY_LOCATION_AT = "location_at"
        const val KEY_CITY = "city"
        const val KEY_TEMPERATURE = "temperature"
        const val KEY_WEATHER_CODE = "weather_code"
        const val KEY_IS_DAY = "is_day"
        const val KEY_TIMEZONE = "timezone"
        const val KEY_SUNRISE = "sunrise"
        const val KEY_SUNSET = "sunset"
        const val KEY_OBSERVED_AT = "observed_at"
        const val KEY_APPARENT_TEMPERATURE = "apparent_temperature"
        const val KEY_HUMIDITY = "humidity"
        const val KEY_PRECIPITATION = "precipitation"
        const val KEY_RAIN = "rain"
        const val KEY_SHOWERS = "showers"
        const val KEY_SNOWFALL = "snowfall"
        const val KEY_CLOUD_COVER = "cloud_cover"
        const val KEY_WIND_SPEED = "wind_speed"
        const val KEY_WIND_GUSTS = "wind_gusts"
        const val KEY_DUST = "dust"
        const val KEY_WEATHER_AT = "weather_at"
        const val KEY_FORECAST = "hourly_forecast"
        private const val KEY_WEATHER_LAT = "weather_latitude"
        private const val KEY_WEATHER_LON = "weather_longitude"
        const val KEY_LAST_RENDER_AT = "last_render_at"
        const val KEY_LAST_RENDER_ERROR = "last_render_error"

        private const val ACTION_REFRESH = "com.navkurd.app.WIDGET_REFRESH"
        private const val ACTION_LOCATE = "com.navkurd.app.WIDGET_LOCATE"
        private const val WEATHER_TTL_MILLIS = 30L * 60L * 1000L
        private const val DUST_THRESHOLD = 50.0
        private const val STRONG_WIND_KMH = 40.0
        private const val STRONG_GUST_KMH = 60.0
        private val executor = Executors.newSingleThreadExecutor()
        private val refreshRunning = AtomicBoolean(false)
        private val forcedRefreshPending = AtomicBoolean(false)
        private val refreshCallbacks = mutableListOf<() -> Unit>()

        private data class WeatherPayload(
            val temperature: Double,
            val apparentTemperature: Double?,
            val weatherCode: Int,
            val isDay: Boolean,
            val timezone: String,
            val sunrise: String?,
            val sunset: String?,
            val observedAt: String,
            val humidity: Int?,
            val precipitation: Double?,
            val rain: Double?,
            val showers: Double?,
            val snowfall: Double?,
            val cloudCover: Int?,
            val windSpeed: Double?,
            val windGusts: Double?,
            val dust: Double?,
            val forecast: JSONArray,
        )

        private enum class WeatherKind {
            CLEAR,
            PARTLY_CLOUDY,
            CLOUDY,
            FOG,
            DRIZZLE,
            RAIN,
            FREEZING_RAIN,
            SNOW,
            SHOWERS,
            THUNDERSTORM,
            HAIL,
            DUST,
            DUST_RAIN,
            STRONG_WIND,
            HOT,
            COLD,
            TORNADO,
            UNAVAILABLE,
        }

        private data class Season(
            val key: String,
        )

        private data class WidgetCopy(
            val locationUnknown: String,
            val mapReady: String,
            val tapLocate: String,
            val spring: String,
            val summer: String,
            val autumn: String,
            val winter: String,
            val preDawn: String,
            val morning: String,
            val noon: String,
            val afternoon: String,
            val evening: String,
            val night: String,
            val lateNight: String,
            val online: String,
            val offline: String,
            val offlineReady: String,
            val downloading: String,
            val paused: String,
            val preparing: String,
            val error: String,
            val deleting: String,
            val offlineMap: String,
        )

        fun setLanguage(context: Context, rawLanguage: String) {
            val language = when (rawLanguage.lowercase(Locale.ROOT).substringBefore('-')) {
                "ar" -> "ar"
                "en" -> "en"
                else -> "ku"
            }
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LANGUAGE, language)
                .remove(KEY_CITY)
                .apply()
            updateAll(context)
            refreshWeather(context, force = true)
        }

        fun dailyWeatherSummary(context: Context): Pair<String, String>? {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            if (!preferences.contains(KEY_TEMPERATURE) || System.currentTimeMillis() - preferences.getLong(KEY_WEATHER_AT, 0L) !in 0..90L * 60L * 1000L) return null
            val language = preferences.getString(KEY_LANGUAGE, "ku") ?: "ku"
            val copy = copyFor(language)
            val city = preferences.getString(KEY_CITY, copy.locationUnknown) ?: copy.locationUnknown
            val temperature = preferences.getFloat(KEY_TEMPERATURE, Float.NaN)
                .toDouble()
                .takeIf { it.isFinite() }
                ?: return null
            val code = preferences.getInt(KEY_WEATHER_CODE, -1)
            val isDay = preferences.getBoolean(KEY_IS_DAY, true)
            val dust = preferences.getFloat(KEY_DUST, Float.NaN).toDouble().takeIf { it.isFinite() }
            val wind = preferences.getFloat(KEY_WIND_SPEED, Float.NaN).toDouble().takeIf { it.isFinite() }
            val gusts = preferences.getFloat(KEY_WIND_GUSTS, Float.NaN).toDouble().takeIf { it.isFinite() }
            val humidity = preferences.getInt(KEY_HUMIDITY, -1).takeIf { it >= 0 }
            val kind = weatherKind(code, temperature, dust, wind, gusts)
            val title = when (language) {
                "en" -> "Today's weather in $city"
                "ar" -> "طقس اليوم في $city"
                else -> "کەش‌وهەوای ئەمڕۆ لە $city"
            }
            val body = buildList {
                add(String.format(Locale.ROOT, "%.0f°C", temperature))
                add(weatherCondition(kind, isDay, language))
                humidity?.let { add("$it%") }
                wind?.let { add(String.format(Locale.ROOT, "%.0f km/h", it)) }
            }.joinToString(" · ")
            return title to body
        }

        fun updateStatus(context: Context, status: String, detail: String) {
            context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_STATUS, status.take(32))
                .putString(KEY_DETAIL, detail.take(96))
                .apply()
            updateAll(context)
        }

        fun storeLocationAndRefresh(
            context: Context,
            latitude: Double,
            longitude: Double,
            accuracy: Double,
        ) {
            if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val previousLatitude = if (preferences.contains(KEY_LATITUDE)) {
                preferences.getFloat(KEY_LATITUDE, 0f).toDouble()
            } else {
                null
            }
            val previousLongitude = if (preferences.contains(KEY_LONGITUDE)) {
                preferences.getFloat(KEY_LONGITUDE, 0f).toDouble()
            } else {
                null
            }
            val moved = if (previousLatitude != null && previousLongitude != null) {
                val distance = FloatArray(1)
                Location.distanceBetween(
                    previousLatitude,
                    previousLongitude,
                    latitude,
                    longitude,
                    distance,
                )
                distance[0] > 1000f
            } else {
                true
            }
            preferences.edit()
                .putFloat(KEY_LATITUDE, latitude.toFloat())
                .putFloat(KEY_LONGITUDE, longitude.toFloat())
                .putFloat(KEY_ACCURACY, accuracy.coerceAtLeast(0.0).toFloat())
                .putLong(KEY_LOCATION_AT, System.currentTimeMillis())
                .apply()
            refreshWeather(context, force = moved)
        }

        fun hasWidgets(context: Context): Boolean = AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, NavKurdWidgetProvider::class.java)).isNotEmpty()

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NavKurdWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { id ->
                render(context, manager, id)
            }
        }

        fun refreshWeather(context: Context, force: Boolean, onComplete: (() -> Unit)? = null) {
            if (!hasWidgets(context) && onComplete == null) return
            val appContext = context.applicationContext
            synchronized(refreshRunning) {
                onComplete?.let { refreshCallbacks.add(it) }
                if (refreshRunning.get()) {
                    if (force) forcedRefreshPending.set(true)
                    return
                }
                refreshRunning.set(true)
            }
            executor.execute {
                var forceNext = force
                while (true) {
                    try {
                        refreshWeatherBlocking(appContext, forceNext)
                    } catch (error: Exception) {
                        NavKurdDiagnostics.record(appContext, "warning", "widget.weather",
                            "Weather refresh unavailable; retained readings keep their original timestamp: ${error.javaClass.simpleName}")
                    } finally { updateAll(appContext) }
                    var completed: List<() -> Unit> = emptyList()
                    val again = synchronized(refreshRunning) {
                        if (forcedRefreshPending.getAndSet(false)) true
                        else {
                            refreshRunning.set(false)
                            completed = refreshCallbacks.toList()
                            refreshCallbacks.clear()
                            false
                        }
                    }
                    if (!again) { completed.forEach { runCatching { it() } }; break }
                    forceNext = true
                }
            }
        }

        private fun refreshWeatherBlocking(context: Context, force: Boolean) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            var coordinates = storedCoordinates(preferences)
            val fresh = NavKurdWidgetLocation.latest(context) ?: if (NavKurdWidgetLocation.enabled(context) &&
                System.currentTimeMillis() - preferences.getLong(KEY_LOCATION_AT, 0L) > 15L * 60000L) NavKurdWidgetLocation.current(context) else null
            if (fresh != null && fresh.time > preferences.getLong(KEY_LOCATION_AT, 0L)) {
                coordinates = fresh.latitude to fresh.longitude
                preferences.edit().putFloat(KEY_LATITUDE, fresh.latitude.toFloat()).putFloat(KEY_LONGITUDE, fresh.longitude.toFloat())
                    .putFloat(KEY_ACCURACY, fresh.accuracy).putLong(KEY_LOCATION_AT, fresh.time).apply()
            }
            if (coordinates == null) {
                val located = NavKurdWidgetLocation.current(context)
                if (located != null) {
                    coordinates = located.latitude to located.longitude
                    preferences.edit().putFloat(KEY_LATITUDE, located.latitude.toFloat()).putFloat(KEY_LONGITUDE, located.longitude.toFloat())
                        .putFloat(KEY_ACCURACY, located.accuracy).putLong(KEY_LOCATION_AT, located.time).apply()
                }
            }
            if (coordinates == null) return

            val now = System.currentTimeMillis()
            val weatherAt = preferences.getLong(KEY_WEATHER_AT, 0L)
            val hasWeather = preferences.contains(KEY_TEMPERATURE)
            val samePlace = preferences.contains(KEY_WEATHER_LAT) &&
                kotlin.math.abs(preferences.getFloat(KEY_WEATHER_LAT, Float.NaN).toDouble() - coordinates.first) < 0.005 &&
                kotlin.math.abs(preferences.getFloat(KEY_WEATHER_LON, Float.NaN).toDouble() - coordinates.second) < 0.005
            if (!force && samePlace && hasWeather && now - weatherAt in 0 until WEATHER_TTL_MILLIS) {
                return
            }

            val (latitude, longitude) = coordinates
            val city = if (samePlace) preferences.getString(KEY_CITY, null)?.takeIf { it.isNotBlank() } ?: resolveCity(context, latitude, longitude) else resolveCity(context, latitude, longitude)
            val payload = fetchWeather(context, latitude, longitude)
            val latest = storedCoordinates(preferences)
            if (latest != null && (kotlin.math.abs(latest.first - latitude) > 0.005 || kotlin.math.abs(latest.second - longitude) > 0.005)) {
                forcedRefreshPending.set(true)
                return
            }
            preferences.edit()
                .putString(KEY_CITY, city)
                .putFloat(KEY_WEATHER_LAT, latitude.toFloat()).putFloat(KEY_WEATHER_LON, longitude.toFloat())
                .putString(KEY_FORECAST, payload.forecast.toString())
                .putFloat(KEY_TEMPERATURE, payload.temperature.toFloat())
                .putFloat(
                    KEY_APPARENT_TEMPERATURE,
                    payload.apparentTemperature?.toFloat() ?: Float.NaN,
                )
                .putInt(KEY_WEATHER_CODE, payload.weatherCode)
                .putBoolean(KEY_IS_DAY, payload.isDay)
                .putString(KEY_TIMEZONE, payload.timezone)
                .putString(KEY_SUNRISE, payload.sunrise)
                .putString(KEY_SUNSET, payload.sunset)
                .putString(KEY_OBSERVED_AT, payload.observedAt)
                .putInt(KEY_HUMIDITY, payload.humidity ?: -1)
                .putFloat(KEY_PRECIPITATION, payload.precipitation?.toFloat() ?: Float.NaN)
                .putFloat(KEY_RAIN, payload.rain?.toFloat() ?: Float.NaN)
                .putFloat(KEY_SHOWERS, payload.showers?.toFloat() ?: Float.NaN)
                .putFloat(KEY_SNOWFALL, payload.snowfall?.toFloat() ?: Float.NaN)
                .putInt(KEY_CLOUD_COVER, payload.cloudCover ?: -1)
                .putFloat(KEY_WIND_SPEED, payload.windSpeed?.toFloat() ?: Float.NaN)
                .putFloat(KEY_WIND_GUSTS, payload.windGusts?.toFloat() ?: Float.NaN)
                .putFloat(KEY_DUST, payload.dust?.toFloat() ?: Float.NaN)
                .putLong(KEY_WEATHER_AT, now)
                .apply()
        }

        private fun storedCoordinates(
            preferences: android.content.SharedPreferences,
        ): Pair<Double, Double>? {
            if (!preferences.contains(KEY_LATITUDE) || !preferences.contains(KEY_LONGITUDE)) {
                return null
            }
            val latitude = preferences.getFloat(KEY_LATITUDE, Float.NaN).toDouble()
            val longitude = preferences.getFloat(KEY_LONGITUDE, Float.NaN).toDouble()
            return if (latitude.isFinite() && longitude.isFinite() && latitude in -90.0..90.0 && longitude in -180.0..180.0) latitude to longitude else null
        }

        @Suppress("DEPRECATION")
        private fun resolveCity(context: Context, latitude: Double, longitude: Double): String {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val language = preferences.getString(KEY_LANGUAGE, "ku") ?: "ku"
            val copy = copyFor(language)
            if (!Geocoder.isPresent()) return copy.locationUnknown
            val locale = when (language) {
                "ar" -> Locale("ar")
                "en" -> Locale.ENGLISH
                else -> Locale("ckb")
            }
            return runCatching {
                val address = Geocoder(context, locale)
                    .getFromLocation(latitude, longitude, 1)
                    ?.firstOrNull()
                address?.locality
                    ?: address?.subAdminArea
                    ?: address?.adminArea
                    ?: copy.locationUnknown
            }.getOrElse { copy.locationUnknown }
        }

        private fun fetchWeather(
            context: Context,
            latitude: Double,
            longitude: Double,
        ): WeatherPayload {
            val endpoint = URL(
                "https://api.open-meteo.com/v1/forecast" +
                    "?latitude=${String.format(Locale.US, "%.5f", latitude)}" +
                    "&longitude=${String.format(Locale.US, "%.5f", longitude)}" +
                    "&current=temperature_2m,relative_humidity_2m,apparent_temperature," +
                    "is_day,precipitation,rain,showers,snowfall,weather_code,cloud_cover," +
                    "wind_speed_10m,wind_gusts_10m" +
                    "&daily=sunrise,sunset&forecast_days=2" +
                    "&hourly=temperature_2m,weather_code,is_day,precipitation_probability" +
                    "&temperature_unit=celsius&wind_speed_unit=kmh&timezone=auto",
            )
            val connection = endpoint.openConnection() as HttpURLConnection
            connection.connectTimeout = 5000
            connection.readTimeout = 5000
            connection.requestMethod = "GET"
            connection.setRequestProperty("Accept", "application/json")
            val version = context.packageManager
                .getPackageInfo(context.packageName, 0)
                .versionName
                ?: "unknown"
            connection.setRequestProperty("User-Agent", "NAV-KURD-Android/$version")
            try {
                val status = connection.responseCode
                require(status in 200..299) { "Weather service returned HTTP $status" }
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                val root = JSONObject(body)
                val current = root.getJSONObject("current")
                fun optionalDouble(key: String): Double? {
                    val value = current.optDouble(key, Double.NaN)
                    return value.takeIf { it.isFinite() }
                }
                val timezone = root.getString("timezone")
                require(timezone in TimeZone.getAvailableIDs()) { "Invalid weather timezone" }
                val validCodes = setOf(0,1,2,3,45,48,51,53,55,56,57,61,63,65,66,67,71,73,75,77,80,81,82,85,86,95,96,99)
                val temperature = current.getDouble("temperature_2m")
                val code = current.getInt("weather_code")
                val day = current.getInt("is_day")
                val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm", Locale.US).apply {
                    timeZone = TimeZone.getTimeZone(timezone); isLenient = false
                }
                val observedAt = current.getString("time")
                val observedTime = parser.parse(observedAt)?.time ?: error("Missing observation time")
                val now = System.currentTimeMillis()
                require(temperature.isFinite() && temperature in -90.0..65.0 && code in validCodes && day in 0..1 &&
                    now - observedTime in -3600000L..10800000L) { "Invalid current weather data" }
                val forecast = JSONArray()
                val hourly = root.optJSONObject("hourly")
                val times = hourly?.optJSONArray("time")
                for (i in 0 until minOf(times?.length() ?: 0, 72)) {
                    val at = runCatching { parser.parse(times?.optString(i) ?: "")?.time }.getOrNull() ?: continue
                    val temp = hourly?.optJSONArray("temperature_2m")?.optDouble(i, Double.NaN) ?: Double.NaN
                    val weather = hourly?.optJSONArray("weather_code")?.optInt(i, -1) ?: -1
                    val phase = hourly?.optJSONArray("is_day")?.optInt(i, -1) ?: -1
                    val chance = hourly?.optJSONArray("precipitation_probability")?.optInt(i, -1) ?: -1
                    if (at <= now || at > now + 10L * 3600000L || !temp.isFinite() || temp !in -90.0..65.0 || weather !in validCodes || phase !in 0..1) continue
                    forecast.put(JSONObject().put("at", at).put("temperature", temp).put("code", weather)
                        .put("isDay", phase == 1).put("chance", if (chance in 0..100) chance else JSONObject.NULL))
                }
                val daily = root.optJSONObject("daily")
                val sunrise = daily?.optJSONArray("sunrise")
                    ?.optString(0)
                    ?.takeIf { it.isNotBlank() }
                val sunset = daily?.optJSONArray("sunset")
                    ?.optString(0)
                    ?.takeIf { it.isNotBlank() }
                val dust = runCatching {
                    fetchDust(context, latitude, longitude)
                }.getOrNull()
                return WeatherPayload(
                    temperature = temperature,
                    apparentTemperature = optionalDouble("apparent_temperature"),
                    weatherCode = code,
                    isDay = day == 1,
                    timezone = timezone,
                    sunrise = sunrise,
                    sunset = sunset,
                    observedAt = observedAt,
                    humidity = current.optInt("relative_humidity_2m", -1).takeIf { it >= 0 },
                    precipitation = optionalDouble("precipitation"),
                    rain = optionalDouble("rain"),
                    showers = optionalDouble("showers"),
                    snowfall = optionalDouble("snowfall"),
                    cloudCover = current.optInt("cloud_cover", -1).takeIf { it >= 0 },
                    windSpeed = optionalDouble("wind_speed_10m"),
                    windGusts = optionalDouble("wind_gusts_10m"),
                    dust = dust,
                    forecast = forecast,
                )
            } finally {
                connection.disconnect()
            }
        }

        private fun fetchDust(
            context: Context,
            latitude: Double,
            longitude: Double,
        ): Double? {
            val endpoint = URL(
                "https://air-quality-api.open-meteo.com/v1/air-quality" +
                    "?latitude=${String.format(Locale.US, "%.5f", latitude)}" +
                    "&longitude=${String.format(Locale.US, "%.5f", longitude)}" +
                    "&current=dust&timezone=auto",
            )
            val connection = endpoint.openConnection() as HttpURLConnection
            connection.connectTimeout = 3000
            connection.readTimeout = 3000
            connection.requestMethod = "GET"
            connection.setRequestProperty("Accept", "application/json")
            val version = context.packageManager
                .getPackageInfo(context.packageName, 0)
                .versionName
                ?: "unknown"
            connection.setRequestProperty("User-Agent", "NAV-KURD-Android/$version")
            return try {
                if (connection.responseCode !in 200..299) return null
                val body = connection.inputStream.bufferedReader().use { it.readText() }
                JSONObject(body)
                    .optJSONObject("current")
                    ?.optDouble("dust", Double.NaN)
                    ?.takeIf { it.isFinite() }
            } finally {
                connection.disconnect()
            }
        }

        private fun render(
            context: Context,
            manager: AppWidgetManager,
            widgetId: Int,
        ) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            val language = preferences.getString(KEY_LANGUAGE, "ku") ?: "ku"
            val copy = copyFor(language)
            val rawStatus = preferences.getString(KEY_STATUS, "NAV KURD") ?: "NAV KURD"
            val rawDetail = preferences.getString(KEY_DETAIL, copy.mapReady) ?: copy.mapReady
            val (status, detail) = localizedStatus(rawStatus, rawDetail, copy)
            val city = preferences.getString(
                KEY_CITY,
                copy.locationUnknown,
            ) ?: copy.locationUnknown
            val hasWeather = preferences.contains(KEY_TEMPERATURE)
            val temperatureValue = preferences.getFloat(KEY_TEMPERATURE, Float.NaN)
                .toDouble()
                .takeIf { it.isFinite() }
            val temperature = if (temperatureValue != null) {
                String.format(
                    Locale.ROOT,
                    "%.0f°",
                    temperatureValue,
                )
            } else {
                "—°"
            }
            val weatherCode = preferences.getInt(KEY_WEATHER_CODE, -1)
            val timezone = preferences.getString(KEY_TIMEZONE, TimeZone.getDefault().id)
                ?.takeIf { it.isNotBlank() }
                ?: TimeZone.getDefault().id
            val reportedIsDay = if (preferences.contains(KEY_IS_DAY)) {
                preferences.getBoolean(KEY_IS_DAY, true)
            } else {
                Calendar.getInstance(TimeZone.getTimeZone(timezone))
                    .get(Calendar.HOUR_OF_DAY) in 6..17
            }
            val humidity = preferences.getInt(KEY_HUMIDITY, -1).takeIf { it >= 0 }
            val windSpeed = preferences.getFloat(KEY_WIND_SPEED, Float.NaN)
                .toDouble()
                .takeIf { it.isFinite() }
            val windGusts = preferences.getFloat(KEY_WIND_GUSTS, Float.NaN)
                .toDouble()
                .takeIf { it.isFinite() }
            val dust = preferences.getFloat(KEY_DUST, Float.NaN)
                .toDouble()
                .takeIf { it.isFinite() }
            val kind = weatherKind(weatherCode, temperatureValue, dust, windSpeed, windGusts)
            val latitude = preferences.getFloat(KEY_LATITUDE, 35.5f).toDouble()
            val season = seasonFor(timezone, latitude)
            val localClock = Calendar.getInstance(TimeZone.getTimeZone(timezone))
            val localMinute = localClock.get(Calendar.HOUR_OF_DAY) * 60 +
                localClock.get(Calendar.MINUTE)
            val sunriseMinute = solarMinute(
                preferences.getString(KEY_SUNRISE, null),
            )
            val sunsetMinute = solarMinute(
                preferences.getString(KEY_SUNSET, null),
            )
            val isDay = if (
                sunriseMinute != null && sunsetMinute != null && sunriseMinute < sunsetMinute
            ) {
                localMinute in sunriseMinute until sunsetMinute
            } else {
                reportedIsDay
            }
            val phase = phaseFor(localMinute, sunriseMinute, sunsetMinute)
            val condition = weatherCondition(kind, isDay, language)
            val seasonLabel = seasonLabel(season.key, copy)
            val phaseLabel = phaseLabel(phase, copy)
            val frame = System.currentTimeMillis() / (10L * 60L * 1000L)

            val layout = if (language == "en") {
                R.layout.nav_kurd_widget_en
            } else {
                R.layout.nav_kurd_widget
            }
            val views = RemoteViews(context.packageName, layout)
            views.setImageViewBitmap(
                R.id.widget_scene,
                NavKurdWidgetArtwork.scene(kind.name, isDay, phase, season.key, frame),
            )
            views.setImageViewBitmap(
                R.id.widget_weather_icon,
                NavKurdWidgetArtwork.weatherIcon(kind.name, isDay, frame),
            )
            fun label(id: Int, text: String, size: Float, width: Float, color: String) {
                NavKurdWidgetTypography.bind(context, views, id, text, language, size, width, color)
            }
            label(R.id.widget_temperature, temperature, 27f, 58f, "#FFFFFF")
            label(R.id.widget_city, city, 16f, 200f, "#FFFFFF")
            label(R.id.widget_condition, condition, 12f, 240f, "#E4F4FF")
            label(R.id.widget_season, seasonLabel, 10f, 62f, "#BDEBFF")
            label(R.id.widget_phase, phaseLabel, 10f, 95f, "#C5D3E9")
            label(R.id.widget_status, status, 8f, 80f, "#D9F3FF")
            label(R.id.widget_detail, detail, 9f, 175f, "#BBCBE0")
            val age = System.currentTimeMillis() - preferences.getLong(KEY_WEATHER_AT, 0L)
            val cachedLabel = when (language) { "en" -> "Cached"; "ar" -> "محفوظ"; else -> "پاشەکەوتکراو" }
            val observed = preferences.getString(KEY_OBSERVED_AT, "")?.replace('T', ' ')?.take(16).orEmpty()
            val attribution = "Open-Meteo · DEV: SARHANG.IO"
            label(R.id.widget_updated, if (hasWeather) "$observed · $attribution${if (age !in 0..90L * 60000L) " · $cachedLabel" else ""}" else copy.tapLocate,
                7.5f, 300f, "#B6C9E1")
            val forecast = runCatching { JSONArray(preferences.getString(KEY_FORECAST, "[]")) }.getOrElse { JSONArray() }
            val future = (0 until forecast.length()).mapNotNull { forecast.optJSONObject(it) }
                .filter { it.optLong("at") > System.currentTimeMillis() && it.optLong("at") <= System.currentTimeMillis() + 10L * 3600000L }
            if (future.isNotEmpty()) label(R.id.widget_detail, when (language) {
                "en" -> "Upcoming hours · forecast"; "ar" -> "الساعات القادمة · توقعات"; else -> "کاتژمێرەکانی داهاتوو · پێشبینی"
            }, 9f, 210f, "#BBCBE0")
            val timeIds = intArrayOf(R.id.widget_hour_0, R.id.widget_hour_1, R.id.widget_hour_2, R.id.widget_hour_3, R.id.widget_hour_4)
            val tempIds = intArrayOf(R.id.widget_forecast_0, R.id.widget_forecast_1, R.id.widget_forecast_2, R.id.widget_forecast_3, R.id.widget_forecast_4)
            val formatter = SimpleDateFormat("HH:mm", Locale.ROOT).apply { timeZone = TimeZone.getTimeZone(timezone) }
            views.setViewVisibility(R.id.widget_forecast_row, if (future.isNotEmpty()) View.VISIBLE else View.GONE)
            for (index in 0..4) {
                val hour = future.getOrNull(if (future.size > 5) index * (future.size - 1) / 4 else index)
                val at = hour?.optLong("at")
                val temp = hour?.optDouble("temperature", Double.NaN)
                label(timeIds[index], if (at != null) formatter.format(java.util.Date(at)) else "—", 9f, 48f, "#BDD8F4")
                label(tempIds[index], if (temp != null && temp.isFinite()) String.format(Locale.ROOT, "%.0f°", temp) else "—", 13f, 48f, "#FFFFFF")
            }
            label(R.id.widget_humidity, humidity?.let { "$it%" } ?: "—%", 9f, 48f, "#FFFFFF")
            label(R.id.widget_wind, windSpeed?.let { String.format(Locale.ROOT, "%.0f km/h", it) } ?: "— km/h", 9f, 58f, "#FFFFFF")
            label(R.id.widget_dust, dust?.let { String.format(Locale.ROOT, "%.0f µg/m³", it) } ?: "", 8.5f, 62f, "#FFFFFF")
            val dustVisibility = if (dust != null) View.VISIBLE else View.GONE
            views.setViewVisibility(R.id.widget_dust_group, dustVisibility)
            views.setViewVisibility(R.id.widget_dust_icon, dustVisibility)
            views.setViewVisibility(R.id.widget_dust, dustVisibility)
            views.setString(R.id.widget_local_time, "setTimeZone", timezone)

            val openIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("navkurd://open")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val locateIntent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_VIEW
                data = Uri.parse("navkurd://locate?action=locate")
                flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            }
            val refreshIntent = Intent(context, NavKurdWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            val attributionIntent = Intent(
                Intent.ACTION_VIEW,
                Uri.parse("https://open-meteo.com/"),
            )
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            views.setOnClickPendingIntent(
                R.id.widget_root,
                PendingIntent.getActivity(context, widgetId, openIntent, flags),
            )
            views.setOnClickPendingIntent(
                R.id.widget_locate,
                PendingIntent.getActivity(context, widgetId + 10000, locateIntent, flags),
            )
            views.setOnClickPendingIntent(
                R.id.widget_refresh,
                PendingIntent.getBroadcast(context, widgetId + 20000, refreshIntent, flags),
            )
            if (hasWeather) {
                views.setOnClickPendingIntent(
                    R.id.widget_updated,
                    PendingIntent.getActivity(
                        context,
                        widgetId + 30000,
                        attributionIntent,
                        flags,
                    ),
                )
            }
            try {
                manager.updateAppWidget(widgetId, views)
                preferences.edit()
                    .putLong(KEY_LAST_RENDER_AT, System.currentTimeMillis())
                    .remove(KEY_LAST_RENDER_ERROR)
                    .apply()
            } catch (error: Exception) {
                val message = error.message ?: error.javaClass.simpleName
                preferences.edit()
                    .putString(KEY_LAST_RENDER_ERROR, message.take(180))
                    .apply()
                NavKurdDiagnostics.record(
                    context,
                    "error",
                    "widget.render",
                    message,
                    error.stackTraceToString(),
                )
            }
        }

        private fun weatherKind(
            code: Int,
            temperature: Double?,
            dust: Double?,
            windSpeed: Double?,
            windGusts: Double?,
        ): WeatherKind {
            val base = when (code) {
                0 -> WeatherKind.CLEAR
                1, 2 -> WeatherKind.PARTLY_CLOUDY
                3 -> WeatherKind.CLOUDY
                45, 48 -> WeatherKind.FOG
                in 51..55 -> WeatherKind.DRIZZLE
                56, 57, 66, 67 -> WeatherKind.FREEZING_RAIN
                in 61..65 -> WeatherKind.RAIN
                in 71..77, 85, 86 -> WeatherKind.SNOW
                in 80..82 -> WeatherKind.SHOWERS
                95 -> WeatherKind.THUNDERSTORM
                96, 99 -> WeatherKind.HAIL
                else -> WeatherKind.UNAVAILABLE
            }
            val dusty = dust != null && dust >= DUST_THRESHOLD
            if (dusty && base in setOf(
                    WeatherKind.DRIZZLE,
                    WeatherKind.RAIN,
                    WeatherKind.FREEZING_RAIN,
                    WeatherKind.SHOWERS,
                )
            ) {
                return WeatherKind.DUST_RAIN
            }
            if (dusty && base in setOf(
                    WeatherKind.CLEAR,
                    WeatherKind.PARTLY_CLOUDY,
                    WeatherKind.CLOUDY,
                )
            ) {
                return WeatherKind.DUST
            }
            val strongWind = (windSpeed ?: 0.0) >= STRONG_WIND_KMH ||
                (windGusts ?: 0.0) >= STRONG_GUST_KMH
            if (strongWind && base in setOf(
                    WeatherKind.CLEAR,
                    WeatherKind.PARTLY_CLOUDY,
                    WeatherKind.CLOUDY,
                )
            ) {
                return WeatherKind.STRONG_WIND
            }
            if (temperature != null && temperature >= 38.0 && base in setOf(
                    WeatherKind.CLEAR,
                    WeatherKind.PARTLY_CLOUDY,
                )
            ) {
                return WeatherKind.HOT
            }
            if (temperature != null && temperature <= 0.0 && base in setOf(
                    WeatherKind.CLEAR,
                    WeatherKind.PARTLY_CLOUDY,
                    WeatherKind.CLOUDY,
                )
            ) {
                return WeatherKind.COLD
            }
            return base
        }

        private fun weatherCondition(
            kind: WeatherKind,
            isDay: Boolean,
            language: String,
        ): String {
            val key = when (kind) {
                WeatherKind.CLEAR -> if (isDay) "clear_day" else "clear_night"
                WeatherKind.PARTLY_CLOUDY -> if (isDay) "partly_day" else "partly_night"
                WeatherKind.CLOUDY -> if (isDay) "cloudy_day" else "cloudy_night"
                WeatherKind.FOG -> "fog"
                WeatherKind.DRIZZLE -> "drizzle"
                WeatherKind.RAIN -> "rain"
                WeatherKind.FREEZING_RAIN -> "freezing_rain"
                WeatherKind.SNOW -> "snow"
                WeatherKind.SHOWERS -> "showers"
                WeatherKind.THUNDERSTORM -> "storm"
                WeatherKind.HAIL -> "hail"
                WeatherKind.DUST -> "dust"
                WeatherKind.DUST_RAIN -> "dust_rain"
                WeatherKind.STRONG_WIND -> "wind"
                WeatherKind.HOT -> "hot"
                WeatherKind.COLD -> "cold"
                WeatherKind.TORNADO -> "tornado"
                WeatherKind.UNAVAILABLE -> "unavailable"
            }
            val translations = when (language) {
                "en" -> mapOf(
                    "clear_day" to "Clear and sunny", "clear_night" to "Clear night",
                    "partly_day" to "Partly cloudy", "partly_night" to "Partly cloudy night",
                    "cloudy_day" to "Cloudy day", "cloudy_night" to "Cloudy night",
                    "fog" to "Fog", "drizzle" to "Drizzle", "rain" to "Rain",
                    "freezing_rain" to "Freezing rain", "snow" to "Snow",
                    "showers" to "Rain showers", "storm" to "Thunderstorm",
                    "hail" to "Hail and thunder", "dust" to "Dusty weather",
                    "dust_rain" to "Dust rain", "wind" to "Strong wind",
                    "hot" to "Extreme heat", "cold" to "Freezing cold",
                    "tornado" to "Tornado alert", "unavailable" to "Weather unavailable",
                )
                "ar" -> mapOf(
                    "clear_day" to "مشمس والسماء صافية", "clear_night" to "ليلة صافية",
                    "partly_day" to "غائم جزئياً", "partly_night" to "ليلة غائمة جزئياً",
                    "cloudy_day" to "نهار غائم", "cloudy_night" to "ليلة غائمة",
                    "fog" to "ضباب", "drizzle" to "رذاذ", "rain" to "أمطار",
                    "freezing_rain" to "مطر متجمد", "snow" to "ثلوج",
                    "showers" to "زخات مطر", "storm" to "عاصفة رعدية",
                    "hail" to "برد ورعد", "dust" to "غبار",
                    "dust_rain" to "مطر محمل بالغبار", "wind" to "رياح قوية",
                    "hot" to "حرارة شديدة", "cold" to "برد قارس",
                    "tornado" to "تحذير إعصار", "unavailable" to "الطقس غير متاح",
                )
                else -> mapOf(
                    "clear_day" to "خۆرەتاو و ئاسمان سافە", "clear_night" to "شەوێکی ڕوون",
                    "partly_day" to "ڕۆژ و نیمچە هەوراوی", "partly_night" to "شەو و نیمچە هەوراوی",
                    "cloudy_day" to "ڕۆژی هەوراوی", "cloudy_night" to "شەوی هەوراوی",
                    "fog" to "تەماوی", "drizzle" to "نمەباران", "rain" to "باراناوی",
                    "freezing_rain" to "بارانی بەستوو", "snow" to "بەفراوی",
                    "showers" to "بارانی پچڕپچڕ", "storm" to "هەورەگرمە و بروسکە",
                    "hail" to "تەرزە و هەورەبروسکە", "dust" to "خۆڵ و تۆز",
                    "dust_rain" to "بارانی خۆڵاوی", "wind" to "بای بەهێز",
                    "hot" to "گەرمای زۆر", "cold" to "سەرمای زۆر",
                    "tornado" to "ئاگاداری گەردەلوول", "unavailable" to "کەش و هەوا بەردەست نییە",
                )
            }
            return translations.getValue(key)
        }

        private fun seasonFor(timezone: String, latitude: Double): Season {
            val calendar = Calendar.getInstance(TimeZone.getTimeZone(timezone))
            val marker = (calendar.get(Calendar.MONTH) + 1) * 100 +
                calendar.get(Calendar.DAY_OF_MONTH)
            val northern = when (marker) {
                in 320..620 -> "spring"
                in 621..921 -> "summer"
                in 922..1220 -> "autumn"
                else -> "winter"
            }
            val key = if (latitude >= 0.0) {
                northern
            } else {
                when (northern) {
                    "spring" -> "autumn"
                    "summer" -> "winter"
                    "autumn" -> "spring"
                    else -> "summer"
                }
            }
            return Season(key)
        }

        private fun solarMinute(value: String?): Int? {
            val time = value?.substringAfter('T', "")?.substringBefore('+')
                ?.substringBefore('Z')
                ?.takeIf { it.length >= 5 }
                ?: return null
            val hour = time.substring(0, 2).toIntOrNull() ?: return null
            val minute = time.substring(3, 5).toIntOrNull() ?: return null
            if (hour !in 0..23 || minute !in 0..59) return null
            return hour * 60 + minute
        }

        private fun phaseFor(
            minute: Int,
            sunrise: Int?,
            sunset: Int?,
        ): String {
            val sunriseMinute = sunrise ?: 6 * 60
            val sunsetMinute = sunset ?: 18 * 60
            val preDawnStart = (sunriseMinute - 90).coerceIn(3 * 60, 6 * 60)
            val morningEnd = (sunriseMinute + 4 * 60).coerceIn(10 * 60, 12 * 60)
            val noonEnd = 14 * 60
            val eveningStart = (sunsetMinute - 75).coerceIn(16 * 60, 19 * 60)
                .coerceAtLeast(noonEnd + 60)
            val nightStart = (sunsetMinute + 75).coerceIn(18 * 60, 22 * 60)
                .coerceAtLeast(eveningStart + 60)
            return when {
                minute < preDawnStart -> "late_night"
                minute < sunriseMinute -> "pre_dawn"
                minute < morningEnd -> "morning"
                minute < noonEnd -> "noon"
                minute < eveningStart -> "afternoon"
                minute < nightStart -> "evening"
                minute < 23 * 60 -> "night"
                else -> "late_night"
            }
        }

        private fun phaseLabel(phase: String, copy: WidgetCopy): String = when (phase) {
            "pre_dawn" -> copy.preDawn
            "morning" -> copy.morning
            "noon" -> copy.noon
            "afternoon" -> copy.afternoon
            "evening" -> copy.evening
            "night" -> copy.night
            else -> copy.lateNight
        }

        private fun seasonLabel(season: String, copy: WidgetCopy): String = when (season) {
            "spring" -> copy.spring
            "summer" -> copy.summer
            "autumn" -> copy.autumn
            else -> copy.winter
        }

        private fun copyFor(language: String): WidgetCopy = when (language) {
            "en" -> WidgetCopy(
                "Unknown location", "Kurdistan map", "Tap locate",
                "Spring", "Summer", "Autumn", "Winter",
                "Pre-dawn", "Morning", "Noon", "Afternoon", "Evening", "Night", "Late night",
                "ONLINE", "OFFLINE", "OFFLINE READY",
                "DOWNLOADING", "PAUSED", "PREPARING", "ERROR", "DELETING", "Offline map",
            )
            "ar" -> WidgetCopy(
                "الموقع غير محدد", "خريطة كوردستان", "اضغط لتحديد الموقع",
                "الربيع", "الصيف", "الخريف", "الشتاء",
                "قبل الفجر", "الصباح", "الظهر", "بعد الظهر", "المساء", "الليل", "آخر الليل",
                "متصل", "غير متصل", "الخريطة دون اتصال جاهزة",
                "جارٍ التنزيل", "متوقف مؤقتاً", "جارٍ التحضير", "خطأ", "جارٍ الحذف", "خريطة دون اتصال",
            )
            else -> WidgetCopy(
                "شوێن دیاری نەکراوە", "خەریتەی کوردستان", "بۆ دیاریکردنی شوێن دابگرە",
                "بەهار", "هاوین", "پاییز", "زستان",
                "بەرەبەیانی", "بەیانی", "نیوەڕۆ", "دوای نیوەڕۆ", "ئێوارە", "شەو", "شەوەزەنگ",
                "پەیوەستە", "ئۆفلاین", "خەریتەی ئۆفلاین ئامادەیە",
                "دادەبەزێت", "ڕاوەستاوە", "ئامادە دەکرێت", "هەڵە", "دەسڕێتەوە", "ماپی ئۆفلاین",
            )
        }

        private fun localizedStatus(
            rawStatus: String,
            rawDetail: String,
            copy: WidgetCopy,
        ): Pair<String, String> {
            val status = when (rawStatus.uppercase(Locale.ROOT)) {
                "ONLINE" -> copy.online
                "OFFLINE" -> copy.offline
                "OFFLINE READY", "READY" -> copy.offlineReady
                "DOWNLOADING" -> copy.downloading
                "PAUSED" -> copy.paused
                "IDLE", "PREPARING" -> copy.preparing
                "ERROR", "FAILED" -> copy.error
                "DELETING" -> copy.deleting
                else -> rawStatus.take(32)
            }
            val progress = Regex("(\\d{1,3})%").find(rawDetail)?.groupValues?.getOrNull(1)
            val detail = when {
                rawDetail.contains("connected", ignoreCase = true) -> copy.mapReady
                rawDetail.contains("remain available", ignoreCase = true) -> copy.offlineReady
                rawDetail.contains("available offline", ignoreCase = true) -> copy.offlineReady
                rawDetail.contains("offline map", ignoreCase = true) && progress != null ->
                    "${copy.offlineMap} $progress%"
                else -> rawDetail.take(96)
            }
            return status to detail
        }

        private fun refreshPendingIntent(context: Context): PendingIntent {
            val intent = Intent(context, NavKurdWidgetProvider::class.java).apply {
                action = ACTION_REFRESH
            }
            return PendingIntent.getBroadcast(
                context,
                90000,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }

        fun scheduleRefresh(context: Context) {
            // Retire the old repeating alarm so only one periodic owner remains.
            context.getSystemService(AlarmManager::class.java).cancel(refreshPendingIntent(context))
            if (hasWidgets(context)) NavKurdWeatherJob.schedule(context, periodic = true)
            else NavKurdWeatherJob.cancelWidget(context)
            NavKurdWidgetLocation.configure(context)
        }

        private fun cancelRefresh(context: Context) {
            context.getSystemService(AlarmManager::class.java).cancel(refreshPendingIntent(context))
            NavKurdWeatherJob.cancelWidget(context)
            NavKurdWidgetLocation.configure(context)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH -> {
                NavKurdWeatherJob.schedule(context, force = true)
            }
            ACTION_LOCATE -> {
                val launch = Intent(context, MainActivity::class.java).apply {
                    action = Intent.ACTION_VIEW
                    data = Uri.parse("navkurd://locate?action=locate")
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                }
                context.startActivity(launch)
            }
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            AppWidgetManager.ACTION_APPWIDGET_UPDATE -> {
                super.onReceive(context, intent)
                scheduleRefresh(context)
                if (hasWidgets(context)) NavKurdWeatherJob.schedule(context)
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        scheduleRefresh(context)
        appWidgetIds.forEach { id -> render(context, appWidgetManager, id) }
    }

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        scheduleRefresh(context)
        NavKurdWeatherJob.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
        render(context, appWidgetManager, appWidgetId)
    }

    override fun onDisabled(context: Context) {
        cancelRefresh(context)
        super.onDisabled(context)
    }

}
