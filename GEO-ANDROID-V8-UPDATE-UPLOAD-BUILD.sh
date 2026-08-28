#!/usr/bin/env bash
set -Eeuo pipefail

readonly download_dir="/storage/emulated/0/Download"
readonly project_dir="$HOME/GEO-ANDROID-SARHANG-SG"
readonly legacy_project_dir="$HOME/GEO-ANDROID"
readonly repo_name="sarhang-sg/GEO-ANDROID"
readonly workflow_name="android-release.yml"
readonly artifact_name="NAV-KURD-8.0.4-signed-release"
temp_dir=""
backup_stash=""

cleanup() {
  if [[ -n "$temp_dir" && "$temp_dir" == "$HOME"/.geo-android-v8.* ]]; then
    rm -rf -- "$temp_dir"
  fi
}
trap cleanup EXIT

die() {
  echo "ERROR: $*" >&2
  exit 1
}

retry() {
  local attempt=1
  local maximum=12
  until "$@"; do
    if (( attempt >= maximum )); then
      return 1
    fi
    echo "Network retry $attempt/$maximum..." >&2
    sleep $(( attempt < 5 ? attempt * 3 : 15 ))
    attempt=$((attempt + 1))
  done
}

echo "1/9 — Preparing Termux..."
[[ -d "$download_dir" ]] || {
  termux-setup-storage
  die "Android storage permission was requested. Allow it, then run this script again."
}

