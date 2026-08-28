# NAV KURD Android 8.0.4

Release date: 2026-08-27
Package: `com.navkurd.app`
Version name/code: `8.0.4` / `80004`
Minimum/target Android: API 24 / API 36

## Release outcome

- GPS tracking now remembers only the user’s tracking choice (never a location
  history), detects stale watches and restarts after foreground resume.
- The broad accuracy area and route strokes render below place/locality icons;
  the compact live-location puck stays above them.
- The Android home widget has separate RTL/LTR layouts, app-matched fonts,
  localized Kurdish/Arabic/English copy, real Open-Meteo weather and air-quality
  readings, reverse geocoding, local clock, six day phases, four seasons and
  rich Canvas-rendered weather scenes/icons without emoji.
- Launcher widgets cannot run continuous Lottie/SVG animation under Android
  `RemoteViews`. NAV KURD therefore advances a weather/particle frame on each
  scheduled refresh and whenever location, language or weather changes. The
  in-app web surface uses continuously animated SVG assets.
- Notification channels now separate daily weather, app updates and general
  activity. A weather summary is scheduled for 08:00 local time. The release
  feed is checked every 12 hours, and the user is notified once per newer
  version. The currently installed version is never notified as an update.
- Flutter exposes real Android CPU/RAM, ABI/device, physical screen,
  density/refresh rate, EGL GPU, storage and safe-area information to the
  trusted web origin. Values Android cannot expose remain `null`.
- Downloads remain scoped-storage safe. The offline PMTiles pack remains in
  persistent trusted-origin storage and is not deleted by transient-cache
  cleanup.
- WebView pause/resume events are bridged into the map so location tracking and
  UI state recover after the app has been backgrounded.

## Verification gates

The release workflow runs:

```bash
bash tools/validate-source.sh
flutter analyze --no-pub --fatal-infos
flutter test --no-pub
flutter build apk --release --no-pub
flutter build apk --release --split-per-abi --no-pub
flutter build appbundle --release --no-pub
```

It then verifies every APK with `apksigner`, verifies the AAB with `jarsigner`,
compares the APK signing certificate with `ANDROID_APP_LINK_SHA256.txt`, and
writes `SHA256SUMS.txt`, `SIGNATURES.txt`, `CERTIFICATE_SHA256.txt` and
`VERSION.txt` into the release artifact.

## Known platform boundary

The production GIS engine remains MapLibre/PMTiles/TypeScript inside a hardened
Flutter WebView. Rewriting that working GIS engine as native Flutter would be a
separate product migration, not a safe optimization patch. Flutter owns Android
lifecycle, permission requests, downloads, notifications, deep links, device
integration, renderer recovery and the offline failure surface.
