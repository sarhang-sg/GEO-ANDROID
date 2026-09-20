import 'dart:convert';
import 'package:sqlite3/sqlite3.dart';
import 'core_failure.dart';
import 'queries.dart';
import 'search_rules.dart';

/// Indexed candidate discovery with the original R16 candidate order and rank.
/// Rescue uses lexeme grams and a BK tree instead of scanning the search corpus.
final class SearchRepository {
  SearchRepository(Database database)
    : sql = Queries(database),
      rules = SearchRules(
        jsonDecode(
              database
                      .select(
                        "SELECT value FROM metadata WHERE key='searchConfig'",
                      )
                      .single['value']
                  as String,
            )
            as Map<String, dynamic>,
      ) {
    database.execute('''
      CREATE TEMP TABLE candidates(seq INTEGER PRIMARY KEY AUTOINCREMENT,id INTEGER UNIQUE);
      CREATE TEMP TABLE phonetic_group(g INTEGER,seq INTEGER,id INTEGER,PRIMARY KEY(g,id));
      CREATE INDEX temp.phonetic_identity ON phonetic_group(id,g);
      CREATE TEMP TABLE word_ids(id INTEGER PRIMARY KEY);
      CREATE TEMP TABLE frontier(id INTEGER PRIMARY KEY,done INTEGER NOT NULL DEFAULT 0);
    ''');
  }
  final Queries sql;
  final SearchRules rules;
  int lastCandidateCount = 0;
  int _count(String type, String key, String language) => sql.integer(
    'SELECT count(*) FROM posting WHERE language=? AND type=? AND key=?',
    [language, type, key],
  );
  Future<void> _yield(bool Function() cancelled) async {
    await Future<void>.delayed(Duration.zero);
    if (cancelled()) {
      throw const CoreFailure(
        'cancelled',
        'Search superseded by a newer request.',
      );
    }
  }

  int _intersect(List<String> keys, String type, String language) {
    if (keys.isEmpty) return 0;
    final marks = List.filled(keys.length, '?').join(',');
    sql.execute(
      '''INSERT OR IGNORE INTO candidates(id)
      SELECT search_id FROM posting WHERE language=? AND type=? AND key IN ($marks)
      GROUP BY search_id HAVING count(*)=? ORDER BY search_id''',
      [language, type, ...keys, keys.length],
    );
    return sql.integer('SELECT count(*) FROM candidates');
  }

  void _append(String type, String key, String language) => sql.execute(
    '''
    INSERT OR IGNORE INTO candidates(id) SELECT search_id FROM posting
    WHERE language=? AND type=? AND key=? ORDER BY search_id''',
    [language, type, key],
  );

  Future<void> _candidates(
    SearchQuery q,
    String language,
    bool Function() cancelled,
  ) async {
    for (final table in [
      'candidates',
      'phonetic_group',
      'word_ids',
      'frontier',
    ]) {
      sql.execute('DELETE FROM $table');
    }
    final postingCounts = <String, int>{};
    int count(String type, String key) => postingCounts.putIfAbsent(
      '$type\u0000$key',
      () => _count(type, key, language),
    );
    if (q.intentIds.isNotEmpty &&
        q.intentIds.every((k) => count('intent', k) > 0) &&
        _intersect(q.intentIds, 'intent', language) > 0) {
      return;
    }
    final text = q.tokens.where((t) => !q.intentIds.contains(t));
    final keys = <String>[];
    var allPresent = true;
    for (final t in text) {
      final three = t.substring(0, t.length < 3 ? t.length : 3);
      final two = t.substring(0, t.length < 2 ? t.length : 2);
      final key = count('prefix', three) > 0 ? three : two;
      if (count('prefix', key) > 0) {
        keys.add(key);
      } else {
        allPresent = false;
      }
    }
    final unique = keys.toSet().toList();
    if (unique.isNotEmpty &&
        (!allPresent || _intersect(unique, 'prefix', language) == 0)) {
      unique.sort((a, b) => count('prefix', a).compareTo(count('prefix', b)));
      _append('prefix', unique.first, language);
    }
    // Preserve alternative-union order, then the smallest group's order. This
    // matters because R16 deduplicates coordinates/names before ranking.
    final counts = <int>[];
    for (var g = 0; g < q.phoneticGroups.length; g++) {
      for (final token in q.phoneticGroups[g]) {
        final offset = sql.integer(
          'SELECT coalesce(max(seq),0) FROM phonetic_group WHERE g=?',
          [g],
        );
        sql.execute(
          '''INSERT OR IGNORE INTO phonetic_group(g,seq,id)
          SELECT ?,?+row_number() OVER (ORDER BY search_id),search_id FROM posting
          WHERE language=? AND type='prefix' AND key=? ORDER BY search_id''',
          [g, offset, language, '~${token.substring(0, 2)}'],
        );
      }
      counts.add(
        sql.integer('SELECT count(*) FROM phonetic_group WHERE g=?', [g]),
      );
      await _yield(cancelled);
    }
    if (counts.isNotEmpty && counts.every((n) => n > 0)) {
      var smallest = 0;
      for (var i = 1; i < counts.length; i++) {
        if (counts[i] < counts[smallest]) smallest = i;
      }
      sql.execute(
        '''INSERT OR IGNORE INTO candidates(id)
        SELECT p.id FROM phonetic_group p WHERE p.g=? AND
        (SELECT count(*) FROM phonetic_group other WHERE other.id=p.id)=? ORDER BY p.seq''',
        [smallest, counts.length],
      );
    }
    if (sql.integer('SELECT count(*) FROM candidates') > 0) return;
    await _rescue(q, language, cancelled);
  }

