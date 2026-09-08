#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root"

fail() { printf 'SOURCE CHECK FAILED: %s\n' "$*" >&2; exit 1; }
require_text() { grep -F -- "$2" "$1" >/dev/null || fail "$3"; }

test "$(sed -n 's/^version:[[:space:]]*//p' pubspec.yaml | head -n 1)" = "9.1.0+90100" \
  || fail "pubspec version is not 9.1.0+90100"
require_text lib/src/app_config.dart "defaultValue: '9.1.0'" "Dart app version is not 9.1.0"
require_text android/app/build.gradle.kts 'compileSdk = 37' "compileSdk must be 37"
require_text android/app/build.gradle.kts 'buildToolsVersion = "37.0.0"' \
  "the app must use Android build-tools 37.0.0"
require_text android/app/build.gradle.kts 'targetSdk = 37' "targetSdk must be 37"
require_text android/settings.gradle.kts 'id("com.android.application") version "9.2.1"' \
  "Android application plugin must be 9.2.1"
require_text android/settings.gradle.kts 'id("com.android.library") version "9.2.1"' \
  "Android library plugin must be 9.2.1"
require_text android/settings.gradle.kts \
  'id("org.jetbrains.kotlin.android") version "2.4.0" apply false' \
  "Kotlin dependency validation must resolve KGP 2.4.0 without applying it"
require_text android/gradle/wrapper/gradle-wrapper.properties 'gradle-9.4.1-all.zip' \
  "Gradle wrapper must be 9.4.1"
if grep -R -E 'id[[:space:]]*\(["'']org\.jetbrains\.kotlin\.android["'']\)|id[[:space:]]+["'']org\.jetbrains\.kotlin\.android["'']' \
    android/app packages/flutter_inappwebview_android/android >/dev/null 2>&1; then
  fail "Kotlin Gradle Plugin must not be applied to Android modules"
fi
require_text android/gradle.properties 'android.newDsl=false' \
  "Flutter 3.47.1 requires the supported legacy Android DSL bridge"
if grep -E '^(android\.builtInKotlin|android\.r8\.proguardAndroidTxt\.disallowed)=' \
    android/gradle.properties >/dev/null; then
  fail "unsupported AGP 9 compatibility flags remain"
fi
test -s pubspec.lock || fail "pubspec.lock is required for deterministic dependency resolution"
require_text pubspec.yaml 'flutter_inappwebview: 6.1.5' "stable flutter_inappwebview 6.1.5 is required"
require_text pubspec.yaml 'path: packages/flutter_inappwebview_android' \
  "stable Android WebView source override is missing"
require_text packages/flutter_inappwebview_android/pubspec.yaml 'version: 1.1.3' \
  "vendored Android WebView source must remain stable 1.1.3"
require_text packages/flutter_inappwebview_android/android/build.gradle \
  "id 'com.android.library'" "Android WebView package does not use the plugin DSL"
require_text packages/flutter_inappwebview_android/android/build.gradle \
  'compileSdk = flutter.compileSdkVersion' "Android WebView compile SDK is stale"
require_text packages/flutter_inappwebview_android/android/build.gradle \
  "getDefaultProguardFile('proguard-android-optimize.txt')" \
  "Android WebView package does not use optimized R8 defaults"
if grep -F "getDefaultProguardFile('proguard-android.txt')" \
    packages/flutter_inappwebview_android/android/build.gradle >/dev/null; then
  fail "unsupported Android WebView ProGuard default remains"
fi
if grep -E '(^|[[:space:]])(buildscript|lintOptions)[[:space:]]*\{' \
    packages/flutter_inappwebview_android/android/build.gradle >/dev/null; then
  fail "legacy Android WebView Gradle build logic remains"
fi
require_text packages/flutter_inappwebview_android/android/proguard-rules.pro \
  'android.webkit.WebView, java.lang.String' "Android WebView ProGuard signature is malformed"
test -s packages/flutter_inappwebview_android/LICENSE \
  || fail "vendored Android WebView Apache license is missing"
require_text pubspec.yaml 'permission_handler: 13.0.1' "permission_handler 13.0.1 is required"
require_text pubspec.yaml 'permission_handler_android: 14.0.0' "permission_handler_android 14.0.0 is required"
require_text analysis_options.yaml '    - packages/**' \
  "vendored third-party packages must be excluded from first-party analysis"

