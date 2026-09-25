package com.navkurd.app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.PersistableBundle
import java.util.concurrent.ConcurrentHashMap

/** Weather networking belongs to an OS-managed job, never a long broadcast callback. */
class NavKurdWeatherJob : JobService() {
    private val active = ConcurrentHashMap<Int, JobParameters>()

    override fun onStartJob(params: JobParameters): Boolean {
        active[params.jobId] = params
        NavKurdWidgetProvider.refreshWeather(applicationContext, force = params.extras.getBoolean("force")) {
            if (active.remove(params.jobId, params)) {
                if (params.extras.getBoolean("daily")) NavKurdNotifications.showDailyWeather(applicationContext)
                jobFinished(params, false)
            }
        }
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        active.remove(params.jobId, params)
        return true
    }

    companion object {
        private const val PERIODIC = 901030
        private const val IMMEDIATE = 901031
        private const val DAILY = 901032

        fun schedule(context: Context, periodic: Boolean = false, force: Boolean = false, daily: Boolean = false) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            val id = if (daily) DAILY else if (periodic) PERIODIC else IMMEDIATE
            if (scheduler.getPendingJob(id) != null) return
            val extras = PersistableBundle().apply { putBoolean("force", force); putBoolean("daily", daily) }
            val builder = JobInfo.Builder(id, ComponentName(context, NavKurdWeatherJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setBackoffCriteria(60_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
                .setExtras(extras)
            if (periodic) builder.setPeriodic(30L * 60L * 1000L).setPersisted(true)
            else builder.setMinimumLatency(0L)
            if (scheduler.schedule(builder.build()) != JobScheduler.RESULT_SUCCESS) {
                NavKurdDiagnostics.record(context, "warning", "widget.schedule", "Android deferred the weather job.")
            }
        }

        fun cancelWidget(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            scheduler.cancel(PERIODIC)
            scheduler.cancel(IMMEDIATE)
        }
    }
}
