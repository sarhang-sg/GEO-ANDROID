import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/native_bridge.dart';
import 'package:permission_handler/permission_handler.dart';

final class PermissionCoordinator {
  PermissionCoordinator(this._bridge);

  final NativeBridge _bridge;

  Future<bool> requestLocation(Uri? origin) async {
    if (!AppConfig.isTrustedOrigin(origin)) return false;
    var status = await Permission.locationWhenInUse.status;
    if (!status.isGranted && !status.isLimited) {
      status = await Permission.locationWhenInUse.request();
    }
    final granted = status.isGranted || status.isLimited;
    if (granted) unawaited(_bridge.refreshWidgetWeather());
    return granted;
  }

  Future<bool> requestNotifications() async {
    var status = await Permission.notification.status;
    if (status.isDenied) status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  }

  Future<bool> ensureDownloadPermission() async {
    final sdk = await _bridge.androidSdkInt();
    // Android 10+ uses scoped storage. Web offline data is kept inside the
    // app's protected WebView storage and exported files use MediaStore or
    // DownloadManager, so broad "all files" access is neither needed nor safe.
    if (sdk == 0 || sdk >= 29) return true;
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  Future<PermissionResponse> handleWebPermission(
    PermissionRequest request,
  ) async {
    final requestOrigin = Uri.tryParse(request.origin.toString());
    if (!AppConfig.isTrustedOrigin(requestOrigin)) {
      return PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.DENY,
      );
    }

    var allGranted = true;
    for (final resource in request.resources) {
      if (resource == PermissionResourceType.CAMERA) {
        final status = await Permission.camera.request();
        allGranted = allGranted && status.isGranted;
      } else {
        allGranted = false;
      }
    }

    return PermissionResponse(
      resources: request.resources,
      action: allGranted
          ? PermissionResponseAction.GRANT
          : PermissionResponseAction.DENY,
    );
  }
}
