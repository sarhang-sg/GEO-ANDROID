import 'dart:async';
import 'dart:convert';
import 'bundled_presentation.dart';
import 'package:flutter/services.dart';
import 'package:geo_android/src/native_bridge.dart';
import 'package:geo_android/src/local/core_resource_handler.dart';
import 'package:nav_kurd_local_core/nav_kurd_local_core.dart';

/// One installed immutable pack and one data isolate for the application.
final class AndroidLocalRuntime {
  AndroidLocalRuntime._(
    this.data,
    this.packDirectory,
    this.packId,
    this.resources,
    this.initialDocument,
    this._initialMapSnapshot,
  );
  static const _channel = MethodChannel('navkurd/local_core');
  static const _events = EventChannel('navkurd/local_core_events');
  late final Stream<Map<String,dynamic>> mapEvents = _events.receiveBroadcastStream().map((event)=>Map<String,dynamic>.from(event as Map));
  Future<void> _mapChanges=Future.value();
  static Map<String,Map<String,Object?>> _archives(Object? value){
    if(value is! Map)throw const CoreFailure('map_protocol','Missing native map archive descriptors.');
    return {for(final entry in value.entries)entry.key as String:Map<String,Object?>.from(entry.value as Map)};
  }
  static Future<AndroidLocalRuntime>? _opening;
  final LocalDataClient data;
  final String packDirectory;
  final String packId;
  final CoreResourceHandler resources;
  final String initialDocument;
  Map<String, dynamic>? _initialMapSnapshot;
  bool _closed = false;
  static Future<AndroidLocalRuntime> open() => _opening ??= _installAndOpen();
  static Future<AndroidLocalRuntime> _installAndOpen() async {
    LocalDataClient? data;
    try {
      final installation =
          _channel.invokeMapMethod<String, dynamic>('install');
      final presentation=await BundledPresentation.open();
      final initialDocument=utf8.decode(await presentation.read("/index.html"));
      final installed = await installation;
      final packDirectory = installed?['packDirectory'];
      final userDatabase = installed?['userDatabase'];
      final packId = installed?['packId'];
      final initialMapSnapshot = installed?['mapSnapshot'];
      if (packDirectory is! String || userDatabase is! String || packId is! String || initialMapSnapshot is! Map) {
        throw const CoreFailure('install_protocol', 'Android returned an invalid local pack descriptor.');
      }
      data = await LocalDataClient.open(
        packDirectory: packDirectory,
        userDatabase: userDatabase,
        mapArchives: _archives(installed?['mapArchives']),
        installerVerifiedPackId: packId,
      );
      if (data.packId != packId) {
        throw const CoreFailure('pack_identity', 'The installed and opened pack identities disagree.');
      }
      return AndroidLocalRuntime._(
        data,
        packDirectory,
        packId,
        CoreResourceHandler(await data.assetIndex(),data,presentation),
        initialDocument,
        Map<String, dynamic>.from(initialMapSnapshot),
      );
    } catch (_) {
      await data?.close();
      _opening = null;
      rethrow;
    }
  }
  Map<String, dynamic>? takeInitialMapSnapshot() {
    final snapshot = _initialMapSnapshot;
    _initialMapSnapshot = null;
    return snapshot;
  }
  Future<Map<String,dynamic>> mapSnapshot() async =>
      (await _channel.invokeMapMethod<String,dynamic>('mapSnapshot'))!;
  Future<Map<String,dynamic>> pauseMaps() async =>
      (await _channel.invokeMapMethod<String,dynamic>('pauseMaps'))!;
  Future<Map<String,dynamic>> downloadMaps()=>_changeMaps('downloadMaps');
  Future<Map<String,dynamic>> deleteMaps() async {
    try {await pauseMaps();}catch(error,stack){
      await NativeBridge.instance.recordDiagnostic(level:'warning',source:'local.maps',message:'Map extraction stopped with an error before deletion: $error',stack:stack.toString());
    }
    return _changeMaps('deleteMaps');
  }
  Future<Map<String,dynamic>> _changeMaps(String method){
    final task=_mapChanges.then((_) async {
      if(_closed)throw const CoreFailure('closed','The native local runtime is closed.');
      if(method=='downloadMaps'){
        final current=await mapSnapshot();if(current['status']=='ready')return current;
      }
      // Drain the sole PMTiles readers before changing/removing their files.
      final bundled=await _channel.invokeMapMethod<String,dynamic>('mapArchives',{'bundled':true});
      await data.setMapArchives(_archives(bundled));
      final result=(await _channel.invokeMapMethod<String,dynamic>(method))!;
      final selected=await _channel.invokeMapMethod<String,dynamic>('mapArchives');
      await data.setMapArchives(_archives(selected));
      return result;
    });
    // Keep the sequencing tail usable; the returned operation retains failures.
    _mapChanges=task.then<void>((_) {},onError:(Object error,StackTrace stack) {});
    return task;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      try {await pauseMaps();}catch(error,stack){await NativeBridge.instance.recordDiagnostic(level:'warning',source:'local.maps',message:'Could not pause map extraction during shutdown: $error',stack:stack.toString());}
      await _mapChanges;
      await data.close();
    } finally { _opening = null; }
  }
}
