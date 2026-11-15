# NAV KURD 11.0.0 security policy

Report vulnerabilities privately to **sarhang.salah9@gmail.com**. Include the app version, Android version, device model, affected feature and reproduction steps. Remove account, precise location and credential data from logs.

## Device and account data

The WebView restricts native operations to the trusted HTTPS application origin. The shared map uses scoped Supabase sessions. Weather synchronization uses app-private preferences and cached observations. GPS and notification access are governed by Android runtime permissions. Background location and alerts depend on the permissions the user has granted.

## Software integrity and signing

The project pins release tooling, verifies the native offline catalog and checks the SHA-256 source and presentation manifests. Signing is configured by the established private keystore in CI. Keep key properties, keystores, passwords and service credentials outside source control. Production receipts bind the APK and AAB to the source commit, version, source manifest and expected certificate listed in `ANDROID_APP_LINK_SHA256.txt`.

Use the Termux downloader or verify the signed release receipt and APK certificate before sideloading an update. A compromised signing key requires the owner’s Android signing-key recovery process.

[Public disclosure policy](https://geo-map-kappa.vercel.app/legal/security.html)
