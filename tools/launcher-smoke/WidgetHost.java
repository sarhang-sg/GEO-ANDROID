package com.navkurd.smoke;

import android.app.Activity;
import android.appwidget.AppWidgetHost;
import android.appwidget.AppWidgetHostView;
import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProviderInfo;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.Resources;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
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
    private int widgetId;
    private int imageId, skyId;
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
        widgetId = id;
        if (!reuse && !manager.bindAppWidgetIdIfAllowed(id, component, optionsFor(getIntent()))) {
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
            skyId = resources.getIdentifier("weather_sky", "id", target);
            forecastId = resources.getIdentifier("weather_forecast", "id", target);
            gpsId = resources.getIdentifier("weather_gps", "id", target);
            refreshId = resources.getIdentifier("weather_refresh", "id", target);
        } catch (android.content.pm.PackageManager.NameNotFoundException e) {
            throw new IllegalStateException(e);
        }
        if (imageId == 0 || forecastId == 0) throw new IllegalStateException("Missing release widget views");
        view = host.createView(this, id, info);
        view.setPadding(0, 0, 0, 0);
        FrameLayout launcher = new FrameLayout(this);
        launcher.addView(view);
        setContentView(launcher);
        resize(getIntent());
    }

    @Override protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        if (view == null || !getIntent().getStringExtra("target").equals(intent.getStringExtra("target")))
            throw new IllegalStateException("Cannot resize a different widget");
        setIntent(intent);
        resize(intent);
    }

    private static Bundle optionsFor(Intent intent) {
        return options(intent.getIntExtra("width", 300), intent.getIntExtra("height", 160),
                intent.getBooleanExtra("exact", false));
    }

    private void resize(Intent intent) {
        main.removeCallbacksAndMessages(null);
        width = intent.getIntExtra("width", 300);
        height = intent.getIntExtra("height", 160);
        marker = intent.getStringExtra("marker");
        if (marker == null) marker = "widget-bitmap-ready";
        float density = getResources().getDisplayMetrics().density;
        // Some launchers report grid dimensions before applying their padding.
        int hostWidth = intent.getIntExtra("hostWidth", width);
        int hostHeight = intent.getIntExtra("hostHeight", height);
        view.setLayoutParams(new FrameLayout.LayoutParams(Math.round(hostWidth*density), Math.round(hostHeight*density)));
        AppWidgetManager manager = AppWidgetManager.getInstance(this);
        if (intent.getBooleanExtra("burst", false)) {
            manager.updateAppWidgetOptions(widgetId, options(136, 258, true));
            manager.updateAppWidgetOptions(widgetId, options(52, 442, true));
        }
        manager.updateAppWidgetOptions(widgetId, optionsFor(intent));
        deadline = SystemClock.uptimeMillis() + 120_000;
        main.postDelayed(this::check, 500);
    }

    @Override protected void onStart() { super.onStart(); host.startListening(); }
    @Override protected void onStop() { host.stopListening(); super.onStop(); }
    @Override protected void onDestroy() { main.removeCallbacksAndMessages(null); super.onDestroy(); }

    private void check() {
        ImageView image = view.findViewById(imageId);
        ImageView sky = view.findViewById(skyId);
        if (image != null && image.getDrawable() instanceof BitmapDrawable &&
                sky != null && sky.getDrawable() instanceof BitmapDrawable) {
            Bitmap b = ((BitmapDrawable) image.getDrawable()).getBitmap();
            if (b != null && Math.abs(b.getWidth() - b.getHeight() * (double) width / height)
                    <= 1.1 + (double) width / height && image.getWidth() > 0) {
                float[] matrix = new float[9];
                image.getImageMatrix().getValues(matrix);
                if (image.getScaleType() != ImageView.ScaleType.FIT_CENTER ||
                        Math.abs(matrix[Matrix.MSCALE_X] - matrix[Matrix.MSCALE_Y]) > .001f)
                    throw new IllegalStateException("Distorted launcher bitmap " + marker);
                checkSky(sky, image);
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

    private void checkSky(ImageView sky, ImageView forecast) {
        if (sky.getScaleType() != ImageView.ScaleType.CENTER_CROP ||
                sky.getWidth() != forecast.getWidth() || sky.getHeight() != forecast.getHeight())
            throw new IllegalStateException("Missing full-size launcher sky " + marker);
        int w = sky.getWidth(), h = sky.getHeight();
        Bitmap card = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        Bitmap backdrop = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888);
        try {
            sky.draw(new Canvas(backdrop));
            view.draw(new Canvas(card));
            for (int[] p : new int[][]{{2,h/2},{w-3,h/2},{w/2,2},{w/2,h-3}}) {
                int actual = card.getPixel(p[0],p[1]), expected = backdrop.getPixel(p[0],p[1]);
                if (Color.alpha(actual) < 250 || Color.alpha(expected) < 250 ||
                        Math.abs(Color.red(actual) - Color.red(expected)) > 5 ||
                        Math.abs(Color.green(actual) - Color.green(expected)) > 5 ||
                        Math.abs(Color.blue(actual) - Color.blue(expected)) > 5)
                    throw new IllegalStateException("Exposed launcher border at " + p[0] + "," + p[1] + " " + marker);
            }
        } finally {
            card.recycle();
            backdrop.recycle();
        }
    }
}
