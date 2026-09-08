# NAV KURD release identity

The public certificate description in this directory and the canonical
`../ANDROID_APP_LINK_SHA256.txt` fingerprint identify the real NAV KURD update
key. The private JKS and its passwords are
deliberately excluded from source ZIPs and Git. GitHub Actions reconstructs the
JKS only for a release build from these encrypted repository secrets:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Never replace those secrets for an existing installed app. A differently
signed APK cannot update the current installation. The release workflow checks
every universal APK against the root `ANDROID_APP_LINK_SHA256.txt` before publishing the
artifact and deletes temporary signing material in its final step.
