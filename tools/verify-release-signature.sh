#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
apk_path="${1:-}"
expected="$(tr -d '\r\n' < "$project_root/ANDROID_APP_LINK_SHA256.txt" | tr '[:lower:]' '[:upper:]')"

if [[ -z "$apk_path" || ! -s "$apk_path" ]]; then
  echo "Usage: bash tools/verify-release-signature.sh /path/to/app-release.apk" >&2
  exit 2
fi

if command -v apksigner >/dev/null 2>&1; then
  digest="$(apksigner verify --print-certs "$apk_path" \
    | awk '/certificate SHA-256 digest:/ { print $NF }' \
    | tr -d ':' | tr '[:lower:]' '[:upper:]' | sort -u)"
elif command -v keytool >/dev/null 2>&1; then
  digest="$(keytool -printcert -jarfile "$apk_path" 2>/dev/null \
    | sed -n 's/^[[:space:]]*SHA256: //p' \
    | head -n 1 \
    | tr -d ':')"
else
  echo "Neither apksigner nor keytool is installed." >&2
  exit 1
fi

[[ "$digest" =~ ^[[:xdigit:]]{64}$ ]] || {
  echo 'Expected exactly one valid APK signing identity.' >&2
  exit 1
}
actual="$(printf '%s' "$digest" | sed 's/../&:/g;s/:$//' | tr '[:lower:]' '[:upper:]')"
test -n "$actual" || {
  echo "Could not read the APK signing certificate." >&2
  exit 1
}
test "$actual" = "$expected" || {
  echo "APK certificate mismatch." >&2
  echo "Expected: $expected" >&2
  echo "Actual:   $actual" >&2
  exit 1
}
echo "APK signature matches NAV KURD: $actual"
