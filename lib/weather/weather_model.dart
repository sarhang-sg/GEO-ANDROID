import 'dart:ui';

const notificationsCopy =
    'بۆ ئەوەی لە کاتی گۆڕانی کەشوهەوا و مەترسییەکاندا ئاگادارت بکەینەوە، تکایە ڕێگە بە نۆتیفیکەیشن بدە.';
const heatCopy = 'ئاگاداری: شەپۆلی گەرمای تاقەتپڕووکێن';
const coldCopy = 'ئاگاداری: شەختە و بەستەڵەک';
const floodCopy = 'ئەگەری لافاو و بارانی بەخوڕ';
const dustCopy = 'ئاگاداری: شەپۆلی خۆڵبارین و دابەزینی کوالیتی هەوا';
const driveCopy = 'ئاگاداری: لە خاڵی مەبەست ئەگەری تەمومژ/مەترسی هەیە';
const umbrellaCopy = 'ئەمڕۆ پێویستت بە چەتر دەبێت';

enum Sky {
  clear,
  partly,
  cloudy,
  lightRain,
  rain,
  heavyRain,
  storm,
  snow,
  blizzard,
  fog,
  dust,
  windy,
  heat,
  frost,
  unknown,
}

String word(String lang, String ku, String ar, String en) => lang == 'en'
    ? en
    : lang == 'ar'
    ? ar
    : ku;
String skyName(Sky sky, bool day, String lang) {
  final (ku, ar, en) = switch (sky) {
    Sky.clear when !day => ('ئاسمانی ڕوون', 'سماء صافية', 'Clear Night'),
    Sky.clear => ('ساماڵ', 'صافٍ', 'Clear Sky'),
    Sky.partly => ('نیمچە هەور', 'غائم جزئياً', 'Partly Cloudy'),
    Sky.cloudy => ('هەوراوی', 'غائم', 'Cloudy'),
    Sky.lightRain => ('نمە باران', 'أمطار خفيفة', 'Light Rain'),
    Sky.rain => ('بارانی مامناوەند', 'أمطار معتدلة', 'Moderate Rain'),
    Sky.heavyRain => ('لێزمە باران', 'أمطار غزيرة', 'Heavy Rain'),
    Sky.storm => ('هەورەبروسکە', 'عاصفة رعدية', 'Thunderstorm'),
    Sky.snow => ('بەفربارین', 'تساقط الثلوج', 'Snow'),
    Sky.blizzard => ('کڕێوەی بەفر', 'عاصفة ثلجية', 'Blizzard'),
    Sky.fog => ('تەمومژ', 'ضباب', 'Fog'),
    Sky.dust => ('خۆڵبارین', 'عاصفة رملية', 'Dust'),
    Sky.windy => ('با و بۆران', 'عاصف', 'Windy'),
    Sky.heat => ('شەپۆلی گەرما', 'موجة حر', 'Heatwave'),
    Sky.frost => ('بەستەڵەک', 'صقيع', 'Freezing'),
    Sky.unknown => ('—', '—', '—'),
  };
  return word(lang, ku, ar, en);
}

Sky weatherSky(int code) => switch (code) {
  0 => Sky.clear,
  1 || 2 => Sky.partly,
  3 => Sky.cloudy,
  45 || 48 => Sky.fog,
  51 || 53 || 55 || 61 || 80 => Sky.lightRain,
  63 || 81 => Sky.rain,
  65 || 82 => Sky.heavyRain,
  56 || 57 || 66 || 67 => Sky.frost,
  71 || 73 || 75 || 77 || 85 || 86 => Sky.snow,
  95 || 96 || 99 => Sky.storm,
  _ => Sky.unknown,
};
int phase(int hour) => hour < 5
    ? 0
    : hour < 7
    ? 1
    : hour < 10
    ? 2
    : hour < 12
    ? 3
    : hour < 15
    ? 4
    : hour < 17
    ? 5
    : hour < 19
    ? 6
    : 7;
int season(DateTime date, double latitude) =>
    (((date.month % 12) ~/ 3) + (latitude < 0 ? 2 : 0)) % 4;
