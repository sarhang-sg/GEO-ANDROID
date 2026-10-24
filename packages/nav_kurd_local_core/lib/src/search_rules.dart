import 'dart:math' as math;
import 'package:unorm_dart/unorm_dart.dart' as unicode;

final class SearchQuery {
  SearchQuery(this.phrase, this.tokens, this.intentIds, this.phoneticGroups);
  final String phrase;
  final List<String> tokens, intentIds;
  final List<List<String>> phoneticGroups;
  Map<String, Object?> toJson() => {
    'phrase': phrase,
    'tokens': tokens,
    'intentIds': intentIds,
    'phoneticGroups': phoneticGroups,
  };
}

/// R16's scoring and normalization contract. Intent/letter tables are compiled
/// from the supplied source, not a second handwritten place-name dictionary.
final class SearchRules {
  SearchRules(Map<String, dynamic> config)
    : digits = Map<String, String>.from(config['digits'] as Map),
      letters = Map<String, String>.from(config['letters'] as Map),
      stopwords = Set<String>.from(config['stopwords'] as List),
      intents = List<Map<String, dynamic>>.from(config['intents'] as List),
      coreIntents = List<Map<String, dynamic>>.from(
        config['coreIntents'] as List,
      );
  final Map<String, String> digits, letters;
  final Set<String> stopwords;
  final List<Map<String, dynamic>> intents, coreIntents;
  static final _invisible = RegExp(
    r'[\u200b-\u200f\u202a-\u202e\u2060-\u206f\ufeff]',
  );
  static final _diacritics = RegExp(
    r'[\u0610-\u061a\u064b-\u065f\u0670\u06d6-\u06ed]',
  );
  static final _separator = RegExp(r'[^\p{L}\p{N}]+', unicode: true);
  static final _arabic = RegExp(r'[\u0600-\u06ff]');
  static final _latinCategory = RegExp(r'^[a-z]{4,}$');
  static List<String> words(String s) =>
      s.split(' ').where((s) => s.isNotEmpty).toList();
  static bool sequence(String a, String b) =>
      a.isNotEmpty && b.isNotEmpty && ' $a '.contains(' $b ');

