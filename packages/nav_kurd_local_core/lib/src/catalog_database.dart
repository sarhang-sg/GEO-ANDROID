import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'core_failure.dart';
import 'core_manifest.dart';

Database openCatalog(CoreManifest manifest) {
  final db = sqlite3.open(
    manifest.file('catalog.sqlite').path,
    mode: OpenMode.readOnly,
  );
  try {
    db.execute(
      'PRAGMA cache_size=-8192; PRAGMA mmap_size=0; PRAGMA temp_store=FILE; PRAGMA temp.cache_size=-2048;',
    );
    if (db.select('PRAGMA user_version').single.values.single != 1 ||
        db.select('PRAGMA application_id').single.values.single != 1313555282) {
      throw const CoreFailure(
        'unsupported_catalog',
        'Unexpected catalog identity/schema.',
      );
    }
    final options = db
        .select('PRAGMA compile_options')
        .map((r) => r.values.single)
        .toSet();
    if (!options.contains('ENABLE_FTS5') || !options.contains('ENABLE_RTREE')) {
      throw const CoreFailure(
        'sqlite_capability',
        'The pinned SQLite runtime must enable FTS5 and R-tree.',
      );
    }
    for (final key in ['releaseId', 'mapDataVersion', 'offlinePackVersion']) {
      final rows = db.select('SELECT value FROM metadata WHERE key=?', [key]);
      if (rows.length != 1 ||
          jsonDecode(rows.single['value'] as String) !=
              manifest.versions[key]) {
        throw CoreFailure(
          'catalog_version',
          'Catalog and pack disagree on $key',
        );
      }
    }
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}
