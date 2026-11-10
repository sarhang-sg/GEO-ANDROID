package com.navkurd.app

import android.content.Context
import android.net.Uri
import android.util.AtomicFile
import com.google.firebase.FirebaseApp
import com.google.firebase.crashlytics.FirebaseCrashlytics
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.Locale
import kotlin.math.*

internal data class WeatherPlace(val lat: Double, val lon: Double, val name: String) {
    val key: String get() = String.format(Locale.US, "%.3f_%.3f", lat, lon)
    fun json() = JSONObject().put("lat",lat).put("lon",lon).put("name",name)
    companion object {
        fun from(obj: JSONObject?): WeatherPlace? {
            if (obj == null) return null
            val lat = obj.optDouble("lat"); val lon = obj.optDouble("lon")
            if (lat !in -90.0..90.0 || lon !in -180.0..180.0) return null
            return WeatherPlace(lat,lon,obj.optString("name").take(120))
        }
    }
}

internal object WeatherStore {
    const val BASE = "https://geo-map-kappa.vercel.app/api/weather"
    fun prefs(c: Context) = c.getSharedPreferences(NavKurdWidgetProvider.PREFERENCES,Context.MODE_PRIVATE)
    fun report(c: Context, where: String, error: Throwable) {
        runCatching { NavKurdDiagnostics.record(c,"warning","weather.$where",error.javaClass.simpleName) }
        runCatching {
            if (FirebaseApp.getApps(c).isNotEmpty())
                FirebaseCrashlytics.getInstance().recordException(IllegalStateException("Weather: $where",error))
        }
    }
    @Volatile private var catalog: JSONArray? = null
    fun cities(c: Context): JSONArray = catalog ?: synchronized(this) {
        catalog ?: c.assets.open("flutter_assets/assets/weather/cities.json").bufferedReader().use { JSONArray(it.readText()) }.also { catalog = it }
    }
    private fun named(c: Context, lat: Double, lon: Double): WeatherPlace {
        val places = cities(c)
        var best = 35.0; var name = String.format(Locale.US,"%.2f°, %.2f°",lat,lon)
        for (i in 0 until places.length()) {
            val item = places.getJSONObject(i); val dy = item.getDouble("lat")-lat
            val dx = (item.getDouble("lon")-lon)*cos(Math.toRadians(lat))
            val distance = 111.2*hypot(dy,dx)
            if (distance < best) { best=distance; name=item.getString("name") }
        }
        return WeatherPlace(lat,lon,name)
    }
    fun chooseGps(c:Context):Boolean {
        val fix=NavKurdWidgetLocation.current(c,foregroundRequest=true) ?: return false
        prefs(c).edit().putBoolean("weather_prefer_gps",true).putFloat("latitude",fix.latitude.toFloat())
            .putFloat("longitude",fix.longitude.toFloat()).putLong("location_at",fix.time).apply()
        return true
    }
    fun select(c: Context, place: WeatherPlace) {
        prefs(c).edit().putString("weather_selected_city",place.json().toString()).putBoolean("weather_prefer_gps",false).apply()
    }
    fun place(c: Context, requestFix: Boolean = false): WeatherPlace? {
        val p=prefs(c)
        val selected = p.getString("weather_selected_city",null)?.let { runCatching { WeatherPlace.from(JSONObject(it)) }.getOrNull() }
        if (requestFix || p.getBoolean("weather_prefer_gps",true)) {
            val fix = runCatching { if (requestFix) NavKurdWidgetLocation.current(c) else NavKurdWidgetLocation.latest(c) }.getOrNull()
            if (fix != null) {
                val place=named(c,fix.latitude,fix.longitude)
                p.edit().putFloat("latitude",fix.latitude.toFloat()).putFloat("longitude",fix.longitude.toFloat())
                    .putLong("location_at",fix.time).putBoolean("weather_prefer_gps",true).apply()
                return place
            }
            if (selected != null) return selected
            if (p.contains("latitude") && p.contains("longitude")) {
                val lat=p.getFloat("latitude",Float.NaN).toDouble(); val lon=p.getFloat("longitude",Float.NaN).toDouble()
                if (lat in -90.0..90.0 && lon in -180.0..180.0) return named(c,lat,lon)
            }
        }
        return selected
    }
    private fun file(c: Context, place: WeatherPlace, scope: String): File {
        val dir=File(c.filesDir,"weather-readings"); dir.mkdirs()
        return File(dir,"${place.key}-$scope.json")
    }
    private fun legacy(c:Context,place:WeatherPlace):JSONObject? {
        val p=prefs(c)
        val lat=p.getFloat("weather_latitude",Float.NaN).toDouble()
        val lon=p.getFloat("weather_longitude",Float.NaN).toDouble()
        val value=p.getFloat("temperature",Float.NaN)
        if (!lat.isFinite() || !lon.isFinite() || abs(lat-place.lat)>.005 || abs(lon-place.lon)>.005 || !value.isFinite()) return null
        val stamp=p.getLong("weather_at",0L)
        if(stamp<=0) return null
        val tz=p.getString("timezone","Asia/Baghdad") ?: "Asia/Baghdad"
        val hours=JSONArray(p.getString("hourly_forecast","[]") ?: "[]")
        val ts=JSONArray();val temp=JSONArray();val codes=JSONArray();val days=JSONArray()
        for(i in 0 until minOf(hours.length(),5)){
            val h=hours.optJSONObject(i) ?: continue
            if(h.optLong("at")<=0 || !h.optDouble("temperature").isFinite())continue
            ts.put(h.optLong("at")/1000);temp.put(h.getDouble("temperature"));codes.put(h.optInt("code",-1));days.put(if(h.optBoolean("isDay"))1 else 0)
        }
        val cur=JSONObject().put("temperature_2m",value.toDouble()).put("time",stamp/1000)
            .put("is_day",if(p.getBoolean("is_day",true))1 else 0).put("weather_code",p.getInt("weather_code",-1))
        p.getFloat("wind_speed",Float.NaN).takeIf{it.isFinite()}?.let {cur.put("wind_speed_10m",it.toDouble())}
        return JSONObject().put("place",place.json()).put("stale",true).put("fetched_at",stamp).put("timezone",tz)
            .put("utc_offset_seconds",java.util.TimeZone.getTimeZone(tz).getOffset(stamp)/1000).put("current",cur)
            .put("hourly",JSONObject().put("time",ts).put("temperature_2m",temp).put("weather_code",codes).put("is_day",days))
    }
    @Synchronized fun cached(c: Context, place: WeatherPlace, scope: String): JSONObject? = runCatching {
        val target=file(c,place,scope)
        if (!target.isFile) return if(scope=="widget") legacy(c,place) else null
        JSONObject(AtomicFile(target).readFully().toString(Charsets.UTF_8)).apply {
            put("place",place.json())
            if (System.currentTimeMillis()-optLong("fetched_at")>90*60_000L) put("stale",true)
        }
    }.getOrNull()
    @Synchronized private fun save(c: Context, place: WeatherPlace, scope: String, data: JSONObject) {
        val target=file(c,place,scope);val atomic=AtomicFile(target); val stream=atomic.startWrite()
        try { stream.write(data.toString().toByteArray()); atomic.finishWrite(stream) }
        catch(e:Exception){ atomic.failWrite(stream); throw e }
        target.parentFile?.listFiles { f -> f.extension=="json" }?.sortedByDescending { it.lastModified() }?.drop(40)?.forEach { it.delete() }
    }
    /** All callers use an IO worker. Credentials for purchased forecasts live only at the proxy. */
    fun fetch(c: Context, place: WeatherPlace, scope: String, force: Boolean=false): JSONObject {
        require(scope=="widget" || scope=="detail")
        val previous=cached(c,place,scope)
        if (!force && previous!=null && !previous.optBoolean("stale") && System.currentTimeMillis()-previous.optLong("fetched_at") in 0 until 600_000L) return previous
        val uri=Uri.parse(BASE).buildUpon().appendQueryParameter("latitude",place.lat.toString())
            .appendQueryParameter("longitude",place.lon.toString()).appendQueryParameter("scope",scope).build()
        val conn=URL(uri.toString()).openConnection() as HttpURLConnection
        try {
            conn.connectTimeout=5000; conn.readTimeout=12000; conn.instanceFollowRedirects=false
            conn.setRequestProperty("Accept","application/json")
            if (conn.responseCode != 200) throw IOException("weather HTTP ${conn.responseCode}")
            val data=conn.inputStream.bufferedReader().use { JSONObject(it.readText()) }
            val cur=data.optJSONObject("current") ?: throw IOException("missing current")
            if (!data.optBoolean("available") || cur.optDouble("temperature_2m") !in -90.0..65.0 ||
                cur.optLong("time")<=0 || data.optJSONArrayOrHours()==null) throw IOException("invalid forecast")
            data.put("place",place.json())
            save(c,place,scope,data)
            return data
        } finally { conn.disconnect() }
    }
    private fun JSONObject.optJSONArrayOrHours() = optJSONObject("hourly")?.optJSONArray("time")
    fun hazard(data: JSONObject): String? {
        if (data.optBoolean("stale")) return null
        val cur=data.optJSONObject("current") ?: return null
        if (System.currentTimeMillis()-cur.optLong("time")*1000 !in -300_000L..5_400_000L) return null
        val temp=cur.optDouble("temperature_2m");val code=cur.optInt("weather_code",-1)
        return when {
            temp>45 -> "heat"; temp<0 -> "cold"; code in listOf(65,82,95,96,99) -> "storm"
            cur.optDouble("european_aqi")>60 -> "dust"; code==45 || code==48 -> "fog"
            code in listOf(56,57,66,67,75,86) -> "ice"; else -> null
        }
    }
}
