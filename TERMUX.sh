#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
signing_properties="$project_root/signing/signing.properties"
keystore_path="$project_root/signing/nav-kurd-release.jks"
default_repo_name="GEO-ANDROID"

usage() {
  cat <<'HELP'
NAV KURD / GEO ANDROID — Termux helper

Commands:
  bash TERMUX.sh setup                 Install Termux tools
  bash TERMUX.sh check                 Validate the source tree
  bash TERMUX.sh key                   Generate the private Android update key
  bash TERMUX.sh publish [OWNER/REPO]  Create/push private GEO-ANDROID repo
  bash TERMUX.sh secrets [OWNER/REPO]  Store signing values in GitHub Actions
  bash TERMUX.sh build [OWNER/REPO]    Run Actions and download APK/AAB files
  bash TERMUX.sh all [OWNER/REPO]      legacy fresh-app bootstrap only

GitHub repository names cannot contain spaces, so "GEO ANDROID" is stored as
"GEO-ANDROID". This script builds on GitHub's Android runner; it does not need
an unsupported desktop Flutter compiler inside Android/Termux.
HELP
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing command: $1. Run: bash TERMUX.sh setup" >&2
    exit 1
  fi
}

github_login() {
  gh api user --jq .login
}

resolve_repo() {
  local requested="${1:-}"
  if [[ -n "$requested" ]]; then
    printf '%s' "$requested"
  else
    printf '%s/%s' "$(github_login)" "$default_repo_name"
  fi
}

read_property() {
  local key="$1"
  sed -n "s/^${key}=//p" "$signing_properties" | head -n 1
}

setup_termux() {
  pkg update -y
  pkg install -y git gh zip unzip openssl-tool coreutils sed ripgrep
  if ! command -v keytool >/dev/null 2>&1; then
    pkg install -y openjdk-21 || pkg install -y openjdk-17 || true
  fi
  termux-wake-lock || true
  echo "Termux tools are ready. Authenticate once with: gh auth login"
}

check_tree() {
  require_command bash
  require_command git
  bash -n "$project_root/TERMUX.sh"
  bash -n "$project_root/tools/generate-signing.sh"
  bash "$project_root/tools/validate-source.sh"
  test -s "$project_root/pubspec.yaml"
  test -s "$project_root/lib/main.dart"
  test -s "$project_root/android/app/src/main/AndroidManifest.xml"
  test -s "$project_root/.github/workflows/android-release.yml"
  if rg -n --hidden \
      -g '!signing/**' \
      -g '!TERMUX.sh' \
      '(storePassword=[A-Fa-f0-9]{24,}|keyPassword=[A-Fa-f0-9]{24,}|BEGIN (RSA|EC|OPENSSH) PRIVATE)' \
      "$project_root" >/dev/null 2>&1; then
    echo "Potential signing secret found outside signing/. Stop and inspect." >&2
    exit 1
  fi
  echo "Source tree checks passed."
}

generate_key() {
  if [[ "${NAV_KURD_CREATE_NEW_APP_KEY:-}" != "YES" ]]; then
    echo "Refusing to create a replacement update key automatically." >&2
    echo "Restore the established JKS, or keep using the existing GitHub Actions secrets." >&2
    echo "Only a genuinely new app may set NAV_KURD_CREATE_NEW_APP_KEY=YES." >&2
    exit 1
  fi
  chmod +x "$project_root/tools/generate-signing.sh"
  "$project_root/tools/generate-signing.sh"
}

stage_source() {
  git -C "$project_root" add -- \
    .github \
    .gitignore \
    .metadata \
    ANDROID_APP_LINK_SHA256.txt \
    BUILD_STATUS.md \
    HANDOFF_ANDROID_9.0.0.md \
    NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh \
    LICENSE \
    README.md \
    RELEASE_CHECKLIST.md \
    SECURITY.md \
    SOURCE_MANIFEST.sha256 \
    TERMUX.sh \
    TERMUX_COMMANDS_CKB.md \
    UPDATE_PATHS.txt \
    analysis_options.yaml \
    android \
    assets \
    docs \
    lib \
    pubspec.yaml \
    test \
    tools
}