  String normalize(String value) => unicode
      .nfkc(
        value
            .replaceAllMapped(RegExp(r'[٠-٩۰-۹]'), (m) => digits[m[0]]!)
            .toLowerCase(),
      )
      .replaceAll(_invisible, '')
      .replaceAll(_diacritics, '')
      .replaceAll('ـ', '')
      .replaceAll(RegExp('[أإآٱ]'), 'ا')
      .replaceAll(RegExp('[يى]'), 'ی')
      .replaceAll('ك', 'ک')
      .replaceAll(RegExp('[ةۀ]'), 'ە')
      .replaceAll('ھ', 'ه')
      .replaceAll(_separator, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  String _skeleton(String text, bool y, bool w, bool latin) {
    if (y) text = text.replaceAll(RegExp('ia|ya'), 'y');
    if (w) text = text.replaceAll(RegExp('ua|wa'), 'w');
    if (latin) {
      for (final pair in [
        ['ph', 'f'],
        ['tsh', 'ch'],
        ['ck|qu|q', 'k'],
        ['dh', 'z'],
        ['th', 's'],
        ['c(?=[eiy])', 's'],
        ['c(?!h)', 'k'],
        ['g(?=[eiy])', 'j'],
        ['x', 'ks'],
        ['dj', 'j'],
      ]) {
        text = text.replaceAll(RegExp(pair[0]), pair[1]);
      }
    }
    return text
        .replaceAll('tsh', 'ch')
        .replaceAll('dj', 'j')
        .replaceAll('v', 'f')
        .replaceAll('w', w ? 'w' : 'u')
        .replaceAll(RegExp(y ? '[aeiou]' : '[aeiouy]'), '')
        .replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  }

  List<List<String>> phonetics(String value) {
    final normalized = unicode
        .nfkd(normalize(value))
        .replaceAll(RegExp(r'\p{M}', unicode: true), '');
    final groups = <List<String>>[];
    for (final word in words(normalized)) {
      final keys = <String>{};
      for (final flags in [
        (false, false),
        (true, false),
        (false, true),
        (true, true),
      ]) {
        var text = word;
        if (flags.$1) text = text.replaceAll(RegExp('[یێ]'), 'y');
        if (flags.$2) text = text.replaceAll(RegExp('[وؤ]'), 'w');
        text = text.replaceAllMapped(_arabic, (m) => letters[m[0]] ?? m[0]!);
        final key = _skeleton(
          text,
          flags.$1,
          flags.$2,
          !_arabic.hasMatch(word),
        );
        if (key.length >= 2) keys.add(key);
      }
      if (keys.isNotEmpty) groups.add(keys.toList());
    }
    return groups;
  }

  SearchQuery prepare(String raw) {
    final normalized = normalize(raw), tokens = words(normalized);
    var matched = intents
        .where(
          (g) => (g['aliases'] as List).any(
            (a) => sequence(normalized, a as String),
          ),
        )
        .toList();
    if (matched.isEmpty &&
        tokens.length == 1 &&
        _latinCategory.hasMatch(tokens[0])) {
      matched = coreIntents
          .where(
            (g) => (g['aliases'] as List).any(
              (a) =>
                  _latinCategory.hasMatch(a as String) &&
                  editDistance(a, tokens[0], 1) <= 1,
            ),
          )
          .toList();
    }
    final consumed = {
      for (final g in matched)
        for (final a in g['aliases'] as List) ...words(a as String),
    };
    final fuzzy =
        tokens.length == 1 &&
        matched.any(
          (g) => (g['aliases'] as List).any(
            (a) =>
                _latinCategory.hasMatch(a as String) &&
                editDistance(a, tokens[0], 1) <= 1,
          ),
        );
    final meaningful = tokens
        .where((t) => !stopwords.contains(t) && !consumed.contains(t) && !fuzzy)
        .toList();
    final ids = matched.map((g) => g['id'] as String).toSet().toList();
    final phrase = meaningful.isNotEmpty
        ? meaningful.join(' ')
        : ids.isNotEmpty
        ? ids.join(' ')
        : normalized;
    return SearchQuery(
      phrase,
      {...meaningful, ...ids}.toList(),
      ids,
      phonetics(meaningful.isNotEmpty ? meaningful.join(' ') : normalized),
    );
  }

  static bool shortAscii(String s) =>
      s.length < 2 && RegExp(r'^[a-z0-9]+$').hasMatch(s);
  static int _phrase(String text, String phrase, List<int> scores) {
    if (text.isEmpty || phrase.isEmpty) return 0;
    if (text == phrase) return scores[0];
    if (shortAscii(phrase)) return words(text).contains(phrase) ? scores[0] : 0;
    if (text.startsWith(phrase)) return scores[1];
    return text.contains(phrase) ? scores[2] : 0;
  }

  static int _quality(List<String> text, String token) {
    if (token.isEmpty || text.isEmpty) return 0;
    if (text.contains(token)) return 5;
    if (!shortAscii(token) && text.any((w) => w.startsWith(token))) return 4;
    if (token.length >= 4 &&
        text.any((w) => w.length >= 3 && token.startsWith(w))) {
      return 3;
    }
    if (token.length >= 4 && text.any((w) => w.contains(token))) return 2;
    final max = token.length >= 8
        ? 2
        : token.length >= 4
        ? 1
        : 0;
    return max > 0 &&
            text.any((w) => w.length >= 4 && editDistance(w, token, max) <= max)
        ? 2
        : 0;
  }

  static int _coverage(String text, List<String> tokens) {
    var score = 0;
    final w = words(text);
    for (final t in tokens) {
      final q = _quality(w, t);
      if (q == 0) return 0;
      score += q * 120;
    }
    return score;
  }

  int score(Map<String, dynamic> row, SearchQuery q, List<String> phonetic) =>
      scoreLazy(row, q, () => phonetic);

  int scoreLazy(
    Map<String, dynamic> row,
    SearchQuery q,
    List<String> Function() loadPhonetic,
  ) {
    if (q.phrase.length < 2 && q.tokens.isEmpty) return 0;
    var score = q.phrase.length < 2
        ? 0
        : _phrase(row['primary_name'] as String, q.phrase, [6000, 3000, 1350]) +
              _phrase(row['all_names'] as String, q.phrase, [5400, 2350, 1050]);
    if (score == 0 &&
        q.intentIds.isEmpty &&
        q.phoneticGroups.isNotEmpty &&
        q.phoneticGroups.every(
          (g) => g.any(
            (t) => loadPhonetic().any(
              (n) => n == t || (t.length >= 3 && n.startsWith(t)),
            ),
          ),
        )) {
      score = 850;
    }
    score += _phrase(row['primary_text'] as String, q.phrase, [
      2300,
      1850,
      720,
    ]);
    score += _phrase(row['all_text'] as String, q.phrase, [1700, 1350, 460]);
    final intents = words(row['intent'] as String).toSet();
    final matching = q.intentIds.where(intents.contains).length;
    if (matching > 0) {
      score += matching == q.intentIds.length ? 4200 + matching * 600 : 1500;
    }
    final primary = _coverage(row['primary_text'] as String, q.tokens);
    score += primary > 0
        ? primary + 520
        : _coverage(row['all_text'] as String, q.tokens);
    final kind = row['kind'];
    return score > 0
        ? score +
              (kind == 'place'
                  ? 90
                  : kind == 'street'
                  ? 80
                  : kind == 'poi'
                  ? 60
                  : kind == 'building'
                  ? 45
                  : 25)
        : 0;
  }
}

int editDistance(String a, String b, [int? maximum]) {
  if (a == b) return 0;
  if (maximum != null && (a.length - b.length).abs() > maximum) {
    return maximum + 1;
  }
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 1; i <= a.length; i++) {
    final current = <int>[i];
    var rowMinimum = i;
    for (var j = 1; j <= b.length; j++) {
      final value = math.min(
        math.min(previous[j] + 1, current[j - 1] + 1),
        previous[j - 1] + (a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1),
      );
      current.add(value);
      rowMinimum = math.min(rowMinimum, value);
    }
    if (maximum != null && rowMinimum > maximum) return maximum + 1;
    previous = current;
  }
  return previous[b.length];
}
