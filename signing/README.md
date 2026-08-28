# NAV KURD release identity

The public certificate description and SHA-256 fingerprint in this directory
identify the real NAV KURD update key. The private JKS and its passwords are
deliberately excluded from source ZIPs and Git. GitHub Actions reconstructs the
JKS only for a release build from these encrypted repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Never replace those secrets for an existing installed app. A differently
signed APK cannot update the current installation. The release workflow checks
every universal APK against `ANDROID_APP_LINK_SHA256.txt` before publishing the
artifact and deletes temporary signing material in its final step.
