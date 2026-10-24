import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'core_failure.dart';

final class CoreManifest {
  CoreManifest._(this.directory, this.json, this.files);
  final Directory directory;
  final Map<String, dynamic> json;
  final Map<String, Map<String, dynamic>> files;
  Map<String, String>? _assets;
  String get packId => json['packId'] as String;
  Map<String, dynamic> get versions =>
      Map<String, dynamic>.from(json['versions'] as Map);

  static bool safePath(String p) =>
      p.isNotEmpty &&
      !p.startsWith('/') &&
      !p.contains('\\') &&
      !p.contains(':') &&
      !p.contains('\u0000') &&
      p.split('/').every((v) => v.isNotEmpty && v != '.' && v != '..');
  static Future<CoreManifest> load(String root) async {
    final dir = Directory(root), file = File('$root/manifest.json');
    if (!await file.exists()) {
      throw const CoreFailure('missing_manifest', 'Core manifest is missing.');
    }
    if (await file.length() > 2 * 1024 * 1024) {
      throw const CoreFailure('invalid_manifest', 'Manifest exceeds 2 MiB.');
    }
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['schema'] != 1 ||
          json['minimumReader'] != 1 ||
          json['searchSchema'] != 1) {
        throw const CoreFailure(
          'unsupported_schema',
          'Unsupported core reader or catalog schema.',
        );
      }
      final pack = json['packId'] as String;
      if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$').hasMatch(pack) ||
          pack.contains('..')) {
        throw const CoreFailure('invalid_manifest', 'Unsafe pack identity.');
      }
      final entries = <String, Map<String, dynamic>>{};
      for (final item in json['files'] as List) {
        final f = Map<String, dynamic>.from(item as Map),
            path = f['path'] as String;
        if (!safePath(path) ||
            entries.containsKey(path) ||
            f['bytes'] is! int ||
            (f['bytes'] as int) < 0 ||
            f['sha256'] is! String ||
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(f['sha256'] as String)) {
          throw const CoreFailure(
            'invalid_manifest',
            'Invalid or duplicated core file descriptor.',
          );
        }
        entries[path] = f;
      }
      for (final required in [
        'catalog.sqlite',
        'maps/kri-base.pmtiles',
        'maps/kri-roads.pmtiles',
        'styles/street.json',
        'styles/night.json',
        'content/asset-map.json',
      ]) {
        if (!entries.containsKey(required)) {
          throw CoreFailure(
            'invalid_manifest',
            'Missing required descriptor: $required',
          );
        }
      }
      final paths = entries.keys.toList()..sort();
      final signature = paths
          .map(
            (p) =>
                '$p\u0000${entries[p]!['bytes']}\u0000${entries[p]!['sha256']}\n',
          )
          .join();
      final hash = sha256.convert(utf8.encode(signature)).toString();
      if (hash != json['contentHash'] ||
          pack !=
              '${(json['versions'] as Map)['offlinePackVersion']}-${hash.substring(0, 16)}') {
        throw const CoreFailure(
          'invalid_manifest',
          'Pack content identity does not match its file inventory.',
        );
      }
      return CoreManifest._(dir, json, entries);
    } on CoreFailure {
      rethrow;
    } on FormatException catch (e) {
      throw CoreFailure('invalid_manifest', e.message);
    } on TypeError {
      throw const CoreFailure(
        'invalid_manifest',
        'Core manifest has invalid field types.',
      );
    }
  }

  File file(String path) {
    if (!files.containsKey(path)) {
      throw CoreFailure('unknown_asset', 'Undeclared core file: $path');
    }
    return File('${directory.path}/$path');
  }

  static const mapPaths = {'maps/kri-base.pmtiles', 'maps/kri-roads.pmtiles'};
  Future<void> verifyMapArchives(Map<String, Map<String, Object?>> ranges, {bool hashes = false}) async {
    if (ranges.length != 2 || !ranges.keys.every(mapPaths.contains)) {
      throw const CoreFailure('map_sources', 'Both declared map archives are required.');
    }
    for (final path in mapPaths) {
      await _verifyEntry(path, files[path]!, hashes, ranges[path]);
    }
  }

  Future<void> verify({bool hashes = true, Map<String, Map<String, Object?>> mapArchives = const {}}) async {
    if (mapArchives.isNotEmpty && (mapArchives.length != 2 || !mapArchives.keys.every(mapPaths.contains))) {
      throw const CoreFailure('map_sources', 'Invalid map archive ownership.');
    }
    for (final entry in files.entries) {
      await _verifyEntry(entry.key, entry.value, hashes, mapArchives[entry.key]);
    }
  }

  Future<void> _verifyEntry(String path, Map<String,dynamic> spec, bool hashes, Map<String,Object?>? range) async {
      final offset = range?['offset'] ?? 0;
      final length = range?['bytes'] ?? spec['bytes'];
      if (offset is! int || offset < 0 || length != spec['bytes'] ||
          (range != null && range['path'] is! String)) {
        throw const CoreFailure('map_sources', 'Invalid installed archive descriptor.');
      }
      final f = range == null ? file(path) : File(range['path'] as String);
      if (await FileSystemEntity.type(f.path, followLinks: false) !=
              FileSystemEntityType.file ||
          (range == null ? await f.length() != length : offset + (length as int) > await f.length())) {
        throw CoreFailure(
          'corrupt_core',
          'Missing file or incorrect size: $path',
        );
      }
      if (hashes &&
          (await sha256.bind(f.openRead(offset, offset + (length as int))).first).toString() !=
              spec['sha256']) {
        throw CoreFailure('corrupt_core', 'Hash mismatch: $path');
      }
  }

  Future<void> _loadAssets() async {
    _assets ??= Map<String, String>.from(
      jsonDecode(await file('content/asset-map.json').readAsString()) as Map,
    );
  }
  Future<Map<String, Map<String, Object>>> assetIndex() async {
    await _loadAssets();
    return {for (final entry in _assets!.entries) entry.key: {
      'path': file(entry.value).path, 'bytes': files[entry.value]!['bytes'] as int,
    }};
  }
  Future<String> assetPath(String originalPath) async {
    await _loadAssets();
    final path = _assets![originalPath];
    if (path == null) {
      throw CoreFailure('unknown_asset', 'No bundled asset for $originalPath');
    }
    final result = file(path);
    if (!await result.exists()) {
      throw CoreFailure('corrupt_core', 'Bundled asset is missing: $path');
    }
    return result.path;
  }
}
