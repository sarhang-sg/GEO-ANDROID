# NAV KURD 11.0.0 for Android

Sarhang Salah’s Kurdish-first GIS and weather app for Android. Release 11.0.0 uses Android version code `110000` and application ID `com.navkurd.app`. Kurdish, Arabic and English are supported.

[Web application](https://geo-map-kappa.vercel.app/) · [Web source](https://github.com/sarhang-sg/GEO-MAP)

## Architecture

Flutter hosts a hardware-accelerated WebView containing the release-bound map UI in `assets/r16`. The native local core supplies the SQLite catalog, PMTiles and device GPS. Pack integrity is checked before native data is used. The regular map launch presents the signature split Loading animation.

Launcher weather actions use a separate weather entry point. City and forecast taps open the corresponding view. Refresh and GPS actions schedule native work. The foreground weather view requests full forecasts, while the widget requests current conditions and five hours. A dedicated Flutter engine renders launcher-sized bitmaps. Native RemoteViews provide accessibility and touch targets. WorkManager coordinates network work and backoff. Android controls background execution and permission availability.

## Build and verify

Use Git LFS, Flutter 3.47.7, Java 17 and the Android SDK packages listed in `tools/install-android-sdk.sh`. Check out the repository with LFS enabled.

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
