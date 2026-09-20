import 'dart:convert';
import 'dart:io';
import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';

/// Minimal new-code smoke check, not parity, performance or device QA.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('Usage: dart run bin/check_core.dart CORE_DIRECTORY');
  }
  final root = Directory(args.single).absolute.path;
  final temporary = await Directory.systemTemp.createTemp(
    'nav-kurd-core-check-',
  );
  LocalDataClient? client;
  try {
    client = await LocalDataClient.open(
      packDirectory: root,
      userDatabase: '${temporary.path}/user.sqlite',
    );
    final versions = await client.versions();
    final assets = await client.assetPath('/icons/nav-kurd-logo.png');
    if (!await File(assets).exists()) {
      throw StateError('Bundled logo is missing.');
    }
    final searchCounts = <String, int>{};
    for (final query in [
      ('en', 'Erbil'),
      ('ku', 'هەولێر'),
      ('ar', 'أربيل'),
      ('ku', 'کارفور'),
      ('ar', 'كارفور'),
    ]) {
      final rows = await client.search(query.$2, query.$1, limit: 5);
      if (rows.isEmpty) {
        throw StateError(
          'New search implementation returned no rows for ${query.$2}.',
        );
      }
      searchCounts['${query.$1}:${query.$2}'] = rows.length;
    }
    final places = await client.viewport(
      [43.9, 36.1, 44.1, 36.3],
      'ku',
      limit: 8,
    );
    if ((places['features'] as List).isEmpty) {
      throw StateError('Local spatial query returned no records.');
    }
    await client.setPreference('language', 'ku');
    await client.close();
    client = null;
    client = await LocalDataClient.open(
      packDirectory: root,
      userDatabase: '${temporary.path}/user.sqlite',
    );
    if (await client.preference('language') != 'ku') {
      throw StateError('Local preference was not persisted.');
    }
    final maps = <String, Object?>{};
    for (final name in ['kri-base', 'kri-roads']) {
      final reader = await PmTilesReader.open('$root/maps/$name.pmtiles');
      try {
        final metadata = await reader.metadata();
        // Actual coverage tile around Erbil; no fabricated tile payload.
        final tile = await reader.tile(8, 159, 100);
        if (tile == null || tile.isEmpty) {
          throw StateError('Cannot read the bundled $name tile.');
        }
        maps[name] = {
          'tileBytes': tile.length,
          'layers': metadata['vector_layers'],
          'bytesRead': reader.bytesRead,
        };
      } finally {
        await reader.close();
      }
    }
    print(
      jsonEncode({
        'scope': 'new-code-smoke-only',
        'versions': versions,
        'searchResultCounts': searchCounts,
        'viewportRows': (places['features'] as List).length,
        'settingsPersisted': true,
        'maps': maps,
      }),
    );
  } finally {
    await client?.close();
    await temporary.delete(recursive: true);
  }
}
