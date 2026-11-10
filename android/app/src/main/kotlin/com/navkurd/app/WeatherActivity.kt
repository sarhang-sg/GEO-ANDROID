package com.navkurd.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import org.json.JSONObject

class WeatherActivity : FlutterActivity() {
    private val scope=CoroutineScope(SupervisorJob()+Dispatchers.Main.immediate)
    private var channel: MethodChannel?=null
    private fun target()=intent?.getStringExtra("weather_route")?.takeIf { it in listOf("cities","forecast") } ?: "details"
    override fun onResume(){super.onResume();NavKurdWidgetLocation.foreground=true}
    override fun onPause(){NavKurdWidgetLocation.foreground=false;super.onPause()}
    override fun getDartEntrypointFunctionName()="weatherMain"
    override fun getInitialRoute()="/"
    override fun configureFlutterEngine(engine:FlutterEngine){
        super.configureFlutterEngine(engine)
        channel=MethodChannel(engine.dartExecutor.binaryMessenger,"navkurd/weather")
        channel!!.setMethodCallHandler { call,result ->
            when(call.method){
                "route"->result.success(target())
                "back"->{returnToMap();result.success(null)}
                "report"->{WeatherStore.report(this,"flutter",IllegalStateException(call.arguments.toString().take(300)));result.success(null)}
                "settings"->{result.success(WeatherPrompts.settings(this))}
                "prompts"->result.success(WeatherPrompts.take(this))
                "language"-> result.success(WeatherStore.prefs(this).getString("language","ku"))
                "snapshot","load","choose","gps"->scope.launch {
                    try {
                        val encoded=withContext(Dispatchers.IO) {
                            if(call.method=="gps") {
                                intent.removeExtra("weather_destination")
                                if(!WeatherStore.chooseGps(this@WeatherActivity)) throw IllegalStateException("no recent location")
                                WeatherWork.once(this@WeatherActivity,"gps")
                            }
                            if(call.method=="choose"){
                                intent.removeExtra("weather_destination")
                                val selection=WeatherPlace.from(JSONObject(call.arguments as String)) ?: error("invalid city")
                                WeatherStore.select(this@WeatherActivity,selection)
                                NavKurdWeatherJob.schedule(this@WeatherActivity,force=true)
                            }
                            val place=WeatherPlace.from(intent?.getStringExtra("weather_destination")?.let { JSONObject(it) })?.takeIf{call.method!="choose" && call.method!="gps"} ?: WeatherStore.place(this@WeatherActivity)
                            if(place==null) return@withContext JSONObject().toString()
                            val cached=WeatherStore.cached(this@WeatherActivity,place,"detail") ?: WeatherStore.cached(this@WeatherActivity,place,"widget")
                            if(call.method=="snapshot") return@withContext (cached ?: JSONObject().put("place",place.json())).toString()
                            try { WeatherStore.fetch(this@WeatherActivity,place,"detail",call.argumentOrForce()).toString() }
                            catch(e:Exception){ WeatherStore.report(this@WeatherActivity,"details",e);(cached ?: JSONObject().put("place",place.json())).put("stale",true).toString() }
                        }
                        result.success(encoded)
                    } catch(e:CancellationException){throw e} catch(e:Exception){WeatherStore.report(this@WeatherActivity,"channel",e);result.error("weather","Weather unavailable",null)}
                }
                else -> result.notImplemented()
            }
        }
    }
    private fun io.flutter.plugin.common.MethodCall.argumentOrForce()=method=="load" && arguments==true
    override fun onNewIntent(intent:Intent){super.onNewIntent(intent);setIntent(intent);channel?.invokeMethod("route",target())}
    private fun returnToMap(){
        startActivity(Intent(this,MainActivity::class.java).setAction(Intent.ACTION_VIEW)
            .setData(android.net.Uri.parse("navkurd://open?weatherReturn=1"))
            .addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP))
        finish()
    }
    override fun onDestroy(){channel?.setMethodCallHandler(null);scope.cancel();super.onDestroy()}
    companion object {
        fun pending(c:Context,route:String,destination:String?=null):PendingIntent {
            val intent=Intent(c,WeatherActivity::class.java).putExtra("weather_route",route)
                .putExtra("weather_destination",destination).setAction("com.navkurd.app.weather.$route").addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(c,if(destination==null)route.hashCode() else 901080,intent,PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }
    }
}

internal object WeatherPrompts {
    @Synchronized fun take(c:Context):Map<String,Boolean>{
        val p=WeatherStore.prefs(c)
        val notify=Build.VERSION.SDK_INT>=33 && androidx.core.content.ContextCompat.checkSelfPermission(c,android.Manifest.permission.POST_NOTIFICATIONS)!=android.content.pm.PackageManager.PERMISSION_GRANTED && !p.getBoolean("notification_explained",false)
        val oem=Build.MANUFACTURER.lowercase(java.util.Locale.ROOT) in setOf("xiaomi","redmi","poco","samsung","vivo","iqoo")
        val battery=oem && !c.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(c.packageName) && !p.getBoolean("battery_explained",false)
        p.edit().apply {if(notify) putBoolean("notification_explained",true);if(battery) putBoolean("battery_explained",true)}.apply()
        return mapOf("notify" to notify,"battery" to battery)
    }
    fun settings(c:Context):Boolean = runCatching{c.startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS));true}.getOrDefault(false)
}
