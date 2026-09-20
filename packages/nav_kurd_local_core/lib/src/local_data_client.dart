import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:sqlite3/sqlite3.dart';
import 'catalog_database.dart';
import 'core_failure.dart';
import 'core_manifest.dart';
import 'local_state.dart';
import 'navigation_history.dart';
import 'r16_preferences.dart';
import 'place_repository.dart';
import 'search_repository.dart';
import 'locality_search_repository.dart';
import 'pmtiles_reader.dart';

/// One isolate owns the catalog, search, spatial reads and mutable preferences.
/// Opened once by the Android composition root before presentation startup.
final class LocalDataClient {
  LocalDataClient._();
  final _messages = ReceivePort(),
      _errors = ReceivePort(),
      _exits = ReceivePort();
  final _ready = Completer<void>();
  final _pending = <int, Completer<Object?>>{};
  SendPort? _port;
  Isolate? _worker;
  int _next = 0;
  bool _closed = false, _closing = false;
  late final String packId;
  late final Map<String, dynamic> versionInfo;
  late final Map<String, Map<String, Object>> _assetIndex;
  Future<void>? _closeFuture;
  static Future<LocalDataClient> open({
    required String packDirectory,
    required String userDatabase,
    Map<String, Map<String, Object?>> mapArchives = const {},
    String? installerVerifiedPackId,
  }) async {
    final root = await Directory(packDirectory).resolveSymbolicLinks(),
        user = File(userDatabase);
    await user.parent.create(recursive: true);
    final userParent = await user.parent.resolveSymbolicLinks();
    final userPath = await user.exists()
        ? await user.resolveSymbolicLinks()
        : '$userParent/${user.uri.pathSegments.last}';
    if (userPath == root ||
        userPath.startsWith('$root${Platform.pathSeparator}')) {
      throw const CoreFailure(
        'invalid_user_store',
        'Mutable user storage must be outside the immutable core pack.',
      );
    }
    final client = LocalDataClient._();
    client._messages.listen(client._message);
    client._errors.listen(
      (Object? e) => client._fail(CoreFailure('worker_error', '$e')),
    );
    client._exits.listen((_) {
      if (!client._closed && !client._closing) {
        client._fail(
          const CoreFailure(
            'worker_exit',
            'The local data worker exited unexpectedly.',
          ),
        );
      }
    });
    try {
      client._worker = await Isolate.spawn(
        _run,
        [
          client._messages.sendPort,
          root,
          userPath,
          mapArchives,
          installerVerifiedPackId,
        ],
        onError: client._errors.sendPort,
        onExit: client._exits.sendPort,
        errorsAreFatal: true,
        debugName: 'nav_kurd_local_core',
      );
      await client._ready.future;
      return client;
    } catch (_) {
      client._dispose();
      rethrow;
    }
  }

  void _message(dynamic raw) {
    final message = raw as Map;
    if (message['port'] is SendPort) {
      _port = message['port'] as SendPort;
      packId = message['packId'] as String;
      versionInfo = Map<String, dynamic>.unmodifiable(
        Map<String, dynamic>.from(message['versions'] as Map),
      );
      _assetIndex = Map<String, Map<String, Object>>.unmodifiable({
        for (final entry in (message['assetIndex'] as Map).entries)
          entry.key as String: Map<String, Object>.unmodifiable(
            Map<String, Object>.from(entry.value as Map),
          ),
      });
      _ready.complete();
      return;
    }
    final error = message['error'] as Map?;
    final failure = error == null
        ? null
        : CoreFailure(error['code'] as String, error['message'] as String);
    if (message['id'] == null) {
      _fail(
        failure ??
            const CoreFailure('worker_protocol', 'Invalid worker response.'),
      );
      return;
    }
    final pending = _pending.remove(message['id']);
    if (pending != null) {
      if (failure != null) {
        pending.completeError(failure);
      } else {
        pending.complete(message['value']);
      }
    }
  }

