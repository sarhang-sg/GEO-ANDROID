# NAV KURD Android 10.4.4

Now updated — NAV KURD 10.4.4 · Reviewed 14 October 2026.

Version **10.4.4+100404** uses the matching web presentation and verified
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

## Source and documentation refresh

- Current 10.4.4 README, deployment instructions and disclosure contacts.
- Consistent policy version/date on Android and Web; existing legal terms and
  third-party rights remain in force.
- Android local-core instructions describe the integrated runtime and locked SQLite 3.7.0 package.
- Unreachable older Android presentation chunks are removed.
- Signed rebuilds are staged by source identity before replacing the public APK.
- Only the verified live Vercel deployment record is retained on GitHub.
