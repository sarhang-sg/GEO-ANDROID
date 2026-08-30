import 'dart:async';

import 'package:flutter/services.dart';

final class NativeBridge {
  NativeBridge._();

  static final NativeBridge instance = NativeBridge._();
  static const MethodChannel _methods = MethodChannel('navkurd/native');
  static const EventChannel _deepLinks = EventChannel('navkurd/deep_links');

  Stream<String> get deepLinks => _deepLinks
      .receiveBroadcastStream()
      .where((event) => event is String)
      .cast<String>();

  Future<String?> initialDeepLink() async {
    try {
      return await _methods.invokeMethod<String>('getInitialDeepLink');
    } on PlatformException {
      return null;
    }
  }

  Future<int> androidSdkInt() async {
    try {
      return await _methods.invokeMethod<int>('getSdkInt') ?? 0;
    } on PlatformException {
      return 0;
    }
  }

  Future<Map<String, dynamic>> runtimeInfo() async {
    try {
      final value = await _methods.invokeMapMethod<String, dynamic>(
        'getRuntimeInfo',
      );
      return value ?? <String, dynamic>{};
    } on PlatformException {
      return <String, dynamic>{};
    }
  }

  Future<bool> clearTransientCache() async {
    try {
      final value = await _methods.invokeMapMethod<String, dynamic>(
        'clearTransientCache',
      );
      return value?['cleared'] == true;
    } on PlatformException {
      return false;
    }
  }

  Future<String?> pickImageFile() async {
    try {
      return await _methods.invokeMethod<String>('pickImage');
    } on PlatformException {
      return null;
    }
  }

  Future<bool> shareText({
    required String title,
    required String text,
    required String url,
  }) async {
    try {
      return await _methods.invokeMethod<bool>('shareText', <String, String>{
            'title': title,
            'text': text,
            'url': url,
          }) ??
          false;
    } on PlatformException {
      return false;
    }
  }

  Future<void> setLanguage(String language) async {
    try {
      await _methods.invokeMethod<void>('setLanguage', <String, String>{
        'language': language,
      });
    } on PlatformException {
      // The web app remains localized even if a launcher has no widget.
    }
  }

  Future<void> scheduleNotifications() async {
    try {
      await _methods.invokeMethod<void>('scheduleNotifications');
    } on PlatformException {
      // Android may suppress background alarms or notifications by policy.
    }
  }

  Future<void> enterImmersiveMode() async {
    try {
      await _methods.invokeMethod<void>('enterImmersiveMode');
    } on PlatformException {
      // Full-screen mode is also requested by the native activity lifecycle.
    }
  }

  Future<void> recordDiagnostic({
    required String level,
    required String source,
    required String message,
    String? stack,
  }) async {
    try {
      final payload = <String, String>{
        'level': level,
        'source': source,
        'message': message,
      };
      if (stack != null) {
        payload['stack'] = stack;
      }
      await _methods.invokeMethod<void>('recordDiagnostic', payload);
    } on PlatformException {
      // Diagnostics must never make the user-facing feature fail.
    }
  }

  Future<String> diagnosticReport() async {
    try {
      return await _methods.invokeMethod<String>('getDiagnosticReport') ??
          '[META] Native Android diagnostics are unavailable.';
    } on PlatformException {
      return '[WARN] Native Android diagnostics could not be collected.';
    }
  }

  Future<void> updateWidgetLocation({
    required double latitude,
    required double longitude,
    required double accuracy,
  }) async {
    try {
      await _methods.invokeMethod<void>('updateWidgetLocation', <String, double>{
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
      });
    } on PlatformException {
      // The map remains fully usable when a launcher has no widget support.
    }
  }

  Future<void> refreshWidgetWeather() async {
    try {
      await _methods.invokeMethod<void>('refreshWidgetWeather');
    } on PlatformException {
      // Weather is a non-critical widget enhancement.
    }
  }

  Future<int?> enqueueDownload({
    required String url,
    required String fileName,
    String? mimeType,
    String? userAgent,
    String? cookies,
  }) async {
    try {
      return await _methods.invokeMethod<int>(
        'enqueueDownload',
        <String, Object?>{
          'url': url,
          'fileName': fileName,
          'mimeType': mimeType,
          'userAgent': userAgent,
          'cookies': cookies,
        },
      );
    } on PlatformException {
      return null;
    }
  }

  Future<String?> saveBase64Download({
    required String fileName,
    required String mimeType,
    required String base64Data,
  }) async {
    try {
      return await _methods.invokeMethod<String>(
        'saveBase64Download',
        <String, String>{
          'fileName': fileName,
          'mimeType': mimeType,
          'base64Data': base64Data,
        },
      );
    } on PlatformException {
      return null;
    }
  }

  Future<void> showNotification({
    required String title,
    required String body,
  }) async {
    try {
      await _methods.invokeMethod<void>('showNotification', <String, String>{
        'title': title,
        'body': body,
      });
    } on PlatformException {
      // Notifications are a non-critical enhancement.
    }
  }

  Future<void> updateWidget({
    required String status,
    required String detail,
  }) async {
    try {
      await _methods.invokeMethod<void>('updateWidget', <String, String>{
        'status': status,
        'detail': detail,
      });
    } on PlatformException {
      // Widgets may not be supported by every launcher.
    }
  }

  Future<void> openDownloads() async {
    try {
      await _methods.invokeMethod<void>('openDownloads');
    } on PlatformException {
      // No compatible downloads application is installed.
    }
  }

  Future<void> openAppSettings() async {
    try {
      await _methods.invokeMethod<void>('openAppSettings');
    } on PlatformException {
      // Settings may be unavailable on non-Android test platforms.
    }
  }
}
