#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  echo "SOURCE CHECK FAILED: $*" >&2
  exit 1
}

test "$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)" = "9.0.0+90000" \
  || fail "pubspec version is not 9.0.0+90000"
grep -F "defaultValue: '9.0.0'" lib/src/app_config.dart >/dev/null \
  || fail "Dart app version is not 9.0.0"
grep -F 'compileSdk = 36' android/app/build.gradle.kts >/dev/null \
  || fail "compileSdk must be 36"
grep -F 'targetSdk = 36' android/app/build.gradle.kts >/dev/null \
  || fail "targetSdk must be 36"
grep -F 'version "9.2.1"' android/settings.gradle.kts >/dev/null \
  || fail "Android Gradle Plugin must be 9.2.1"
grep -F 'gradle-9.4.1-all.zip' android/gradle/wrapper/gradle-wrapper.properties >/dev/null \
  || fail "Gradle wrapper must be 9.4.1"
grep -F '@drawable/ic_splash_transparent' android/app/src/main/res/values-v31/styles.xml >/dev/null \
  || fail "Android 12 splash icon must be transparent"
if grep -F '_LaunchPanel' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "duplicate Flutter launch panel still exists"
fi
grep -F 'WindowInsetsCompat.Type.systemBars()' \
  android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt >/dev/null \
  || fail "native immersive mode is missing"
grep -F '"pickImage" -> launchImagePicker(result)' \
  android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt >/dev/null \
  || fail "native image picker bridge is missing"
grep -F '"shareText" -> result.success(shareText(call))' \
  android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt >/dev/null \
  || fail "native Android share bridge is missing"
grep -F 'onShowFileChooser: _handleFileChooser' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "WebView image chooser integration is missing"
grep -F "handlerName: 'nativeShare'" lib/src/nav_kurd_page.dart >/dev/null \
  || fail "WebView native share integration is missing"
grep -F 'InAppWebViewController.clearAllCache()' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "WebView cache cleanup does not use the current static API"
grep -F 'useHybridComposition: true' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "satellite rendering does not use Android hybrid composition"
grep -F 'hardwareAcceleration: true' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "satellite rendering is not hardware accelerated"
grep -F 'algorithmicDarkeningAllowed: false' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "Android may still darken satellite raster tiles"
if grep -F 'forceDark:' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "deprecated WebView forceDark setting breaks fatal-info analysis"
fi
grep -F 'offscreenPreRaster: true' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "satellite tiles are not pre-rasterized offscreen"
grep -F 'android:hardwareAccelerated="true"' \
  android/app/src/main/AndroidManifest.xml >/dev/null \
  || fail "Android application hardware acceleration is disabled"
if grep -E '(controller\.platform\.clearAllCache|\.clearCache\()' \
    lib/src/nav_kurd_page.dart >/dev/null; then
  fail "deprecated WebView cache API is still present"
fi
grep -F 'Map<Object?, Object?>' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "native language payload is not statically typed"
if grep -R -F 'share_plus' pubspec.yaml lib test >/dev/null 2>&1; then
  fail "obsolete share_plus dependency or source reference is still present"
fi
grep -F '[META] Native Android diagnostics' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdDiagnostics.kt >/dev/null \
  || fail "native diagnostics are missing"
grep -F 'api.open-meteo.com' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt >/dev/null \
  || fail "real widget weather source is missing"
grep -F 'is_day' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt >/dev/null \
  || fail "widget day/night phase is missing"
grep -F 'air-quality-api.open-meteo.com' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt >/dev/null \
  || fail "widget dust weather source is missing"
grep -F 'NavKurdWidgetArtwork.scene' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt >/dev/null \
  || fail "state-driven widget artwork is missing"
grep -F 'R.id.widget_dust_group' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt >/dev/null \
  || fail "widget metric-group visibility is not synchronized"
grep -F '@font/uniqaidar_money_heist_002' android/app/src/main/res/layout/nav_kurd_widget.xml >/dev/null \
  || fail "Kurdish/Arabic widget does not use UniQAIDAR Money Heist 002"
grep -F '@font/red_hat_display_variable' android/app/src/main/res/layout/nav_kurd_widget_en.xml >/dev/null \
  || fail "English widget does not use Red Hat Display Variable"
test -s android/app/src/main/res/font/uniqaidar_money_heist_002.ttf \
  || fail "Kurdish/Arabic widget font asset is missing"
test -s android/app/src/main/res/font/red_hat_display_variable.ttf \
  || fail "English widget font asset is missing"
if grep -R -E 'widget_season_icon|seasonIcon\(' \
    android/app/src/main/res/layout \
    android/app/src/main/kotlin/com/navkurd/app >/dev/null; then
  fail "widget still renders a duplicate seasonal sun/moon symbol"
fi
for widget_layout in \
  android/app/src/main/res/layout/nav_kurd_widget.xml \
  android/app/src/main/res/layout/nav_kurd_widget_en.xml; do
  test "$(grep -c '@+id/widget_weather_icon' "$widget_layout")" = "1" \
    || fail "$widget_layout must contain exactly one primary weather symbol"
done
grep -F 'androidx.core.content.FileProvider' android/app/src/main/AndroidManifest.xml >/dev/null \
  || fail "secure native image-picker provider is missing"
grep -F 'FileProvider.getUriForFile' android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt >/dev/null \
  || fail "image picker still lacks a secure content URI"
grep -F 'android:allowBackup="false"' android/app/src/main/AndroidManifest.xml >/dev/null \
  || fail "backup/clone hardening is missing"
grep -F 'nativeRuntimeInfo' lib/src/nav_kurd_page.dart >/dev/null \
  || fail "real Android hardware bridge is missing"
