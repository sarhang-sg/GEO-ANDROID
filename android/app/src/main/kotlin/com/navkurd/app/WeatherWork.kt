package com.navkurd.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.work.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.util.Calendar
import java.util.TimeZone
import java.util.concurrent.TimeUnit

class WeatherWork(context:Context,params:WorkerParameters):CoroutineWorker(context,params) {
    override suspend fun doWork():Result = withContext(Dispatchers.IO) {
        val c=applicationContext
        try {
            val mode=inputData.getString("mode") ?: "periodic"
            if(mode=="journey") return@withContext checkJourney(c)
            if(mode=="paint"){WeatherBitmaps.update(c);return@withContext Result.success()}
            if(!NavKurdWidgetProvider.hasWidgets(c) && mode!="daily") return@withContext Result.success()
            val place=WeatherStore.place(c,mode=="gps")
            if(place==null) {WeatherBitmaps.update(c);return@withContext Result.success()}
            val p=WeatherStore.prefs(c)
            val data=try { WeatherStore.fetch(c,place,"widget",mode=="manual" || mode=="gps" || mode=="daily") }
                catch(e:Exception){p.edit().putBoolean("weather_offline",true).apply();WeatherBitmaps.update(c);throw e}
            val current=data.getJSONObject("current")
            if(WeatherStore.place(c)?.key!=place.key){paint(c);return@withContext Result.success()}
            p.edit().putBoolean("weather_offline",data.optBoolean("stale")).putString("city",place.name)
                .putLong("weather_at",current.getLong("time")*1000L).putFloat("temperature",current.getDouble("temperature_2m").toFloat())
                .putString("timezone",data.optString("timezone")).putInt("weather_code",current.getInt("weather_code"))
                .putBoolean("is_day",current.optInt("is_day")==1).apply()
            if(mode=="daily" && !data.optBoolean("stale")) NavKurdNotifications.showDailyWeather(c)
            if(NavKurdWidgetProvider.hasWidgets(c)){
                periodic(c,interval(data));WeatherBitmaps.update(c)
            }
            if(data.optBoolean("stale") && runAttemptCount<3) Result.retry() else Result.success()
        } catch(e:CancellationException){throw e} catch(e:Exception){
            WeatherStore.report(c,"worker",e)
            if(runAttemptCount<4) Result.retry() else Result.success()
        }
    }

    private fun checkJourney(c:Context):Result {
        val p=WeatherStore.prefs(c);val raw=p.getString("weather_journey",null) ?: return Result.success()
        val now=System.currentTimeMillis()
        if(now-p.getLong("weather_journey_seen",0L) !in 0..3*3600000L){journey(c,null);return Result.success()}
        val destination=WeatherPlace.from(JSONObject(raw)) ?: return Result.success()
        val data=WeatherStore.fetch(c,destination,"widget")
        if(data.optBoolean("stale")) return if(runAttemptCount<3) Result.retry() else Result.success()
        val hazard=WeatherStore.hazard(data) ?: return Result.success()
        if(raw!=p.getString("weather_journey",null))return Result.success()
        val id=destination.key+":"+hazard
        if(id==p.getString("weather_last_warning","") && now-p.getLong("weather_warning_at",0L)<3*3600000L) return Result.success()
        val manager=c.getSystemService(NotificationManager::class.java)
        if(!manager.areNotificationsEnabled() || (Build.VERSION.SDK_INT>=33 && ContextCompat.checkSelfPermission(c,Manifest.permission.POST_NOTIFICATIONS)!=PackageManager.PERMISSION_GRANTED)) return Result.success()
        val channel="nav_kurd_route_weather"
        if(Build.VERSION.SDK_INT>=26) {
            manager.createNotificationChannel(NotificationChannel(channel,"ئاگاداریی کەشوهەوای ڕێگا",NotificationManager.IMPORTANCE_HIGH).apply { enableVibration(false) })
            if(manager.getNotificationChannel(channel).importance==NotificationManager.IMPORTANCE_NONE)return Result.success()
        }
        val msg="ئاگاداری: لە خاڵی مەبەست ئەگەری تەمومژ/مەترسی هەیە"
        manager.notify(901080,NotificationCompat.Builder(c,channel).setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(destination.name).setContentText(msg).setStyle(NotificationCompat.BigTextStyle().bigText(msg))
            .setPriority(NotificationCompat.PRIORITY_HIGH).setCategory(NotificationCompat.CATEGORY_STATUS)
            .setOnlyAlertOnce(true).setAutoCancel(true).setContentIntent(WeatherActivity.pending(c,"details",destination.json().toString())).build())
        p.edit().putString("weather_last_warning",id).putLong("weather_warning_at",now).apply()
        return Result.success()
    }

