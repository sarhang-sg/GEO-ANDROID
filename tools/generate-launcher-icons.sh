#!/usr/bin/env bash
set -Eeuo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_image="$project_root/tools/assets/nav-kurd-launcher-source.png"
expected_sha256="bacc220ac47f0ade5c79efbd35228c61fcea70c304922564218474e245903f63"
res_root="$project_root/android/app/src/main/res"

test -f "$source_image" || { printf 'Launcher source is missing: %s\n' "$source_image" >&2; exit 1; }
command -v convert >/dev/null 2>&1 || { printf 'ImageMagick convert is required.\n' >&2; exit 1; }
actual_sha256="$(sha256sum "$source_image" | awk '{print $1}')"
test "$actual_sha256" = "$expected_sha256" || {
  printf 'Launcher source SHA-256 mismatch.\nExpected: %s\nActual:   %s\n' "$expected_sha256" "$actual_sha256" >&2
  exit 1
}

render_icon() {
  local target="$1"
  local size="$2"
  mkdir -p "$(dirname "$target")"
  convert "$source_image" \
    -filter Lanczos \
    -resize "${size}x${size}!" \
    -alpha off \
    -colorspace sRGB \
    -strip \
    -interlace none \
    -define png:color-type=2 \
    "PNG24:$target"
}

for spec in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
  density="${spec%%:*}"
  size="${spec##*:}"
  render_icon "$res_root/mipmap-$density/ic_launcher.png" "$size"
  render_icon "$res_root/mipmap-$density/ic_launcher_round.png" "$size"
done

for spec in mdpi:108 hdpi:162 xhdpi:216 xxhdpi:324 xxxhdpi:432; do
  density="${spec%%:*}"
  size="${spec##*:}"
  render_icon "$res_root/mipmap-$density/ic_launcher_foreground.png" "$size"
done

python3 "$project_root/tools/verify-launcher-pngs.py"
printf 'Generated 15 launcher assets from the approved NAV KURD artwork.\n'
