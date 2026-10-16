# NAV KURD local core — 10.4.4

Now updated — NAV KURD 10.4.4 · Reviewed 14 October 2026.

The Android runtime uses this library for its read-only SQLite catalog,
mutable preferences, query worker and random-access PMTiles readers. Flutter
owns the native lifecycle and permissions; the bundled MapLibre interface uses
these local services through the Android adapter.

## Integration contract

`CorePackInstaller` in the Android `com.navkurd.app.localcore` package streams
the install-time `src/main/assets/nav_kurd_core` pack into app-private storage.
`AndroidLocalRuntime.open()` invokes the native installation channel and awaits
`ensureInstalled()` before opening the returned paths. It supplies `packDirectory`,
`userDatabase`, and the manifest's content-derived `packId`. No website or core
download is involved. It never deletes an old published pack or user storage.

Open one `LocalDataClient` with those paths. Keep that client for the native
app lifecycle; close it at final disposal. Search, place, viewport, reverse and
preference operations share its single worker. New search generations cancel
older searches with a typed `cancelled` failure. The caller must also associate
its UI requests with the current generation. Never create one client per
keystroke, layer or language. `AndroidLocalRuntime` owns this client and exposes it through
`CoreResourceHandler` and the native bridge.

`CoreManifest.assetPath(originalWebPath)` resolves exact bundled artwork.
`manifest.file(relativePath)` only accepts declared core files. The map-style
JSON uses `navkurd-core:///` resource identifiers as the adapter contract. These
are logical local identifiers, not HTTP URLs or a loopback server. The native
resource adapter resolves them to installed files and the supplied tile reader.
The bundled MapLibre interface owns rendering.

`PmTilesReader` opens an installed file and returns uncompressed MVT bytes for
native zooms 5–12. The renderer overzooms the maxzoom-12 source to display zoom
18. Out-of-range or absent native tiles return null; malformed data throws.
`metadata()` returns the archive's actual vector-layer metadata. Close every
reader when the native map is disposed. Tile reads serialize on each file
cursor, with a 4 MiB directory LRU, 8 MiB compressed-read ceiling and 16 MiB
decoded-entry ceiling. No entire archive is read into RAM.

## Storage and query behavior

- SQLite `3.7.0` Dart package supplies the pinned native binary through its
  standard build hook. No system SQLite fallback, custom binary substitution,
  Flutter test implementation or altered dependency hook is used.
- FTS5 and R-tree capability checks are mandatory at catalog open. Search uses
  compiled prefix/intent/phonetic postings, lexeme grams and a BK tree because
  plain FTS ranking cannot implement the multilingual search contract. There is no unused
  second FTS search index.
- Search reads 256 candidate rows at a time, maintains at most 100 results and
  bounds the pending request queue to 64. SQL temporary tables keep broad
  candidate sets on disk; a maximum of 48 prepared statements is cached per
  query owner. Search does not load a whole language corpus or scan all search
  rows on each keypress. A category can legitimately have many indexed
  candidates; no arbitrary truncation changes its ranking.
- The catalog connection uses an 8 MiB page cache, a 2 MiB temporary page
  cache and no full-file mmap. Place pages are limited to 256 source records
  and 8 MiB decoded source payload. Settings use a separate 2 MiB cache.
  These are implementation limits, not measured Android memory claims.
- Reverse lookup returns a nearest named locality, distance and containing
  administrative polygons, with coverage information. It never fabricates an
  exact address or an offline routing graph.
- Preferences are allowlisted JSON values up to 64 KiB, persisted in one
  WAL-backed user store. Absence means the UI retains its approved default.
  The native state adapter routes allowlisted local preferences to this store.
- Pack versions come from the existing release configuration. `packId` is
  `offlinePackVersion-contentHashPrefix`. Search schema and reader schema are
  compatibility fields, not competing release versions. The installed receipt
  and active pointer identify that same immutable pack.

## Validation

The Android repository pins Flutter 3.47.7 and its compatible Dart SDK. Resolve
the committed package locks and run the existing checks:

```bash
flutter pub get --enforce-lockfile
python3 tools/verify-local-data.py
cd packages/nav_kurd_local_core
dart pub get --enforce-lockfile
dart analyze --fatal-infos
dart test
```

The signed-release workflow also verifies the real offline catalog and bundled
assets. App version 10.4.4 is provided by `assets/application-release.json`;
geographic data retains its source provenance and content-derived pack identity.
Physical GPS, camera and launcher behavior require device testing.
