package com.navkurd.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import kotlin.math.*

internal object WeatherBitmaps {
    private val rendering=Mutex()
    private data class Extent(val w:Float,val h:Float)
    @Suppress("DEPRECATION")
    private fun sizes(b:Bundle):List<Extent>{
        if(Build.VERSION.SDK_INT>=31){
            val list=b.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES).orEmpty()
                .filter { it.width.isFinite() && it.height.isFinite() && it.width>=16 && it.height>=16 }
                .map { Extent(it.width,it.height) }.distinct().sortedBy{ it.w*it.h }
            if(list.isNotEmpty())return if(list.size<=4)list else listOf(list.first(),list[list.size/3],list[list.size*2/3],list.last()).distinct()
        }
        fun dim(key:String,default:Int)=b.getInt(key,default).takeIf { it>0 }?.toFloat()?:default.toFloat()
        val minW=dim(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH,260);val maxW=dim(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH,minW.toInt())
        val minH=dim(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,110);val maxH=dim(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT,minH.toInt())
        return listOf(Extent(minW,maxH),Extent(maxW,minH)).distinct()
    }
    private class Renderer(val engine:FlutterEngine,val channel:MethodChannel){
        suspend fun png(size:Extent,scale:Double,data:Map<String,Any?>):ByteArray {
            val outcome=CompletableDeferred<ByteArray>()
            return withContext(Dispatchers.Main.immediate){
                channel.invokeMethod("render",mapOf("width" to size.w.toDouble(),"height" to size.h.toDouble(),"ratio" to scale,"weather" to data),object:MethodChannel.Result{
                    override fun success(result:Any?) {if(result is ByteArray)outcome.complete(result) else outcome.completeExceptionally(IllegalStateException("invalid bitmap"))}
                    override fun error(code:String,message:String?,details:Any?){outcome.completeExceptionally(IllegalStateException("bitmap: $code"))}
                    override fun notImplemented(){outcome.completeExceptionally(IllegalStateException("missing bitmap renderer"))}
                })
                withTimeoutOrNull(15000) { outcome.await() } ?: throw java.io.IOException("Widget bitmap timed out")
            }
        }
    }
    private suspend fun start(c:Context):Renderer = withContext(Dispatchers.Main.immediate){
        val loader=FlutterInjector.instance().flutterLoader()
        loader.startInitialization(c);loader.ensureInitializationComplete(c,null)
        val engine=FlutterEngine(c,null,false)
        try{
            val channel=MethodChannel(engine.dartExecutor.binaryMessenger,"navkurd/weather_bitmap");val ready=CompletableDeferred<Unit>()
            channel.setMethodCallHandler { call,result -> if(call.method=="ready"){result.success(null);ready.complete(Unit)}else result.notImplemented() }
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"weatherBitmapMain"))
            withTimeoutOrNull(25000) { ready.await() } ?: throw java.io.IOException("Widget engine did not become ready")
            Renderer(engine,channel)
        }catch(e:Throwable){engine.destroy();throw e}
    }
    private fun bridge(value:Any?):Any?=when(value){
        null,JSONObject.NULL->null
        is JSONObject->value.keys().asSequence().associateWith { bridge(value.opt(it)) }
        is JSONArray->(0 until value.length()).map { bridge(value.opt(it)) }
        else->value
    }
    private fun action(c:Context,name:String)=PendingIntent.getBroadcast(c,name.hashCode(),Intent(c,WeatherWidgetAction::class.java).setAction("com.navkurd.app.weather.$name"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun views(c:Context,s:Extent,bitmap:Bitmap?,data:JSONObject):RemoteViews{
        val small=s.w<200 || s.h<58
        val v=RemoteViews(c.packageName,if(small)R.layout.weather_small else R.layout.weather_dashboard)
        val name = data.optJSONObject("place")?.optString("name").orEmpty()
        val current = data.optJSONObject("current")
        val temp = current?.optDouble("temperature_2m")?.takeIf { it.isFinite() }?.roundToInt()
        val city = name.ifBlank { c.getString(R.string.weather_pick_city) }
        val stamp = current?.optLong("time") ?: 0L
        val clock = android.text.format.DateFormat.getTimeFormat(c)
        if (data.optString("timezone").isNotBlank())
            clock.timeZone = java.util.TimeZone.getTimeZone(data.getString("timezone"))
        val last = if (stamp > 0L && temp != null) c.getString(R.string.weather_last_reading, clock.format(java.util.Date(stamp * 1000L))) else ""
        val forecast = if (temp == null) c.getString(R.string.weather_open_forecast)
            else listOf("${temp}°C", last).filter { it.isNotEmpty() }.joinToString(if (small) " · " else "\n")
        if (bitmap != null) v.setImageViewBitmap(R.id.weather_bitmap, bitmap)
        if (bitmap == null) {
            val now = java.util.Calendar.getInstance(clock.timeZone)
            val background = when (now.get(java.util.Calendar.HOUR_OF_DAY)) {
                in 5..6 -> R.drawable.widget_dawn
                in 7..14 -> R.drawable.widget_morning
                in 15..16 -> R.drawable.widget_afternoon
                in 17..18 -> R.drawable.widget_sunset
                else -> R.drawable.widget_night
            }
            v.setInt(R.id.weather_root, "setBackgroundResource", background)
        }
        v.setTextViewText(R.id.weather_city, if (bitmap == null) city else "")
        v.setTextViewText(R.id.weather_forecast, if (bitmap == null) forecast else "")
        if (!small) {
            v.setTextViewText(R.id.weather_gps, if (bitmap == null) "◎" else "")
            v.setTextViewText(R.id.weather_refresh, if (bitmap == null) "↻" else "")
        }
        v.setContentDescription(R.id.weather_bitmap, listOf(city, forecast, "Open-Meteo · Developer: Sarhang Salah").joinToString(" · "))
        v.setOnClickPendingIntent(R.id.weather_root,WeatherActivity.pending(c,"details"));v.setOnClickPendingIntent(R.id.weather_bitmap,WeatherActivity.pending(c,"details"))
        v.setOnClickPendingIntent(R.id.weather_city,WeatherActivity.pending(c,"cities"));v.setOnClickPendingIntent(R.id.weather_forecast,WeatherActivity.pending(c,"forecast"))
        if(!small){
            v.setOnClickPendingIntent(R.id.weather_gps,action(c,"gps"));v.setOnClickPendingIntent(R.id.weather_refresh,action(c,"manual"))
        }
        return v
    }
    // Publish functional RemoteViews before starting Flutter, even if the launcher is offline.
    fun showFallback(c: Context, manager: AppWidgetManager, ids: IntArray, data: JSONObject? = null) {
        val record = data ?: run {
            val values = WeatherStore.prefs(c).all
            val name = values["city"] as? String
            val temp = (values["temperature"] as? Number)?.toDouble()
            val time = (values["weather_at"] as? Number)?.toLong()
            JSONObject().apply {
                if (!name.isNullOrBlank() && temp != null && temp.isFinite() && time != null && time > 0L) {
                    put("place", JSONObject().put("name", name))
                    put("current", JSONObject().put("temperature_2m", temp).put("time", time / 1000))
                }
                (values["timezone"] as? String)?.let { put("timezone", it) }
            }
        }
        for (id in ids) {
            try {
                val extents = sizes(manager.getAppWidgetOptions(id))
                val rendered = linkedMapOf<SizeF, RemoteViews>()
                for (e in extents) rendered[SizeF(e.w, e.h)] = views(c, e, null, record)
                manager.updateAppWidget(id, forLauncher(rendered))
            } catch (e: RuntimeException) {
                WeatherStore.report(c, "nativeWidget", e)
            }
        }
    }

    private fun forLauncher(rendered: LinkedHashMap<SizeF, RemoteViews>): RemoteViews =
        if (rendered.size == 1) rendered.values.first()
        else if (Build.VERSION.SDK_INT >= 31) RemoteViews(rendered)
        else RemoteViews(rendered.values.last(), rendered.values.first())

    suspend fun update(c:Context)=rendering.withLock {
        val m=AppWidgetManager.getInstance(c);val ids=m.getAppWidgetIds(ComponentName(c,NavKurdWidgetProvider::class.java))
        if(ids.isEmpty())return@withLock
        val place=WeatherStore.place(c)
        val data=place?.let { WeatherStore.cached(c,it,"widget") ?: WeatherStore.cached(c,it,"detail") ?: JSONObject().put("place",it.json()) } ?: JSONObject()
        if(WeatherStore.prefs(c).getBoolean("weather_offline",false))data.put("stale",true)
        val args=data.keys().asSequence().associateWith { bridge(data.opt(it)) }
        val p=WeatherStore.prefs(c);val d=c.resources.displayMetrics
        var renderer:Renderer?=null
        try{
            val active=start(c);renderer=active
            for(id in ids){
                val extents=sizes(m.getAppWidgetOptions(id));val rendered=linkedMapOf<SizeF,RemoteViews>()
                for(extent in extents){
                    val area=extent.w.toDouble()*extent.h
                    val cap=min(420000.0,max(16384.0,d.widthPixels.toDouble()*d.heightPixels*.95/extents.size))
                    val ratio=min(d.density.toDouble().coerceIn(1.0,3.0),sqrt(cap/area))
                    val bytes=active.png(extent,ratio,args)
                    val bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.size) ?: throw IllegalStateException("PNG decoding failed")
                    rendered[SizeF(extent.w,extent.h)]=views(c,extent,bitmap,data)
                }
                m.updateAppWidget(id, forLauncher(rendered))
            }
            p.edit().putLong("last_render_at",System.currentTimeMillis()).remove("last_render_error").apply()
        }catch(e:CancellationException){throw e}catch(e:Exception){
            p.edit().putString("last_render_error",e.javaClass.simpleName).apply();WeatherStore.report(c,"bitmap",e)
            showFallback(c, m, ids, data)
            throw e
        }finally{renderer?.let{r->withContext(NonCancellable+Dispatchers.Main.immediate){r.channel.setMethodCallHandler(null);r.engine.destroy()}}}
    }
}