grep -F 'RELEASE_URL' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdNotificationReceiver.kt >/dev/null \
  || fail "native release update check is missing"
grep -F 'ACTION_DAILY_WEATHER' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdNotificationScheduler.kt >/dev/null \
  || fail "daily weather notification schedule is missing"
if find android/app/src/main lib -type f \( -name '*.kt' -o -name '*.dart' -o -name '*.xml' \) -print0 | \
  xargs -0 grep -Pn '[\x{1F300}-\x{1FAFF}]' >/dev/null; then
  fail "emoji found in Android widget or Flutter source"
fi
grep -F '<TextClock' android/app/src/main/res/layout/nav_kurd_widget.xml >/dev/null \
  || fail "location-time TextClock is missing"
if grep -Eq '<[[:space:]]*View([[:space:]>])' \
  android/app/src/main/res/layout/nav_kurd_widget.xml; then
  fail "widget layout contains android.view.View, which RemoteViews cannot inflate"
fi
grep -F '<FrameLayout' android/app/src/main/res/layout/nav_kurd_widget.xml >/dev/null \
  || fail "RemoteViews-safe widget divider is missing"
grep -F 'KEY_LAST_RENDER_ERROR' \
  android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt >/dev/null \
  || fail "widget render diagnostics are missing"
grep -F 'level == ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW' \
  android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt >/dev/null \
  || fail "real memory-pressure classification is missing"
grep -F "Unrecognized feature: 'usb'" lib/src/nav_kurd_page.dart >/dev/null \
  || fail "known harmless WebView Permissions-Policy filter is missing"
grep -F "host == 'auth'" lib/src/url_policy.dart >/dev/null \
  || fail "Android OAuth callback routing is missing"
grep -F "_oauthCallbackKeys" lib/src/url_policy.dart >/dev/null \
  || fail "OAuth callback query allow-list is missing"
grep -F "access_token" test/url_policy_test.dart >/dev/null \
  || fail "OAuth token rejection test is missing"
if grep -F "import 'dart:ui';" lib/main.dart >/dev/null; then
  fail "lib/main.dart contains a redundant dart:ui import"
fi
if grep -R -F '<String, ?>' lib test >/dev/null; then
  fail "invalid wildcard map type found in Dart source"
fi
grep -F 'Keystore signing SHA-256' .github/workflows/android-release.yml >/dev/null \
  || fail "workflow does not report the reconstructed keystore identity"
grep -F 'Actual APK SHA-256' .github/workflows/android-release.yml >/dev/null \
  || fail "workflow does not report the signed APK identity"
grep -F "awk '/certificate SHA-256 digest:/" .github/workflows/android-release.yml >/dev/null \
  || fail "workflow does not parse current apksigner certificate output"
grep -F 'CERTIFICATE_SHA256.txt' .github/workflows/android-release.yml >/dev/null \
  || fail "workflow does not preserve the verified APK certificate record"
grep -F -- '--dart-define=NAV_KURD_APP_URL=https://geo-map-kappa.vercel.app' \
  .github/workflows/android-release.yml >/dev/null \
  || fail "release workflow does not build the canonical production origin"
if grep -R -F --exclude='validate-source.sh' 'geo-map-two.vercel.app' \
    .github android lib test tools NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh \
    >/dev/null 2>&1; then
  fail "obsolete geo-map-two production origin is still present"
fi
grep -F 'Refusing to upload a signing key with the wrong Android identity.' \
  TERMUX.sh >/dev/null \
  || fail "Termux signing-secret upload is not fingerprint-gated"
grep -F 'readonly repo_name="sarhang-sg/GEO-ANDROID"' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not target the final private Android repository"
grep -F 'gh repo create "$repo_name"' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater cannot create the fresh private Android repository"
grep -F 'FAILURE ANNOTATIONS' NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not preserve fallback workflow diagnostics"
grep -F 'Verified APK certificate record was not found.' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not verify the workflow certificate record"
grep -F 'readonly web_repo_name="sarhang-sg/GEO-MAP"' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not target the canonical private Web repository"
if grep -E 'WEB_UPDATE_(PATHS|MANIFEST)|source_root/web-update' \
    NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null; then
  fail "Android publisher can still overwrite the completed Web source"
fi
grep -F 'Preparing the signed direct-download update on current Web main' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Android publisher does not preserve the completed Web main"
grep -F 'public/downloads/NAV-KURD-9.0.0.apk' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Android publisher does not install the verified direct APK"
grep -F 'Waiting for Web quality and Chromium checks' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not gate the Web deployment on quality checks"
if grep -F 'APK v1 certificate block was not found.' \
  NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh >/dev/null; then
  fail "Termux updater still assumes obsolete APK v1 signing"
fi

for forbidden in \
  android.permission.MANAGE_EXTERNAL_STORAGE \
  android.permission.ACCESS_BACKGROUND_LOCATION \
  android.permission.READ_CONTACTS \
  android.permission.RECORD_AUDIO; do
  if grep -F "$forbidden" android/app/src/main/AndroidManifest.xml >/dev/null; then
    fail "unnecessary high-risk permission found: $forbidden"
  fi
done

while IFS= read -r script; do
  bash -n "$script"
done < <(find . -path './.git' -prune -o -type f -name '*.sh' -print)

if command -v node >/dev/null 2>&1; then
  sed -n "/^const String _documentStartBridgeScript = r'''/,/^''';/p" \
    lib/src/nav_kurd_page.dart | sed '1d;$d' | node --check -
  sed -n "/^const String _afterLoadBridgeScript = r'''/,/^''';/p" \
    lib/src/nav_kurd_page.dart | sed '1d;$d' | node --check -
fi

echo "NAV KURD 9.0.0 source checks passed."
