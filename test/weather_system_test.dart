import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:geo_android/weather/weather_model.dart';
import 'package:geo_android/weather/weather_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime.utc(2026, 11, 3, 7, 5);
  Map<String, dynamic> reading(double temp) => {
    'place': {'name': 'چپگژ · حاجیاوا', 'lat': 36.3},
    'utc_offset_seconds': 10800,
    'current': {
      'time': now.millisecondsSinceEpoch ~/ 1000,
      'temperature_2m': temp,
      'weather_code': 2,
      'is_day': 1,
      'wind_speed_10m': 5,
      'pm2_5': 18,
      'european_aqi': 30,
    },
    'hourly': {
      'time': [
        for (var i = 0; i < 5; i++)
          now.millisecondsSinceEpoch ~/ 1000 + i * 3600,
      ],
      'temperature_2m': [21, 22, 23, 21, 20],
      'weather_code': [1, 2, 3, 0, 51],
      'is_day': [1, 1, 1, 1, 1],
    },
  };
  test(
    'Iraq 10 AM and nighttime use different palettes, strict temperature edges',
    () {
      final m = WeatherModel(reading(45), 'ku', now);
      expect(phase(m.date.hour), 3);
      expect(m.extreme, isNull);
      expect(WeatherModel(reading(45.01), 'ku', now).extreme, heatCopy);
      expect(WeatherModel(reading(0), 'ku', now).extreme, isNull);
      expect(WeatherModel(reading(-.01), 'ku', now).extreme, coldCopy);
      expect(
        m.colors,
        isNot(WeatherModel(m.data, 'ku', DateTime.utc(2026, 11, 3, 20)).colors),
      );
      expect(m.seasonName, 'پاییز');
      expect(
        m.hourLabel(
          DateTime.utc(2026, 11, 3, 23).millisecondsSinceEpoch ~/ 1000,
        ),
        'سبەی 02:00',
      );
      expect(skyName(Sky.partly, true, 'ku'), 'نیمچە هەور');
      expect(skyName(Sky.storm, true, 'ku'), 'هەورەبروسکە');
    },
  );
  test(
    'stale observations suppress extreme alerts and preserve original time',
    () {
      final m = WeatherModel({...reading(48), 'stale': true}, 'ku', now);
      expect(m.extreme, isNull);
      expect(m.status, 'دوایین نوێکردنەوە لە 10:05');
    },
  );
  testWidgets('headless renderer emits six distinct valid launcher sizes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final size in [
        const Size(48, 48),
        const Size(110, 49),
        const Size(250, 60),
        const Size(270, 108),
        const Size(300, 175),
        const Size(340, 275),
      ]) {
        final bytes = await weatherBitmap(
          size,
          1.5,
          WeatherModel(reading(21), 'ku', now),
        );
        expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final header = ByteData.sublistView(bytes);
        expect(header.getUint32(16), closeTo(size.width * 1.5, 1));
        expect(header.getUint32(20), closeTo(size.height * 1.5, 1));
      }
    });
  });
}
