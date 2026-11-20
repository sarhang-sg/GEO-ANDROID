package com.navkurd.app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.PixelFormat
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.AtomicFile
import java.io.File
import android.util.SizeF
import android.widget.RemoteViews
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
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
    private class Renderer(val engine: FlutterEngine, val channel: MethodChannel, val surface: ImageReader) {
        fun close() {
            channel.setMethodCallHandler(null)
            surface.setOnImageAvailableListener(null, null)
            try {
                engine.renderer.stopRenderingToSurface()
            } finally {
                try { engine.destroy() } finally { surface.close() }
            }
        }
        suspend fun png(size:Extent,scale:Double,data:Map<String,Any?>):ByteArray {
            val outcome=CompletableDeferred<ByteArray>()
            return withContext(Dispatchers.Main.immediate){
                channel.invokeMethod("render",mapOf("width" to size.w.toDouble(),"height" to size.h.toDouble(),"ratio" to scale,"weather" to data),object:MethodChannel.Result{
                    override fun success(result:Any?) {if(result is ByteArray)outcome.complete(result) else outcome.completeExceptionally(IllegalStateException("invalid bitmap"))}
                    override fun error(code:String,message:String?,details:Any?){outcome.completeExceptionally(IllegalStateException("bitmap: $code ${message.orEmpty().take(160)}"))}
                    override fun notImplemented(){outcome.completeExceptionally(IllegalStateException("missing bitmap renderer"))}
                })
                withTimeoutOrNull(15000) { outcome.await() } ?: throw java.io.IOException("Widget bitmap timed out")
            }
        }
    }
    private suspend fun start(c:Context):Renderer = withContext(Dispatchers.Main.immediate){
        val loader=FlutterInjector.instance().flutterLoader()
        // Engine flags apply to the process. The worker binds the dedicated
        // weather process so the map can keep its hardware renderer.
        val args = arrayOf(FlutterShellArgs.ARG_DISABLE_IMPELLER)
        loader.startInitialization(c)
        loader.ensureInitializationComplete(c, args)
        val engine = FlutterEngine(c, args, false)
        val surface = try {
            if (Build.VERSION.SDK_INT >= 29) {
                ImageReader.newInstance(
                    8, 8, PixelFormat.RGBA_8888, 3,
                    HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT,
                )
            } else {
                ImageReader.newInstance(8, 8, PixelFormat.RGBA_8888, 3)
            }
        } catch (e: Throwable) {
            engine.destroy()
            throw e
        }
        val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "navkurd/weather_bitmap")
        val renderer = Renderer(engine, channel, surface)
        try{
            surface.setOnImageAvailableListener({ it.acquireLatestImage()?.close() }, Handler(Looper.getMainLooper()))
            engine.renderer.startRenderingToSurface(surface.surface, false)
            engine.renderer.surfaceChanged(8, 8)
            val ready=CompletableDeferred<Unit>()
            channel.setMethodCallHandler { call,result -> if(call.method=="ready"){result.success(null);ready.complete(Unit)}else result.notImplemented() }
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(),"weatherBitmapMain"))
            withTimeoutOrNull(25000) { ready.await() } ?: throw java.io.IOException("Widget engine did not become ready")
            renderer
        }catch(e:Throwable){renderer.close();throw e}
    }
    private fun bridge(value:Any?):Any?=when(value){
        null,JSONObject.NULL->null
        is JSONObject->value.keys().asSequence().associateWith { bridge(value.opt(it)) }
        is JSONArray->(0 until value.length()).map { bridge(value.opt(it)) }
        else->value
    }
    private fun action(c:Context,name:String)=PendingIntent.getBroadcast(c,name.hashCode(),Intent(c,WeatherWidgetAction::class.java).setAction("com.navkurd.app.weather.$name"),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    private fun views(context:Context,s:Extent,bitmap:Bitmap?,data:JSONObject):RemoteViews{
        val language = data.optString("language", "ku")
        val configuration = android.content.res.Configuration(context.resources.configuration)
        configuration.setLocale(java.util.Locale.forLanguageTag(if(language=="ku") "ckb" else language))
        val c = context.createConfigurationContext(configuration)
        val small=s.w<200 || s.h<58
        val v=RemoteViews(c.packageName,if(small)R.layout.weather_small else R.layout.weather_dashboard)
        val name = data.optJSONObject("place")?.optString("name").orEmpty()
        val current = data.optJSONObject("current")
        val temp = current?.optDouble("temperature_2m")?.takeIf { it.isFinite() }?.roundToInt()
        val city = name.ifBlank { c.getString(R.string.weather_pick_city) }
        val stamp = current?.optLong("time") ?: 0L
        val clock = java.text.SimpleDateFormat("HH:mm",java.util.Locale.forLanguageTag(if(language=="ku") "ckb" else language))
        if (data.optString("timezone").isNotBlank())
            clock.timeZone = java.util.TimeZone.getTimeZone(data.getString("timezone"))
        val last = if (stamp > 0L && temp != null) c.getString(R.string.weather_last_reading, clock.format(java.util.Date(stamp * 1000L))) else ""
        val forecast = if (temp == null) c.getString(R.string.weather_open_forecast)
            else listOf("${temp}°C", last).filter { it.isNotEmpty() }.joinToString(if (small) " · " else "\n")
        v.setImageViewBitmap(R.id.weather_bitmap, bitmap)
        val waiting = when (language) {
            "ar" -> "جارٍ الاتصال..."
            "en" -> "Connecting..."
            else -> c.getString(R.string.weather_syncing)
        }
        v.setTextViewText(R.id.weather_pending, waiting)
        v.setViewVisibility(R.id.weather_pending, if (bitmap == null) android.view.View.VISIBLE else android.view.View.GONE)
        // RemoteViews supplies accessible hit targets. All visible forecast content comes from Flutter.
        v.setTextViewText(R.id.weather_city, "")
        v.setTextViewText(R.id.weather_forecast, "")
        v.setContentDescription(R.id.weather_city, city)
        v.setContentDescription(R.id.weather_forecast, forecast)
        if (!small) {
            v.setTextViewText(R.id.weather_gps, "")
            v.setTextViewText(R.id.weather_refresh, "")
            v.setContentDescription(R.id.weather_gps, c.getString(R.string.weather_gps))
            v.setContentDescription(R.id.weather_refresh, c.getString(R.string.weather_refresh))
        }
        v.setContentDescription(R.id.weather_bitmap, listOf(city, forecast, "Open-Meteo · Developer: Sarhang Salah").joinToString(" · "))
        v.setOnClickPendingIntent(R.id.weather_root,WeatherActivity.pending(c,"details"));v.setOnClickPendingIntent(R.id.weather_bitmap,WeatherActivity.pending(c,"details"))
        v.setOnClickPendingIntent(R.id.weather_city,WeatherActivity.pending(c,"cities"));v.setOnClickPendingIntent(R.id.weather_forecast,WeatherActivity.pending(c,"forecast"))
        if(!small){
            v.setOnClickPendingIntent(R.id.weather_gps,action(c,"gps"));v.setOnClickPendingIntent(R.id.weather_refresh,action(c,"manual"))
        }
        return v
    }
    // The isolated renderer can finish after the owner has selected another city.
    private fun revisionFile(c: Context) = AtomicFile(File(c.filesDir,"weather-widget-source"))
    fun invalidateSource(c: Context) {
        val file=revisionFile(c)
        val out=file.startWrite()
        try { out.write(java.util.UUID.randomUUID().toString().toByteArray());file.finishWrite(out) }
        catch(e:Exception){file.failWrite(out);throw e}
    }
    private fun sourceRevision(c:Context) = runCatching { revisionFile(c).readFully().decodeToString() }.getOrDefault("")
    private fun bitmapFile(c:Context, id:Int, extent:Extent, language:String, placeKey:String) =
        AtomicFile(File(c.cacheDir,"weather-widget-$id-$language-$placeKey-${extent.w.toInt()}x${extent.h.toInt()}.png"))

    fun restore(c:Context, manager:AppWidgetManager, ids:IntArray) {
        val language=WeatherStore.prefs(c).getString("language","ku") ?: "ku"
        val place=WeatherStore.place(c)
        val key=place?.key ?: "pending"
        val reading=place?.let { WeatherStore.cached(c,it,"widget") ?: JSONObject().put("place",it.json()) } ?: JSONObject()
        reading.put("language",language)
        for (id in ids) {
            val extents = sizes(manager.getAppWidgetOptions(id))
            val previous = c.cacheDir.listFiles { f -> f.name.startsWith("weather-widget-$id-$language-$key-") && f.name.endsWith(".png") }
                ?.maxByOrNull { it.lastModified() }
            runCatching {
                val rendered = linkedMapOf<SizeF,RemoteViews>()
                for (extent in extents) {
                    val exact = bitmapFile(c,id,extent,language,key).baseFile
                    val saved = exact.takeIf { it.isFile } ?: previous
                    val bitmap = saved?.let { BitmapFactory.decodeFile(it.path) }
                    rendered[SizeF(extent.w,extent.h)] = views(c,extent,bitmap,reading)
                }
                if (rendered.isNotEmpty()) manager.updateAppWidget(id,forLauncher(rendered))
            }.onFailure { WeatherStore.report(c,"restoreBitmap",it) }
        }
    }
    fun discard(c:Context, ids:IntArray) {
        ids.forEach { id -> c.cacheDir.listFiles { f -> f.name.startsWith("weather-widget-$id-") }?.forEach { it.delete() } }
    }

    private fun forLauncher(rendered: LinkedHashMap<SizeF, RemoteViews>): RemoteViews =
        if (rendered.size == 1) rendered.values.first()
        else if (Build.VERSION.SDK_INT >= 31) RemoteViews(rendered)
        else RemoteViews(rendered.values.last(), rendered.values.first())

    suspend fun update(c:Context)=rendering.withLock {
        val m=AppWidgetManager.getInstance(c);val ids=m.getAppWidgetIds(ComponentName(c,NavKurdWidgetProvider::class.java))
        if(ids.isEmpty())return@withLock
        val revision=sourceRevision(c)
        val place=WeatherStore.place(c)
        val data=place?.let { WeatherStore.cached(c,it,"widget") ?: WeatherStore.cached(c,it,"detail") ?: JSONObject().put("place",it.json()) } ?: JSONObject()
        if(WeatherStore.prefs(c).getBoolean("weather_offline",false))data.put("stale",true)
        val p = WeatherStore.prefs(c)
        try {
            data.put("language",p.getString("language","ku")).put("widgetSourceRevision",revision)
            WeatherRenderService.publish(c, data)
            p.edit().putLong("last_render_at", System.currentTimeMillis()).remove("last_render_error").apply()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            p.edit().putString("last_render_error", e.javaClass.simpleName).apply()
            WeatherStore.report(c, "bitmap", e)
            restore(c, m, ids)
            throw e
        }
    }

    // Runs in :weather_render. Only the owning app process reads or writes preferences.
    suspend fun publishBitmaps(c: Context, data: JSONObject) = rendering.withLock {
        val m = AppWidgetManager.getInstance(c)
        val ids = m.getAppWidgetIds(ComponentName(c, NavKurdWidgetProvider::class.java))
        if (ids.isEmpty()) return@withLock
        val revision=data.optString("widgetSourceRevision")
        val key=WeatherPlace.from(data.optJSONObject("place"))?.key ?: "pending"
        if (revision!=sourceRevision(c)) return@withLock
        val args = data.keys().asSequence().associateWith { bridge(data.opt(it)) }
        val d = c.resources.displayMetrics
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
                    val file = bitmapFile(c,id,extent,data.optString("language","ku"),key)
                    val stream = file.startWrite()
                    try { stream.write(bytes); file.finishWrite(stream) }
                    catch (e:Exception) { file.failWrite(stream); throw e }
                    rendered[SizeF(extent.w,extent.h)]=views(c,extent,bitmap,data)
                }
                if (revision!=sourceRevision(c)) return@withLock
                m.updateAppWidget(id, forLauncher(rendered))
                val retained = extents.map { bitmapFile(c,id,it,data.optString("language","ku"),key).baseFile.name }.toSet()
                c.cacheDir.listFiles { f -> f.name.startsWith("weather-widget-$id-") && f.name.endsWith(".png") && f.name !in retained }?.forEach { it.delete() }
            }
        } finally {
            renderer?.let { r -> withContext(NonCancellable + Dispatchers.Main.immediate) { r.close() } }
        }
    }
}
