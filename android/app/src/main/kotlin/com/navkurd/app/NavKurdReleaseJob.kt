package com.navkurd.app

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.concurrent.Executors
import java.util.concurrent.Future

/** Update HTTP runs only in an OS-managed, connectivity-constrained worker. */
class NavKurdReleaseJob : JobService() {
    private val main = Handler(Looper.getMainLooper())
    private val active = mutableMapOf<Int, Pair<JobParameters, Future<*>>>()

    override fun onStartJob(params: JobParameters): Boolean {
        if (!NavKurdNotifications.canNotify(this, NavKurdNotifications.CHANNEL_APP_UPDATES)) return false
        val future = executor.submit {
            var retry = false
            try {
                NavKurdNotificationReceiver().checkForUpdate(applicationContext)
                getSharedPreferences(PREFS, MODE_PRIVATE).edit().putLong("checked_at", System.currentTimeMillis()).apply()
            } catch (error: Exception) {
                retry = true
                NavKurdDiagnostics.record(applicationContext, "warning", "notification.update-check", error.message ?: "Update check deferred")
            }
            main.post {
                if (active[params.jobId]?.first === params) {
                    active.remove(params.jobId)
                    jobFinished(params, retry)
                }
            }
        }
        active[params.jobId] = params to future
        return true
    }

    override fun onStopJob(params: JobParameters): Boolean {
        active.remove(params.jobId)?.second?.cancel(true)
        return true
    }

    companion object {
        private const val PERIODIC = 901040
        private const val IMMEDIATE = 901041
        private const val PREFS = "nav_kurd_update_worker"
        private val executor = Executors.newSingleThreadExecutor()

        fun schedule(context: Context, periodic: Boolean = false) {
            val scheduler = context.getSystemService(JobScheduler::class.java)
            val id = if (periodic) PERIODIC else IMMEDIATE
            if (scheduler.getPendingJob(id) != null) return
            val checked = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getLong("checked_at", 0L)
            if (!periodic && System.currentTimeMillis() - checked in 0 until 6L * 60L * 60L * 1000L) return
            val builder = JobInfo.Builder(id, ComponentName(context, NavKurdReleaseJob::class.java))
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setBackoffCriteria(60_000L, JobInfo.BACKOFF_POLICY_EXPONENTIAL)
            if (periodic) builder.setPeriodic(12L * 60L * 60L * 1000L).setPersisted(true)
            else builder.setMinimumLatency(20_000L)
            if (scheduler.schedule(builder.build()) != JobScheduler.RESULT_SUCCESS) {
                NavKurdDiagnostics.record(context, "warning", "notification.schedule", "Android deferred the update job.")
            }
        }
    }
}
