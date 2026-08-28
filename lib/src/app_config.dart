import 'dart:core';

abstract final class AppConfig {
  static const String appName = 'NAV KURD';
  static const String appVersion = String.fromEnvironment(
    'NAV_KURD_VERSION',
    defaultValue: '8.0.4',
  );
  static const String canonicalOrigin = 'https://geo-map-kappa.vercel.app';
  static const String configuredAppUrl = String.fromEnvironment(
    'NAV_KURD_APP_URL',
    defaultValue: canonicalOrigin,
  );

  static Uri get appUri {
    final parsed = Uri.tryParse(configuredAppUrl.trim());
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      return Uri.parse(canonicalOrigin);
    }
    return parsed.replace(fragment: '');
  }

  static bool isTrustedOrigin(Uri? uri) {
    if (uri == null || uri.scheme != 'https') return false;
    final origin = appUri;
    return uri.host.toLowerCase() == origin.host.toLowerCase() &&
        uri.port == origin.port;
  }
}
