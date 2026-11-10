package com.navkurd.smoke;

import android.app.Activity;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetHostView;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Context;
import android.content.SharedPreferences;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.drawable.BitmapDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.util.Log;
import android.view.View;
import android.widget.ImageView;

public final class WidgetHost extends Activity {
    private final Handler main = new Handler(Looper.getMainLooper());
    private AppWidgetHost host;
    private AppWidgetHostView view;
    private int imageId;
    private int forecastId;
    private long deadline;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        String target = getIntent().getStringExtra("target");
        if (!"com.navkurd.app".equals(target) && !"com.navkurd.app.debug".equals(target)) {
            throw new IllegalArgumentException("Unknown smoke target");
        }
        ComponentName component = new ComponentName(target, "com.navkurd.app.NavKurdWidgetProvider");
        AppWidgetManager manager = AppWidgetManager.getInstance(this);
        host = new AppWidgetHost(this, 41);
        SharedPreferences records = getSharedPreferences("widgets", MODE_PRIVATE);
        boolean reuse = getIntent().getBooleanExtra("reuse", false);
        int id = reuse ? records.getInt(target, -1) : host.allocateAppWidgetId();
        Bundle options = new Bundle();
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 300);
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 300);
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 160);
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 160);
        if (!reuse && !manager.bindAppWidgetIdIfAllowed(id, component, options)) {
            throw new IllegalStateException("Launcher did not bind the target widget");
        }
        AppWidgetProviderInfo info = manager.getAppWidgetInfo(id);
        if (info == null || !component.equals(info.provider)) {
            throw new IllegalStateException("Lost launcher widget on update");
        }
        if (getIntent().getBooleanExtra("initial", false)) {
            if (!records.edit().putInt(target, id).commit()) throw new IllegalStateException("Cannot retain widget ID");
            setContentView(host.createView(this, id, info));
            Log.i("NavKurdSmoke", "previous-widget-bound " + id);
            return;
        }
        try {
            Context remote = createPackageContext(target, 0);
            Resources resources = remote.getResources();
            imageId = resources.getIdentifier("weather_bitmap", "id", target);
            forecastId = resources.getIdentifier("weather_forecast", "id", target);
        } catch (android.content.pm.PackageManager.NameNotFoundException e) {
            throw new IllegalStateException(e);
        }
        if (imageId == 0 || forecastId == 0) throw new IllegalStateException("Missing release widget views");
        view = host.createView(this, id, info);
        int pxW = Math.round(300 * getResources().getDisplayMetrics().density);
        int pxH = Math.round(160 * getResources().getDisplayMetrics().density);
        setContentView(view, new android.view.ViewGroup.LayoutParams(pxW, pxH));
        deadline = SystemClock.uptimeMillis() + 120_000;
        main.postDelayed(this::check, 500);
    }

    @Override protected void onStart() { super.onStart(); host.startListening(); }
    @Override protected void onStop() { host.stopListening(); super.onStop(); }
    @Override protected void onDestroy() { main.removeCallbacksAndMessages(null); super.onDestroy(); }

    private void check() {
        ImageView image = view.findViewById(imageId);
        if (image != null && image.getDrawable() instanceof BitmapDrawable) {
            Bitmap b = ((BitmapDrawable) image.getDrawable()).getBitmap();
            if (b != null && b.getWidth() >= 100 && b.getHeight() >= 48) {
                View forecast = view.findViewById(forecastId);
                if (forecast == null || !forecast.isClickable()) throw new IllegalStateException("Inactive forecast tap");
                Log.i("NavKurdSmoke", "widget-bitmap-ready " + b.getWidth() + "x" + b.getHeight());
                return;
            }
        }
        if (SystemClock.uptimeMillis() < deadline) main.postDelayed(this::check, 500);
        else Log.e("NavKurdSmoke", "widget-bitmap-timeout");
    }
}
