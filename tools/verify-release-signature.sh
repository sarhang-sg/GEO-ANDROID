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
    | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' \
    | head -n 1 \
    | tr -d ':')"
elif command -v keytool >/dev/null 2>&1; then
  digest="$(keytool -printcert -jarfile "$apk_path" 2>/dev/null \
    | sed -n 's/^[[:space:]]*SHA256: //p' \
    | head -n 1 \
    | tr -d ':')"
else
  echo "Neither apksigner nor keytool is installed." >&2
  exit 1
fi

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
