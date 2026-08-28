import 'package:flutter_test/flutter_test.dart';
import 'package:geo_android/src/app_config.dart';
import 'package:geo_android/src/url_policy.dart';

void main() {
  group('UrlPolicy', () {
    test('keeps the canonical app inside the WebView', () {
      final decision = UrlPolicy.decide(
        Uri.parse('${AppConfig.canonicalOrigin}/?action=locate'),
        userGesture: true,
        linkActivated: true,
      );
      expect(decision, UrlDecision.allowInWebView);
    });

    test('keeps Supabase OAuth redirects inside the WebView', () {
      final decision = UrlPolicy.decide(
        Uri.parse('https://example.supabase.co/auth/v1/callback'),
        userGesture: false,
        linkActivated: false,
      );
      expect(decision, UrlDecision.allowInWebView);
    });

    test('opens OAuth identity-provider pages in the system browser', () {
      final decision = UrlPolicy.decide(
        Uri.parse('https://accounts.google.com/o/oauth2/v2/auth'),
        userGesture: false,
        linkActivated: false,
      );
      expect(decision, UrlDecision.openExternally);
    });

    test('opens user-selected external HTTPS links outside', () {
      final decision = UrlPolicy.decide(
        Uri.parse('https://example.com/help'),
        userGesture: true,
        linkActivated: true,
      );
      expect(decision, UrlDecision.openExternally);
    });

    test('blocks unknown custom schemes', () {
      final decision = UrlPolicy.decide(
        Uri.parse('unknown-app://unsafe'),
        userGesture: true,
        linkActivated: true,
      );
      expect(decision, UrlDecision.block);
    });

    test('maps navkurd deep links to the configured HTTPS app', () {
      final uri = UrlPolicy.appUriForDeepLink(
        'navkurd://locate?action=coordinate&lat=35.55&lng=45.44',
      );
      expect(uri.host, AppConfig.appUri.host);
      expect(uri.queryParameters['action'], 'coordinate');
      expect(uri.queryParameters['lat'], '35.55');
      expect(uri.queryParameters['lng'], '45.44');
    });

    test('maps a PKCE callback into the trusted WebView origin', () {
      final uri = UrlPolicy.appUriForDeepLink(
        'navkurd://auth/callback?code=one-time-code&error_description=',
      );
      expect(uri.host, AppConfig.appUri.host);
      expect(uri.path, '/');
      expect(uri.queryParameters, <String, String>{'code': 'one-time-code'});
      expect(uri.fragment, isEmpty);
    });

    test('never forwards OAuth tokens from a custom deep link', () {
      final uri = UrlPolicy.appUriForDeepLink(
        'navkurd://auth/callback?code=safe&access_token=secret&refresh_token=secret',
      );
      expect(uri.queryParameters['code'], 'safe');
      expect(uri.queryParameters.containsKey('access_token'), isFalse);
      expect(uri.queryParameters.containsKey('refresh_token'), isFalse);
    });

    test('rejects an empty OAuth callback', () {
      final uri = UrlPolicy.appUriForDeepLink('navkurd://auth/callback');
      expect(uri, AppConfig.appUri);
    });
  });
}
