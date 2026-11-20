package com.navkurd.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Bundle
import java.util.Calendar
import java.util.TimeZone
import kotlin.math.abs

class NavKurdWidgetProvider:AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        WeatherBitmaps.restore(context, manager, ids)
        scheduleRefresh(context)
        WeatherWork.paint(context)
        NavKurdWeatherJob.schedule(context)
    }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) {
        WeatherBitmaps.restore(context, manager, intArrayOf(id))
        WeatherWork.paint(context)
    }
    override fun onDeleted(context:Context, ids:IntArray) { WeatherBitmaps.discard(context,ids) }
    override fun onEnabled(context:Context){scheduleRefresh(context);NavKurdWeatherJob.schedule(context)}
    override fun onDisabled(context:Context){NavKurdWeatherJob.cancelWidget(context);context.getSystemService(AlarmManager::class.java).cancel(phaseIntent(context));NavKurdWidgetLocation.configure(context)}
    override fun onReceive(context:Context,intent:Intent){
        super.onReceive(context,intent)
        if(intent.action in listOf(Intent.ACTION_BOOT_COMPLETED,Intent.ACTION_MY_PACKAGE_REPLACED,Intent.ACTION_TIME_CHANGED,Intent.ACTION_TIMEZONE_CHANGED) && hasWidgets(context)){
            val manager = AppWidgetManager.getInstance(context)
            WeatherBitmaps.restore(context, manager, manager.getAppWidgetIds(ComponentName(context, NavKurdWidgetProvider::class.java)))
            scheduleRefresh(context);WeatherWork.paint(context)
        }
    }
    companion object {
        const val PREFERENCES="nav_kurd_widget";const val KEY_LANGUAGE="language";const val KEY_CITY="city"
        const val KEY_LATITUDE="latitude";const val KEY_LONGITUDE="longitude";const val KEY_WEATHER_AT="weather_at"
        const val KEY_LAST_RENDER_AT="last_render_at";const val KEY_LAST_RENDER_ERROR="last_render_error"
        const val KEY_TIMEZONE="timezone";const val KEY_IS_DAY="is_day";const val KEY_WEATHER_CODE="weather_code";const val KEY_DUST="dust"
        fun hasWidgets(context:Context)=AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context,NavKurdWidgetProvider::class.java)).isNotEmpty()
        fun setLanguage(c:Context,rawLanguage:String){val lang=rawLanguage.substringBefore('-').lowercase().takeIf{it=="en" || it=="ar"}?:"ku";val p=WeatherStore.prefs(c);if (p.getString(KEY_LANGUAGE,"ku")!=lang) { p.edit().putString(KEY_LANGUAGE,lang).apply(); if(hasWidgets(c)) WeatherWork.paint(c) }}
        fun updateStatus(c:Context,status:String,detail:String){WeatherStore.prefs(c).edit().putString("status",status).putString("detail",detail.take(128)).apply()}
        fun refreshWeather(context:Context,force:Boolean){if(hasWidgets(context))NavKurdWeatherJob.schedule(context,force=force)}
        fun storeLocationAndRefresh(context:Context,location:android.location.Location){
            if (!WeatherStore.recordFix(context,location)) return
            val p=WeatherStore.prefs(context)
            val moved=abs(location.latitude-p.getFloat("weather_latitude",1000f))>.008 ||
                abs(location.longitude-p.getFloat("weather_longitude",1000f))>.008
            if(moved && WeatherStore.widgetUsesGps(context)) refreshWeather(context,true)
        }
        fun dailyWeatherSummary(c:Context):Pair<String,String>?{
            val p=WeatherStore.prefs(c);if(System.currentTimeMillis()-p.getLong(KEY_WEATHER_AT,0L) !in 0..5_400_000L || p.getBoolean("weather_offline",false))return null
            val t=p.getFloat("temperature",Float.NaN);if(!t.isFinite())return null
            val city=p.getString(KEY_CITY,null) ?: return null
            return city to "${Math.round(t)}°C · Open-Meteo"
        }
        fun scheduleRefresh(c:Context){if(!hasWidgets(c))return;NavKurdWeatherJob.schedule(c,periodic=true);NavKurdWidgetLocation.configure(c);phaseAlarm(c)}
        private fun phaseIntent(c:Context)=PendingIntent.getBroadcast(c,901091,Intent(c,WeatherWidgetAction::class.java).setAction("com.navkurd.app.weather.phase"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        fun phaseAlarm(c:Context){
            val tz=WeatherStore.prefs(c).getString(KEY_TIMEZONE,"Asia/Baghdad") ?: "Asia/Baghdad"
            val now=Calendar.getInstance(TimeZone.getTimeZone(tz));val next=now.clone() as Calendar
            val hour=listOf(5,7,10,12,15,17,19,24).first { it>now.get(Calendar.HOUR_OF_DAY) }
            if(hour==24)next.add(Calendar.DATE,1)
            next.set(Calendar.HOUR_OF_DAY,hour%24);next.set(Calendar.MINUTE,0);next.set(Calendar.SECOND,0);next.set(Calendar.MILLISECOND,0)
            c.getSystemService(AlarmManager::class.java).set(AlarmManager.RTC,next.timeInMillis,phaseIntent(c))
        }
    }
}
