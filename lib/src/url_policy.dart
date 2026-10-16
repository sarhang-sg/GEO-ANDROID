import 'package:geo_android/src/app_config.dart';

enum UrlDecision { allowInWebView, openExternally, block }

abstract final class UrlPolicy {
  static const Set<String> _oauthCallbackKeys = <String>{
    'code',
    'error',
    'error_code',
    'error_description',
  };
  static const Set<String> _sensitiveAuthKeys = <String>{
    'access_token',
    'refresh_token',
    'provider_token',
    'provider_refresh_token',
    'id_token',
  };
  static const Set<String> _externalSchemes = <String>{
    'mailto',
    'tel',
    'sms',
    'geo',
    'market',
  };

  static const Set<String> _externalAuthHosts = <String>{
    'accounts.google.com',
    'appleid.apple.com',
    'github.com',
  };

  static UrlDecision decide(
    Uri uri, {
    required bool userGesture,
    required bool linkActivated,
  }) {
    final scheme = uri.scheme.toLowerCase();
    if (_externalSchemes.contains(scheme)) return UrlDecision.openExternally;
    if (scheme != 'http' && scheme != 'https') return UrlDecision.block;
    if (scheme == 'http') return UrlDecision.openExternally;

    if (_isExternalAuthHost(uri.host)) return UrlDecision.openExternally;
    if (AppConfig.isTrustedOrigin(uri)) return UrlDecision.allowInWebView;
    if (uri.host.toLowerCase().endsWith('.supabase.co')) {
      return UrlDecision.allowInWebView;
    }
    return userGesture || linkActivated
        ? UrlDecision.openExternally
        : UrlDecision.allowInWebView;
  }

  static bool _isExternalAuthHost(String host) {
    final normalized = host.toLowerCase();
    return _externalAuthHosts.any(
      (candidate) =>
          normalized == candidate || normalized.endsWith('.$candidate'),
    );
  }

  static Uri appUriForDeepLink(String? deepLink) {
    final base = AppConfig.appUri;
    final parsed = Uri.tryParse(deepLink ?? '');
    if (parsed == null) return base;

    if (AppConfig.isTrustedOrigin(parsed)) return parsed;
    if (parsed.scheme != 'navkurd') return base;

    final host = parsed.host.toLowerCase();
    final path = parsed.path.toLowerCase();
    if (host == 'auth' && (path.isEmpty || path == '/callback')) {
      final query = <String, String>{};
      for (final entry in parsed.queryParameters.entries) {
        if (!_oauthCallbackKeys.contains(entry.key)) continue;
        final value = entry.value.trim();
        if (value.isNotEmpty && value.length <= 4096) {
          query[entry.key] = value;
        }
      }
      if (!query.containsKey('code') &&
          !query.containsKey('error') &&
          !query.containsKey('error_code')) {
        return base;
      }
      return base.replace(
        path: '/',
        queryParameters: query,
        fragment: '',
      );
    }

    final query = Map<String, String>.from(parsed.queryParameters)
      ..removeWhere((key, _) => _sensitiveAuthKeys.contains(key.toLowerCase()));
    if (parsed.host == 'locate' || parsed.path == '/locate') {
      query.putIfAbsent('action', () => 'locate');
    }
    return base.replace(queryParameters: query.isEmpty ? null : query);
  }
}