  void _fail(CoreFailure error) {
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final p in _pending.values) {
      p.completeError(error);
    }
    _pending.clear();
    _dispose();
  }

  void _dispose() {
    if (_closed) return;
    _closed = true;
    _worker?.kill(priority: Isolate.immediate);
    _messages.close();
    _errors.close();
    _exits.close();
  }

  Future<Object?> _request(String op, [Map<String, Object?> args = const {}]) {
    if (_closed || _closing) {
      return Future.error(
        const CoreFailure('closed', 'Local data client is closed.'),
      );
    }
    if (_pending.length >= 64) {
      return Future.error(
        const CoreFailure('busy', 'Local data request queue is full.'),
      );
    }
    final id = ++_next, c = Completer<Object?>();
    _pending[id] = c;
    _port!.send({'id': id, 'op': op, ...args});
    return c.future;
  }

  Future<List<Map<String, Object?>>> search(
    String text,
    String language, {
    int limit = 20,
  }) async => List<Map<String, Object?>>.from(
    await _request('search', {
          'text': text,
          'language': language,
          'limit': limit,
        })
        as List,
  );
  Future<Map<String, Object?>> localitySearch(
    String text,
    String language, {
    bool quick = false,
  }) async => Map<String, Object?>.from(
    await _request('localitySearch', {
          'text': text,
          'language': language,
          'quick': quick,
        })
        as Map,
  );
  Future<Map<String, Object?>> statistics() async =>
      Map<String, Object?>.from(await _request('statistics') as Map);
  Future<Map<String, Object?>> poiManifest() async =>
      Map<String, Object?>.from(await _request('poiManifest') as Map);
  Future<Map<String, Object?>> poiShard(String dataset, String key) async =>
      Map<String, Object?>.from(
        await _request('poiShard', {'dataset': dataset, 'key': key}) as Map,
      );
  Future<Map<String, Object?>> viewport(
    List<double> bounds,
    String language, {
    List<String> datasets = const ['base', 'natural', 'locality'],
    int after = 0,
    int limit = 128,
    int minimumLocalityRank = 0,
  }) async => Map<String, Object?>.from(
    await _request('viewport', {
          'bounds': bounds,
          'language': language,
          'datasets': datasets,
          'minimumLocalityRank': minimumLocalityRank,
          'after': after,
          'limit': limit,
        })
        as Map,
  );
  Future<Map<String, Object?>?> place(int catalogId, String language) async =>
      (await _request('place', {'idValue': catalogId, 'language': language}))
          as Map<String, Object?>?;
  Future<Map<String, Object?>> reverse(
    double longitude,
    double latitude,
    String language,
  ) async => Map<String, Object?>.from(
    await _request('reverse', {
          'longitude': longitude,
          'latitude': latitude,
          'language': language,
        })
        as Map,
  );
  Future<Map<String, Object?>> importR16Preferences(
    Map<String, Object?> values,
  ) async => Map<String, Object?>.from(
    await _request('importR16Preferences', {'values': values}) as Map,
  );
  Future<void> saveUiSnapshot(Map<String, Object?> snapshot) async {
    await _request('saveUiSnapshot', {'snapshot': snapshot});
  }

  Future<Object?> preference(String key) =>
      _request('preference', {'key': key});
  Future<void> setPreference(String key, Object? value) async {
    await _request('setPreference', {'key': key, 'value': value});
  }

  Future<void> removePreference(String key) async {
    await _request('removePreference', {'key': key});
  }

  Future<Map<String, Object?>> importNavigationHistory(String? raw) async =>
      Map<String, Object?>.from(
        await _request('importNavigationHistory', {'raw': raw}) as Map,
      );
  Future<List<Map<String, Object?>>> navigationHistory(String? userId) async =>
      List<Map<String, Object?>>.from(
        await _request('navigationHistory', {'userId': userId}) as List,
      );
  Future<void> queueNavigationHistory(
    Map<String, Object?> entry,
    String? userId,
  ) async {
    await _request('queueNavigationHistory', {
      'entry': entry,
      'userId': userId,
    });
  }

  Future<void> removeNavigationHistory(
    String? id,
    String userId, {
    int? expectedRevision,
  }) async {
    await _request('removeNavigationHistory', {
      'entryId': id,
      'userId': userId,
      'expectedRevision': expectedRevision,
    });
  }

  Future<String> assetPath(String path) async =>
      await _request('asset', {'path': path}) as String;
  Future<Map<String, Map<String, Object>>> assetIndex() async => _assetIndex;
  Future<Uint8List?> mapTile(String archive, int z, int x, int y) async {
    final result = await _request('mapTile', {
      'archive': archive,
      'z': z,
      'x': x,
      'y': y,
    });
    return result == null
        ? null
        : (result as TransferableTypedData).materialize().asUint8List();
  }

  Future<Map<String, Object?>> mapMetadata(String archive) async =>
      Map<String, Object?>.from(
        await _request('mapMetadata', {'archive': archive}) as Map,
      );
  Future<void> setMapArchives(
    Map<String, Map<String, Object?>> archives,
  ) async {
    await _request('setMapArchives', {'archives': archives});
  }

  Future<Map<String, Object?>> versions() async => <String, Object?>{
    'packId': packId,
    ...versionInfo,
  };
  Future<void> close() {
    if (_closeFuture != null) return _closeFuture!;
    if (_closed) return Future.value();
    final response = _request('close');
    _closing = true;
    return _closeFuture = response.then(
      (_) => _dispose(),
      onError: (Object e, StackTrace s) {
        _dispose();
        Error.throwWithStackTrace(e, s);
      },
    );
  }
}