missing_packages=()
command -v git >/dev/null 2>&1 || missing_packages+=(git)
command -v gh >/dev/null 2>&1 || missing_packages+=(gh)
command -v curl >/dev/null 2>&1 || missing_packages+=(curl)
command -v unzip >/dev/null 2>&1 || missing_packages+=(unzip)
command -v zip >/dev/null 2>&1 || missing_packages+=(zip)
command -v sha256sum >/dev/null 2>&1 || missing_packages+=(coreutils)
if (( ${#missing_packages[@]} )); then
  pkg update -y
  pkg install -y "${missing_packages[@]}"
fi
termux-wake-lock 2>/dev/null || true

for required in git gh curl unzip sha256sum; do
  command -v "$required" >/dev/null 2>&1 || die "Missing command after setup: $required"
done
retry gh auth status -h github.com >/dev/null 2>&1 ||
  die "Run 'gh auth login', choose GitHub.com + HTTPS + web browser, then rerun."

account="$(retry gh api user --jq .login)"
[[ "$account" == "sarhang-sg" ]] ||
  die "The active GitHub account is $account; sign in as sarhang-sg."

repo_has_main=false
if gh repo view "$repo_name" >/dev/null 2>&1; then
  visibility="$(retry gh repo view "$repo_name" --json visibility --jq .visibility)"
  [[ "$visibility" == "PRIVATE" ]] || die "$repo_name must remain PRIVATE."
else
  echo "Creating the fresh private Android repository..."
  retry gh repo create "$repo_name" \
    --private \
    --description "NAV KURD 8.0.4 Flutter Android"
fi
if gh api "repos/$repo_name/branches/main" >/dev/null 2>&1; then
  repo_has_main=true
fi

echo "2/9 — Verifying the final source ZIP..."
source_zip="$(find "$download_dir" -maxdepth 2 -type f \
  -name 'NAV-KURD-v8.0.4-ANDROID.zip' \
  -printf '%T@ %p\n' 2>/dev/null |
  sort -nr | head -n 1 | cut -d' ' -f2-)"
[[ -n "$source_zip" && -s "$source_zip" ]] ||
  die "NAV-KURD-v8.0.4-ANDROID.zip was not found in Download."
checksum_file="$source_zip.sha256"
if [[ ! -s "$checksum_file" ]]; then
  checksum_file="$(find "$download_dir" -maxdepth 2 -type f \
    -name 'SHA256SUMS.txt' \
    -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
fi
[[ -n "$checksum_file" && -s "$checksum_file" ]] ||
  die "The source ZIP checksum file is missing."
source_name="$(basename "$source_zip")"
expected_source_hash="$(awk -v file="$source_name" '$2 == file || $2 == "*" file { print $1; exit }' "$checksum_file" | tr '[:upper:]' '[:lower:]')"
[[ "$expected_source_hash" =~ ^[0-9a-f]{64}$ ]] ||
  die "The checksum list has no valid entry for $source_name."
actual_source_hash="$(sha256sum "$source_zip" | awk '{ print $1 }')"
[[ "$actual_source_hash" == "$expected_source_hash" ]] ||
  die "The source ZIP SHA-256 checksum does not match."
echo "$(basename "$source_zip"): OK"
unzip -tq "$source_zip" >/dev/null || die "The source ZIP is damaged."
if unzip -Z1 "$source_zip" |
  grep -E '(^|/)([^/]*\.(jks|keystore)|signing\.properties|key\.properties)$' >/dev/null; then
  die "Private signing material must not be inside the source ZIP."
fi

temp_dir="$(mktemp -d "$HOME/.geo-android-v8.XXXXXX")"
unzip -q "$source_zip" -d "$temp_dir/source"
source_root="$(find "$temp_dir/source" -maxdepth 2 -type f -name pubspec.yaml \
  -print -quit | xargs -r dirname)"
[[ -n "$source_root" && -s "$source_root/UPDATE_PATHS.txt" ]] ||
  die "The source archive has no valid UPDATE_PATHS.txt."
[[ -s "$source_root/SOURCE_MANIFEST.sha256" ]] ||
  die "The source archive has no source manifest."
(
  cd "$source_root"
  sha256sum -c SOURCE_MANIFEST.sha256
  bash tools/validate-source.sh
  git init -q
  git add -A
  git -c core.whitespace=cr-at-eol diff --cached --check
  rm -rf -- .git
)

echo "3/9 — Preparing a clean review branch..."
if [[ -e "$project_dir" && ! -d "$project_dir/.git" ]]; then
  die "The Android workspace exists but is not a Git repository: $project_dir"
fi
if [[ ! -d "$project_dir/.git" ]]; then
  retry gh repo clone "$repo_name" "$project_dir"
fi
[[ -d "$project_dir/.git" ]] || die "Git repository is unavailable: $project_dir"
git -C "$project_dir" remote set-url origin "https://github.com/$repo_name.git"
if [[ -n "$(git -C "$project_dir" status --porcelain --untracked-files=all)" ]]; then
  backup_label="NAV-KURD-8.0.4-SAFE-BACKUP-$(date -u +%Y%m%d-%H%M%S)"
  git -C "$project_dir" stash push --include-untracked -m "$backup_label" >/dev/null
  backup_stash="$(git -C "$project_dir" stash list -1 --format='%gd %s')"
  [[ -z "$(git -C "$project_dir" status --porcelain --untracked-files=all)" ]] ||
    die "The existing local edits could not be preserved safely."
  echo "Existing local edits were preserved in: $backup_stash"
fi

if [[ "$repo_has_main" == true ]]; then
  retry git -C "$project_dir" -c http.version=HTTP/1.1 fetch origin main
  git -C "$project_dir" switch main
  git -C "$project_dir" merge --ff-only origin/main
  branch_name="codex/nav-kurd-v8-$(date -u +%Y%m%d-%H%M%S)-$$"
  git -C "$project_dir" switch -c "$branch_name"
else
  branch_name="main"
  git -C "$project_dir" switch -C main
fi

while IFS= read -r relative || [[ -n "$relative" ]]; do
  [[ -z "$relative" || "$relative" == \#* ]] && continue
  [[ "$relative" != /* && "$relative" != *".."* ]] ||
    die "Unsafe update path: $relative"
  [[ -e "$source_root/$relative" ]] || die "Missing source path: $relative"
  if [[ -d "$source_root/$relative" ]]; then
    mkdir -p "$project_dir/$relative"
    cp -a "$source_root/$relative/." "$project_dir/$relative/"
  else
    mkdir -p "$(dirname "$project_dir/$relative")"
    cp -a "$source_root/$relative" "$project_dir/$relative"
  fi
done < "$source_root/UPDATE_PATHS.txt"

(
  cd "$project_dir"
  bash tools/validate-source.sh
  while IFS= read -r relative || [[ -n "$relative" ]]; do
    [[ -z "$relative" || "$relative" == \#* ]] && continue
    git add -A -- "$relative"
  done < UPDATE_PATHS.txt
  git diff --cached --check
)

if git -C "$project_dir" diff --cached --quiet && [[ "$repo_has_main" == true ]]; then
  echo "The repository already contains NAV KURD 8.0.4."
  git -C "$project_dir" switch main
  git -C "$project_dir" branch -D "$branch_name"
  build_ref="main"
  pull_request_url=""
else
  git -C "$project_dir" config user.name \
    "$(git -C "$project_dir" config user.name || gh api user --jq .login)"
  git -C "$project_dir" config user.email \
    "$(git -C "$project_dir" config user.email ||
      printf '%s+%s@users.noreply.github.com' \
        "$(gh api user --jq .id)" "$(gh api user --jq .login)")"
  git -C "$project_dir" commit -m "Release NAV KURD Android 8.0.4"

  echo "4/9 — Uploading the root fixes..."
  if [[ "$repo_has_main" == true ]]; then
    retry git -C "$project_dir" -c http.version=HTTP/1.1 push -u origin "$branch_name"
    pull_request_url="$(retry gh pr create \
      --repo "$repo_name" \
      --base main \
      --head "$branch_name" \
      --draft \
      --title "NAV KURD Android 8.0.4" \
      --body "Android 8.0.4: GPS resume recovery, multilingual state-rendered weather widget, daily weather and update notifications, real hardware diagnostics, secure downloads and verified release signing.")"
    build_ref="$branch_name"
  else
    retry git -C "$project_dir" -c http.version=HTTP/1.1 push -u origin main
    build_ref="main"
    pull_request_url=""
  fi
fi

if [[ ! -s "$project_dir/signing/nav-kurd-release.jks" ||
  ! -s "$project_dir/signing/signing.properties" ]]; then
  if [[ -s "$legacy_project_dir/signing/nav-kurd-release.jks" &&
    -s "$legacy_project_dir/signing/signing.properties" ]]; then
    echo "Restoring the established private update key from the preserved Android workspace..."
    mkdir -p "$project_dir/signing"
    cp -p "$legacy_project_dir/signing/nav-kurd-release.jks" \
      "$project_dir/signing/nav-kurd-release.jks"
    cp -p "$legacy_project_dir/signing/signing.properties" \
      "$project_dir/signing/signing.properties"
    chmod 600 "$project_dir/signing/nav-kurd-release.jks" \
      "$project_dir/signing/signing.properties"
  fi
fi

if command -v keytool >/dev/null 2>&1 &&
  [[ -s "$project_dir/signing/nav-kurd-release.jks" &&
    -s "$project_dir/signing/signing.properties" ]]; then
  echo "Refreshing the fingerprint-verified GitHub signing secrets..."
  retry bash "$project_dir/TERMUX.sh" secrets "$repo_name"
else
  existing_secret_count="$(gh secret list --repo "$repo_name" --json name \
    --jq '[.[].name | select(. == "ANDROID_KEYSTORE_BASE64" or . == "ANDROID_KEYSTORE_PASSWORD" or . == "ANDROID_KEY_ALIAS" or . == "ANDROID_KEY_PASSWORD")] | length')"
  [[ "$existing_secret_count" == "4" ]] ||
    die "The established signing JKS was not found. Restore $legacy_project_dir/signing before building."
  echo "Using the four existing encrypted GitHub signing secrets."
fi

echo "5/9 — Starting the signed Android workflow..."
head_sha="$(git -C "$project_dir" rev-parse "$build_ref")"
retry gh workflow run "$workflow_name" --repo "$repo_name" --ref "$build_ref"

run_id=""
for _ in $(seq 1 60); do
  run_id="$(gh run list \
    --repo "$repo_name" \
    --workflow "$workflow_name" \
    --branch "$build_ref" \
    --event workflow_dispatch \
    --limit 20 \
    --json databaseId,headSha \
    --jq "map(select(.headSha == \"$head_sha\"))[0].databaseId // empty" 2>/dev/null || true)"
  [[ -n "$run_id" ]] && break
  sleep 5
done
[[ -n "$run_id" ]] || die "Could not find the newly dispatched workflow."
echo "Run: https://github.com/$repo_name/actions/runs/$run_id"

echo "6/9 — Waiting for tests and signed build..."
while true; do
  run_state="$(retry gh api "repos/$repo_name/actions/runs/$run_id" \
    --jq '.status + "|" + (.conclusion // "")')"
  status="${run_state%%|*}"
  conclusion="${run_state#*|}"
  printf 'Status: %s%s\n' "$status" "${conclusion:+ / $conclusion}"
  [[ "$status" == "completed" ]] && break
  sleep 15
done

if [[ "$conclusion" != "success" ]]; then
  error_log="$download_dir/GEO-ANDROID-V8-ERROR-$run_id.txt"
  failed_log="$temp_dir/GEO-ANDROID-V8-FAILED-$run_id.txt"
  failed_log_ready=false
  for attempt in $(seq 1 8); do
    if gh run view "$run_id" --repo "$repo_name" --log-failed \
        > "$failed_log" 2>&1 &&
      [[ -s "$failed_log" ]] &&
      ! grep -qiE \
        'error connecting|could not resolve host|failed to connect|connection timed out' \
        "$failed_log"; then
      failed_log_ready=true
      break
    fi
    sleep 10
  done
  {
    echo "NAV KURD Android workflow failed"
    echo "Run: https://github.com/$repo_name/actions/runs/$run_id"
    echo "Status: $status"
    echo "Conclusion: $conclusion"
    echo
    if [[ "$failed_log_ready" == true ]]; then
      cat "$failed_log"
    else
      echo "Raw failed-step log was unavailable after eight retries."
      [[ ! -s "$failed_log" ]] || cat "$failed_log"
    fi
    echo
    echo "=== JOBS AND STEPS ==="
    gh api "repos/$repo_name/actions/runs/$run_id/jobs?per_page=100" \
      --jq '.jobs[] |
        "JOB\t\(.id)\t\(.name)\t\(.status)\t\(.conclusion)",
        (.steps[] | "STEP\t\(.number)\t\(.name)\t\(.status)\t\(.conclusion)")' \
      2>&1 || true
    echo
    echo "=== FAILURE ANNOTATIONS ==="
    while read -r job_id; do
      [[ -n "$job_id" ]] || continue
      echo "--- JOB $job_id ---"
      gh api --paginate \
        "repos/$repo_name/check-runs/$job_id/annotations?per_page=100" \
        --jq '.[] |
          "[\(.annotation_level)] \(.path // "-"):\(.start_line // 0) \(.title // "")\n\(.message // "")\n\(.raw_details // "")"' \
        2>&1 || true
    done < <(
      gh api "repos/$repo_name/actions/runs/$run_id/jobs?per_page=100" \
        --jq '.jobs[] | select(.conclusion == "failure") | .id' \
        2>/dev/null || true
    )
  } > "$error_log"
  die "Build failed. Non-empty log saved to: $error_log"
fi

echo "7/9 — Downloading the signed artifact with resume support..."
artifact_id="$(retry gh api "repos/$repo_name/actions/runs/$run_id/artifacts?per_page=100" \
  --jq ".artifacts[] | select(.name == \"$artifact_name\" and .expired == false) | .id" |
  head -n 1)"
[[ -n "$artifact_id" ]] || die "Signed release artifact was not found."
artifact_zip="$temp_dir/$artifact_name.zip"
artifact_part="$artifact_zip.part"
github_token="$(gh auth token)"
for attempt in $(seq 1 20); do
  if [[ -s "$artifact_part" ]] && unzip -tq "$artifact_part" >/dev/null 2>&1; then
    mv "$artifact_part" "$artifact_zip"
    break
  fi
  echo "Artifact download attempt $attempt/20 ($(stat -c %s "$artifact_part" 2>/dev/null || echo 0) bytes saved)..."
  curl -fL \
    --continue-at - \
    --connect-timeout 30 \
    --max-time 1800 \
    --retry 5 \
    --retry-delay 5 \
    --retry-all-errors \
    --speed-limit 1024 \
    --speed-time 120 \
    -H "Accept: application/vnd.github+json" \
    -H "Authorization: Bearer $github_token" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$repo_name/actions/artifacts/$artifact_id/zip" \
    -o "$artifact_part" || true
done
unset github_token
if [[ ! -s "$artifact_zip" ]]; then
  if [[ -s "$artifact_part" ]] && unzip -tq "$artifact_part" >/dev/null 2>&1; then
    mv "$artifact_part" "$artifact_zip"
  else
    die "Artifact download did not complete. Run this script again; GitHub keeps it for 30 days."
  fi
fi
unzip -tq "$artifact_zip" >/dev/null || die "Downloaded artifact ZIP is damaged."

release_dir="$download_dir/GEO-ANDROID-V8-RELEASE-$run_id"
mkdir -p "$release_dir"
unzip -oq "$artifact_zip" -d "$release_dir"
(
  cd "$release_dir"
  sha256sum -c SHA256SUMS.txt
)

echo "8/9 — Verifying the real APK certificate..."
universal_apk="$release_dir/NAV-KURD-8.0.4.apk"
[[ -s "$universal_apk" ]] || die "Universal NAV-KURD-8.0.4.apk was not found."
certificate_digest_file="$release_dir/CERTIFICATE_SHA256.txt"
[[ -s "$certificate_digest_file" ]] ||
  die "Verified APK certificate record was not found."
actual_digest="$(tr -d '[:space:]:' < "$certificate_digest_file" |
  tr '[:lower:]' '[:upper:]')"
expected_digest="$(tr -d '[:space:]:' < "$source_root/ANDROID_APP_LINK_SHA256.txt" |
  tr '[:lower:]' '[:upper:]')"
[[ "${#actual_digest}" -eq 64 ]] ||
  die "Verified APK certificate record is malformed."
[[ "$actual_digest" == "$expected_digest" ]] ||
  die "APK signature mismatch. Installation was stopped."
actual_fingerprint="$(printf '%s' "$actual_digest" | sed 's/../&:/g;s/:$//')"

install_apk="$download_dir/NAV-KURD-8.0.4-$run_id.apk"
cp -f "$universal_apk" "$install_apk"

if [[ -n "$pull_request_url" ]]; then
  echo "Merging the build-verified update into private main..."
  retry gh pr ready "$pull_request_url" --repo "$repo_name" >/dev/null
  if retry gh pr merge "$pull_request_url" \
      --repo "$repo_name" --squash --delete-branch; then
    retry git -C "$project_dir" fetch origin main
    git -C "$project_dir" switch main
    git -C "$project_dir" merge --ff-only origin/main
    pull_request_url=""
  else
    echo "GitHub rules kept the verified PR open for manual merge: $pull_request_url" >&2
  fi
fi

echo "9/9 — COMPLETED"
echo "APK: $install_apk"
echo "All APK/AAB files: $release_dir"
echo "Certificate: $actual_fingerprint"
[[ -n "$pull_request_url" ]] && echo "Draft PR: $pull_request_url"
[[ -n "$backup_stash" ]] && echo "Preserved local edits: $backup_stash"
echo "Install this signed APK. Remove the old blank widget once, then add NAV KURD again."
if command -v termux-open >/dev/null 2>&1; then
  termux-open --view "$install_apk" || true
fi
