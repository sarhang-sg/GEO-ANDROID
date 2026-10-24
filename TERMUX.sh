#!/usr/bin/env bash
set -Eeuo pipefail
nav_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$nav_root"
nav_version="$(sed -n 's/^version:[[:space:]]*\([^+]*\)+.*/\1/p' pubspec.yaml)"
nav_code="$(sed -n 's/^version:.*+\([0-9]*\).*/\1/p' pubspec.yaml)"
case "${1:-help}" in
  validate)
    command -v python3 >/dev/null || { echo 'Python is required.' >&2; exit 1; }
    if head -c 48 android/app/src/main/assets/nav_kurd_core/catalog.sqlite | grep -q '^version https://git-lfs'; then
      [[ -d .git ]] || { echo 'This source archive contains a Git LFS pointer. Download the complete source ZIP or clone with git lfs.' >&2; exit 1; }
      git lfs pull --include='android/app/src/main/assets/nav_kurd_core/catalog.sqlite' --exclude=''
    fi
    python3 tools/update-source-manifest.py --check
    python3 tools/verify-local-data.py
    bash tools/validate-source.sh
    ;;
  download|update)
    command -v gh >/dev/null || { echo 'Install the GitHub CLI and sign in before downloading.' >&2; exit 1; }
    command -v python3 >/dev/null || { echo 'Python is required.' >&2; exit 1; }
    nav_downloads="${NAV_KURD_DOWNLOADS:-/storage/emulated/0/Download}"
    mkdir -p "$nav_downloads"
    nav_staging="$(mktemp -d "$nav_downloads/.nav-kurd-download.XXXXXX")"
    trap 'rm -rf "$nav_staging"' EXIT
    gh release view "v$nav_version" --repo sarhang-sg/GEO-ANDROID \
      --json isDraft,isPrerelease,publishedAt > "$nav_staging/RELEASE-STATUS.json"
    # A missing release fails instead of downloading a previous version.
    gh release download "v$nav_version" --repo sarhang-sg/GEO-ANDROID \
      --pattern "NAV-KURD-$nav_version.apk" --pattern DOWNLOAD-RECEIPT.json --dir "$nav_staging"
    python3 - "$nav_staging" "$nav_version" "$nav_code" "$nav_root/ANDROID_APP_LINK_SHA256.txt" <<'RECEIPT'
import hashlib,json,pathlib,sys
folder=pathlib.Path(sys.argv[1]);version=sys.argv[2];code=int(sys.argv[3])
status=json.loads((folder/'RELEASE-STATUS.json').read_text())
if status.get('isDraft') is not False or status.get('isPrerelease') is not False or not status.get('publishedAt'):
 raise SystemExit('The exact release must be public and final before downloading.')
r=json.loads((folder/'DOWNLOAD-RECEIPT.json').read_text())
source=pathlib.Path(sys.argv[4]).parent/'SOURCE_MANIFEST.sha256'
if r.get('sourceManifestSha256')!=hashlib.sha256(source.read_bytes()).hexdigest():
 raise SystemExit('Release receipt belongs to a different source manifest.')
cert=pathlib.Path(sys.argv[4]).read_text().replace(':','').strip().upper()
if (r.get('versionName'),r.get('versionCode'),r.get('packageId'),r.get('signingCertificateSha256'))!=(version,code,'com.navkurd.app',cert):
 raise SystemExit('Release identity/certificate receipt does not match.')
expected=r['files']['apk'];apk=folder/f'NAV-KURD-{version}.apk'
if expected['name']!=apk.name or apk.stat().st_size!=expected['bytes']:
 raise SystemExit('APK size/name does not match.')
with apk.open('rb') as f:
 if hashlib.file_digest(f,'sha256').hexdigest()!=expected['sha256']:raise SystemExit('APK digest does not match.')
RECEIPT
    mv -f "$nav_staging/NAV-KURD-$nav_version.apk" "$nav_downloads/NAV-KURD-$nav_version.apk"
    printf 'Verified APK: %s\n' "$nav_downloads/NAV-KURD-$nav_version.apk"
    ;;
  *) printf '%s\n' 'Usage: bash TERMUX.sh validate|download' ;;
esac