  Future<void> _rescue(
    SearchQuery q,
    String language,
    bool Function() cancelled,
  ) async {
    // All positive scorer paths are covered: phrase substrings, word prefixes,
    // reverse prefixes, limited edits, and partial category matches. Phonetic
    // matches cannot be absent from the prefix postings assembled above.
    for (final token in {...q.tokens, q.phrase}.where((t) => t.isNotEmpty)) {
      if (SearchRules.shortAscii(token)) {
        sql.execute(
          'INSERT OR IGNORE INTO word_ids SELECT id FROM lexeme WHERE word=?',
          [token],
        );
      } else {
        final length = token.length < 3 ? token.length : 3;
        var rare = token.substring(0, length), count = 1 << 62;
        for (var i = 0; i + length <= token.length; i++) {
          final gram = token.substring(i, i + length),
              n = sql.integer('SELECT count(*) FROM lexeme_gram WHERE gram=?', [
                gram,
              ]);
          if (n < count) {
            rare = gram;
            count = n;
          }
        }
        sql.execute(
          '''INSERT OR IGNORE INTO word_ids SELECT l.id FROM lexeme_gram g
          JOIN lexeme l ON l.id=g.lexeme_id WHERE g.gram=? AND instr(l.word,?)>0''',
          [rare, token],
        );
      }
      if (token.length >= 4) {
        for (var n = 3; n <= token.length; n++) {
          sql.execute(
            'INSERT OR IGNORE INTO word_ids SELECT id FROM lexeme WHERE word=?',
            [token.substring(0, n)],
          );
        }
        final maximum = token.length >= 8 ? 2 : 1;
        sql.execute('DELETE FROM frontier');
        sql.execute('INSERT INTO frontier(id) VALUES (1)');
        while (true) {
          final nodes = sql.select(
            'SELECT f.id,l.word FROM frontier f JOIN lexeme l ON l.id=f.id WHERE f.done=0 ORDER BY f.id LIMIT 64',
          );
          if (nodes.isEmpty) break;
          for (final node in nodes) {
            final id = node['id'] as int,
                word = node['word'] as String,
                d = editDistance(word, token);
            if (word.length >= 4 && d <= maximum) {
              sql.execute('INSERT OR IGNORE INTO word_ids VALUES (?)', [id]);
            }
            sql.execute('UPDATE frontier SET done=1 WHERE id=?', [id]);
            sql.execute(
              'INSERT OR IGNORE INTO frontier(id) SELECT child FROM bk_edge WHERE parent=? AND distance BETWEEN ? AND ?',
              [id, d - maximum, d + maximum],
            );
          }
          await _yield(cancelled);
        }
      }
    }
    sql.execute(
      '''INSERT OR IGNORE INTO candidates(id) SELECT p.search_id FROM word_ids w
      JOIN lexeme_posting p ON p.lexeme_id=w.id WHERE p.language=? ORDER BY p.search_id''',
      [language],
    );
    for (final intent in q.intentIds) {
      _append('intent', intent, language);
    }
    // R16's corpus-rescue visits source order, not index traversal order.
    sql.execute('UPDATE candidates SET seq=-id');
    sql.execute('UPDATE candidates SET seq=-seq');
  }

  Future<List<Map<String, Object?>>> search(
    String text,
    String language, {
    int limit = 20,
    bool Function()? cancelled,
  }) async {
    if (!['ku', 'ar', 'en'].contains(language) ||
        text.length > 4096 ||
        limit < 1 ||
        limit > 120) {
      throw const CoreFailure(
        'invalid_search',
        'Expected KU/AR/EN, at most 4096 UTF-16 units and limit 1–120.',
      );
    }
    final stop = cancelled ?? () => false, query = rules.prepare(text);
    lastCandidateCount = 0;
    await _yield(stop);
    if (query.phrase.length < 2 && query.tokens.isEmpty) return [];
    await _candidates(query, language, stop);
    lastCandidateCount = sql.integer('SELECT count(*) FROM candidates');
    final ranked = <Map<String, Object?>>[];
    final seen = <String>{};
    var after = 0;
    while (true) {
      final rows = sql.select(
        '''SELECT c.seq,r.* FROM candidates c JOIN search_row r ON r.id=c.id
        WHERE c.seq>? ORDER BY c.seq LIMIT 256''',
        [after],
      );
      if (rows.isEmpty) break;
      for (final row in rows) {
        after = row['seq'] as int;
        List<String>? phonetic;
        final score = rules.scoreLazy(
          row,
          query,
          () => phonetic ??= List<String>.from(
            jsonDecode(row['phonetic'] as String) as List,
          ),
        );
        if (score <= 0) continue;
        if (!seen.add(row['dedup_key'] as String)) continue;
        final item = <String, Object?>{
          'id': row['id'],
          'ordinal': row['ordinal'],
          'sourceKey': row['source_key'],
          'n': row['name'],
          'q': row['query_text'],
          'k': row['kind'],
          'c': row['category'],
          'x': row['longitude'],
          'y': row['latitude'],
          's': '',
          'score': score,
        };
        var low = 0, high = ranked.length;
        while (low < high) {
          final mid = (low + high) ~/ 2, other = ranked[mid];
          if ((other['score'] as int) > score ||
              (other['score'] == score &&
                  (other['n'] as String).compareTo(item['n'] as String) <= 0)) {
            low = mid + 1;
          } else {
            high = mid;
          }
        }
        ranked.insert(low, item);
        if (ranked.length > limit) ranked.removeLast();
      }
      await _yield(stop);
    }
    return ranked;
  }

  void close() => sql.close();
}