publish_repo() {
  require_command gh
  require_command git
  gh auth status >/dev/null
  local repo
  repo="$(resolve_repo "${1:-}")"

  if [[ ! -d "$project_root/.git" ]]; then
    git -C "$project_root" init -b main
    git -C "$project_root" config user.name "$(github_login)"
    git -C "$project_root" config user.email "$(gh api user --jq '.id|tostring')+$(github_login)@users.noreply.github.com"
  fi

  stage_source
  if ! git -C "$project_root" diff --cached --quiet; then
    git -C "$project_root" commit -m "Build NAV KURD Flutter Android app"
  fi

  if gh repo view "$repo" >/dev/null 2>&1; then
    local visibility
    visibility="$(gh repo view "$repo" --json visibility --jq .visibility)"
    if [[ "$visibility" != "PRIVATE" ]]; then
      echo "Refusing to push: $repo is not private." >&2
      exit 1
    fi
    if git -C "$project_root" remote get-url origin >/dev/null 2>&1; then
      git -C "$project_root" remote set-url origin "https://github.com/$repo.git"
    else
      git -C "$project_root" remote add origin "https://github.com/$repo.git"
    fi
    git -C "$project_root" push -u origin main
  else
    gh repo create "$repo" --private --source "$project_root" --remote origin --push
  fi
  echo "Private repository published: https://github.com/$repo"
}

upload_secrets() {
  require_command gh
  require_command base64
  require_command keytool
  gh auth status >/dev/null
  [[ -s "$keystore_path" && -s "$signing_properties" ]] || generate_key
  local repo
  repo="$(resolve_repo "${1:-}")"
  gh repo view "$repo" >/dev/null

  local expected_fingerprint
  local actual_fingerprint
  local store_password
  local key_alias
  expected_fingerprint="$(tr -d '[:space:]:' < "$project_root/ANDROID_APP_LINK_SHA256.txt" |
    tr '[:lower:]' '[:upper:]')"
  store_password="$(read_property storePassword)"
  key_alias="$(read_property keyAlias)"
  actual_fingerprint="$(keytool -list -v \
    -keystore "$keystore_path" \
    -storepass "$store_password" \
    -alias "$key_alias" |
    sed -n 's/^[[:space:]]*SHA256: //p' |
    head -n 1 |
    tr -d '[:space:]:' |
    tr '[:lower:]' '[:upper:]')"
  [[ "${#expected_fingerprint}" -eq 64 &&
    "$actual_fingerprint" == "$expected_fingerprint" ]] || {
    echo "Refusing to upload a signing key with the wrong Android identity." >&2
    echo "Expected: $expected_fingerprint" >&2
    echo "Actual:   $actual_fingerprint" >&2
    exit 1
  }

  base64 -w 0 "$keystore_path" | gh secret set ANDROID_KEYSTORE_BASE64 --repo "$repo"
  gh secret set ANDROID_KEYSTORE_PASSWORD --repo "$repo" --body "$store_password"
  gh secret set ANDROID_KEY_ALIAS --repo "$repo" --body "$key_alias"
  gh secret set ANDROID_KEY_PASSWORD --repo "$repo" --body "$(read_property keyPassword)"
  unset store_password
  echo "Encrypted GitHub Actions signing secrets configured."
}

build_release() {
  require_command gh
  local repo
  repo="$(resolve_repo "${1:-}")"
  gh workflow run android-release.yml --repo "$repo" --ref main
  sleep 5
  local run_id
  run_id="$(gh run list \
    --repo "$repo" \
    --workflow android-release.yml \
    --branch main \
    --limit 1 \
    --json databaseId \
    --jq '.[0].databaseId')"
  [[ -n "$run_id" && "$run_id" != "null" ]] || {
    echo "Could not find the GitHub Actions run." >&2
    exit 1
  }
  gh run watch "$run_id" --repo "$repo" --exit-status
  mkdir -p "$project_root/release"
  gh run download "$run_id" \
    --repo "$repo" \
    --name NAV-KURD-9.0.0-signed-release \
    --dir "$project_root/release"
  echo "Signed APK/AAB files downloaded to: $project_root/release"
}

command_name="${1:-help}"
repo_argument="${2:-}"
case "$command_name" in
  setup) setup_termux ;;
  check) check_tree ;;
  key) generate_key ;;
  publish) publish_repo "$repo_argument" ;;
  secrets) upload_secrets "$repo_argument" ;;
  build) build_release "$repo_argument" ;;
  all)
    generate_key
    publish_repo "$repo_argument"
    upload_secrets "$repo_argument"
    build_release "$repo_argument"
    ;;
  help|-h|--help) usage ;;
  *)
    usage
    exit 2
    ;;
esac
