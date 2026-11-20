package com.navkurd.app;

import android.app.Activity;
import android.app.Instrumentation;
import android.content.Context;
import android.content.SharedPreferences;
import android.location.Location;
import android.os.Bundle;

/** Exercises the shipped preference resolver on the disposable debug emulator. */
public final class WidgetLocationCheck extends Instrumentation {
    @Override public void onCreate(Bundle arguments) {
        super.onCreate(arguments);
        start();
    }

    private static Location fix(double latitude, double longitude, long timestamp) {
        Location location = new Location("gps");
        location.setLatitude(latitude);
        location.setLongitude(longitude);
        location.setAccuracy(8);
        location.setTime(timestamp);
        return location;
    }

    private static void samePlace(WeatherPlace place, double lat, double lon) {
        if (place == null || Math.abs(place.getLat() - lat) > .00001 || Math.abs(place.getLon() - lon) > .00001)
            throw new AssertionError("Unexpected widget coordinates");
    }

    @Override public void onStart() {
        Context context = getTargetContext();
        WeatherStore store = WeatherStore.INSTANCE;
        SharedPreferences prefs = store.prefs(context);
        Bundle outcome = new Bundle();
        int status = Activity.RESULT_CANCELED;
        try {
            long now = System.currentTimeMillis();
            WeatherPlace city = new WeatherPlace(35.52,45.43,"Sulaymaniyah",null);
            // Reproduce the old version after browsing a city and disabling GPS.
            prefs.edit().remove("weather_widget_pinned_city").remove("location_at")
                .putBoolean("weather_prefer_gps",false)
                .putString("weather_selected_city",city.json().toString()).commit();
            store.recordFix(context,fix(36.30,44.87,now-3000));
            samePlace(store.place(context,false),36.30,44.87);
            store.setWidgetCity(context,city);
            store.recordFix(context,fix(36.34,44.92,now-1000));
            samePlace(store.place(context,true),35.52,45.43);
            if (store.recordFix(context,fix(36.33,44.91,now-2000)))
                throw new AssertionError("Stale fix replaced a newer device position");
            store.setWidgetCity(context,null);
            samePlace(store.place(context,true),36.34,44.92);
            outcome.putString("widgetLocation","PASS legacy browsing, GPS off, explicit pin, stale fix and automatic GPS");
            status = Activity.RESULT_OK;
        } catch (Throwable error) {
            outcome.putString("failure",error.toString());
        }
        finish(status,outcome);
    }
}
