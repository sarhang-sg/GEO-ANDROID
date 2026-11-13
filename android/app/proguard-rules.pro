-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-dontwarn org.chromium.**
-dontwarn com.google.android.play.core.**

# Room derives this name from WorkDatabase and constructs it through reflection.
-keepnames class androidx.work.impl.WorkDatabase
-keep class androidx.work.impl.WorkDatabase_Impl {
    <init>();
}

# WorkManager persists the worker name and instantiates it after process restart.
-keep class com.navkurd.app.WeatherWork {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
