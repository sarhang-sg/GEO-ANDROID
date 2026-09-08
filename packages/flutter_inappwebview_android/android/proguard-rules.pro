# Modified by NAV KURD to correct the upstream WebView method signature.
# WebView
-keepattributes *JavascriptInterface*
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
    public void *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class com.pichillilorenzo.flutter_inappwebview_android$JavaScriptBridgeInterface {
     <fields>;
     <methods>;
     public *;
     private *;
}
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }

-dontwarn android.window.BackEvent