if grep -F '_LaunchPanel' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "duplicate Flutter launch panel remains"
fi
require_text lib/src/nav_kurd_page.dart "nav-kurd:native-resume" \
  "native document-picker resume recovery is missing"
if grep -F 'nav-kurd:native-pause' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "obsolete native-pause JavaScript injection remains"
fi
if grep -F 'onShowFileChooser: _handleFileChooser' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "custom beta WebView file chooser callback remains"
fi
if grep -R -E 'pickImageFile|"pickImage" ->|launchImagePicker|FileProvider|getUriForFile' \
    lib android/app/src/main >/dev/null 2>&1; then
  fail "obsolete duplicate image-picker bridge remains"
fi
test ! -e android/app/src/main/res/xml/file_paths.xml || fail "obsolete FileProvider paths remain"

require_text android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt \
  'WindowInsetsCompat.Type.systemBars()' "native immersive mode is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt \
  '"shareText" -> result.success(shareText(call))' "native share bridge is missing"
require_text lib/src/nav_kurd_page.dart "handlerName: 'nativeShare'" "WebView native share integration is missing"
require_text lib/src/nav_kurd_page.dart 'InAppWebViewController.clearAllCache()' "current cache cleanup API is missing"
require_text lib/src/nav_kurd_page.dart 'onDownloadStartRequest:' "current WebView download callback is missing"
if grep -E 'onDownloadStarting:|DownloadStartResponse' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "obsolete WebView download API remains"
fi
require_text lib/src/nav_kurd_page.dart 'useHybridComposition: true' "hybrid composition is missing"
require_text lib/src/nav_kurd_page.dart 'hardwareAcceleration: true' "hardware acceleration is missing"
require_text lib/src/nav_kurd_page.dart 'algorithmicDarkeningAllowed: false' "satellite darkening protection is missing"
require_text lib/src/nav_kurd_page.dart 'offscreenPreRaster: true' "offscreen pre-rasterization is missing"
if grep -E '(forceDark:|controller\.platform\.clearAllCache|\.clearCache\()' lib/src/nav_kurd_page.dart >/dev/null; then
  fail "deprecated WebView API remains"
fi
require_text android/app/src/main/AndroidManifest.xml 'android:hardwareAccelerated="true"' "application hardware acceleration is disabled"
require_text android/app/src/main/AndroidManifest.xml 'android:allowBackup="false"' "backup hardening is missing"
require_text lib/src/nav_kurd_page.dart 'Map<Object?, Object?>' "native language payload is not statically typed"
require_text lib/src/nav_kurd_page.dart 'nativeRuntimeInfo' "real Android runtime bridge is missing"
require_text lib/src/native_bridge.dart "'showNotificationOnce'" \
  "one-time native notification bridge is missing"
require_text lib/src/nav_kurd_page.dart "key: 'offline-map-ready'" \
  "offline-map completion notification is not one-time"
require_text android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt \
  'private const val NOTIFICATION_PREFS = "nav_kurd_notification_markers"' \
  "persistent notification marker storage is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt \
  'private fun showNotificationOnce' "native one-time notification gate is missing"

if grep -R -F 'share_plus' pubspec.yaml lib test >/dev/null 2>&1; then
  fail "obsolete share_plus dependency or source reference remains"
fi
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdDiagnostics.kt \
  '[META] Native Android diagnostics' "native diagnostics are missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'api.open-meteo.com' "widget weather source is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'air-quality-api.open-meteo.com' "widget air-quality source is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'NavKurdWidgetArtwork.scene' "state-driven widget artwork is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'NavKurdWidgetTypography.bind' "launcher-independent widget text is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetTypography.kt \
  'ResourcesCompat.getFont' "bundled widget font loading is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetTypography.kt \
  'StaticLayout.Builder' "Kurdish/Arabic shaped text rendering is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetTypography.kt \
  'views.setContentDescription(viewId, text)' "widget text accessibility is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  '&daily=sunrise,sunset&forecast_days=1' "solar day-length weather data is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'in 621..921 -> "summer"' "astronomical season boundaries are missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'minute < preDawnStart -> "late_night"' "seven-part local day cycle is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  '"Open-Meteo · DEV: SARHANG.IO"' "widget developer attribution is missing"
