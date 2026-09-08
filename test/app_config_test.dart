import 'package:flutter_test/flutter_test.dart';
import 'package:geo_android/src/app_config.dart';

void main() {
  test('release version and canonical HTTPS origin are stable', () {
    expect(AppConfig.appVersion, '9.1.0');
    expect(AppConfig.appUri.scheme, 'https');
    expect(AppConfig.appUri.host, 'geo-map-kappa.vercel.app');
  });

  test('trusted origin rejects lookalike and insecure hosts', () {
    expect(
      AppConfig.isTrustedOrigin(
        Uri.parse('https://geo-map-kappa.vercel.app.example.test'),
      ),
      isFalse,
    );
    expect(
      AppConfig.isTrustedOrigin(Uri.parse('http://geo-map-kappa.vercel.app')),
      isFalse,
    );
  });
}
