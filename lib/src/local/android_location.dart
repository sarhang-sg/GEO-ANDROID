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
  Stream<Map<String, dynamic>> get events => _stream ??= _events.receiveBroadcastStream().map(
    (event) => Map<String, dynamic>.from(event as Map),
  );
  Future<Map<String, dynamic>> status() async =>
      (await _methods.invokeMapMethod<String, dynamic>('status'))!;
  Future<void> start() => _starting ??= _start().whenComplete(() => _starting = null);
  Future<void> _start() async {
    if (!await _permissions.requestNativeLocation()) {
      throw PlatformException(code: 'permission_denied', message: 'Location permission is not granted.');
    }
    await _methods.invokeMethod<void>('start');
  }
  Future<void> stop() => _methods.invokeMethod<void>('stop');
}
