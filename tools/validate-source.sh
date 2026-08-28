#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() {
  echo "SOURCE CHECK FAILED: $*" >&2
  exit 1
}

test "$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)" = "8.0.4+80004" \
  || fail "pubspec version is not 8.0.4+80004"
grep -F "defaultValue: '8.0.4'" lib/src/app_config.dart >/dev/null \
  || fail "Dart app version is not 8.0.4"
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
    .github android lib test tools GEO-ANDROID-V8-UPDATE-UPLOAD-BUILD.sh \
    >/dev/null 2>&1; then
  fail "obsolete geo-map-two production origin is still present"
fi
grep -F 'Refusing to upload a signing key with the wrong Android identity.' \
  TERMUX.sh >/dev/null \
  || fail "Termux signing-secret upload is not fingerprint-gated"
grep -F 'readonly repo_name="sarhang-sg/GEO-ANDROID"' \
  GEO-ANDROID-V8-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not target the final private Android repository"
grep -F 'gh repo create "$repo_name"' \
  GEO-ANDROID-V8-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater cannot create the fresh private Android repository"
grep -F 'FAILURE ANNOTATIONS' GEO-ANDROID-V8-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not preserve fallback workflow diagnostics"
grep -F 'Verified APK certificate record was not found.' \
  GEO-ANDROID-V8-UPDATE-UPLOAD-BUILD.sh >/dev/null \
  || fail "Termux updater does not verify the workflow certificate record"
if grep -F 'APK v1 certificate block was not found.' \
  GEO-ANDROID-V8-UPDATE-UPLOAD-BUILD.sh >/dev/null; then
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

echo "NAV KURD 8.0.4 source checks passed."
