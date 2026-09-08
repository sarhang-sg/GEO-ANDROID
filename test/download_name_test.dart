import 'package:flutter_test/flutter_test.dart';
import 'package:geo_android/src/download_name.dart';

void main() {
  group('DownloadName', () {
    test('removes Android-forbidden characters', () {
      expect(
        DownloadName.sanitize('map:iraq/kurdistan?.pmtiles'),
        'map_iraq_kurdistan_.pmtiles',
      );
    });

    test('falls back for empty names', () {
      expect(DownloadName.sanitize('...'), 'nav-kurd-file');
    });

    test('preserves a short extension when truncating', () {
      final stem = List<String>.filled(150, 'a').join();
      final name = DownloadName.sanitize('$stem.geojson');
      expect(name.length, 120);
      expect(name.endsWith('.geojson'), isTrue);
    });
  });
}