    companion object {
        private val internet=Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()
        fun interval(data:JSONObject?):Long {
            val tz=TimeZone.getTimeZone(data?.optString("timezone","Asia/Baghdad") ?: "Asia/Baghdad")
            val hour=Calendar.getInstance(tz).get(Calendar.HOUR_OF_DAY)
            return if(hour<6) 210L else if(data!=null && WeatherStore.hazard(data)!=null) 30L else 60L
        }
        fun periodic(c:Context,minutes:Long){
            val p=WeatherStore.prefs(c)
            // UPDATE retains the existing period start time and avoids a parallel schedule.
            val req=PeriodicWorkRequestBuilder<WeatherWork>(minutes,TimeUnit.MINUTES).setConstraints(internet)
                .setInputData(workDataOf("mode" to "periodic")).setBackoffCriteria(BackoffPolicy.EXPONENTIAL,1,TimeUnit.MINUTES).build()
            WorkManager.getInstance(c).enqueueUniquePeriodicWork("weather-periodic",ExistingPeriodicWorkPolicy.UPDATE,req)
            p.edit().putLong("weather_interval",minutes).apply()
        }
        fun once(c:Context,mode:String){
            val req=OneTimeWorkRequestBuilder<WeatherWork>().setInputData(workDataOf("mode" to mode)).setBackoffCriteria(BackoffPolicy.EXPONENTIAL,1,TimeUnit.MINUTES)
            // A user action can paint the cached state immediately while offline.
            if(mode=="daily" || mode=="journey")req.setConstraints(internet)
            WorkManager.getInstance(c).enqueueUniqueWork("weather-now-$mode",ExistingWorkPolicy.KEEP,req.build())
        }
        fun paint(c:Context){
            val work=OneTimeWorkRequestBuilder<WeatherWork>().setInputData(workDataOf("mode" to "paint")).build()
            // A final resize is delivered even when an earlier size is being rendered.
            WorkManager.getInstance(c).enqueueUniqueWork("weather-paint",ExistingWorkPolicy.REPLACE,work)
        }
        @Synchronized fun manual(c:Context,mode:String){
            val now=System.currentTimeMillis();val p=WeatherStore.prefs(c)
            if(now-p.getLong("weather_tap_$mode",0L) in 0 until 90_000L)return
            p.edit().putLong("weather_tap_$mode",now).apply();once(c,mode)
        }
        @Synchronized fun journey(c:Context,raw:String?){
            val p=WeatherStore.prefs(c);val wm=WorkManager.getInstance(c)
            if(raw==null){
                p.edit().remove("weather_journey").remove("weather_journey_seen").apply()
                wm.cancelUniqueWork("weather-journey");wm.cancelUniqueWork("weather-now-journey");return
            }
            val place=runCatching { WeatherPlace.from(JSONObject(raw)) }.getOrNull() ?: return
            val encoded=place.json().toString();val changed=encoded!=p.getString("weather_journey",null)
            p.edit().putString("weather_journey",encoded).putLong("weather_journey_seen",System.currentTimeMillis()).apply()
            if(changed){
                val req=PeriodicWorkRequestBuilder<WeatherWork>(30,TimeUnit.MINUTES).setInitialDelay(30,TimeUnit.MINUTES).setConstraints(internet)
                    .setInputData(workDataOf("mode" to "journey")).setBackoffCriteria(BackoffPolicy.EXPONENTIAL,1,TimeUnit.MINUTES).build()
                wm.enqueueUniquePeriodicWork("weather-journey",ExistingPeriodicWorkPolicy.UPDATE,req);once(c,"journey")
            }
        }
    }
}
class WeatherWidgetAction:BroadcastReceiver(){
    override fun onReceive(c:Context,intent:Intent){
        when(intent.action){
            "com.navkurd.app.weather.manual"->WeatherWork.manual(c,"manual")
            "com.navkurd.app.weather.gps"->WeatherWork.manual(c,"gps")
            "com.navkurd.app.weather.phase"-> { if(NavKurdWidgetProvider.hasWidgets(c)){WeatherWork.paint(c);NavKurdWidgetProvider.phaseAlarm(c)} }
        }
    }
}
