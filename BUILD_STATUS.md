# Build status

Prepared on 2026-08-30.

## Completed locally

- Audited the supplied NAV KURD web source and confirmed no embedded
  service-role, private-key or provider-secret values were present.
- Updated the Flutter/Dart Android shell and Kotlin platform bridge to
  `9.0.0+90000`.
- Removed both duplicate Android/Flutter launch logos so the deployed animated
  map loader is the only loading screen.
- Added native API-36 immersive mode, scoped offline storage, GPS resume events,
  real widget weather/location and sanitized Android/Flutter/WebView diagnostics.
- Rebuilt the widget with separate RTL/LTR layouts, app-matched fonts,
  Kurdish/Arabic/English copy, timezone-correct local phase/season and
  Canvas-rendered WMO weather/dust/wind/heat/cold art without emoji.
- Added daily weather notifications and a signed-release feed check that never
  alerts the currently installed version.
- Added a trusted bridge for actual CPU, RAM, ABI, physical display, density,
  refresh rate, EGL GPU, storage and safe-area capability values.
- Added a validated `navkurd://auth/callback` path for Google PKCE return from
  Chrome into the existing authenticated WebView session.
- Aligned AGP 9.2.1, Gradle 9.4.1, compile/target SDK 36 and Java 17.
- Validated Android source/XML/embedded JavaScript with the source gate.
- Validated the Termux and signing shell scripts with `bash -n`.
- Preserved the public SHA-256 identity of the existing 4096-bit RSA update
  key; private JKS/passwords remain only in encrypted Actions secrets.
- Added Flutter analysis/tests and a signed GitHub Actions release workflow.
- Aligned every release build with the final production origin
  `https://geo-map-kappa.vercel.app` and added a regression gate that rejects
  the retired origin.
- Added a fresh-account Termux publisher that creates only the private
  `sarhang-sg/GEO-ANDROID` repository, preserves any existing local work,
  reuses the established fingerprint-verified update key and retrieves the
  signed release artifact.
- Added the Android system image picker and native share chooser without a
  third-party picker/share plugin, plus WebView integration restricted to the
  trusted production origin.
- Fixed manual search focus versus GPS camera-follow and normalized Android
  safe-area insets from physical pixels to CSS pixels.
- Reworked the shared Web/Android UI into a compact premium glass system,
  synchronized the widget language immediately, and retained the existing red
  support/payment styling unchanged.
- Completed the Web typecheck, production/offline build, security, platform,
  PMTiles and release-integrity suites successfully.
- Locked Android satellite rendering to hardware-accelerated hybrid composition,
  disabled WebView force-dark/algorithmic darkening and enabled offscreen raster
  preparation so raster satellite tiles do not turn black in the APK.

## Build gate

This workspace does not include a local Flutter SDK, so the signed binary gate
must run in the pinned GitHub Actions Flutter 3.47.1 environment.

The complete Web v9 source has already passed its quality/Chromium/migration
gates and reached private `main`. Use `NAV-KURD-v9.0.0-ANDROID-TERMUX.sh` after
GitHub authentication. It creates
the fresh private repository (or a review branch when `main` already exists),
dispatches the signed workflow, waits for all checks, verifies the checksum and
certificate, and downloads the APK/AAB artifact without requiring desktop
Flutter in Termux. It then sends only the certificate-verified APK and generated
download/release metadata through a separate Web review branch. It never copies
Android-packaged Web UI/runtime source over the completed Web release, and it
merges only after the Web quality/Chromium workflow succeeds.
