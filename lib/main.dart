import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_android/src/app.dart';
import 'package:geo_android/src/native_bridge.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final bridge = NativeBridge.instance;

      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(
          bridge.recordDiagnostic(
            level: 'error',
            source: 'flutter.framework',
            message: details.exceptionAsString(),
            stack: details.stack?.toString(),
          ),
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(
          bridge.recordDiagnostic(
            level: 'error',
            source: 'flutter.platform',
            message: error.toString(),
            stack: stack.toString(),
          ),
        );
        return true;
      };

      await bridge.enterImmersiveMode();
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
        ),
      );

      final initialDeepLink = await bridge.initialDeepLink();
      runApp(NavKurdApp(initialDeepLink: initialDeepLink));
    },
    (error, stack) {
      debugPrint('Uncaught NAV KURD error: $error\n$stack');
      unawaited(
        NativeBridge.instance.recordDiagnostic(
          level: 'error',
          source: 'flutter.zone',
          message: error.toString(),
          stack: stack.toString(),
        ),
      );
    },
  );
}
