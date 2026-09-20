import 'package:sqlite3/sqlite3.dart';

/// Bounded connection-owned statement cache; all callers are on one isolate.
final class Queries {
  Queries(this.database);
  final Database database;
  final _statements = <String, PreparedStatement>{};
  PreparedStatement _statement(String sql) {
    final existing = _statements.remove(sql);
    if (existing != null) {
      _statements[sql] = existing;
      return existing;
    }
    if (_statements.length == 48) {
      _statements.remove(_statements.keys.first)!.close();
    }
    return _statements[sql] = database.prepare(sql);
  }

  ResultSet select(String sql, [List<Object?> values = const []]) =>
      _statement(sql).select(values);
  void execute(String sql, [List<Object?> values = const []]) =>
      _statement(sql).execute(values);
  int integer(String sql, [List<Object?> values = const []]) =>
      select(sql, values).first.values.first as int;
  void close() {
    for (final s in _statements.values) {
      s.close();
    }
    _statements.clear();
  }
}
