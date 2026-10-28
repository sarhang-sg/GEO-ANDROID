import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_android/src/local/android_location.dart';
import 'package:geo_android/src/native_bridge.dart';
import 'package:geo_android/src/permission_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const permission = MethodChannel('flutter.baseflow.com/permissions/methods');
  const location = MethodChannel('navkurd/location');
  const native = MethodChannel('navkurd/native');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Completer<int> grant;
  late List<String> commands;
  late AndroidLocation client;

  setUp(() {
    grant = Completer<int>();
    commands = [];
    messenger.setMockMethodCallHandler(permission, (call) async {
      expect(call.method, 'checkPermissionStatus');
      return grant.future;
    });
    messenger.setMockMethodCallHandler(location, (call) async {
      commands.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(native, (_) async => null);
    client = AndroidLocation(PermissionCoordinator(NativeBridge.instance));
  });
  tearDown(() {
    for (final channel in [permission, location, native]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });

  test('stop during a permission prompt prevents a late GPS start', () async {
    final pending = client.start();
    await client.stop();
    grant.complete(1);
    await pending;
    expect(commands, ['stop']);
  });

  test('a new start owns its pending request after cancellation', () async {
    final old = client.start();
    await client.stop();
    final current = client.start();
    expect(identical(current, client.start()), isTrue);
    grant.complete(1);
    await Future.wait([old, current]);
    expect(commands, ['stop', 'start']);
    await client.stop();
    expect(commands, ['stop', 'start', 'stop']);
  });
}
