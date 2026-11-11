package com.navkurd.app

import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.os.RemoteException
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.json.JSONObject

/** The foreground map and this unexported bitmap service have separate Flutter engines and VMs. */
class WeatherRenderService : Service() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val requests = Messenger(Handler(Looper.getMainLooper()) { request ->
        if (request.what == RENDER && request.sendingUid == Process.myUid()) {
            val reply = request.replyTo
            val snapshot = request.data.getString(SNAPSHOT)
            if (reply != null && snapshot != null) scope.launch {
                val result = try {
                    WeatherBitmaps.publishBitmaps(applicationContext, JSONObject(snapshot))
                    DONE
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    android.util.Log.w("NavKurdWidget", "Cannot render weather widget", e)
                    FAILED
                }
                try {
                    reply.send(Message.obtain(null, result))
                } catch (_: RemoteException) {
                    // The worker that bound this service has already stopped.
                }
            }
        }
        true
    })

    override fun onBind(intent: Intent): IBinder = requests.binder

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val RENDER = 1
        private const val DONE = 2
        private const val FAILED = 3
        private const val SNAPSHOT = "weather"

        suspend fun publish(context: Context, snapshot: JSONObject) = withContext(Dispatchers.Main.immediate) {
            val app = context.applicationContext
            val done = CompletableDeferred<Unit>()
            val reply = Messenger(Handler(Looper.getMainLooper()) { message ->
                if (message.what == DONE) done.complete(Unit)
                else done.completeExceptionally(IOException("Weather renderer reported an error"))
                true
            })
            val request = Message.obtain(null, RENDER).apply {
                replyTo = reply
                data = Bundle().apply { putString(SNAPSHOT, snapshot.toString()) }
            }
            val connection = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                    if (done.isCompleted) return
                    try {
                        Messenger(binder).send(request)
                    } catch (e: RemoteException) {
                        done.completeExceptionally(e)
                    }
                }
                override fun onServiceDisconnected(name: ComponentName) {
                    done.completeExceptionally(IOException("Weather renderer disconnected"))
                }
                override fun onBindingDied(name: ComponentName) = onServiceDisconnected(name)
                override fun onNullBinding(name: ComponentName) = onServiceDisconnected(name)
            }
            if (!app.bindService(Intent(app, WeatherRenderService::class.java), connection, Context.BIND_AUTO_CREATE))
                throw IOException("Cannot bind weather renderer")
            try {
                withTimeoutOrNull(100_000L) { done.await() } ?: throw IOException("Weather renderer timed out")
            } finally {
                done.cancel()
                app.unbindService(connection)
            }
        }
    }
}