if grep -F 'drawHeat(canvas' android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetArtwork.kt >/dev/null; then
  fail "legacy extreme-heat wave lines remain"
fi
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'R.layout.nav_kurd_widget_en' "English widget layout is not canonical"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetProvider.kt \
  'R.layout.nav_kurd_widget' "Kurdish/Arabic widget layout is not canonical"
if find android/app/src/main -type f -name '*_v9_font*' -print -quit | grep -q .; then
  fail "temporary widget wrapper layout remains"
fi
require_text android/app/src/main/res/layout/nav_kurd_widget.xml \
  '@font/uniqaidar_money_heist_002' "Kurdish/Arabic widget font is incorrect"
require_text android/app/src/main/res/layout/nav_kurd_widget_en.xml \
  '@font/red_hat_display_variable' "English widget font is incorrect"
test -s android/app/src/main/res/font/uniqaidar_money_heist_002.ttf \
  || fail "UniQAIDAR font asset is missing"
test -s android/app/src/main/res/font/red_hat_display_variable.ttf \
  || fail "Red Hat Display font asset is missing"
test ! -e android/app/src/main/res/font/nav_kurd_arabic.ttf \
  || fail "duplicate Arabic font asset remains"
test ! -e android/app/src/main/res/font/nav_kurd_latin.ttf \
  || fail "duplicate Latin font asset remains"
if grep -F '<stroke' android/app/src/main/res/drawable/widget_background.xml >/dev/null; then
  fail "widget background must not have an outer border"
fi
if grep -F 'RectF(1f, 1f' android/app/src/main/kotlin/com/navkurd/app/NavKurdWidgetArtwork.kt >/dev/null; then
  fail "widget artwork outer stroke remains"
fi

for layout in android/app/src/main/res/layout/nav_kurd_widget.xml android/app/src/main/res/layout/nav_kurd_widget_en.xml; do
  test "$(grep -c '@+id/widget_weather_icon' "$layout")" = "1" \
    || fail "$layout must contain one primary weather symbol"
done
test "$(grep -Ec '<Text(View|Clock)' android/app/src/main/res/layout/nav_kurd_widget.xml)" = \
  "$(grep -Fc '@font/uniqaidar_money_heist_002' android/app/src/main/res/layout/nav_kurd_widget.xml)" \
  || fail "every Kurdish/Arabic widget text node must use UniQAIDAR"
test "$(grep -Ec '<Text(View|Clock)' android/app/src/main/res/layout/nav_kurd_widget_en.xml)" = \
  "$(grep -Fc '@font/red_hat_display_variable' android/app/src/main/res/layout/nav_kurd_widget_en.xml)" \
  || fail "every English widget text node must use Red Hat Display"
if find android/app/src/main lib -type f \( -name '*.kt' -o -name '*.dart' -o -name '*.xml' \) -print0 \
  | xargs -0 grep -Pn '[\x{1F300}-\x{1FAFF}]' >/dev/null; then
  fail "emoji found in Android or Flutter source"
fi

python3 tools/verify-launcher-pngs.py
test "$(sha256sum tools/assets/nav-kurd-launcher-source.png | awk '{print $1}')" = \
  "bacc220ac47f0ade5c79efbd35228c61fcea70c304922564218474e245903f63" \
  || fail "launcher icons were not generated from the approved artwork"
test ! -e android/app/src/main/res/drawable/ic_launcher_background.xml \
  || fail "obsolete launcher background drawable remains"
test ! -e android/app/src/main/res/drawable-v24/ic_launcher_foreground.xml \
  || fail "obsolete launcher foreground drawable remains"
require_text tools/generate-launcher-icons.sh 'Generated 15 launcher assets' \
  "deterministic launcher generator is missing"

require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdNotificationReceiver.kt \
  'RELEASE_URL' "release update check is missing"
require_text android/app/src/main/kotlin/com/navkurd/app/NavKurdNotificationScheduler.kt \
  'ACTION_DAILY_WEATHER' "daily weather schedule is missing"
require_text lib/src/url_policy.dart "host == 'auth'" "OAuth callback routing is missing"
require_text test/url_policy_test.dart 'access_token' "OAuth token rejection test is missing"

