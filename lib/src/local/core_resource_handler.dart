import 'dart:io';
import 'bundled_presentation.dart';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/native_bridge.dart';
import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';

/// Manifest-owned static assets, served at their approved HTTPS-origin URLs.
/// There is no network retry for a damaged local file.
final class CoreResourceHandler {
  CoreResourceHandler(this._assets, this._data, this._presentation);
  final BundledPresentation _presentation;
  final LocalDataClient _data;
  final Map<String, Map<String, Object>> _assets;
  final _layerCache = LinkedHashMap<String, Uint8List>();
  final _layerLoads = <String, Future<Uint8List>>{};
  final _metadataLoads = <String, Future<Map<String, Object?>>>{};
  Future<Map<String, Uint8List>>? _coverageLoad;
  int _layerCacheBytes = 0;
  static const _maximumLayerCacheBytes = 12 * 1024 * 1024;
  static const _mime = <String, String>{
    'css': 'text/css',
    'html': 'text/html',
    'js': 'application/javascript',
    'json': 'application/json',
    'webmanifest': 'application/manifest+json',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'webp': 'image/webp',
    'gif': 'image/gif',
    'ico': 'image/x-icon',
    'ttf': 'font/ttf',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'md': 'text/plain',
  };
  Future<WebResourceResponse?> respond(WebResourceRequest request) async {
    final uri = Uri.tryParse(request.url.toString());
    if (!AppConfig.isTrustedOrigin(uri)) return null;
    final prefix = AppConfig.appUri.path.endsWith('/')
        ? AppConfig.appUri.path
        : '${AppConfig.appUri.path}/';
    final path = uri!.path;
    final original = prefix != '/' && path.startsWith(prefix)
        ? '/${path.substring(prefix.length)}'
        : path;
    if (original.startsWith('/__navkurd/maps/'))
      return _map(request, uri, original);
    final dataset = _layers[original];
    if (dataset != null) return _layer(request, dataset);
    final uiPath = original == '/' ? '/index.html' : original;
    if (_presentation.contains(uiPath)) return _ui(request, uiPath);
    final asset = _assets[original];
    if (asset == null) return null;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        throw const CoreFailure('asset_method', 'Local assets are read-only.');
      }
      final size = asset['bytes']! as int;
      if (size > 8 * 1024 * 1024)
        throw const CoreFailure(
          'asset_size',
          'UI resource exceeds the bounded response size.',
        );
      final file = File(asset['path']! as String);
      if (await file.length() != size)
        throw CoreFailure(
          'corrupt_core',
          'Installed resource size changed: $original',
        );
      final bytes = request.method == 'HEAD'
          ? Uint8List(0)
          : await file.readAsBytes();
      if (request.method != 'HEAD' && bytes.length != size)
        throw CoreFailure(
          'corrupt_core',
          'Installed resource changed during read: $original',
        );
      final extension = original.split('.').last.toLowerCase(),
          mime = _mime[extension];
      if (mime == null)
        throw CoreFailure(
          'asset_type',
          'Unsupported bundled resource type: $extension',
        );
      return WebResourceResponse(
        contentType: mime,
        contentEncoding:
            const {'css', 'html', 'js', 'json', 'svg', 'md'}.contains(extension)
            ? 'utf-8'
            : null,
        statusCode: 200,
        reasonPhrase: 'OK',
        data: bytes,
        headers: {
          'Content-Length': '$size',
          'Cache-Control': 'no-store',
          'X-Content-Type-Options': 'nosniff',
        },
      );
    } catch (error, stack) {
      await NativeBridge.instance.recordDiagnostic(
        level: 'error',
        source: 'local.resource',
        message: '$original: $error',
        stack: stack.toString(),
      );
      return WebResourceResponse(
        contentType: 'text/plain',
        contentEncoding: 'utf-8',
        statusCode: 500,
        reasonPhrase: 'Local resource unavailable',
        headers: const {'Cache-Control': 'no-store'},
        data: Uint8List.fromList(
          'Required local resource is unavailable.'.codeUnits,
        ),
      );
    }
  }

  Future<WebResourceResponse> _ui(
    WebResourceRequest request,
    String path,
  ) async {
    try {
      _readOnly(request);
      final mime = _mime[path.split('.').last];
      if (mime == null)
        throw CoreFailure(
          'asset_type',
          'Unsupported bundled presentation resource: $path',
        );
      return _response(request, await _presentation.read(path), mime);
    } catch (error, stack) {
      return _failure('local.presentation', error, stack);
    }
  }

  static const _layers = {
    '/data/kri/kri-boundary.geojson': 'boundary',
    '/data/kri/kri-boundary-line.geojson': 'boundary_line',
    '/data/kri/kri-governorates.geojson': 'governorate',
    '/data/kri/kri-districts.geojson': 'district',
    '/data/kri/kri-labels.geojson': 'region_labels',
    '/data/kri/kri-road-labels.geojson': 'road_labels',
    '/data/kri/kri-outside-mask.geojson': 'mask',
    '/data/kri/kri-localities-major-runtime.geojson': 'major',
    '/data/kri/kri-localities-cluster-runtime.geojson': 'cluster',
    '/data/kri/kri-security-features.geojson': 'security',
    '/data/kri/kri-reviewed-poi-corrections.geojson': 'reviewed',
  };
  static const _coverageDatasets = <String>[
    'boundary',
    'boundary_line',
    'governorate',
    'district',
    'region_labels',
    'road_labels',
    'mask',
  ];
  WebResourceResponse _response(
    WebResourceRequest request,
    Uint8List bytes,
    String mime, {
    int status = 200,
  }) => WebResourceResponse(
    contentType: mime,
    statusCode: status,
    reasonPhrase: status == 200
        ? 'OK'
        : status == 204
        ? 'No Content'
        : 'Not Found',
    contentEncoding:
        (mime.contains('json') ||
            mime.startsWith('text/') ||
            mime == 'application/javascript' ||
            mime == 'image/svg+xml')
        ? 'utf-8'
        : null,
    data: request.method == 'HEAD' ? Uint8List(0) : bytes,
    headers: {
      'Content-Length': '${bytes.length}',
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  );
  void _readOnly(WebResourceRequest request) {
    if (request.method != 'GET' && request.method != 'HEAD')
      throw const CoreFailure('asset_method', 'Local resources are read-only.');
  }

  Future<WebResourceResponse> _failure(
    String source,
    Object error,
    StackTrace stack,
  ) async {
    await NativeBridge.instance.recordDiagnostic(
      level: 'error',
      source: source,
      message: '$error',
      stack: stack.toString(),
    );
    return WebResourceResponse(
      contentType: 'text/plain',
      contentEncoding: 'utf-8',
      statusCode: 500,
      reasonPhrase: 'Local resource unavailable',
      headers: const {'Cache-Control': 'no-store'},
      data: Uint8List.fromList(
        utf8.encode('Required local resource is unavailable.'),
      ),
    );
  }

  Future<WebResourceResponse> _map(
    WebResourceRequest request,
    Uri uri,
    String path,
  ) async {
    try {
      _readOnly(request);
      final meta = RegExp(
        r'^/__navkurd/maps/(base|roads)\.json$',
      ).firstMatch(path);
      if (meta != null) {
        final archive = meta.group(1)!,
            info = await (_metadataLoads[archive] ??= _data.mapMetadata(
              archive,
            ));
        final prefix = AppConfig.appUri.path.endsWith('/')
            ? AppConfig.appUri.path
            : '${AppConfig.appUri.path}/';
        final template = uri
            .replace(
              path: '${prefix}__navkurd/maps/$archive/{z}/{x}/{y}.pbf',
              query: '',
              fragment: '',
            )
            .toString()
            .replaceAll('%7B', '{')
            .replaceAll('%7D', '}');
        final payload = {
          ...Map<String, Object?>.from(info['metadata'] as Map),
          'tilejson': '3.0.0',
          'tiles': [template],
          'minzoom': info['minZoom'],
          'maxzoom': info['maxZoom'],
          'bounds': info['bounds'],
        };
        return _response(
          request,
          Uint8List.fromList(utf8.encode(jsonEncode(payload))),
          'application/json',
        );
      }
      final tile = RegExp(
        r'^/__navkurd/maps/(base|roads)/(\d{1,2})/(\d{1,10})/(\d{1,10})\.pbf$',
      ).firstMatch(path);
      if (tile == null)
        return _response(request, Uint8List(0), 'text/plain', status: 404);
      final bytes = await _data.mapTile(
        tile.group(1)!,
        int.parse(tile.group(2)!),
        int.parse(tile.group(3)!),
        int.parse(tile.group(4)!),
      );
      return _response(
        request,
        bytes ?? Uint8List(0),
        'application/x-protobuf',
        status: bytes == null ? 204 : 200,
      );
    } catch (error, stack) {
      return _failure('local.map', error, stack);
    }
  }

  Future<WebResourceResponse> _layer(
    WebResourceRequest request,
    String dataset,
  ) async {
    try {
      _readOnly(request);
      return _response(
        request,
        await _layerBytes(dataset),
        'application/geo+json',
      );
    } catch (error, stack) {
      return _failure('local.layer', error, stack);
    }
  }

  Future<Uint8List> _layerBytes(String dataset) async {
    final cached = _layerCache.remove(dataset);
    if (cached != null) {
      _layerCache[dataset] = cached;
      return cached;
    }
    if (_coverageDatasets.contains(dataset)) {
      final layers = await (_coverageLoad ??= _buildCoverageLayers().then(
        (result) {
          for (final entry in result.entries) {
            _cacheLayer(entry.key, entry.value);
          }
          return result;
        },
        onError: (Object error, StackTrace stack) {
          _coverageLoad = null;
          Error.throwWithStackTrace(error, stack);
        },
      ));
      _coverageLoad = null;
      return layers[dataset]!;
    }
    return _layerLoads[dataset] ??= _buildLayer(dataset).then(
      (bytes) {
        _layerLoads.remove(dataset);
        _cacheLayer(dataset, bytes);
        return bytes;
      },
      onError: (Object error, StackTrace stack) {
        _layerLoads.remove(dataset);
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  void _cacheLayer(String dataset, Uint8List bytes) {
    if (bytes.length > _maximumLayerCacheBytes) return;
    final previous = _layerCache.remove(dataset);
    if (previous != null) _layerCacheBytes -= previous.length;
    while (_layerCache.isNotEmpty &&
        _layerCacheBytes + bytes.length > _maximumLayerCacheBytes) {
      _layerCacheBytes -= _layerCache.remove(_layerCache.keys.first)!.length;
    }
    _layerCache[dataset] = bytes;
    _layerCacheBytes += bytes.length;
  }

  Future<Map<String, Uint8List>> _buildCoverageLayers() async {
    var after = 0, decodedSourceBytes = 0;
    final features = <String, List<Object?>>{
      for (final dataset in _coverageDatasets) dataset: <Object?>[],
    };
    while (true) {
      final page = await _data.viewport(
        [-180, -90, 180, 90],
        'ku',
        datasets: _coverageDatasets,
        after: after,
        limit: 256,
      );
      decodedSourceBytes += page['decodedSourceBytes'] as int;
      if (decodedSourceBytes > 56 * 1024 * 1024) {
        throw const CoreFailure(
          'layer_size',
          'Static coverage layers exceed their bounded source size.',
        );
      }
      for (final raw in page['features'] as List) {
        final feature = raw as Map;
        final dataset = feature['dataset'];
        final bucket = features[dataset];
        if (bucket == null) {
          throw const CoreFailure(
            'layer_dataset',
            'Static coverage query returned an unexpected dataset.',
          );
        }
        bucket.add(raw);
      }
      if (page['hasMore'] != true) break;
      final next = page['nextId'] as int;
      if (next <= after) {
        throw const CoreFailure(
          'cursor',
          'Static coverage cursor did not advance.',
        );
      }
      after = next;
    }
    return {
      for (final entry in features.entries)
        entry.key: _encodeLayer(entry.value),
    };
  }

  Uint8List _encodeLayer(List<Object?> features) {
    final bytes = Uint8List.fromList(
      utf8.encode(
        jsonEncode({'type': 'FeatureCollection', 'features': features}),
      ),
    );
    if (bytes.length > 8 * 1024 * 1024) {
      throw const CoreFailure(
        'layer_size',
        'Static map layer exceeds 8 MiB.',
      );
    }
    return bytes;
  }

  Future<Uint8List> _buildLayer(String dataset) async {
    var after = 0, total = 0;
    final features = <Object?>[];
    while (true) {
      final page = await _data.viewport(
        [-180, -90, 180, 90],
        'ku',
        datasets: [dataset],
        after: after,
        limit: 256,
      );
      total += page['decodedSourceBytes'] as int;
      if (total > 8 * 1024 * 1024)
        throw const CoreFailure(
          'layer_size',
          'Static map layer exceeds 8 MiB.',
        );
      features.addAll(page['features'] as List);
      if (page['hasMore'] != true) break;
      final next = page['nextId'] as int;
      if (next <= after)
        throw const CoreFailure('cursor', 'Map layer cursor did not advance.');
      after = next;
    }
    return _encodeLayer(features);
  }
}
