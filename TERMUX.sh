#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADS="${NAV_KURD_DOWNLOADS:-/storage/emulated/0/Download}"
DEFAULT_REPO="sarhang-sg/GEO-ANDROID"
MAX_ATTEMPTS=12
VERSION="9.1.0"

log() { printf '\n[NAV KURD ANDROID] %s\n' "$*"; }
fail() { printf '\n[NAV KURD ANDROID] ERROR: %s\n' "$*" >&2; exit 1; }

retry() {
  local attempt=1
  while ! "$@"; do
    if (( attempt >= MAX_ATTEMPTS )); then
      fail "Command failed after ${MAX_ATTEMPTS} attempts: $*"
    fi
    log "Network attempt ${attempt}/${MAX_ATTEMPTS} failed; retrying"
    sleep $(( attempt < 6 ? attempt * 3 : 18 ))
    attempt=$((attempt + 1))
  done
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1. Run: bash TERMUX.sh setup"
}

setup() {
  command -v pkg >/dev/null 2>&1 || fail "Run this command inside Termux."
  termux-setup-storage >/dev/null 2>&1 || true
  retry pkg update -y
  retry pkg install -y git gh zip unzip openssl-tool coreutils sed ripgrep openjdk-21
  require_command keytool
  termux-wake-lock >/dev/null 2>&1 || true
  log "Tools are ready. Authenticate once with: gh auth login"
}

check() {
  bash -n "$ROOT/TERMUX.sh"
  bash "$ROOT/tools/validate-source.sh"
  test -s "$ROOT/pubspec.yaml"
  test -s "$ROOT/lib/main.dart"
  test -s "$ROOT/android/app/src/main/AndroidManifest.xml"
  test -s "$ROOT/.github/workflows/android-release.yml"
  if rg -n --hidden -g '!signing/**' -g '!TERMUX.sh' \
      '(storePassword=.{8,}|keyPassword=.{8,}|BEGIN (RSA|EC|OPENSSH) PRIVATE)' \
      "$ROOT" >/dev/null 2>&1; then
    fail "Potential signing secret exists in the source tree"
  fi
  log "Source checks passed"
}

with_signing() {
  require_command unzip
  require_command keytool
  local callback="$1"
  local repo="$2"
  local archive="${DOWNLOADS}/backap.zip"
  [[ -s "$archive" ]] || archive="${DOWNLOADS}/apk.zip"
  [[ -s "$archive" ]] || fail "Missing ${DOWNLOADS}/backap.zip (or apk.zip)"
  local temp_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -r "$temp_dir"' RETURN
  unzip -q "$archive" -d "$temp_dir"
  local keystore properties
  keystore="$(find "$temp_dir" -type f -name 'nav-kurd-release.jks' -print -quit)"
  properties="$(find "$temp_dir" -type f -name 'signing.properties' -print -quit)"
  [[ -s "$keystore" && -s "$properties" ]] || fail "apk.zip does not contain the signing JKS and signing.properties"

  local store_password key_password key_alias expected actual
  store_password="$(sed -n 's/^storePassword=//p' "$properties" | head -n 1 | tr -d '\r')"
  key_password="$(sed -n 's/^keyPassword=//p' "$properties" | head -n 1 | tr -d '\r')"
  key_alias="$(sed -n 's/^keyAlias=//p' "$properties" | head -n 1 | tr -d '\r')"
  [[ -n "$store_password" && -n "$key_password" && -n "$key_alias" ]] ||
    fail "signing.properties is incomplete"
  expected="$(tr -d '[:space:]:' < "$ROOT/ANDROID_APP_LINK_SHA256.txt" | tr '[:lower:]' '[:upper:]')"
  actual="$(keytool -list -v -keystore "$keystore" -storepass "$store_password" -alias "$key_alias" \
    | sed -n 's/^[[:space:]]*SHA256: //p' | head -n 1 | tr -d '[:space:]:' | tr '[:lower:]' '[:upper:]')"
  [[ "${#expected}" -eq 64 && "$actual" == "$expected" ]] || fail "The signing key fingerprint does not match NAV KURD"
  "$callback" "$repo" "$keystore" "$store_password" "$key_alias" "$key_password"
  unset store_password key_password
  trap - RETURN
  rm -r "$temp_dir"
}

upload_signing_values() {
  local repo="$1" keystore="$2" store_password="$3" key_alias="$4" key_password="$5"
  require_command gh
  gh auth status >/dev/null 2>&1 || gh auth login
  retry gh repo view "$repo" --json nameWithOwner --jq '.nameWithOwner' >/dev/null
  local encoded
  encoded="$(base64 -w 0 "$keystore")"
  retry gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repo" --body "$encoded"
  retry gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$repo" --body "$store_password"
  retry gh secret set ANDROID_KEY_ALIAS --repo "$repo" --body "$key_alias"
  retry gh secret set ANDROID_KEY_PASSWORD --repo "$repo" --body "$key_password"
  unset encoded
  log "Signing secrets configured"
}

secrets() {
  local repo="${1:-$DEFAULT_REPO}"
  with_signing upload_signing_values "$repo"
}

build() {
  require_command gh
  local repo="${1:-$DEFAULT_REPO}"
  gh auth status >/dev/null 2>&1 || gh auth login
  retry gh repo view "$repo" --json nameWithOwner --jq '.nameWithOwner' >/dev/null
  local previous_run
  previous_run="$(gh run list --repo "$repo" --workflow android-release.yml --event workflow_dispatch \
    --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  retry gh workflow run android-release.yml --repo "$repo" --ref main
  local run_id=""
  local attempt
  for attempt in $(seq 1 30); do
    run_id="$(gh run list --repo "$repo" --workflow android-release.yml --event workflow_dispatch \
      --branch main --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
    [[ -n "$run_id" && "$run_id" != "null" && "$run_id" != "$previous_run" ]] && break
    sleep 4
  done
  [[ -n "$run_id" && "$run_id" != "null" && "$run_id" != "$previous_run" ]] ||
    fail "Could not identify the newly dispatched Android workflow run"
  retry gh run watch "$run_id" --repo "$repo" --exit-status

  local target
  target="$(mktemp -d)"
  trap 'rm -rf -- "$target"' RETURN
  retry gh run download "$run_id" --repo "$repo" \
    --name "NAV-KURD-${VERSION}-signed-release" --dir "$target"
  (cd "$target" && sha256sum -c SHA256SUMS.txt)
  mkdir -p "$DOWNLOADS"
  install -m 0644 "$target/NAV-KURD-${VERSION}.apk" "$DOWNLOADS/NAV-KURD-${VERSION}.apk"
  install -m 0644 "$target/NAV-KURD-${VERSION}.aab" "$DOWNLOADS/NAV-KURD-${VERSION}.aab"
  trap - RETURN
  rm -rf -- "$target"
  log "Signed APK and AAB saved in Android Download"
}

case "${1:-help}" in
  setup) setup ;;
  check) check ;;
  secrets) secrets "${2:-}" ;;
  build) build "${2:-}" ;;
  all) check; secrets "${2:-}"; build "${2:-}" ;;
  *) printf '%s\n' "Usage: bash TERMUX.sh setup|check|secrets [OWNER/REPO]|build [OWNER/REPO]|all [OWNER/REPO]" ;;
esac
