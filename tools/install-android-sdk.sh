#!/usr/bin/env bash
set -Eeuo pipefail

readonly MAX_ATTEMPTS=12
readonly FLUTTER_PLUGIN_PLATFORM="android-36"
readonly ANDROID_PLATFORM="android-37.0"
readonly ANDROID_DEFAULT_BUILD_TOOLS="36.0.0"
readonly ANDROID_BUILD_TOOLS="37.0.0"

fail() {
  printf 'ANDROID SDK SETUP FAILED: %s\n' "$*" >&2
  exit 1
}

resolve_sdkmanager() {
  local candidate root

  if [[ -n "${SDKMANAGER_BIN:-}" ]]; then
    [[ -x "$SDKMANAGER_BIN" ]] || fail "SDKMANAGER_BIN is not executable: $SDKMANAGER_BIN"
    printf '%s\n' "$SDKMANAGER_BIN"
    return 0
  fi

  if command -v sdkmanager >/dev/null 2>&1; then
    command -v sdkmanager
    return 0
  fi

  for root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}" /usr/local/lib/android/sdk; do
    [[ -n "$root" && -d "$root" ]] || continue
    for candidate in \
      "$root/cmdline-tools/latest/bin/sdkmanager" \
      "$root/cmdline-tools"/*/bin/sdkmanager \
      "$root/tools/bin/sdkmanager"; do
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done
  done

  return 1
}

main() {
  local sdkmanager_path attempt
  sdkmanager_path="$(resolve_sdkmanager)" \
    || fail "sdkmanager was not found in PATH, ANDROID_SDK_ROOT or ANDROID_HOME"

  printf 'Using sdkmanager: %s\n' "$sdkmanager_path"
  for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    if "$sdkmanager_path" \
      "platform-tools" \
      "platforms;${FLUTTER_PLUGIN_PLATFORM}" \
      "platforms;${ANDROID_PLATFORM}" \
      "build-tools;${ANDROID_DEFAULT_BUILD_TOOLS}" \
      "build-tools;${ANDROID_BUILD_TOOLS}"; then
      printf 'Installed platform-tools, %s, %s, build-tools %s and %s.\n' \
        "$FLUTTER_PLUGIN_PLATFORM" "$ANDROID_PLATFORM" \
        "$ANDROID_DEFAULT_BUILD_TOOLS" "$ANDROID_BUILD_TOOLS"
      return 0
    fi

    if [[ "$attempt" -eq "$MAX_ATTEMPTS" ]]; then
      fail "Android SDK installation failed after ${MAX_ATTEMPTS} attempts"
    fi

    printf 'Android SDK network attempt %s/%s failed; retrying.\n' \
      "$attempt" "$MAX_ATTEMPTS" >&2
    sleep $((attempt < 6 ? attempt * 3 : 18))
  done
}

main "$@"
