import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';

/// One immutable, release-bound R16 presentation shipped in the application.
final class BundledPresentation {
  BundledPresentation._(this.files);
  final Map<String,Map<String,Object?>> files;
  final _cache = <String, Uint8List>{};
  int _cacheBytes = 0;
  static const _maximumCacheBytes = 8 * 1024 * 1024;
  static Future<BundledPresentation> open() async {
    final manifest=jsonDecode(await rootBundle.loadString('assets/r16/manifest.json')) as Map;
    if(manifest['schema']!=1||manifest['appVersion']!=AppConfig.appVersion||manifest['files'] is! List)throw const CoreFailure('presentation_manifest','Bundled presentation identity is invalid.');
    final files=<String,Map<String,Object?>>{};
    for(final raw in manifest['files'] as List){
      final row=Map<String,Object?>.from(raw as Map),path=row['path'],bytes=row['bytes'],hash=row['sha256'];
      if(path is! String||path.isEmpty||path.startsWith('/')||path.contains('\\')||path.split('/').any((v)=>v.isEmpty||v=='.'||v=='..')||bytes is! int||bytes<0||bytes>16*1024*1024||hash is! String||!RegExp(r'^[0-9a-f]{64}$').hasMatch(hash)||files.containsKey('/$path'))throw const CoreFailure('presentation_manifest','Invalid bundled presentation file.');
      files['/$path']=row;
    }
    if(!files.containsKey('/index.html'))throw const CoreFailure('presentation_missing','Bundled R16 document is absent.');
    return BundledPresentation._(Map.unmodifiable(files));
  }
  bool contains(String path)=>files.containsKey(path);
  Future<Uint8List> read(String path) async {
    final file=files[path];
    if(file==null)throw CoreFailure('presentation_missing','Bundled resource is absent: $path');
    final cached = _cache.remove(path);
    if (cached != null) {
      _cache[path] = cached;
      return cached;
    }
    final data=await rootBundle.load('assets/r16$path'),bytes=data.buffer.asUint8List(data.offsetInBytes,data.lengthInBytes);
    if(bytes.length!=file['bytes']||sha256.convert(bytes).toString()!=file['sha256'])throw CoreFailure('presentation_integrity','Bundled resource is corrupt: $path');
    if (bytes.length <= _maximumCacheBytes) {
      while (_cache.isNotEmpty && _cacheBytes + bytes.length > _maximumCacheBytes) {
        _cacheBytes -= _cache.remove(_cache.keys.first)!.length;
      }
      _cache[path] = bytes;
      _cacheBytes += bytes.length;
    }
    return bytes;
  }
}
