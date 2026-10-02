# NAV KURD Android 10.0.0

Source release date: 2026-10-02. Version: `10.0.0+100000`. Package: `com.navkurd.app`.

## Changes

- Rebuilt the bundled V10 presentation and closed SQLite pack from the reviewed web sources. Removed superseded hashed presentation assets.
- Added release-time SQLite integrity, foreign-key, record-count, exact asset manifest and presentation-version checks.
- Added account notification delivery from the existing authenticated inbox while the app is active or resumes. Receipts are bounded, account-specific and cleared on account changes; opening a notification uses the trusted native deep link.
- Check Android notification permission, global settings and each channel before delivery. Record successful delivery only after Android accepts it.
- Keep daily weather scheduling stable across ordinary launches; reschedule for boot, package and clock/time-zone changes. Use fresh real weather for summaries.
- Run release HTTP requests in a connectivity-constrained JobScheduler job with a bounded response, throttling and a single executor, outside the broadcast receiver.
- Accept update downloads only from the canonical app or the canonical GitHub release path for the reported version.
- Preserve AGP built-in Kotlin ownership across Flutter migration and exclude generated plugin registration from the source manifest.
- Keep `DEVLOPER: SARHANG SALAH` beside Open-Meteo in the launcher widget.

## Verification and release status

Flutter analysis, 14 existing Dart tests and a local debug ARM64 compilation passed during preparation. The bundled closed data pack passed full SQLite and file integrity verification. A debug compilation is not a signed release.

The existing `android-release.yml` builds the universal release APK and AAB, then verifies package/version, established signing certificate, source manifest, required local assets and hashes. `RUN-TERMUX.sh` from the coordinated release kit waits for that exact commit and refuses to publish an unverified binary. Installation is an in-place update using the existing identity.

Account push while the app process is terminated still requires a real Firebase/backend delivery configuration. This source includes active/resumed inbox notifications and scheduled local weather/update notifications; it does not simulate cloud push. Physical-device GPS, battery/temperature, background restrictions and installation over the old signed app remain acceptance checks.
