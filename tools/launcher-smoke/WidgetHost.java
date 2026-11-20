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
import android.util.SizeF;
import android.graphics.Matrix;
import android.widget.FrameLayout;
import java.util.ArrayList;
import android.view.View;
import android.widget.ImageView;

public final class WidgetHost extends Activity {
    private final Handler main = new Handler(Looper.getMainLooper());
    private AppWidgetHost host;
    private AppWidgetHostView view;
    private int imageId;
    private int forecastId;
    private long deadline;
    private int width, height, gpsId, refreshId;
    private String marker;

    private static Bundle options(int w, int h, boolean exact) {
        Bundle options = new Bundle();
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, w);
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, exact ? w : w + 48);
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, exact ? h : Math.max(32, h - 30));
        options.putInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, h);
        ArrayList<SizeF> sizes = new ArrayList<>();
        if (exact) {
            sizes.add(new SizeF(w, h));
            if (w != h) sizes.add(new SizeF(h, w));
        }
        options.putParcelableArrayList(AppWidgetManager.OPTION_APPWIDGET_SIZES, sizes);
        return options;
    }

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
        width = getIntent().getIntExtra("width", 300);
        height = getIntent().getIntExtra("height", 160);
        marker = getIntent().getStringExtra("marker");
        if (marker == null) marker = "widget-bitmap-ready";
        boolean exact = getIntent().getBooleanExtra("exact", false);
        Bundle options = options(width, height, exact);
        if (!reuse && !manager.bindAppWidgetIdIfAllowed(id, component, options)) {
            throw new IllegalStateException("Launcher did not bind the target widget");
        }
        AppWidgetProviderInfo info = manager.getAppWidgetInfo(id);
        if (info == null || !component.equals(info.provider)) {
            throw new IllegalStateException("Lost launcher widget on update");
        }
        if (!records.edit().putInt(target, id).commit()) throw new IllegalStateException("Cannot retain widget ID");
        if (getIntent().getBooleanExtra("initial", false)) {
            setContentView(host.createView(this, id, info));
            Log.i("NavKurdSmoke", "previous-widget-bound " + id);
            return;
        }
        try {
            Context remote = createPackageContext(target, 0);
            Resources resources = remote.getResources();
            imageId = resources.getIdentifier("weather_bitmap", "id", target);
            forecastId = resources.getIdentifier("weather_forecast", "id", target);
            gpsId = resources.getIdentifier("weather_gps", "id", target);
            refreshId = resources.getIdentifier("weather_refresh", "id", target);
        } catch (android.content.pm.PackageManager.NameNotFoundException e) {
            throw new IllegalStateException(e);
        }
        if (imageId == 0 || forecastId == 0) throw new IllegalStateException("Missing release widget views");
        view = host.createView(this, id, info);
        view.setPadding(0, 0, 0, 0);
        float density = getResources().getDisplayMetrics().density;
        FrameLayout launcher = new FrameLayout(this);
        launcher.addView(view, new FrameLayout.LayoutParams(Math.round(width*density), Math.round(height*density)));
        setContentView(launcher);
        if (getIntent().getBooleanExtra("burst", false)) {
            manager.updateAppWidgetOptions(id, options(136, 258, true));
            manager.updateAppWidgetOptions(id, options(52, 442, true));
        }
        manager.updateAppWidgetOptions(id, options);
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
            if (b != null && Math.abs(b.getWidth() - b.getHeight() * (double) width / height)
                    <= 1.1 + (double) width / height && image.getWidth() > 0) {
                float[] matrix = new float[9];
                image.getImageMatrix().getValues(matrix);
                if (image.getScaleType() != ImageView.ScaleType.FIT_CENTER ||
                        Math.abs(matrix[Matrix.MSCALE_X] - matrix[Matrix.MSCALE_Y]) > .001f)
                    throw new IllegalStateException("Distorted launcher bitmap " + marker);
                boolean stacked = width < 92 && height >= 245;
                boolean actions = stacked || (width >= 92 && (height >= 145 || (width >= 200 && height >= 64)));
                View gps = view.findViewById(gpsId), refresh = view.findViewById(refreshId);
                if (gps == null || refresh == null || gps.isShown() != actions || refresh.isShown() != actions)
                    throw new IllegalStateException("Incorrect visible widget controls " + marker);
                if (actions) {
                    int[] first = new int[2], second = new int[2];
                    gps.getLocationOnScreen(first);
                    refresh.getLocationOnScreen(second);
                    if (!gps.isClickable() || !refresh.isClickable() || (stacked ?
                        second[1] < first[1] + gps.getHeight() : second[0] < first[0] + gps.getWidth()))
                        throw new IllegalStateException("Overlapping action targets " + marker);
                }
                View forecast = view.findViewById(forecastId);
                if (forecast == null || !forecast.isClickable()) throw new IllegalStateException("Inactive forecast tap");
                CharSequence reading = forecast.getContentDescription();
                if (reading != null && reading.toString().contains("°C")) {
                    Log.i("NavKurdSmoke", marker + " " + width + "x" + height + "dp, bitmap " + b.getWidth() + "x" + b.getHeight());
                    return;
                }
            }
        }
        if (SystemClock.uptimeMillis() < deadline) main.postDelayed(this::check, 500);
        else Log.e("NavKurdSmoke", "widget-bitmap-timeout");
    }
}
