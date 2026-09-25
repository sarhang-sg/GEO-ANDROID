import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'core_failure.dart';
import 'queries.dart';

/// One mutable store, separate from the replaceable read-only pack. Missing
/// preferences remain absent so the approved UI supplies its existing defaults.
final class LocalState {
  LocalState(String path) : database = sqlite3.open(path) {
    try {
      database.execute(
        'PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA cache_size=-2048; PRAGMA foreign_keys=ON; PRAGMA busy_timeout=5000;',
      );
      final version =
          database.select('PRAGMA user_version').single.values.single as int;
      if (version > 2) {
        throw const CoreFailure(
          'unsupported_user_store',
          'Refusing to downgrade local user data.',
        );
      }
      if (version == 0) {
        database.execute('''BEGIN IMMEDIATE;
        CREATE TABLE preference(key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_ms INTEGER NOT NULL) WITHOUT ROWID;
        CREATE TABLE import_receipt(id TEXT PRIMARY KEY,source_schema INTEGER NOT NULL,source_hash TEXT NOT NULL,completed_ms INTEGER NOT NULL) WITHOUT ROWID;
        PRAGMA user_version=1; COMMIT;''');
      }
      if (version < 2) {
        database.execute('''BEGIN IMMEDIATE;
        CREATE TABLE navigation_history(owner TEXT NOT NULL,id TEXT NOT NULL,payload TEXT NOT NULL,
          queued_ms INTEGER NOT NULL,revision INTEGER NOT NULL,PRIMARY KEY(owner,id)) WITHOUT ROWID;
        CREATE INDEX navigation_history_recent ON navigation_history(owner,queued_ms DESC,id);
        PRAGMA user_version=2; COMMIT;''');
      }
      sql = Queries(database);
    } catch (_) {
      database.close();
      rethrow;
    }
  }
  final Database database;
  late final Queries sql;
  static const keys = {
    'theme',
    'language',
    'mapMode',
    'layerVisibility',
    'controlVisibility',
    'camera',
    'tutorialCompleted',
    'trackingEnabled',
    'notificationPreferences',
    'lastNonSensitiveState',
    'weatherForecastCache',
  };
  void _key(String key) {
    if (!keys.contains(key)) {
      throw CoreFailure('invalid_preference', 'Unowned preference key: $key');
    }
  }

  Object? get(String key) {
    _key(key);
    final row = sql.select('SELECT value FROM preference WHERE key=?', [key]);
    return row.isEmpty ? null : jsonDecode(row.single['value'] as String);
  }

  void set(String key, Object? value) {
    _key(key);
    if (const {'tutorialCompleted','trackingEnabled'}.contains(key) && value is! bool) throw const CoreFailure('invalid_preference','Expected a boolean preference.');
    final encoded = jsonEncode(value);
    if (utf8.encode(encoded).length > 65536) {
      throw const CoreFailure('preference_size', 'Preference exceeds 64 KiB.');
    }
    if (key == 'language' && !['ku', 'ar', 'en'].contains(value)) {
      throw const CoreFailure('invalid_preference', 'Unsupported language.');
    }
    if (key == 'mapMode' && !['street', 'night', 'satellite'].contains(value)) {
      throw const CoreFailure('invalid_preference', 'Unsupported map mode.');
    }
    sql.execute(
      '''INSERT INTO preference VALUES (?,?,?) ON CONFLICT(key) DO UPDATE
      SET value=excluded.value,updated_ms=excluded.updated_ms''',
      [key, encoded, DateTime.now().millisecondsSinceEpoch],
    );
  }

  void remove(String key) {
    _key(key);
    sql.execute('DELETE FROM preference WHERE key=?', [key]);
  }

  Map<String,Object?> snapshot()=>{
    for(final row in sql.select('SELECT key,value FROM preference ORDER BY key'))row['key'] as String:jsonDecode(row['value'] as String)
  };
  void update(Map<String,Object?> values){
    database.execute('BEGIN IMMEDIATE');
    try{values.forEach(set);database.execute('COMMIT');}catch(_){database.execute('ROLLBACK');rethrow;}
  }
  Map<String,Object?> importUi(Map<String,Object?> values,String sourceHash){
    if(!RegExp(r'^[0-9a-f]{64}$').hasMatch(sourceHash))throw const CoreFailure('invalid_import','Invalid import checksum.');
    database.execute('BEGIN IMMEDIATE');
    try {
      final existing=sql.select("SELECT source_hash,completed_ms FROM import_receipt WHERE id='r16-ui-v1'");
      final already=existing.isNotEmpty;
      if(!already){
        for(final item in values.entries){if(get(item.key)==null)set(item.key,item.value);}
        sql.execute('INSERT INTO import_receipt VALUES (?,?,?,?)',['r16-ui-v1',1,sourceHash,DateTime.now().millisecondsSinceEpoch]);
      }
      database.execute('COMMIT');
      return {'sourceHash':already?existing.single['source_hash']:sourceHash,'alreadyImported':already};
    }catch(_){database.execute('ROLLBACK');rethrow;}
  }

  void close() {
    sql.close();
    database.close();
  }
}
