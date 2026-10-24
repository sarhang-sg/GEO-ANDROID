import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'core_failure.dart';
import 'local_state.dart';

/// Pending routes share the one mutable database. An empty owner is an
/// anonymous on-device route and is never claimed by a signed-in account.
final class NavigationHistory {
  NavigationHistory(this.state);
  final LocalState state;
  static const _receipt = 'r16-navigation-history-v1';
  static const _maximumImportBytes = 8 * 1024 * 1024;

  String _owner(Object? value) {
    if (value == null) return '';
    if (value is! String || value.length > 160 || value.isEmpty) {
      throw const CoreFailure('history_owner', 'Invalid navigation history owner.');
    }
    return value;
  }

  Map<String, Object?> _entry(Map value) {
    bool number(Object? v) => v is num && v.isFinite;
    final id = value['id'], destination = value['destination'];
    if (id is! String || id.trim().isEmpty || id.length > 160 ||
        destination is! String || destination.length > 65536 ||
        !const ['arrived', 'cancelled'].contains(value['status']) ||
        !number(value['startedAt']) || !number(value['endedAt'])) {
      throw const CoreFailure('history_entry', 'Invalid navigation history entry.');
    }
    final coordinate = value['coordinate'];
    if (coordinate != null && (coordinate is! List || coordinate.length != 2 ||
        !coordinate.every(number))) {
      throw const CoreFailure('history_coordinate', 'Invalid history coordinate.');
    }
    final output = <String, Object?>{
      'id': id, 'status': value['status'], 'startedAt': value['startedAt'],
      'endedAt': value['endedAt'], 'destination': destination, 'coordinate': coordinate,
      'travelMode': const ['walking', 'bicycle'].contains(value['travelMode']) ? value['travelMode'] : 'car',
    };
    for (final key in const ['plannedDistanceMeters', 'remainingDistanceMeters', 'plannedDurationSeconds', 'elapsedSeconds']) {
      final raw = value[key];
      final parsed = raw is String ? num.tryParse(raw) : raw;
      output[key] = number(parsed) ? parsed : 0;
    }
    if (utf8.encode(jsonEncode(output)).length > 128 * 1024) {
      throw const CoreFailure('history_size', 'Navigation history entry exceeds its size limit.');
    }
    return output;
  }

  List<Map<String, Object?>> list(String? userId) {
    final owner = userId == null ? null : _owner(userId);
    final rows = owner == null
        ? state.sql.select('SELECT owner,payload,revision FROM navigation_history ORDER BY queued_ms DESC,id LIMIT 40')
        : state.sql.select('SELECT owner,payload,revision FROM navigation_history WHERE owner=? ORDER BY queued_ms DESC,id LIMIT 40', [owner]);
    return [for (final row in rows) {
      ...Map<String, Object?>.from(jsonDecode(row['payload'] as String) as Map),
      'userId': row['owner'] == '' ? null : row['owner'], 'localRevision': row['revision'],
    }];
  }

  void queue(Map entry, String? userId) {
    final owner = _owner(userId), value = _entry(entry);
    state.sql.execute('''INSERT INTO navigation_history VALUES (?,?,?,?,1)
      ON CONFLICT(owner,id) DO UPDATE SET payload=excluded.payload,queued_ms=excluded.queued_ms,
      revision=navigation_history.revision+1''',
      [owner, value['id'], jsonEncode(value), DateTime.now().millisecondsSinceEpoch]);
    // Do not evict an unsynchronized route to enforce the 40-row display limit.
  }

  void remove(String? id, String userId, {int? expectedRevision}) {
    final owner = _owner(userId);
    if (expectedRevision != null) {
      if (id == null || expectedRevision < 1) throw const CoreFailure('history_revision', 'Invalid history acknowledgement.');
      state.sql.execute('DELETE FROM navigation_history WHERE owner=? AND id=? AND revision=?', [owner, id, expectedRevision]);
    } else if (id == null) {
      state.sql.execute('DELETE FROM navigation_history WHERE owner=?', [owner]);
    } else {
      state.sql.execute('DELETE FROM navigation_history WHERE owner=? AND id=?', [owner, id]);
    }
  }

  Map<String, Object?> importLegacy(String? raw) {
    if (raw != null && utf8.encode(raw).length > _maximumImportBytes) {
      throw const CoreFailure('history_import_size', 'Legacy history is too large; it was left untouched.');
    }
    final hash = sha256.convert(utf8.encode(raw ?? '')).toString();
    state.database.execute('BEGIN IMMEDIATE');
    try {
      final receipt = state.sql.select('SELECT source_hash FROM import_receipt WHERE id=?', [_receipt]);
      if (receipt.isNotEmpty) {
        final previous = receipt.single['source_hash'];
        if (raw != null && previous != hash) {
          throw const CoreFailure('history_import_conflict', 'Legacy history changed after import; both copies were preserved for recovery.');
        }
        state.database.execute('COMMIT');
        return {'sourceHash': previous, 'capturedSourceHash': hash, 'alreadyImported': true};
      }
      final parsed = raw == null ? <Object?>[] : jsonDecode(raw);
      if (parsed is! List || parsed.length > 4096) {
        throw const CoreFailure('history_import', 'Invalid legacy history; it was left untouched.');
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var index = 0; index < parsed.length; index++) {
        final item = parsed[index];
        if (item is! Map) throw const CoreFailure('history_import', 'Invalid legacy route; it was left untouched.');
        final value = _entry(item), owner = _owner(item['userId']);
        state.sql.execute('INSERT OR IGNORE INTO navigation_history VALUES (?,?,?,?,1)',
          [owner, value['id'], jsonEncode(value), now - index]);
      }
      state.sql.execute('INSERT INTO import_receipt VALUES (?,?,?,?)', [_receipt, 1, hash, now]);
      state.database.execute('COMMIT');
      return {'sourceHash': hash, 'capturedSourceHash': hash, 'alreadyImported': false};
    } catch (_) {
      state.database.execute('ROLLBACK');
      rethrow;
    }
  }
}
