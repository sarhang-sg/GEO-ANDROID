import 'dart:convert';
import 'dart:math' as math;
import 'package:sqlite3/sqlite3.dart';
import 'core_failure.dart';
import 'queries.dart';

final class PlaceRepository {
  PlaceRepository(Database database) : sql = Queries(database);
  final Queries sql;
  static const datasets = {
    'base',
    'natural',
    'locality',
    'major',
    'cluster',
    'security',
    'reviewed',
    'road_labels',
    'governorate',
    'district',
    'region_labels',
    'boundary',
    'boundary_line',
    'mask',
  };
  static void _language(String language) {
    if (!['ku', 'ar', 'en'].contains(language)) {
      throw const CoreFailure('invalid_language', 'Expected KU, AR or EN.');
    }
  }

  static void _bounds(List<double> b) {
    if (b.length != 4 ||
        b.any((v) => !v.isFinite) ||
        b[0] < -180 ||
        b[2] > 180 ||
        b[1] < -90 ||
        b[3] > 90 ||
        b[0] > b[2] ||
        b[1] > b[3]) {
      throw const CoreFailure(
        'invalid_bounds',
        'Expected [west,south,east,north] in world bounds.',
      );
    }
  }

  Map<String, Object?> _feature(Row row, String language) {
    final p = jsonDecode(row['properties'] as String) as Map<String, dynamic>;
    final localized = row['localized'];
    if (localized != null) {
      final v = jsonDecode(localized as String) as Map<String, dynamic>;
      for (final lang in ['ku', 'ar', 'en']) {
        for (final field in [
          'name',
          'admin_governorate',
          'admin_district',
          'admin_subdistrict',
          'category',
        ]) {
          p.remove('${field}_$lang');
        }
      }
      p.remove('name_ku_status');
      p['name'] = v['name'];
      p['name_$language'] = v['name'];
      p['name_verified'] = v['name_verified'] == 1;
      for (final field in [
        'admin_governorate',
        'admin_district',
        'admin_subdistrict',
        'category',
      ]) {
        p['${field}_$language'] = v[field];
      }
      if (language == 'ku') p['name_ku_status'] = v['name_status'];
    }
    return {
      'type': 'Feature',
      'id': row['source_id'],
      'catalogId': row['id'],
      'dataset': row['dataset'],
      'geometry': jsonDecode(row['geometry'] as String),
      'properties': p,
    };
  }

  Map<String, Object?>? get(int catalogId, String language) {
    _language(language);
    final rows = sql.select(
      '''SELECT f.*,l.properties AS localized FROM feature f LEFT JOIN feature_language l
      ON l.feature_id=f.id AND l.language=? WHERE f.id=?''',
      [language, catalogId],
    );
    return rows.isEmpty ? null : _feature(rows.single, language);
  }

  Map<String,Object?> poiManifest() {
    final rows=sql.select("SELECT value FROM metadata WHERE key='viewportPoiManifest'");
    if(rows.isEmpty) throw const CoreFailure('missing_index','POI viewport index is absent.');
    return Map<String,Object?>.from(jsonDecode(rows.single['value'] as String) as Map);
  }

  Map<String,Object?> poiShard(String dataset,String key) {
    if(!const {'base','natural'}.contains(dataset)||key.length>128) throw const CoreFailure('invalid_shard','Invalid POI partition.');
    if(sql.select('SELECT 1 FROM poi_shard WHERE dataset=? AND key=?',[dataset,key]).isEmpty) throw const CoreFailure('missing_shard','POI partition is absent.');
    final rows=sql.select('''SELECT f.*,NULL AS localized FROM poi_shard_feature p JOIN feature f ON f.id=p.feature_id
      WHERE p.dataset=? AND p.key=? ORDER BY p.ordinal''',[dataset,key]);
    final features=<Map<String,Object?>>[];var bytes=0;
    for(final row in rows){
      bytes+=utf8.encode(row['geometry'] as String).length+utf8.encode(row['properties'] as String).length;
      if(bytes>8*1024*1024)throw const CoreFailure('page_size','POI partition exceeds 8 MiB.');
      features.add(_feature(row,'ku'));
    }
    return {'type':'FeatureCollection','features':features};
  }

