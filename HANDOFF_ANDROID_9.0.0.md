# Fresh-chat handoff — NAV KURD Android 9.0.0

Use this file when continuing the Android work in a new chat.

## Product identity

- Flutter project: this repository root
- Package: `com.navkurd.app`
- Version: `9.0.0+90001`
- Canonical trusted origin: `https://geo-map-kappa.vercel.app`
- Canonical private repository: `sarhang-sg/GEO-ANDROID`
- CI workflow: `.github/workflows/android-release.yml`

## Architecture

Flutter owns lifecycle and the visible Android shell. A hardened
`flutter_inappwebview` hosts the canonical web GIS. Kotlin owns downloads, the
system image picker, native sharing, MediaStore, notifications, deep links,
diagnostics, the home widget and real device information. JavaScript handlers
are registered only for the trusted origin.

## Important implementation files

- `lib/src/nav_kurd_page.dart` — WebView lifecycle, trusted handlers and resume
  events.
- `lib/src/native_bridge.dart` — typed Dart↔Kotlin channel.
- `android/app/src/main/kotlin/com/navkurd/app/MainActivity.kt` — native
  operations.
- `NavKurdWidgetProvider.kt` / `NavKurdWidgetArtwork.kt` — real weather data,
  localization, rendered widget scenes and 30-minute refresh.
- `NavKurdNotification*.kt` — daily weather and semantic release checks.
- `NavKurdRuntimeInfo.kt` — actual CPU/RAM/screen/EGL/storage capability data.
- `tools/validate-source.sh` — fast source gate.

## Signing rules

The installed app identity must remain the certificate SHA-256 stored in
`ANDROID_APP_LINK_SHA256.txt`. Private JKS/password files must never be added to
Git or a normal source ZIP. GitHub Actions expects the four existing encrypted
secrets named in the workflow. Never generate a replacement key for an update.

## Build and retrieve from Termux

The verified Web 9.0.0 release is already complete. Put the Android ZIP, its
`.sha256` sidecar and `NAV-KURD-v9.0.0-ANDROID-TERMUX.sh` with its `.sha256`
sidecar in Android Download. After confirming the final canonical URL is live,
run:

```bash
termux-setup-storage
cd /storage/emulated/0/Download
sha256sum -c NAV-KURD-v9.0.0-ANDROID.zip.sha256
sha256sum -c NAV-KURD-v9.0.0-ANDROID-TERMUX.sh.sha256
chmod +x NAV-KURD-v9.0.0-ANDROID-TERMUX.sh
bash NAV-KURD-v9.0.0-ANDROID-TERMUX.sh
```

The script validates source, creates only private `sarhang-sg/GEO-ANDROID`,
fingerprint-gates the established JKS before uploading encrypted Actions
secrets, runs analyze/tests/build/signature checks, downloads the artifact and
verifies its SHA-256 and certificate. The same run then adds only the verified
direct APK and generated download/release metadata on a Web review branch,
waits for the complete quality/Chromium workflow, and merges only after it is
green. It never replaces the completed Web UI or runtime source.

## Before release

1. `bash tools/validate-source.sh`
2. Run the GitHub Actions workflow and require a green analyze/test/build.
3. Install `NAV-KURD-9.0.0.apk` over 8.0.2 on a physical Android 7+ device.
4. Verify GPS resume, all three languages, widget refresh, notification
   permission/channel behavior, offline-pack persistence and scoped downloads.
5. Copy the signed APK into the web project at
   `public/downloads/NAV-KURD-9.0.0.apk`, rebuild/deploy web, and verify the
   public file SHA-256 matches the CI artifact.
6. Submit APKPure using `docs/APKPURE_9.0.0.md`.

## Platform truth

Continuous Lottie/SVG motion is not supported inside Android launcher
`RemoteViews`. The widget uses a rich state-driven bitmap frame that changes
with real weather/time/season and each scheduled refresh. Animated SVG weather
art runs continuously inside the app/web surface.

## Completed

- Android identity, API levels and version are fixed at `com.navkurd.app`,
  API 24–36 and `9.0.0+90001`.
- Flutter lifecycle/WebView shell, trusted native bridge, GPS resume recovery,
  scoped downloads, offline persistence, permissions and renderer recovery are
  implemented.
- Multilingual widget, scheduled weather/update notifications and real
  hardware/runtime diagnostics are implemented.
- The Android photo input now uses the system image picker, sharing uses the
  native Android chooser, and malformed Web share URLs no longer escape as
  unhandled promise errors.
