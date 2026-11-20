![NAV KURD cover by Sarhang Salah](docs/images/nav-kurd-cover.jpg)

# NAV KURD 11.0.0 for Android

Sarhang Salah’s Kurdish-first GIS and weather app for Android. Release 11.0.0 uses Android version code `110002` and application ID `com.navkurd.app`. Kurdish, Arabic and English are supported.

[Web application](https://geo-map-kappa.vercel.app/) · [Web source](https://github.com/sarhang-sg/GEO-MAP)

## Map and weather

The place card fits between the map controls. It shows the same weather gradients and location QR code as the web app. The QR opens the named coordinates on another device. The 3D GPS arrow follows the camera at a fixed screen size, adjustable in **Appearance & controls**. Open **Weather → Widget location** to pin the displayed city or return to automatic GPS. Automatic mode retains the last device position when GPS is off. Weather browsing and favorites have their own state.

<p align="center">
  <img src="docs/images/nav-kurd-screen-1.jpg" width="30%" alt="NAV KURD navigation" />
  <img src="docs/images/nav-kurd-screen-2.jpg" width="30%" alt="Place details" />
  <img src="docs/images/nav-kurd-screen-3.jpg" width="30%" alt="Weather and map controls" />
</p>

## Architecture

Flutter hosts a hardware-accelerated WebView containing the release-bound map UI in `assets/r16`. The native local core supplies the SQLite catalog, PMTiles and device GPS. Pack integrity is checked before native data is used. The regular map launch presents the signature split Loading animation.

The APK includes a separate routable OpenStreetMap road graph covering 40°–50° E and 30°–40° N. The native BRouter engine calculates new driving, walking and cycling routes offline, including turn instructions. New route requests outside that region use the configured online providers. Route geometry, directions and GPS tracking use the shared map presentation on both platforms.

Launcher weather actions use a separate weather entry point. City and forecast taps open the corresponding view. Refresh and GPS actions schedule native work. The foreground weather view requests full forecasts, while the widget requests current conditions and five hours. A dedicated Flutter engine renders launcher-sized bitmaps. Native RemoteViews provide accessibility and touch targets. WorkManager coordinates network work and backoff. Android controls background execution and permission availability.

## Build and verify

On a fresh installation with no saved city or GPS fix, the widget shows live weather for Erbil. Selecting a city or enabling GPS takes precedence. Widget deep links open the forecast directly. Notification and battery guidance appear in the map application.

Use Git LFS, Python 3, Flutter 3.47.7, Java 17 and the Android SDK packages listed in `tools/install-android-sdk.sh`. Check out the repository with LFS enabled. Gradle fetches the archived road graph at build time and verifies each segment against `contracts/offline-routing.json`. The installed app can calculate regional routes on first use without downloading additional data.

```sh
git lfs pull
flutter pub get --enforce-lockfile
bash TERMUX.sh validate
flutter analyze --no-pub lib test
flutter test --no-pub
flutter build apk --debug
```

For changes shared with the web application, install the matching web checkout’s locked npm dependencies. Run `python3 tools/sync-web-presentation.py --web ../GEO-MAP`, then `python3 tools/update-source-manifest.py`. The presentation verifies each bundled resource against its own manifest. The SQLite and PMTiles file hashes are independent of the UI release.

## Distribution

The main-branch release workflow checks the source manifest and local catalog, analyzes the code, tests both Flutter and the native core and builds the signed universal APK and AAB. It verifies the configured signing identity and runs launcher checks before publication. Public release assets include `DOWNLOAD-RECEIPT.json`. On Termux, `bash TERMUX.sh download` validates the exact version, source manifest, certificate identity and APK digest.

Developer: Sarhang Salah. Weather attribution is Open-Meteo · Developer: Sarhang Salah. See [SECURITY.md](SECURITY.md) for disclosure and signing practices.
