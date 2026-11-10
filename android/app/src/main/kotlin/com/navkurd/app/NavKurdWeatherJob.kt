package com.navkurd.app

import android.app.job.JobScheduler
import android.content.Context
import androidx.work.WorkManager

/** Existing map and notification call sites share the same persistent WorkManager jobs. */
object NavKurdWeatherJob {
    fun schedule(context:Context,periodic:Boolean=false,force:Boolean=false,daily:Boolean=false){
        val scheduler=context.getSystemService(JobScheduler::class.java)
        listOf(901030,901031,901032).forEach { if(scheduler.getPendingJob(it)!=null)scheduler.cancel(it) }
        if(periodic) WeatherWork.periodic(context,WeatherStore.prefs(context).getLong("weather_interval",WeatherWork.interval(null)))
        else WeatherWork.once(context,if(daily)"daily" else if(force)"refresh" else "initial")
    }
    fun cancelWidget(context:Context){
        val work=WorkManager.getInstance(context)
        for(name in listOf("weather-periodic","weather-paint","weather-now-initial","weather-now-manual","weather-now-gps","weather-now-refresh")) work.cancelUniqueWork(name)
    }
}