- Search/shared-location/region focus explicitly stops GPS camera-follow while
  preserving the live marker; physical Android insets are normalized to CSS
  pixels so search stays near the top.
- The compact Android settings actions, synchronized three-language widget,
  consistent tutorial icons, simple loader and premium shared UI are included;
  the red support/payment section is intentionally unchanged.
- The signed workflow builds universal and per-ABI APKs plus AAB, verifies
  package/version/certificate identity and publishes checksums.
- The final production origin is consistent across Dart, Android App Links,
  notification update checks and every workflow build command.
- Satellite mode uses hardware-accelerated hybrid composition with algorithmic
  darkening disabled through the supported WebView API; deprecated `forceDark`
  is excluded so fatal-info analysis stays green.
- Sanitized source ZIP and standalone Termux publisher are prepared and
  checksum-gated.

## Remaining

- Run the supplied Termux publisher from the owner's authenticated
  `sarhang-sg` account so GitHub Actions can compile/sign the release.
- Install the resulting universal APK on a physical Android 7+ device for the
  final GPS/widget/notification/offline smoke test.
- Confirm the publisher's direct-APK Web quality/Chromium run and Vercel
  production deployment, then submit the verified APK to APKPure.

## Changed files

- Release/build: `.github/workflows/android-release.yml`, `pubspec.yaml`,
  `android/app/build.gradle.kts`, Gradle wrapper/settings and ProGuard rules.
- Flutter: `lib/main.dart`, `lib/src/app*.dart`, `native_bridge.dart`,
  `nav_kurd_page.dart`, `permission_coordinator.dart`, `url_policy.dart` and
  their tests.
- Android native: `AndroidManifest.xml`, `MainActivity.kt`,
  `NavKurdNotification*.kt`, `NavKurdRuntimeInfo.kt`,
  `NavKurdWidget*.kt`, widget layouts/drawables/fonts and XML configuration.
- Release operations: `TERMUX.sh`,
  `NAV-KURD-V9-UPDATE-UPLOAD-BUILD.sh`, `tools/*`, `UPDATE_PATHS.txt`,
  `SOURCE_MANIFEST.sha256`, release/APKPure docs, README, status and checklist.
- Public signing metadata: `ANDROID_APP_LINK_SHA256.txt` and `signing/*` public
  records. Private JKS/password files remain excluded.

## Build, signing and artifact status

- Source/type/shell gate: PASS (`tools/validate-source.sh`, `TERMUX.sh check`,
  embedded JavaScript syntax and shell syntax).
- Android release compile: pending only because this workspace has no Flutter
  SDK; the pinned GitHub Actions job is the authoritative compile gate.
- Signing identity: PASS. The preserved update certificate matches the public
  SHA-256 record; the private key is not present in the source archive.
- Android source archive: `NAV-KURD-v9.0.0-ANDROID.zip`.
- Signed APK target after Actions: `NAV-KURD-9.0.0.apk` plus per-ABI APKs.
- AAB target after Actions: `NAV-KURD-9.0.0.aab`.
- Web production: complete at `https://geo-map-kappa.vercel.app`.
- Known issues: no known source-gate failures. Signed binaries remain pending
  until the owner runs the Termux publisher.

## Current release checkpoint — 2026-08-29

- `bash tools/validate-source.sh`: PASS.
- Version/application ID gate: PASS (`9.0.0+90001`, `com.navkurd.app`).
- Canonical Android build origin gate: PASS
  (`https://geo-map-kappa.vercel.app`; retired origin rejected).
- Complete sanitized Android source ZIP and standalone Termux publisher:
  prepared with SHA-256 sidecars; private signing material is excluded.
- Existing update certificate fingerprint: verified against
  `ANDROID_APP_LINK_SHA256.txt`.
- Web typecheck, 166-module production build, offline runtime, security,
  platform, PMTiles, dependency and release-integrity gates: PASS.
- Android source gate, XML parsing, embedded JavaScript syntax and shell syntax:
  PASS after the native image/share bridge and widget synchronization patches.
- Signed APK/AAB: pending. The abandoned old-account runner returned a pre-job
  startup failure; no compile or signing step ran.
- Exact next step: run `NAV-KURD-v9.0.0-ANDROID-TERMUX.sh`. It creates or
  updates private `sarhang-sg/GEO-ANDROID`, uploads the four
  fingerprint-verified signing secrets, runs `android-release.yml`, then
  verifies and retrieves the signed APK/AAB artifact. It then updates private
  `sarhang-sg/GEO-MAP`, requires the quality/Chromium workflow to pass, and
  publishes the same verified APK as the direct download.