  Map<String, Object?> viewport(
    List<double> bounds,
    String language, {
    List<String> selected = const ['base', 'natural', 'locality'],
    int after = 0,
    int limit = 128,
    int minimumLocalityRank = 0,
  }) {
    _bounds(bounds);
    _language(language);
    if (minimumLocalityRank < 0 || minimumLocalityRank > 100 || selected.isEmpty ||
        selected.any((s) => !datasets.contains(s)) ||
        limit < 1 ||
        limit > 256 ||
        after < 0) {
      throw const CoreFailure(
        'invalid_viewport',
        'Invalid datasets, cursor or page size (1–256).',
      );
    }
    final marks = List.filled(selected.length, '?').join(',');
    final rows = sql.select(
      '''SELECT f.*,l.properties AS localized FROM feature_bounds b
      JOIN feature f ON f.id=b.id LEFT JOIN feature_language l ON l.feature_id=f.id AND l.language=?
      WHERE b.max_x>=? AND b.min_x<=? AND b.max_y>=? AND b.min_y<=? AND f.id>? AND f.dataset IN ($marks)
      AND (?=0 OR f.dataset!='locality' OR EXISTS(SELECT 1 FROM locality_search s WHERE s.feature_id=f.id AND s.language=? AND s.rank>=?))
      ORDER BY f.id LIMIT ?''',
      [
        language,
        bounds[0],
        bounds[2],
        bounds[1],
        bounds[3],
        after,
        ...selected,
        minimumLocalityRank,language,minimumLocalityRank,
        limit + 1,
      ],
    );
    final items = <Map<String, Object?>>[];
    var bytes = 0;
    for (final row in rows.take(limit)) {
      bytes +=
          utf8.encode(row['geometry'] as String).length +
          utf8.encode(row['properties'] as String).length;
      if (bytes > 8 * 1024 * 1024) {
        throw const CoreFailure(
          'page_size',
          'Viewport page exceeds 8 MiB; request a smaller page.',
        );
      }
      items.add(_feature(row, language));
    }
    return {
      'features': items,
      'hasMore': rows.length > limit,
      'nextId': items.isEmpty ? after : items.last['catalogId'],
      'decodedSourceBytes': bytes,
    };
  }

  Map<String, Object?> reverse(
    double longitude,
    double latitude,
    String language, {
    double maximumMetres = 50000,
  }) {
    _bounds([longitude, latitude, longitude, latitude]);
    _language(language);
    if (!maximumMetres.isFinite ||
        maximumMetres <= 0 ||
        maximumMetres > 50000) {
      throw const CoreFailure(
        'invalid_radius',
        'Reverse lookup radius must be in (0,50000] metres.',
      );
    }
    Map<String, Object?>? nearest;
    var nearestDistance = maximumMetres;
    final dy = maximumMetres / 110574,
        dx = math.min(
          180.0,
          maximumMetres /
              (111320 * math.max(0.01, math.cos(latitude * math.pi / 180))),
        );
    final bounds = [
      math.max(-180.0, longitude - dx),
      math.max(-90.0, latitude - dy),
      math.min(180.0, longitude + dx),
      math.min(90.0, latitude + dy),
    ];
    var after = 0;
    while (true) {
      final page = viewport(
        bounds,
        language,
        selected: const ['locality'],
        after: after,
      );
      for (final f in page['features'] as List<Map<String, Object?>>) {
        if (((f['properties'] as Map)['name'] as String? ?? '')
            .trim()
            .isEmpty) {
          continue;
        }
        final c = (f['geometry'] as Map)['coordinates'] as List;
        final distance = _distance(
          longitude,
          latitude,
          (c[0] as num).toDouble(),
          (c[1] as num).toDouble(),
        );
        if (distance <= nearestDistance) {
          nearest = f;
          nearestDistance = distance;
        }
      }
      if (page['hasMore'] != true) break;
      after = page['nextId'] as int;
    }
    final area = viewport(
      [longitude, latitude, longitude, latitude],
      language,
      selected: const ['governorate', 'district', 'boundary'],
    );
    final containing = (area['features'] as List<Map<String, Object?>>)
        .where((f) => _contains(f['geometry'] as Map, longitude, latitude))
        .toList();
    return {
      'nearest': nearest,
      'distanceMetres': nearest == null ? null : nearestDistance,
      'administrativeAreas': containing
          .where((f) => f['dataset'] != 'boundary')
          .toList(),
      'withinCoverage': containing.any((f) => f['dataset'] == 'boundary'),
      'precision': 'nearest-locality-only',
    };
  }

  static double _distance(double x, double y, double xx, double yy) {
    final a =
        math.pow(math.sin((yy - y) * math.pi / 360), 2) +
        math.cos(y * math.pi / 180) *
            math.cos(yy * math.pi / 180) *
            math.pow(math.sin((xx - x) * math.pi / 360), 2);
    return 6371000 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }

  static bool _ring(List points, double x, double y) {
    var inside = false;
    for (var i = 0, j = points.length - 1; i < points.length; j = i++) {
      final a = points[i] as List, b = points[j] as List;
      final ax = (a[0] as num).toDouble(),
          ay = (a[1] as num).toDouble(),
          bx = (b[0] as num).toDouble(),
          by = (b[1] as num).toDouble();
      if ((ay > y) != (by > y) && x < (bx - ax) * (y - ay) / (by - ay) + ax) {
        inside = !inside;
      }
    }
    return inside;
  }

  static bool _contains(Map geometry, double x, double y) {
    final coordinates = geometry['coordinates'] as List;
    final polygons = geometry['type'] == 'Polygon'
        ? [coordinates]
        : geometry['type'] == 'MultiPolygon'
        ? coordinates
        : [];
    for (final p in polygons) {
      final rings = p as List;
      if (rings.isNotEmpty &&
          _ring(rings.first as List, x, y) &&
          !rings.skip(1).any((r) => _ring(r as List, x, y))) {
        return true;
      }
    }
    return false;
  }

  void close() => sql.close();
}
