import 'package:flutter/services.dart';
import 'package:geo_android/src/permission_coordinator.dart';

/// Permission requests share the existing coordinator; Android owns fixes.
final class AndroidLocation {
  AndroidLocation(this._permissions);
  final PermissionCoordinator _permissions;
  static const _methods = MethodChannel('navkurd/location');
  static const _events = EventChannel('navkurd/location_events');
  Stream<Map<String, dynamic>>? _stream;
  Future<void>? _starting;
  int _generation = 0;
  Stream<Map<String, dynamic>> get events => _stream ??= _events.receiveBroadcastStream().map(
    (event) => Map<String, dynamic>.from(event as Map),
  );
  Future<Map<String, dynamic>> status() async =>
      (await _methods.invokeMapMethod<String, dynamic>('status'))!;
  Future<void> start() {
    if (_starting != null) return _starting!;
    final generation = _generation;
    late final Future<void> task;
    task = _start(generation).whenComplete(() {
      if (identical(_starting, task)) _starting = null;
    });
    return _starting = task;
  }
  Future<void> _start(int generation) async {
    final granted = await _permissions.requestNativeLocation();
    if (generation != _generation) return;
    if (!granted) {
      throw PlatformException(code: 'permission_denied', message: 'Location permission is not granted.');
    }
    await _methods.invokeMethod<void>('start');
  }
  Future<void> stop() {
    _generation++;
    _starting = null;
    return _methods.invokeMethod<void>('stop');
  }
}
