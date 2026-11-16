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