Future<void> _run(List<Object?> args) async {
  final reply = args[0] as SendPort, inbox = ReceivePort();
  Database? database;
  LocalState? state;
  SearchRepository? search;
  PlaceRepository? places;
  LocalitySearchRepository? localitySearch;
  final maps = <String, PmTilesReader>{};
  try {
    final manifest = await CoreManifest.load(args[1] as String);
    var mapArchives = Map<String, Map<String, Object?>>.from(args[3] as Map);
    final installerVerifiedPackId = args[4] as String?;
    if (installerVerifiedPackId == null) {
      await manifest.verify(hashes: false, mapArchives: mapArchives);
    } else {
      if (installerVerifiedPackId != manifest.packId) {
        throw const CoreFailure(
          'pack_identity',
          'The native installer receipt and local manifest disagree.',
        );
      }
      // Android has already checked the immutable ready receipt for every
      // core file. Revalidate only the selected random-access map ranges here.
      await manifest.verifyMapArchives(mapArchives);
    }
    database = openCatalog(manifest);
    state = LocalState(args[2] as String);
    search = SearchRepository(database);
    places = PlaceRepository(database);
    localitySearch = LocalitySearchRepository(database, search.rules, places);
    final localityOwner = localitySearch;
    final searchOwner = search, placeOwner = places, stateOwner = state;
    final ui = R16Preferences(stateOwner);
    final history = NavigationHistory(stateOwner);
    Future<PmTilesReader> mapReader(String archive) async {
      if (!const {'base', 'roads'}.contains(archive)) {
        throw const CoreFailure(
          'invalid_archive',
          'Expected the bundled base or roads archive.',
        );
      }
      final path = 'maps/kri-$archive.pmtiles', range = mapArchives[path];
      return maps[archive] ??= await PmTilesReader.open(
        range == null ? manifest.file(path).path : range['path'] as String,
        offset: range?['offset'] as int? ?? 0,
        length: range?['bytes'] as int?,
      );
    }

    var latestSearch = 0;
    var closing = false;
    Future<void> dataQueue = Future.value(), mapQueue = Future.value();
    Future<void> dispatch(Map<String, dynamic> message) async {
      final id = message['id'] as int, op = message['op'];
      try {
        final Object? result;
        switch (op) {
          case 'search':
            result = await searchOwner.search(
              message['text'] as String,
              message['language'] as String,
              limit: message['limit'] as int,
              cancelled: () => id != latestSearch,
            );
          case 'localitySearch':
            result = await localityOwner.search(
              message['text'] as String,
              message['language'] as String,
              quick: message['quick'] as bool,
              cancelled: () => id != latestSearch,
            );
          case 'statistics':
            result = {
              'datasets': {
                for (final r in database!.select(
                  'SELECT id,records FROM dataset',
                ))
                  r['id'] as String: r['records'],
              },
              'search': {
                for (final r in database.select(
                  'SELECT language,count(*) AS records FROM search_row GROUP BY language',
                ))
                  r['language'] as String: r['records'],
              },
            };
          case 'poiManifest':
            result = placeOwner.poiManifest();
          case 'poiShard':
            result = placeOwner.poiShard(
              message['dataset'] as String,
              message['key'] as String,
            );
          case 'viewport':
            result = placeOwner.viewport(
              List<double>.from(message['bounds'] as List),
              message['language'] as String,
              selected: List<String>.from(message['datasets'] as List),
              minimumLocalityRank: message['minimumLocalityRank'] as int,
              after: message['after'] as int,
              limit: message['limit'] as int,
            );
          case 'place':
            result = placeOwner.get(
              message['idValue'] as int,
              message['language'] as String,
            );
          case 'reverse':
            result = placeOwner.reverse(
              message['longitude'] as double,
              message['latitude'] as double,
              message['language'] as String,
            );
          case 'importNavigationHistory':
            result = history.importLegacy(message['raw'] as String?);
          case 'navigationHistory':
            result = history.list(message['userId'] as String?);
          case 'queueNavigationHistory':
            history.queue(
              message['entry'] as Map,
              message['userId'] as String?,
            );
            result = null;
          case 'removeNavigationHistory':
            history.remove(
              message['entryId'] as String?,
              message['userId'] as String,
              expectedRevision: message['expectedRevision'] as int?,
            );
            result = null;
          case 'importR16Preferences':
            result = ui.importLegacy(
              Map<String, Object?>.from(message['values'] as Map),
            );
          case 'saveUiSnapshot':
            ui.save(message['snapshot'] as Map);
            result = null;
          case 'preference':
            result = stateOwner.get(message['key'] as String);
          case 'setPreference':
            stateOwner.set(message['key'] as String, message['value']);
            result = null;
          case 'removePreference':
            stateOwner.remove(message['key'] as String);
            result = null;
          case 'asset':
            result = await manifest.assetPath(message['path'] as String);
          case 'mapTile':
            final reader = await mapReader(message['archive'] as String);
            final tile = await reader.tile(
              message['z'] as int,
              message['x'] as int,
              message['y'] as int,
            );
            result = tile == null
                ? null
                : TransferableTypedData.fromList([tile]);
          case 'mapMetadata':
            final reader = await mapReader(message['archive'] as String);
            result = {
              'metadata': await reader.metadata(),
              'minZoom': reader.minimumZoom,
              'maxZoom': reader.maximumZoom,
              'bounds': reader.bounds,
            };
          case 'setMapArchives':
            final next = Map<String, Map<String, Object?>>.from(
              message['archives'] as Map,
            );
            await manifest.verifyMapArchives(next);
            for (final reader in maps.values) {
              await reader.close();
            }
            maps.clear();
            mapArchives = next;
            result = null;
          default:
            throw const CoreFailure(
              'invalid_operation',
              'Unknown local data operation.',
            );
        }
        reply.send({'id': id, 'value': result});
      } catch (e) {
        final failure = e is CoreFailure
            ? e
            : CoreFailure(
                e is SqliteException ? 'database_error' : 'local_error',
                e.toString(),
              );
        reply.send({'id': id, 'error': failure.toJson()});
      }
    }

    inbox.listen((dynamic raw) {
      final message = Map<String, dynamic>.from(raw as Map),
          id = message['id'] as int,
          op = message['op'];
      if (op == 'search' || op == 'localitySearch' || op == 'close') {
        latestSearch = id;
      }
      if (op == 'close') {
        if (closing) return;
        closing = true;
        Future.wait([dataQueue, mapQueue]).then((_) async {
          for (final reader in maps.values) {
            await reader.close();
          }
          maps.clear();
          localityOwner.close();
          searchOwner.close();
          placeOwner.close();
          stateOwner.close();
          database!.close();
          inbox.close();
          reply.send({'id': id, 'value': null});
        });
        return;
      }
      if (closing) {
        reply.send({
          'id': id,
          'error': const CoreFailure(
            'closed',
            'Local data client is closing.',
          ).toJson(),
        });
        return;
      }
      if (op == 'mapTile' || op == 'mapMetadata' || op == 'setMapArchives') {
        mapQueue = mapQueue.then((_) => dispatch(message));
      } else {
        dataQueue = dataQueue.then((_) => dispatch(message));
      }
    });
    reply.send({
      'port': inbox.sendPort,
      'packId': manifest.packId,
      'versions': manifest.versions,
      'assetIndex': await manifest.assetIndex(),
    });
  } catch (e) {
    for (final reader in maps.values) {
      await reader.close();
    }
    localitySearch?.close();
    search?.close();
    places?.close();
    state?.close();
    database?.close();
    inbox.close();
    final failure = e is CoreFailure
        ? e
        : CoreFailure('local_startup', e.toString());
    reply.send({'error': failure.toJson()});
  }
}
