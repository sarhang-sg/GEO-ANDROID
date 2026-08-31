# NAV KURD Android 9.0.0

Version name/code: `9.0.0` / `90000`
Package: `com.navkurd.app`
Minimum/target Android: API `24` / `36`

## Native and reliability changes

- Secure Android image selection now returns a temporary `content://` URI through a non-exported `FileProvider`; the contribution form keeps its state while the image is compressed.
- Share actions open the native Android share sheet and report success/cancel state to the map UI.
- Warm widget taps no longer reload the WebView or reset the current map state.
- Cancelled non-main-frame WebView resources are filtered from diagnostics while real main-frame errors remain visible.
- Malformed Web/PWA/weather URLs fall back safely instead of surfacing `Failed to construct URL` promise errors.
- Backup/restore and task isolation are hardened as a best-effort defense against unintended copies without requesting invasive permissions.
- Satellite raster rendering is pinned to hardware-accelerated hybrid
  composition; Android WebView force-dark and algorithmic darkening are disabled
  and offscreen pre-rasterization is enabled to prevent black satellite tiles.

## Widget

- Rebuilt Kurdish/Arabic RTL and English LTR layouts on a shared clean grid.
- Removed duplicate sun, moon and cloud artwork; each weather state now has one primary weather symbol.
- Uses the same bundled NAV KURD Arabic and Latin font families as the app.
- Normalized city, temperature, condition, local time, season/phase, humidity, wind and dust placement.
- Dust occupies a complete metric group only when real data is available, preventing orphan icons or empty gaps.
- Retains real Open-Meteo weather, reverse geocoding, day/night, local time, season, refresh and locate behavior.
- Updated buttons and status chips to the luxe blue/cyan visual system.

## Shared NAV KURD 9 interface

- Luxe deep-blue/white/cyan UI shared with Web.
- Compact animated right controls and Android settings actions.
- New nine-slice Loading component, new direct-download component and supplied Android artwork.
- Improved tutorial progress, place category icons, safe-top search and GPS/search camera behavior.
- Red support/payment styling remains unchanged.

## Release gate

The signed workflow builds universal and split APKs plus an AAB, validates
`9.0.0+90000`, and verifies the established certificate fingerprint before
publishing artifacts. The Termux publisher updates the completed Web repository
with only the verified APK and generated download/release metadata; it never
replaces Web UI/runtime source.