test "$(find .github/workflows -maxdepth 1 -type f | wc -l | tr -d ' ')" = "1" \
  || fail "Android repository must contain exactly one workflow"
require_text .github/workflows/android-release.yml 'name: NAV KURD Android release' "workflow name is stale"
require_text .github/workflows/android-release.yml 'Use Flutter 3.47.1' "Flutter 3.47.1 is required"
require_text .github/workflows/android-release.yml 'bash tools/install-android-sdk.sh' "canonical Android SDK setup is missing"
require_text .github/workflows/android-release.yml '      - "packages/**"' \
  "vendored package changes must trigger Android CI"
require_text .github/workflows/android-release.yml 'flutter pub get --enforce-lockfile' \
  "CI must enforce the committed dependency lockfile"
require_text .github/workflows/android-release.yml 'flutter analyze --no-pub --fatal-infos lib test' \
  "strict first-party Flutter analysis is missing"
if grep -F -- '--android-skip-build-dependency-validation' \
    .github/workflows/android-release.yml tools README.md >/dev/null 2>&1; then
  fail "Android build dependency validation must not be skipped"
fi
require_text tools/install-android-sdk.sh 'cmdline-tools/latest/bin/sdkmanager' "sdkmanager path resolution is missing"
require_text tools/install-android-sdk.sh 'readonly MAX_ATTEMPTS=12' "Android SDK retry count is not 12"
require_text tools/install-android-sdk.sh 'readonly FLUTTER_PLUGIN_PLATFORM="android-36"' \
  "Flutter plugin compile SDK package is missing"
require_text tools/install-android-sdk.sh 'readonly ANDROID_PLATFORM="android-37.0"' "Android 17 SDK package identifier is incorrect"
require_text tools/install-android-sdk.sh 'readonly ANDROID_DEFAULT_BUILD_TOOLS="36.0.0"' \
  "AGP default build-tools package is missing"
require_text tools/install-android-sdk.sh 'readonly ANDROID_BUILD_TOOLS="37.0.0"' "Android 17 build-tools package is incorrect"
require_text tools/install-android-sdk.sh '"platform-tools"' "Android platform-tools package is missing"
require_text .github/workflows/android-release.yml 'Build signed universal APK' "universal APK build is missing"
if grep -F -- '--split-per-abi' .github/workflows/android-release.yml >/dev/null; then
  fail "obsolete ABI-split APK builds remain"
fi
require_text .github/workflows/android-release.yml 'Actual APK SHA-256' "APK signing identity verification is missing"
require_text .github/workflows/android-release.yml 'CERTIFICATE_SHA256.txt' "certificate evidence is missing"
require_text .github/workflows/android-release.yml 'deststoretype PKCS12' \
  "release signing must migrate temporary JKS input to PKCS12"
require_text .github/workflows/android-release.yml 'storeFile=nav-kurd-release.p12' \
  "Gradle release signing is not using the temporary PKCS12 store"
require_text .github/workflows/android-release.yml 'actions/upload-artifact@v7' \
  "Android release evidence uploader is stale"
require_text TERMUX.sh 'MAX_ATTEMPTS=12' "Termux network retry count is not 12"
require_text TERMUX.sh 'The signing key fingerprint does not match NAV KURD' "Termux signing fingerprint gate is missing"

for forbidden in android.permission.MANAGE_EXTERNAL_STORAGE android.permission.ACCESS_BACKGROUND_LOCATION \
  android.permission.READ_CONTACTS android.permission.RECORD_AUDIO; do
  if grep -F "$forbidden" android/app/src/main/AndroidManifest.xml >/dev/null; then
    fail "unnecessary high-risk permission found: $forbidden"
  fi
done

while IFS= read -r script; do bash -n "$script"; done \
  < <(find . -path './.git' -prune -o -type f -name '*.sh' -print)

if command -v node >/dev/null 2>&1; then
  sed -n "/^const String _documentStartBridgeScript = r'''/,/^''';/p" lib/src/nav_kurd_page.dart \
    | sed '1d;$d' | node --check -
  sed -n "/^const String _afterLoadBridgeScript = r'''/,/^''';/p" lib/src/nav_kurd_page.dart \
    | sed '1d;$d' | node --check -
fi

printf '%s\n' 'NAV KURD 9.1.0 (90100) source checks passed.'
