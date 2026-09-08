# NAV KURD Android 9.1.0

Version name/code: `9.1.0` / `90100`
Package: `com.navkurd.app`
Minimum/target Android: API `24` / `37`

## Native and reliability changes

- The standards-based WebView file chooser owns image selection; returning from the picker keeps the mounted contribution form and preview state intact.
- Share actions open the native Android share sheet and report success/cancel state to the map UI.
- Warm widget taps no longer reload the WebView or reset the current map state.
- Cancelled non-main-frame WebView resources are filtered from diagnostics while real main-frame errors remain visible.
- Malformed Web/PWA/weather URLs fall back safely instead of surfacing `Failed to construct URL` promise errors.
- Backup/restore and task isolation are hardened as a best-effort defense against unintended copies without requesting invasive permissions.
- Satellite raster rendering is pinned to hardware-accelerated hybrid
  composition; algorithmic darkening is disabled through the supported WebView
  API, deprecated `forceDark` is excluded, and offscreen pre-rasterization is
  enabled to prevent black satellite tiles.

## Widget

- Rebuilt Kurdish/Arabic RTL and English LTR layouts on a shared clean grid.
- Removed duplicate sun, moon and cloud artwork; each weather state now has one primary weather symbol.
- Kurdish and Arabic text uses `UniQAIDAR-Money-Heist-002.ttf`; English uses the exact `RedHatDisplay-Variable.woff2` family converted to Android's native TTF container.
- Normalized city, temperature, condition, local time, season/phase, humidity, wind and dust placement.
- Dust occupies a complete metric group only when real data is available, preventing orphan icons or empty gaps.
- Retains real Open-Meteo weather, reverse geocoding, day/night, local time, season, refresh and locate behavior.
- Updated buttons and status chips to the luxe blue/cyan visual system.

## Shared NAV KURD 9.1.0 interface

- Luxe deep-blue/white/cyan UI shared with Web.
- Compact animated right controls and Android settings actions.
- New nine-slice Loading component, new direct-download component and supplied Android artwork.
- Improved tutorial progress, place category icons, safe-top search and GPS/search camera behavior.
- Red support/payment styling remains unchanged.

## Release gate

The signed workflow builds one universal APK plus an AAB, validates
`9.1.0+90100`, and verifies the established certificate fingerprint before
publishing artifacts. The one-shot Termux publisher first creates the clean
Android root, verifies the signed release, then creates the clean Web root with
that verified APK and regenerated download metadata.
