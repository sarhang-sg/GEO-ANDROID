# NAV KURD local core

Phase 1 data library for the approved R16 project. It provides one read-only
SQLite catalog, one mutable preferences database, one query isolate, and one
random-access PMTiles reader per open archive. It does not replace the R16 UI.

## Integration contract

`CorePackInstaller` in the Android `com.navkurd.app.localcore` package streams
the install-time `src/main/assets/nav_kurd_core` pack into app-private storage.
Call `ensureInstalled()` from the future native composition root and await its
future before opening the returned paths. It supplies `packDirectory`,
`userDatabase`, and the manifest's content-derived `packId`. No website or core
download is involved. It never deletes an old published pack or user storage.

Open one `LocalDataClient` with those paths. Keep that client for the native
app lifecycle; close it at final disposal. Search, place, viewport, reverse and
preference operations share its single worker. New search generations cancel
older searches with a typed `cancelled` failure. The caller must also associate
its UI requests with the current generation. Never create one client per
keystroke, layer or language. The current WebView remains its existing owner
until the later feature cutover; this package is not initialized by R16.

`CoreManifest.assetPath(originalWebPath)` resolves exact bundled artwork.
`manifest.file(relativePath)` only accepts declared core files. The map-style
JSON uses `navkurd-core:///` resource identifiers as the adapter contract. These
are logical local identifiers, not HTTP URLs or a loopback server. The later
native adapter must resolve them to installed files and map its source API to
the supplied file reader. No native renderer is selected or claimed by this
implementation-only deliverable.

`PmTilesReader` opens an installed file and returns uncompressed MVT bytes for
native zooms 5–12. The renderer overzooms the maxzoom-12 source to display zoom
18. Out-of-range or absent native tiles return null; malformed data throws.
`metadata()` returns the archive's actual vector-layer metadata. Close every
reader when the native map is disposed. Tile reads serialize on each file
cursor, with a 4 MiB directory LRU, 8 MiB compressed-read ceiling and 16 MiB
decoded-entry ceiling. No entire archive is read into RAM.

## Storage and query behavior

- SQLite `3.5.2` Dart package supplies the pinned native binary through its
  standard build hook. No system SQLite fallback, custom binary substitution,
  Flutter test implementation or altered dependency hook is used.
- FTS5 and R-tree capability checks are mandatory at catalog open. Search uses
  compiled prefix/intent/phonetic postings, lexeme grams and a BK tree because
  plain FTS ranking cannot implement the R16 contract. There is no unused
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
  There is no dual write to WebView storage and no Phase 1 user-data import.
- Pack versions come from the existing release configuration. `packId` is
  `offlinePackVersion-contentHashPrefix`. Search schema and reader schema are
  compatibility fields, not competing release versions. The installed receipt
  and active pointer identify that same immutable pack.

## Build and minimal check

Use the recorded Node 24.19.0 and Dart 3.10.0 toolchains and the checked-in
`pubspec.lock`. Restore exact sources with `python3 tools/restore_project.py`
from the extracted checkpoint first. The pack is already generated; do not
rebuild it to resume work. When source data changes in a later authorized step:

```bash
node android/tools/native-data/build_core.mjs --web-root web --output /absolute/new/core-directory
```

The compiler refuses existing output, validates original release PMTiles
hashes and record crosswalks, checks SQLite integrity/foreign keys, and only
publishes declared, closed files. It never mutates the supplied Web inputs.

The optional `bin/check_core.dart CORE_DIRECTORY` is a small real-data smoke
check of newly written APIs. The checkpoint records its existing result; do
not repeat it merely to resume. Full parity, device performance, visual
comparisons, native renderer integration and failure-injection QA are deferred
to Final QA under the user's final Phase 1 instruction.
