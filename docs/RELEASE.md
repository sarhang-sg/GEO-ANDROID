# NAV KURD Android 10.4.6

Weather update: native launcher widgets, dedicated weather screen, deep links, cached forecasts, background refresh and localized presentation. This replaces the previous Android build; data catalogue content remains independently versioned.

Now updated — NAV KURD 10.4.6 · Reviewed 10 November 2026.

Version **10.4.6+100406** uses the matching web presentation and verified
immutable offline catalog. Catalog data identity is independent of app version.

- Back cancels the top dialog/panel before leaving the app and preserves drafts.
- Native resume restores map/GPS lifecycle state when visibility events are
  missing. Invalid/future camera preferences are rejected safely.
- Shared account code discards stale responses after logout or account changes.
  Worker waits, language replies and GeoJSON imports are hardened.
- Matching web source rebuilds the UI; previous generated chunks are removed.
- The catalog omitted by the uploaded ZIP is recovered from Git LFS and
  verified. Packaged sources include the real database rather than its pointer.
- Flutter 3.47.7, compatible current public client packages and SQLite 3.7.0 are
  locked. Existing design, permissions and signing identity are retained.

Pull requests verify complete source/data inventories, analyze and test app and
local-core code, exercise real offline data and compile without release secrets.
Main release CI additionally checks APK/AAB version, assets and signatures and
publishes with the established certificate.

A source archive is not a signed APK. Physical GPS/camera, launcher widgets and
authenticated operations still need device/account QA.

## Android 10.4.6 fixes

The map now checks the installed package version and the bundled web presentation independently. The first launch shows progress while installing the offline catalog. Kurdish and Central Kurdish Android locales have framework delegates and right-to-left text. The weather widget immediately displays working city and forecast actions and can show cached readings while its Flutter bitmap is rendering. Its renderer no longer requires a display view. The release workflow installs the signed APK on an Android emulator and checks the map, widget bitmap, forecast tap and Back before publication.

## Source and documentation refresh

- Current 10.4.6 README, deployment instructions and disclosure contacts.
- Consistent policy version/date on Android and Web; existing legal terms and
  third-party rights remain in force.
- Android local-core instructions describe the integrated runtime and locked SQLite 3.7.0 package.
- Unreachable older Android presentation chunks are removed.
- Signed rebuilds are staged by source identity before replacing the public APK.
- Only the verified live Vercel deployment record is retained on GitHub.
