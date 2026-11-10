#!/usr/bin/env bash
set -euo pipefail
apk=$(realpath "${1:?Supply the APK to exercise}")
target=${2:?Supply the package ID}
case "$target" in com.navkurd.app|com.navkurd.app.debug) ;; *) exit 2 ;; esac
here=$(cd "$(dirname "$0")" && pwd)
sdk=${ANDROID_HOME:?Android SDK is required}
tools="$sdk/build-tools/37.0.0"
platform="$sdk/platforms/android-36/android.jar"
export PATH="$sdk/platform-tools:$sdk/emulator:$sdk/cmdline-tools/latest/bin:$PATH"
work=$(mktemp -d)
emulator_pid=
finish() {
    code=$?
    if ((code)); then
        tail -30 "$work/emulator.log" || true
        adb logcat -b crash -d -t 160 || true
        adb logcat -d -s NavKurdSmoke:I NavKurdWidget:W flutter:I AndroidRuntime:E | tail -150 || true
        adb shell dumpsys activity activities | grep -m1 'mResumedActivity\|topResumedActivity' || true
        adb shell dumpsys activity exit-info "$target" | head -60 || true
        timeout 15 adb shell uiautomator dump /sdcard/nav-kurd-failure.xml >/dev/null 2>&1 &&
            adb shell cat /sdcard/nav-kurd-failure.xml | head -c 8000 || true
    fi
    if [[ -n "$emulator_pid" ]]; then adb emu kill >/dev/null 2>&1 || true; fi
    rm -rf "$work"
    exit "$code"
}
trap finish EXIT
test -c /dev/kvm
if [[ ! -w /dev/kvm ]]; then sudo setfacl -m "u:$(id -un):rw" /dev/kvm; fi
sdkmanager --install emulator platform-tools 'system-images;android-35;google_apis;x86_64' >/dev/null
export ANDROID_AVD_HOME="$work/avd"
mkdir -p "$ANDROID_AVD_HOME" "$work/classes" "$work/dex"
printf 'no\n' | avdmanager create avd --force --name navkurd --package 'system-images;android-35;google_apis;x86_64' >/dev/null
emulator -avd navkurd -port 5554 -gpu swiftshader -no-window -noaudio -no-boot-anim -no-snapshot -memory 2048 >"$work/emulator.log" 2>&1 &
emulator_pid=$!
export ANDROID_SERIAL=emulator-5554
timeout 120 adb wait-for-device
timeout 240 bash -c 'until [[ "$(adb shell getprop sys.boot_completed | tr -d "\r")" == 1 ]]; do sleep 2; done'
adb shell input keyevent 82
adb shell settings put system screen_off_timeout 600000
adb shell settings put secure immersive_mode_confirmations confirmed
javac --release 8 -classpath "$platform" -d "$work/classes" "$here/WidgetHost.java"
"$tools/d8" --min-api 28 --lib "$platform" --output "$work/dex" "$work/classes/com/navkurd/smoke/WidgetHost.class"
"$tools/aapt2" link -I "$platform" --manifest "$here/AndroidManifest.xml" -o "$work/host.apk"
(cd "$work/dex" && zip -q "$work/host.apk" classes.dex)
"$tools/zipalign" -f 4 "$work/host.apk" "$work/aligned.apk"
keytool -genkeypair -alias smoke -keystore "$work/emulator-only.jks" -storepass android -keypass android -keyalg RSA -dname 'CN=Emulator test' -validity 2 >/dev/null 2>&1
"$tools/apksigner" sign --ks "$work/emulator-only.jks" --ks-pass pass:android --out "$work/test.apk" "$work/aligned.apk"
adb install --no-streaming "$work/test.apk"
adb shell appwidget grantbind --package com.navkurd.smoke
reuse_widget=false
if [[ "$target" == com.navkurd.app ]]; then
    # Exercise the signed, in-place update from the version reported by the user.
    if [[ -n "${PREVIOUS_SIGNED_APK:-}" ]]; then
        previous=$PREVIOUS_SIGNED_APK
        digest=876df2758627e7a5e3507e46ba4efcc678308e040703b99353f0b8f0512cd044
    else
        previous="$work/previous.apk"
        digest=abfa0f8bcc08b4893fe81d6a6da7e73f59db6d6c088510107e8dfc71166777d0
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 \
            https://github.com/sarhang-sg/GEO-ANDROID/releases/download/v10.4.4/NAV-KURD-10.4.4.apk \
            -o "$previous"
    fi
    printf '%s  %s\n' "$digest" "$previous" | sha256sum -c --strict
    adb install --no-streaming "$previous"
    adb shell am start -W -n "$target/com.navkurd.app.MainActivity" || echo 'Previous build failed to start'
    adb shell am start -W -n com.navkurd.smoke/.WidgetHost --es target "$target" --ez initial true
    timeout 30 bash -c 'until adb logcat -d -s NavKurdSmoke:I | grep -F previous-widget-bound >/dev/null; do sleep 1; done'
    adb shell input keyevent KEYCODE_HOME
    adb shell am force-stop com.navkurd.smoke
    adb logcat -b crash -d | tail -35
    reuse_widget=true
    adb shell am force-stop "$target"
    adb logcat -b crash -c
fi
adb install -r --no-streaming "$apk"
# One device installation exercises the public launcher, then an actual bound widget.
adb shell am start -W -n "$target/com.navkurd.app.MainActivity"
ready=false
for attempt in $(seq 1 45); do
    if timeout 10 adb shell uiautomator dump /sdcard/nav-kurd-smoke.xml >/dev/null 2>&1; then
        adb shell cat /sdcard/nav-kurd-smoke.xml > "$work/window.xml"
        if grep -E 'ئێستا نا|Not now|ليس الآن' "$work/window.xml" >/dev/null; then
            adb shell input keyevent 4
        elif grep -F 'class="android.webkit.WebView"' "$work/window.xml" >/dev/null; then
            ready=true; break
        fi
    fi
    sleep 1
done
if [[ $ready != true ]]; then echo 'Map did not reach Android WebView'; exit 1; fi
echo 'PASS launcher opened the bundled map'
adb shell am start -W -n com.navkurd.smoke/.WidgetHost --es target "$target" --ez reuse "$reuse_widget"
timeout 145 bash -c 'until adb logcat -d -s NavKurdSmoke:I | grep -F widget-bitmap-and-tap >/dev/null; do sleep 2; done'
top_is() { adb shell dumpsys activity activities | grep -E '(topResumedActivity|mResumedActivity).*'"$target"'/([^ ]*\.)?'"$1"'[ }]'>/dev/null; }
for _ in $(seq 1 15); do if top_is WeatherActivity; then break; fi; sleep 1; done
top_is WeatherActivity
for _ in $(seq 1 3); do adb shell input keyevent 4; sleep 2; if top_is MainActivity; then break; fi; done
top_is MainActivity
if adb logcat -b crash -d | grep -F "Process: $target," >/dev/null; then echo 'Application crashed during smoke test'; exit 1; fi
echo 'PASS launcher bitmap, real widget tap and Back to map'
