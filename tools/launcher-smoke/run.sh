#!/usr/bin/env bash
set -euo pipefail
apk=$(realpath "${1:?Supply the APK to exercise}")
target=${2:?Supply the package ID}
case "$target" in com.navkurd.app|com.navkurd.app.debug) ;; *) exit 2 ;; esac
here=$(cd "$(dirname "$0")" && pwd)
python3 "$here/../test-offline-routes.py" "$apk" "${@:3}"
sdk=${ANDROID_HOME:?Android SDK is required}
tools="$sdk/build-tools/37.0.0"
platform="$sdk/platforms/android-36/android.jar"
export PATH="$sdk/platform-tools:$sdk/emulator:$sdk/cmdline-tools/latest/bin:$PATH"
work=$(mktemp -d)
evidence="${RUNNER_TEMP:-/tmp}/nav-kurd-launcher-check"
mkdir -p "$evidence"
emulator_pid=
finish() {
    code=$?
    if ((code)); then
        adb exec-out screencap -p > "$evidence/failure.png" || true
        tail -30 "$work/emulator.log" || true
        adb logcat -b crash -d -t 160 || true
        adb logcat -d -s NavKurdStartup:I NavKurdSmoke:I NavKurdWidget:W flutter:I AndroidRuntime:E | tail -150 || true
        adb shell dumpsys activity activities | grep -m1 'mResumedActivity\|topResumedActivity' || true
        adb shell dumpsys activity exit-info "$target" | head -60 || true
        timeout 15 adb shell uiautomator dump /sdcard/nav-kurd-failure.xml >/dev/null 2>&1 &&
            adb shell cat /sdcard/nav-kurd-failure.xml | head -c 8000 || true
    fi
    adb logcat -b crash -d > "$evidence/crash.txt" || true
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
    # This is the public signed upgrade baseline. The downloaded APK is checked
    # against its published receipt before installation, then upgraded in place.
    previous=${PREVIOUS_SIGNED_APK:-"$work/previous.apk"}
    digest=3d1d9bd9ea6cc9b97dad6eff98e59ad5a81e13371d46534d984be3f11ea981ff
    if [[ -z "${PREVIOUS_SIGNED_APK:-}" ]]; then
        curl -fsSL --retry 3 --connect-timeout 15 --max-time 180 \
            https://github.com/sarhang-sg/GEO-ANDROID/releases/download/v10.4.6/NAV-KURD-10.4.6.apk \
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
adb logcat -b main -c
# One device installation exercises the public launcher, then an actual bound widget.
adb shell am start -W -n "$target/com.navkurd.app.MainActivity"
# ADB can report success before UIAutomator creates its hierarchy (especially
# during a WebView cold start). Only accept a fresh, complete accessibility tree.
read_window() {
    local path=/data/local/tmp/nav-kurd-window.xml
    adb shell rm -f "$path" || return 1
    timeout 18 adb shell uiautomator dump "$path" >/dev/null 2>&1 || return 1
    adb shell test -s "$path" || return 1
    adb exec-out cat "$path" > "$work/window.xml" || return 1
    python3 -c 'import sys,xml.etree.ElementTree as ET; assert ET.parse(sys.argv[1]).getroot().tag == "hierarchy"' "$work/window.xml" 2>/dev/null
}
wait_screen() {
    local kind=$1 action x y pid frame
    case "$kind" in map) frame=map-drawn ;; weather) frame=forecast-drawn ;; *) return 2 ;; esac
    for _ in $(seq 1 30); do
        if read_window; then
            # Some WebView versions expose only the host view to UIAutomator.
            # The activity reports its first usable frame after the real map
            # paints, or after the requested forecast heading enters the viewport.
            pid=$(adb shell pidof -s "$target" | tr -d '\r') || pid=
            local drawn=no
            if [[ "$pid" =~ ^[0-9]+$ ]] && adb logcat --pid="$pid" -b main -d -v raw -s NavKurdStartup:I | grep -Fx "$frame" >/dev/null; then
                drawn=yes
            fi
            read -r action x y < <(python3 "$here/map-window.py" "$work/window.xml" "$kind" "$target" "$drawn")
            case "$action" in
                tap) adb shell input tap "$x" "$y" ;;
                ready) cp "$work/window.xml" "$evidence/$kind.xml"; return 0 ;;
            esac
        fi
        sleep 1
    done
    echo "$kind screen did not finish loading" >&2
    return 1
}
wait_screen map
echo 'PASS launcher opened the bundled map'
adb exec-out screencap -p > "$evidence/map.png"
adb shell am start -W -n com.navkurd.smoke/.WidgetHost --es target "$target" --ez reuse "$reuse_widget"
timeout 145 bash -c 'until adb logcat -d -s NavKurdSmoke:I | grep -F widget-bitmap-ready >/dev/null; do sleep 2; done'
adb exec-out screencap -p > "$evidence/widget.png"
for _ in $(seq 1 12); do
    if read_window && grep -q ':id/weather_forecast' "$work/window.xml"; then
        cp "$work/window.xml" "$evidence/widget.xml"
        break
    fi
    sleep 1
done
test -s "$evidence/widget.xml"
read -r tap_x tap_y < <(python3 - "$evidence/widget.xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
root = ET.parse(sys.argv[1]).getroot()
node = next(n for n in root.iter("node") if n.get("resource-id", "").endswith(":id/weather_forecast"))
x1, y1, x2, y2 = map(int, re.findall(r"\d+", node.attrib["bounds"]))
assert x2 > x1 and y2 > y1 and node.get("clickable") == "true"
print((x1 + x2) // 2, (y1 + y2) // 2)
PY
)
adb shell input tap "$tap_x" "$tap_y"
top_is() { adb shell dumpsys activity activities | grep -E '(topResumedActivity|mResumedActivity).*'"$target"'/([^ ]*\.)?'"$1"'[ }]'>/dev/null; }
for _ in $(seq 1 15); do if top_is WeatherActivity; then break; fi; sleep 1; done
top_is WeatherActivity
wait_screen weather
adb exec-out screencap -p > "$evidence/weather.png"
for _ in $(seq 1 3); do adb shell input keyevent 4; sleep 2; if top_is MainActivity; then break; fi; done
top_is MainActivity
if adb logcat -b crash -d | grep -E "(Process|Cmdline): ${target//./\\.}(:weather_render)?(,|[[:space:]]|$)" >/dev/null; then
    echo 'Application or weather renderer crashed during smoke test'; exit 1
fi
echo 'PASS launcher bitmap, real widget tap and Back to map'
