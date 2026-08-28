#!/usr/bin/env bash
set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
signing_dir="$project_root/signing"
keystore_path="$signing_dir/nav-kurd-release.jks"
properties_path="$signing_dir/signing.properties"
certificate_path="$signing_dir/CERTIFICATE.txt"
fingerprint_path="$signing_dir/ANDROID_APP_LINK_SHA256.txt"

for command_name in openssl keytool; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
done

mkdir -p "$signing_dir"
umask 077

if [[ -e "$keystore_path" || -e "$properties_path" ]]; then
  echo "Signing material already exists; nothing was overwritten."
  exit 0
fi

if [[ -s "$fingerprint_path" && "${NAV_KURD_CREATE_NEW_APP_KEY:-}" != "YES" ]]; then
  echo "Refusing to replace the established NAV KURD update identity." >&2
  echo "Restore the original private JKS or use the existing GitHub Actions secrets." >&2
  echo "Only a genuinely new application may set NAV_KURD_CREATE_NEW_APP_KEY=YES." >&2
  exit 1
fi

store_password="$(openssl rand -hex 24)"
key_password="$(openssl rand -hex 24)"
key_alias="navkurd"

keytool -genkeypair \
  -keystore "$keystore_path" \
  -storetype JKS \
  -storepass "$store_password" \
  -keypass "$key_password" \
  -alias "$key_alias" \
  -keyalg RSA \
  -keysize 4096 \
  -sigalg SHA256withRSA \
  -validity 10000 \
  -dname "CN=Sarhang Salah, OU=NAV KURD, O=SARHANG IO, L=Sulaymaniyah, ST=Kurdistan Region, C=IQ" \
  -noprompt >/dev/null 2>&1

{
  printf 'storePassword=%s\n' "$store_password"
  printf 'keyPassword=%s\n' "$key_password"
  printf 'keyAlias=%s\n' "$key_alias"
  printf 'storeFile=nav-kurd-release.jks\n'
} > "$properties_path"

keytool -list -v \
  -keystore "$keystore_path" \
  -storepass "$store_password" \
  -alias "$key_alias" > "$certificate_path"
sed -n 's/^[[:space:]]*SHA256: //p' "$certificate_path" > "$fingerprint_path"

chmod 600 "$keystore_path" "$properties_path"
chmod 644 "$certificate_path" "$fingerprint_path"

echo "NAV KURD release signing material created in: $signing_dir"
echo "Keep nav-kurd-release.jks and signing.properties private and backed up."
