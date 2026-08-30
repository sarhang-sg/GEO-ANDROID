# Android release checklist

- [x] `bash TERMUX.sh check` passes.
- [x] `bash tools/validate-source.sh` reports NAV KURD 8.0.4 source checks passed.
- [ ] The repository visibility is PRIVATE.
- [ ] GitHub Actions signing secrets are configured.
- [ ] `flutter analyze --fatal-infos` and `flutter test` pass in Actions.
- [ ] Universal, arm64-v8a, armeabi-v7a and x86_64 APKs exist.
- [ ] AAB exists for future distribution needs.
- [ ] `apksigner verify --verbose --print-certs` passes for every APK.
- [ ] SHA-256 checksums are retained with the release.
- [ ] GPS prompt, current-location button and route refresh work.
- [ ] Supabase login and contribution photo picker work.
- [ ] Selecting a contribution photo opens the Android system image picker and
  returns the chosen image to the trusted WebView.
- [ ] Every location Share action opens the Android system share chooser.
- [ ] Selecting a search result does not jump back to the active GPS position.
- [ ] Offline PMTiles pack pauses, resumes, verifies and opens offline.
- [ ] DownloadManager saves into `Downloads/NAV KURD`.
- [ ] Offline-ready notification appears after permission is granted.
- [ ] Daily weather notification uses the selected language and real cached data.
- [ ] Update notification appears for an older build, only once per release, and
  does not appear on 8.0.4.
- [ ] Home-screen widget opens the Locate action.
- [ ] Widget shows cached city, location time, correct day/night icon, season,
  real weather and offline-map state.
- [ ] Widget follows Kurdish/Arabic/English app language and contains no emoji.
- [ ] Widget scene changes across dawn/morning/noon/afternoon/evening/night,
  seasons and available WMO weather states.
- [ ] Status/navigation bars are hidden and appear transiently after an edge swipe.
- [ ] Android feedback preview includes native device/WebView diagnostics.
- [ ] Runtime report contains real CPU/RAM/screen/EGL/storage values or explicit
  nulls where Android withholds data.
- [ ] Android 10+ uses scoped storage without all-files access.
- [ ] `navkurd://locate?action=locate` opens the installed app.
- [ ] Signing key and password backup is stored privately.
- [ ] Universal APK certificate equals `ANDROID_APP_LINK_SHA256.txt`.
- [ ] Web quality, real Chromium smoke and Vercel production deployment are
  green with the exact certificate-verified direct APK.