const _phases = [
  ['پاش نیوەشەو', 'بعد منتصف الليل', 'After midnight'],
  ['بەرەبەیان', 'الفجر', 'Dawn'],
  ['بەیانی', 'الصباح', 'Morning'],
  ['پێش نیوەڕۆ', 'قبل الظهر', 'Late morning'],
  ['نیوەڕۆ', 'الظهيرة', 'Noon'],
  ['دوای نیوەڕۆ', 'بعد الظهر', 'Afternoon'],
  ['ئێوارە', 'الغروب', 'Sunset'],
  ['شەوەزەنگ', 'الليل', 'Night'],
];
const _seasons = [
  ['زستان', 'الشتاء', 'Winter'],
  ['بەهار', 'الربيع', 'Spring'],
  ['هاوین', 'الصيف', 'Summer'],
  ['پاییز', 'الخريف', 'Autumn'],
];
const _base = [
  (0xff232675, 0xff512979),
  (0xffff9475, 0xffb899ff),
  (0xff00d3fb, 0xffffdd4a),
  (0xff00cfff, 0xffffe041),
  (0xff04cbf4, 0xffffda32),
  (0xff279bff, 0xffffb531),
  (0xffff7034, 0xffc41c85),
  (0xff29227a, 0xff4e237f),
];
num? number(Object? value) => value is num && value.isFinite ? value : null;
Map<String, dynamic> object(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : {};

class WeatherModel {
  WeatherModel(this.data, this.lang, this.now);
  final Map<String, dynamic> data;
  final String lang;
  final DateTime now;
  Map<String, dynamic> get current => object(data['current']);
  Map<String, dynamic> get place => object(data['place']);
  String get city => place['name'] is String ? place['name'] as String : '';
  double? get temp => number(current['temperature_2m'])?.toDouble();
  int get code => number(current['weather_code'])?.toInt() ?? -1;
  double? get wind => number(current['wind_speed_10m'])?.toDouble();
  double? get pm => number(current['pm2_5'])?.toDouble();
  double? get aqi => number(current['european_aqi'])?.toDouble();
  bool get hasData => temp != null && weatherSky(code) != Sky.unknown;
  bool get day => current['is_day'] == 1;
  bool get stale =>
      data['stale'] == true ||
      (hasData &&
          now.millisecondsSinceEpoch - (number(current['time']) ?? 0) * 1000 >
              5400000);
  int get offset => number(data['utc_offset_seconds'])?.toInt() ?? 10800;
  DateTime local(DateTime time) => time.toUtc().add(Duration(seconds: offset));
  DateTime get date => local(now);
  String get phaseName =>
      _phases[phase(date.hour)][lang == 'en'
          ? 2
          : lang == 'ar'
          ? 1
          : 0];
  String get seasonName =>
      _seasons[season(date, number(place['lat'])?.toDouble() ?? 36)][lang ==
              'en'
          ? 2
          : lang == 'ar'
          ? 1
          : 0];
  String t(String ku, String ar, String en) => word(lang, ku, ar, en);
  String clock(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  String hourLabel(num epoch) {
    final d = local(
      DateTime.fromMillisecondsSinceEpoch(epoch.toInt() * 1000, isUtc: true),
    );
    final tomorrow = DateTime.utc(date.year, date.month, date.day + 1);
    return '${d.year == tomorrow.year && d.month == tomorrow.month && d.day == tomorrow.day ? t("سبەی ", "غداً ", "Tomorrow ") : ""}${clock(d)}';
  }

  String get status {
    final at = number(current['time']);
    if (at == null) {
      return t('لە هەوڵی پەیوەندیکردندایە...', 'جارٍ الاتصال…', 'Connecting…');
    }
    return '${t("دوایین نوێکردنەوە لە", "آخر تحديث في", "Last updated at")} ${clock(local(DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000, isUtc: true)))}';
  }

  Sky get sky {
    final s = weatherSky(code);
    if (s == Sky.unknown) return s;
    if (s == Sky.snow && (wind ?? 0) >= 56 && (code == 75 || code == 86)) {
      return Sky.blizzard;
    }
    if (s == Sky.clear || s == Sky.partly || s == Sky.cloudy) {
      if ((number(current['dust']) ?? 0) >= 150) return Sky.dust;
      if ((wind ?? 0) >= 55) return Sky.windy;
    }
    return s;
  }

  String? get extreme => !hasData || stale
      ? null
      : temp! > 45
      ? t(heatCopy, 'تنبيه: موجة حر شديدة', 'Extreme heat warning')
      : temp! < 0
      ? t(coldCopy, 'تنبيه: صقيع وتجمد', 'Freezing warning')
      : null;
  String? get advice => switch (sky) {
    Sky.lightRain ||
    Sky.rain ||
    Sky.heavyRain ||
    Sky.storm => t(umbrellaCopy, 'خذ مظلة اليوم', 'Take an umbrella today'),
    _ => null,
  };
  String get thermal => temp == null
      ? '—'
      : temp! < 0
      ? t('بەستەڵەک', 'صقيع', 'Freezing')
      : temp! < 18
      ? t('فێنک', 'مائل للبرودة', 'Cool')
      : temp! > 35
      ? t('گەرم', 'حار', 'Hot')
      : t('مامناوەند', 'معتدل', 'Mild');
  List<Color> get colors {
    var (a, b) = _base[phase(date.hour)];
    if (sky == Sky.dust) {
      a = 0xffedbe7c;
      b = 0xffdf742e;
    }
    final seasonAccent = const [
      0xff89cfff,
      0xff60dfc5,
      0xffffc42b,
      0xffff985e,
    ][season(date, number(place['lat'])?.toDouble() ?? 36)];
    final conditionAccent = switch (sky) {
      Sky.storm => 0xff6953c9,
      Sky.snow || Sky.blizzard || Sky.frost => 0xffb6f3ff,
      Sky.heavyRain || Sky.rain || Sky.lightRain => 0xff337bce,
      Sky.fog => 0xffabc8d4,
      Sky.partly || Sky.cloudy => 0xffa7bdf3,
      _ => a,
    };
    final warmth = ((temp ?? 18) + 15).clamp(0, 65) / 65;
    return [
      Color.lerp(Color(a), Color(conditionAccent), .17)!,
      Color.lerp(Color(b), Color(seasonAccent), .12)!,
      Color.lerp(const Color(0xff799bff), const Color(0xffff9361), warmth)!,
    ];
  }

  List<({num at, num temp, int code, bool day})> get hours {
    final h = object(data['hourly']);
    final ts = h['time'];
    final t = h['temperature_2m'];
    final c = h['weather_code'];
    final d = h['is_day'];
    if (ts is! List || t is! List || c is! List || d is! List) return [];
    return [
      for (
        var i = 0;
        i < ts.length && i < t.length && i < c.length && i < d.length;
        i++
      )
        if (number(ts[i]) != null &&
            number(t[i]) != null &&
            number(c[i]) != null &&
            (d[i] == 0 || d[i] == 1))
          (
            at: ts[i] as num,
            temp: t[i] as num,
            code: (c[i] as num).toInt(),
            day: d[i] == 1,
          ),
    ];
  }

  List<Map<String, dynamic>> get days => data['daily'] is List
      ? (data['daily'] as List).whereType<Map>().map(object).toList()
      : [];
}
