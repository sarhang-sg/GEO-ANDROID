#!/usr/bin/env bash
set -euo pipefail
sdk=${ANDROID_HOME:?Android SDK is required}
image="$sdk/system-images/android-35/google_apis/x86_64/system.img"
if [[ ! -s "$image" || ! -x "$sdk/emulator/emulator" ]]; then
    timeout 420 "$sdk/cmdline-tools/latest/bin/sdkmanager" --install \
        emulator platform-tools 'system-images;android-35;google_apis;x86_64'
fi
test -s "$image"
test -x "$sdk/emulator/emulator"
df -h "${RUNNER_TEMP:-/tmp}"
# This reviewed emulator keeps the host renderer stable during Flutter surface changes.
archive="${RUNNER_TEMP:-/tmp}/nav-kurd-emulator-14212360"
mkdir -p "$archive"
if [[ ! -x "$archive/emulator/emulator" ]]; then
    curl -fsSL --retry 3 --connect-timeout 20 --max-time 240 \
        https://dl.google.com/android/repository/emulator-linux_x64-14212360.zip -o "$archive/emulator.zip"
    printf '%s  %s\n' 9a6641da7f4a3133dc320e1eb411644a12ab6966c9a8af0c8bd10cb401308f74 "$archive/emulator.zip" | sha256sum -c --strict
    unzip -q "$archive/emulator.zip" -d "$archive"
    rm "$archive/emulator.zip"
fi
"$archive/emulator/emulator" -version
