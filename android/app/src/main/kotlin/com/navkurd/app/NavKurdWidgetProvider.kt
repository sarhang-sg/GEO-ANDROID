package com.navkurd.app

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationManager
import android.net.Uri
import android.os.SystemClock
import android.view.View
import android.widget.RemoteViews
import androidx.core.content.ContextCompat
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
        const val KEY_LAST_RENDER_AT = "last_render_at"
        const val KEY_LAST_RENDER_ERROR = "last_render_error"

        private const val ACTION_REFRESH = "com.navkurd.app.WIDGET_REFRESH"
        private const val ACTION_LOCATE = "com.navkurd.app.WIDGET_LOCATE"
        private const val WEATHER_TTL_MILLIS = 30L * 60L * 1000L
        private const val WIDGET_REFRESH_MILLIS = 30L * 60L * 1000L
        private const val DUST_THRESHOLD = 50.0
        private const val STRONG_WIND_KMH = 40.0
        private const val STRONG_GUST_KMH = 60.0
        private val executor = Executors.newSingleThreadExecutor()
        private val refreshRunning = AtomicBoolean(false)
        private val forcedRefreshPending = AtomicBoolean(false)

        private data class WeatherPayload(
            val temperature: Double,
            val apparentTemperature: Double?,
            val weatherCode: Int,
            val isDay: Boolean,
            val timezone: String,
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
            val dawn: String,
            val morning: String,
            val noon: String,
            val afternoon: String,
            val evening: String,
            val night: String,
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
            if (!preferences.contains(KEY_TEMPERATURE)) return null
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

        fun updateAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val component = ComponentName(context, NavKurdWidgetProvider::class.java)
            manager.getAppWidgetIds(component).forEach { id ->
                render(context, manager, id)
            }
        }

        fun refreshWeather(
            context: Context,
            force: Boolean,
            onComplete: (() -> Unit)? = null,
        ) {
            val appContext = context.applicationContext
            if (!refreshRunning.compareAndSet(false, true)) {
                if (force) forcedRefreshPending.set(true)
                onComplete?.invoke()
                return
            }
            executor.execute {
                try {
                    refreshWeatherBlocking(appContext, force)
                } catch (error: Exception) {
                    val preferences = appContext.getSharedPreferences(
                        PREFERENCES,
                        Context.MODE_PRIVATE,
                    )
                    if (!preferences.contains(KEY_WEATHER_AT)) {
                        NavKurdDiagnostics.record(
                            appContext,
                            "warning",
                            "widget.weather",
                            error.message ?: "Weather update failed",
                        )
                    }
                } finally {
                    updateAll(appContext)
                    refreshRunning.set(false)
                    onComplete?.invoke()
                    if (forcedRefreshPending.getAndSet(false)) {
                        refreshWeather(appContext, force = true)
                    }
                }
            }
        }

        private fun refreshWeatherBlocking(context: Context, force: Boolean) {
            val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            var coordinates = storedCoordinates(preferences)
            if (coordinates == null) {
                coordinates = lastKnownCoordinates(context)
                coordinates?.let { (latitude, longitude) ->
                    preferences.edit()
                        .putFloat(KEY_LATITUDE, latitude.toFloat())
                        .putFloat(KEY_LONGITUDE, longitude.toFloat())
                        .putLong(KEY_LOCATION_AT, System.currentTimeMillis())
                        .apply()
                }
            }
            if (coordinates == null) return

            val now = System.currentTimeMillis()
            val weatherAt = preferences.getLong(KEY_WEATHER_AT, 0L)
            val hasWeather = preferences.contains(KEY_TEMPERATURE)
            if (!force && hasWeather && now - weatherAt in 0 until WEATHER_TTL_MILLIS) {
                return
            }

            val (latitude, longitude) = coordinates
            val city = resolveCity(context, latitude, longitude)
            preferences.edit().putString(KEY_CITY, city).apply()
            val payload = fetchWeather(context, latitude, longitude)
            preferences.edit()
                .putFloat(KEY_TEMPERATURE, payload.temperature.toFloat())
                .putFloat(
                    KEY_APPARENT_TEMPERATURE,
                    payload.apparentTemperature?.toFloat() ?: Float.NaN,
                )
                .putInt(KEY_WEATHER_CODE, payload.weatherCode)
                .putBoolean(KEY_IS_DAY, payload.isDay)
                .putString(KEY_TIMEZONE, payload.timezone)
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
            return preferences.getFloat(KEY_LATITUDE, 0f).toDouble() to
                preferences.getFloat(KEY_LONGITUDE, 0f).toDouble()
        }

        private fun lastKnownCoordinates(context: Context): Pair<Double, Double>? {
            val fine = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_FINE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
            val coarse = ContextCompat.checkSelfPermission(
                context,
                Manifest.permission.ACCESS_COARSE_LOCATION,
            ) == PackageManager.PERMISSION_GRANTED
            if (!fine && !coarse) return null
            return runCatching {
                val manager = context.getSystemService(LocationManager::class.java)
                manager.allProviders
                    .mapNotNull { provider ->
                        runCatching { manager.getLastKnownLocation(provider) }.getOrNull()
                    }
                    .maxByOrNull { it.time }
                    ?.let { it.latitude to it.longitude }
            }.getOrNull()
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
                    "&temperature_unit=celsius&wind_speed_unit=kmh&timezone=auto",
            )
            val connection = endpoint.openConnection() as HttpURLConnection
            connection.connectTimeout = 10000
            connection.readTimeout = 10000
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
                val timezone = root.optString("timezone", TimeZone.getDefault().id)
                    .takeIf { it.isNotBlank() }
                    ?: TimeZone.getDefault().id
                val dust = runCatching {
                    fetchDust(context, latitude, longitude)
                }.getOrNull()
                return WeatherPayload(
                    temperature = current.getDouble("temperature_2m"),
                    apparentTemperature = optionalDouble("apparent_temperature"),
                    weatherCode = current.getInt("weather_code"),
                    isDay = current.optInt("is_day", 1) == 1,
                    timezone = timezone,
                    observedAt = current.optString("time", ""),
                    humidity = current.optInt("relative_humidity_2m", -1).takeIf { it >= 0 },
                    precipitation = optionalDouble("precipitation"),
                    rain = optionalDouble("rain"),
                    showers = optionalDouble("showers"),
                    snowfall = optionalDouble("snowfall"),
                    cloudCover = current.optInt("cloud_cover", -1).takeIf { it >= 0 },
                    windSpeed = optionalDouble("wind_speed_10m"),
                    windGusts = optionalDouble("wind_gusts_10m"),
                    dust = dust,
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
            connection.connectTimeout = 7000
            connection.readTimeout = 7000
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
            val temperature = if (hasWeather) {
                String.format(
                    Locale.ROOT,
                    "%.0f°",
                    temperatureValue ?: 0.0,
                )
            } else {
                "—°"
            }
            val weatherCode = preferences.getInt(KEY_WEATHER_CODE, -1)
            val timezone = preferences.getString(KEY_TIMEZONE, TimeZone.getDefault().id)
                ?.takeIf { it.isNotBlank() }
                ?: TimeZone.getDefault().id
            val isDay = if (preferences.contains(KEY_IS_DAY)) {
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
            val localHour = Calendar.getInstance(TimeZone.getTimeZone(timezone))
                .get(Calendar.HOUR_OF_DAY)
            val phase = phaseFor(localHour)
            val condition = weatherCondition(kind, isDay, language)
            val seasonLabel = seasonLabel(season.key, copy)
            val phaseLabel = phaseLabel(phase, copy)
            val frame = System.currentTimeMillis() / (10L * 60L * 1000L)

            val layout = if (language == "en") R.layout.nav_kurd_widget_en else R.layout.nav_kurd_widget
            val views = RemoteViews(context.packageName, layout)
            views.setImageViewBitmap(
                R.id.widget_scene,
                NavKurdWidgetArtwork.scene(kind.name, isDay, phase, season.key, frame),
            )
            views.setImageViewBitmap(
                R.id.widget_weather_icon,
                NavKurdWidgetArtwork.weatherIcon(kind.name, isDay, frame),
            )
            views.setTextViewText(R.id.widget_temperature, temperature)
            views.setTextViewText(R.id.widget_city, city)
            views.setTextViewText(R.id.widget_condition, condition)
            views.setTextViewText(R.id.widget_season, seasonLabel)
            views.setTextViewText(R.id.widget_phase, phaseLabel)
            views.setTextViewText(R.id.widget_status, status)
            views.setTextViewText(R.id.widget_detail, detail)
            views.setTextViewText(R.id.widget_updated, if (hasWeather) "Open-Meteo" else copy.tapLocate)
            views.setTextViewText(R.id.widget_humidity, humidity?.let { "$it%" } ?: "—%")
            views.setTextViewText(
                R.id.widget_wind,
                windSpeed?.let { String.format(Locale.ROOT, "%.0f km/h", it) } ?: "— km/h",
            )
            views.setTextViewText(
                R.id.widget_dust,
                dust?.let { String.format(Locale.ROOT, "%.0f µg/m³", it) } ?: "",
            )
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
            val locateIntent = Intent(context, NavKurdWidgetProvider::class.java).apply {
                action = ACTION_LOCATE
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
                PendingIntent.getBroadcast(context, widgetId + 10000, locateIntent, flags),
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
            val month = Calendar.getInstance(TimeZone.getTimeZone(timezone))
                .get(Calendar.MONTH) + 1
            val northernMonth = if (latitude < 0.0) ((month + 5) % 12) + 1 else month
            return when (northernMonth) {
                in 3..5 -> Season("spring")
                in 6..8 -> Season("summer")
                in 9..11 -> Season("autumn")
                else -> Season("winter")
            }
        }

        private fun phaseFor(hour: Int): String = when (hour) {
            in 5..7 -> "dawn"
            in 8..10 -> "morning"
            in 11..14 -> "noon"
            in 15..17 -> "afternoon"
            in 18..20 -> "evening"
            else -> "night"
        }

        private fun phaseLabel(phase: String, copy: WidgetCopy): String = when (phase) {
            "dawn" -> copy.dawn
            "morning" -> copy.morning
            "noon" -> copy.noon
            "afternoon" -> copy.afternoon
            "evening" -> copy.evening
            else -> copy.night
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
                "Dawn", "Morning", "Noon", "Afternoon", "Evening", "Night",
                "ONLINE", "OFFLINE", "OFFLINE READY",
                "DOWNLOADING", "PAUSED", "PREPARING", "ERROR", "DELETING", "Offline map",
            )
            "ar" -> WidgetCopy(
                "الموقع غير محدد", "خريطة كوردستان", "اضغط لتحديد الموقع",
                "الربيع", "الصيف", "الخريف", "الشتاء",
                "الفجر", "الصباح", "الظهر", "بعد الظهر", "المساء", "الليل",
                "متصل", "غير متصل", "الخريطة دون اتصال جاهزة",
                "جارٍ التنزيل", "متوقف مؤقتاً", "جارٍ التحضير", "خطأ", "جارٍ الحذف", "خريطة دون اتصال",
            )
            else -> WidgetCopy(
                "شوێن دیاری نەکراوە", "خەریتەی کوردستان", "بۆ دیاریکردنی شوێن دابگرە",
                "بەهار", "هاوین", "پاییز", "زستان",
                "بەیانی زوو", "بەیانی", "نیوەڕۆ", "دوا نیوەڕۆ", "ئێوارە", "شەو",
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
            val alarmManager = context.getSystemService(AlarmManager::class.java)
            alarmManager.setInexactRepeating(
                AlarmManager.ELAPSED_REALTIME,
                SystemClock.elapsedRealtime() + WIDGET_REFRESH_MILLIS,
                WIDGET_REFRESH_MILLIS,
                refreshPendingIntent(context),
            )
        }

        private fun cancelRefresh(context: Context) {
            context.getSystemService(AlarmManager::class.java)
                .cancel(refreshPendingIntent(context))
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_REFRESH -> {
                val pending = goAsync()
                refreshWeather(context, force = true) { pending.finish() }
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
                val pending = goAsync()
                refreshWeather(context, force = false) { pending.finish() }
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
        refreshWeather(context, force = false)
    }

    override fun onDisabled(context: Context) {
        cancelRefresh(context)
        super.onDisabled(context)
    }

}
