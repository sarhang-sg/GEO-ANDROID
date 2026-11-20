import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:geo_android/src/kurdish_localizations.dart'
    show navKurdDelegates;
import 'package:geo_android/weather/weather_art.dart';
import 'package:geo_android/weather/weather_model.dart';

TextStyle ink(double size, {FontWeight weight = FontWeight.w500}) => TextStyle(
  color: Colors.white,
  fontFamily: 'NAVKurdArabic',
  fontFamilyFallback: const ['NAVKurdLatin', 'sans-serif'],
  fontSize: size,
  fontWeight: weight,
  height: 1.48,
  textBaseline: TextBaseline.alphabetic,
  shadows: const [
    Shadow(color: Color(0xbe10253c), blurRadius: 4, offset: Offset(0, 1)),
  ],
);
Widget label(
  String text,
  double size, {
  FontWeight weight = FontWeight.w500,
  TextAlign align = TextAlign.start,
}) => Text(
  text.replaceAllMapped(
    RegExp(r'-?\d+(?:[.,]\d+)?\s*(?:km/h|µg/m³|°C|°|%)'),
    (m) => '\u2066${m[0]}\u2069',
  ),
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
  textAlign: align,
  style: ink(size, weight: weight),
);

class GlassBadge extends StatelessWidget {
  const GlassBadge(this.text, {super.key, this.size = 11});
  final String text;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: size * .55, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0x60203a52),
      borderRadius: BorderRadius.circular(20),
    ),
    child: label(text, size),
  );
}

Widget glyph(Sky sky, bool day, double size) => SizedBox.square(
  dimension: size,
  child: CustomPaint(painter: WeatherIcon(sky, day)),
);

class WeatherWidgetArt extends StatelessWidget {
  const WeatherWidgetArt(this.weather, {super.key});
  final WeatherModel weather;

  static const _credit = 'Open-Meteo · Developer: Sarhang Salah';

  Widget _number(
    String value,
    double size, {
    FontWeight weight = FontWeight.w600,
  }) => Text(
    value,
    maxLines: 1,
    textDirection: TextDirection.ltr,
    overflow: TextOverflow.ellipsis,
    style: ink(size, weight: weight).copyWith(
      fontFamily: 'NAVKurdLatin',
      fontFamilyFallback: const ['NAVKurdArabic'],
      height: 1.19,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    ),
  );

  Widget _clock({required bool date}) => Directionality(
    textDirection: TextDirection.ltr,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _number(weather.clock(weather.date), 15, weight: FontWeight.bold),
        if (date) ...[
          const SizedBox(width: 4),
          _number('${weather.date.day}/${weather.date.month}', 9),
        ],
      ],
    ),
  );

  Widget _current({
    required bool stacked,
    required bool description,
    bool spacious = false,
  }) {
    final temp = _number(
      weather.temp == null ? '—' : '${weather.temp!.round()}°',
      spacious ? 48 : 32,
      weight: FontWeight.bold,
    );
    final icon = glyph(weather.sky, weather.day, spacious ? 72 : 47);
    final name = label(
      skyName(weather.sky, weather.day, weather.lang),
      spacious ? 18 : 13,
    );
    final reading = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        icon,
        const SizedBox(width: 4),
        temp,
        if (description && !spacious) ...[const SizedBox(width: 5), name],
      ],
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: stacked
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [icon, temp, if (description) name],
            )
          : spacious && description
          ? Column(mainAxisSize: MainAxisSize.min, children: [reading, name])
          : reading,
    );
  }

  // Each forecast uses the available cross-axis: columns across a wide card,
  // time/icon/reading rows down a tall card, and two lines down a single cell.
  Widget _forecast(
    int count, {
    required bool vertical,
    required bool slim,
    bool fullRow = false,
  }) {
    final entries = weather.hours.take(count).map((hour) {
      final time = _number(weather.hourLabel(hour.at), fullRow ? 13 : 10);
      final sky = weatherSky(hour.code);
      final icon = glyph(sky, hour.day, fullRow ? 27 : 19);
      final temp = _number(
        '${hour.temp.round()}°',
        fullRow ? 16 : 12,
        weight: FontWeight.bold,
      );
      final value = Row(mainAxisSize: MainAxisSize.min, children: [icon, temp]);
      if (vertical && !slim) {
        return Row(
          children: [
            Expanded(
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FittedBox(fit: BoxFit.scaleDown, child: time),
              ),
            ),
            if (fullRow) ...[
              icon,
              const SizedBox(width: 7),
              Expanded(
                flex: 2,
                child: label(skyName(sky, hour.day, weather.lang), 13),
              ),
              temp,
            ] else
              value,
          ],
        );
      }
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            time,
            if (slim) value else ...[icon, temp],
          ],
        ),
      );
    }).toList();
    return Flex(
      direction: vertical ? Axis.vertical : Axis.horizontal,
      children: [for (final entry in entries) Expanded(child: entry)],
    );
  }

  Widget _metrics(double width) {
    final values = [
      if (weather.wind != null) '${weather.wind!.round()} km/h',
      if (weather.aqi != null) 'AQI ${weather.aqi!.round()}',
      if (width >= 180 && weather.pm != null)
        'PM2.5 ${weather.pm!.round()} µg/m³',
    ];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final value in values)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: GlassBadge(value, size: 10),
            ),
        ],
      ),
    );
  }

  Widget _attribution(double width) {
    final text = width >= 118
        ? _credit
        : width >= 92
        ? 'Open-Meteo\nDeveloper: Sarhang Salah'
        : 'Open-Meteo\nDeveloper:\nSarhang Salah';
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          text,
          textAlign: TextAlign.center,
          textDirection: TextDirection.ltr,
          style: ink(9).copyWith(fontFamily: 'NAVKurdLatin', height: 1.15),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final slim = w < 92;
      // The native hit targets use the same dimensions and action breakpoints.
      final stackedActions = slim && h >= 245;
      final actions =
          stackedActions || (w >= 92 && (h >= 145 || (w >= 200 && h >= 64)));
      final strip = w >= 200 && h < 110;
      final sideCredit = actions && !stackedActions && (w >= 210 || strip);
      final showCredit = h >= (slim ? 86 : 54);
      final pad = math.min(12.0, w * .045);
      final header = math.min(24.0, h);
      final actionHeight = !actions
          ? 0.0
          : stackedActions
          ? 80.0
          : 40.0;
      final creditWidth = math.max(1.0, w - pad * 2 - (sideCredit ? 88 : 0));
      final creditHeight = !showCredit
          ? 0.0
          : creditWidth >= 118
          ? 15.0
          : creditWidth >= 92
          ? 24.0
          : 34.0;
      final clockInHeader = w >= 195;
      final city = weather.city.isEmpty
          ? weather.t('شار هەڵبژێرە', 'اختر مدينة', 'Choose city')
          : weather.city;
      final showStatus = weather.stale || !weather.hasData;
      final available = math.max(
        0.0,
        h - header - (sideCredit ? actionHeight : actionHeight + creditHeight),
      );
      final bodyClock = !clockInHeader && available >= 89;
      final showMetrics = w >= 100 && available >= 115 && weather.hasData;
      final statusLine = showStatus && available >= 115;
      final bodyHeight = math.max(
        0.0,
        available -
            (bodyClock ? 24 : 0) -
            (showMetrics ? 19 : 0) -
            (statusLine ? 17 : 0),
      );
      final vertical = slim || (h > w && bodyHeight >= 130);
      final hours = weather.hours;
      final slots = vertical
          ? ((bodyHeight - (slim ? 77 : 52)) / (slim ? 32 : 23)).floor()
          : (bodyHeight >= 71 ? ((w - 2 * pad) / 33).floor() : 0);
      final count = math.min(hours.length, slots.clamp(0, 5));
      final hourHeight = vertical
          ? math.min(bodyHeight * .68, count * (slim ? 42.0 : 38.0))
          : math.min(bodyHeight * .50, 60.0);
      return WeatherGlass(
        weather: weather,
        radius: math.min(20.0, math.min(w, h) * .18),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: pad,
              right: pad,
              height: header,
              child: Row(
                textDirection: TextDirection.ltr,
                children: [
                  if (clockInHeader)
                    FittedBox(fit: BoxFit.scaleDown, child: _clock(date: true)),
                  Expanded(
                    child: Align(
                      alignment: clockInHeader
                          ? Alignment.centerRight
                          : Alignment.center,
                      child: label(
                        city,
                        w < 80 ? 11 : 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (strip && actions)
              Positioned(
                top: header,
                bottom: sideCredit ? creditHeight : 2,
                left: 89,
                right: pad,
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _current(stacked: false, description: w >= 245),
                    ),
                    if (w >= 270 && hours.length >= 2 && h >= 65)
                      Expanded(
                        flex: 2,
                        child: _forecast(2, vertical: false, slim: true),
                      ),
                  ],
                ),
              )
            else
              Positioned(
                top: header,
                left: pad,
                right: pad,
                height: available,
                child: Column(
                  children: [
                    if (bodyClock)
                      SizedBox(
                        height: 24,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: _clock(date: w >= 95),
                        ),
                      ),
                    Expanded(
                      child: _current(
                        stacked: slim && bodyHeight >= 58,
                        spacious: w >= 180 && bodyHeight >= 140,
                        description:
                            (w >= 104 && bodyHeight >= 34) ||
                            (slim && bodyHeight >= 100),
                      ),
                    ),
                    if (count > 0)
                      SizedBox(
                        height: hourHeight,
                        child: _forecast(
                          count,
                          vertical: vertical,
                          slim: slim,
                          fullRow: vertical && w >= 185,
                        ),
                      ),
                    if (showMetrics) SizedBox(height: 19, child: _metrics(w)),
                    if (statusLine)
                      SizedBox(
                        height: 17,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: label(weather.status, 10),
                        ),
                      ),
                  ],
                ),
              ),
            if (showCredit)
              Positioned(
                left: (sideCredit ? 88 : 0) + pad,
                right: pad,
                bottom: sideCredit ? 1 : actionHeight,
                height: math.min(
                  creditHeight,
                  math.max(
                    0.0,
                    h - header - actionHeight + (sideCredit ? actionHeight : 0),
                  ),
                ),
                child: _attribution(creditWidth),
              ),
            if (showStatus && !statusLine && w >= 60 && !clockInHeader)
              const Positioned(
                left: 1,
                top: 2,
                child: Icon(Icons.history, size: 10, color: Colors.white),
              ),
            if (actions)
              Positioned(
                left: 0,
                bottom: 0,
                width: stackedActions ? w : 88,
                height: actionHeight,
                child: Flex(
                  direction: stackedActions ? Axis.vertical : Axis.horizontal,
                  textDirection: TextDirection.ltr,
                  children: const [
                    Expanded(
                      child: Center(
                        child: Icon(
                          Icons.my_location,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Icon(
                          Icons.refresh,
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    },
  );
}

Future<void>? _fontLoad;
Future<void> weatherFonts() => _fontLoad ??= Future.wait([
  for (final entry in const {
    'NAVKurdArabic':
        'android/app/src/main/res/font/uniqaidar_money_heist_002.ttf',
    'NAVKurdLatin':
        'android/app/src/main/res/font/red_hat_display_variable.ttf',
    'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
  }.entries)
    (FontLoader(entry.key)..addFont(rootBundle.load(entry.value))).load(),
]).then((_) {});
Future<Uint8List> weatherBitmap(
  Size size,
  double ratio,
  WeatherModel model,
) async {
  if (size.isEmpty || !size.isFinite || ratio <= 0 || !ratio.isFinite) {
    throw ArgumentError('Invalid launcher dimensions');
  }
  await weatherFonts();
  final focus = FocusManager();
  final builds = BuildOwner(focusManager: focus);
  final pipeline = PipelineOwner();
  final root = RenderRepaintBoundary();
  pipeline.rootNode = root;
  final layer = OffsetLayer()..attach(root);
  root.scheduleInitialPaint(layer);
  // Establish constraints on the empty root. Adding the widget then schedules
  // its LayoutBuilder for the pipeline owner's layout phase.
  root.layout(BoxConstraints.tight(size));
  final widget = MediaQuery(
    data: MediaQueryData(
      size: size,
      devicePixelRatio: ratio,
      textScaler: TextScaler.noScaling,
    ),
    child: Localizations(
      locale: model.lang == 'ku' ? const Locale('ckb') : Locale(model.lang),
      delegates: [
        // The bitmap tree has no display frame to wait for asynchronous Material delegates.
        for (final delegate
            in navKurdDelegates
                .whereType<LocalizationsDelegate<WidgetsLocalizations>>())
          if (delegate.isSupported(
            model.lang == 'ku' ? const Locale('ckb') : Locale(model.lang),
          ))
            delegate,
      ],
      child: Directionality(
        textDirection: model.lang == 'en'
            ? TextDirection.ltr
            : TextDirection.rtl,
        child: DefaultTextStyle(style: ink(13), child: WeatherWidgetArt(model)),
      ),
    ),
  );
  final tree = RenderObjectToWidgetAdapter<RenderBox>(
    container: root,
    child: widget,
  ).attachToRenderTree(builds);
  ui.Image? image;
  try {
    builds.buildScope(tree);
    builds.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    image = await root.toImage(pixelRatio: ratio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG encoding failed');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    final scheduler = SchedulerBinding.instance;
    final settled = scheduler.endOfFrame;
    scheduler.scheduleWarmUpFrame();
    // A headless Android engine can be paused without a display vsync.
    await settled.timeout(const Duration(milliseconds: 250), onTimeout: () {});

    RenderObjectToWidgetAdapter<RenderBox>(
      container: root,
    ).attachToRenderTree(builds, tree);
    builds.buildScope(tree);
    builds.finalizeTree();
    pipeline.rootNode = null;
    layer.detach();
    root.dispose();
    pipeline.dispose();
    focus.dispose();
  }
}

const bitmapChannel = MethodChannel('navkurd/weather_bitmap');
Future<void> startWeatherRenderer() async {
  WidgetsFlutterBinding.ensureInitialized();
  bitmapChannel.setMethodCallHandler((call) async {
    if (call.method != 'render') throw MissingPluginException();
    final args = object(call.arguments);
    final snapshot = object(args['weather']);
    final lang = snapshot['language'];
    final weather = WeatherModel(
      snapshot,
      lang == 'ar' || lang == 'en' ? lang as String : 'ku',
      DateTime.now(),
    );
    return weatherBitmap(
      Size(
        (args['width'] as num).toDouble(),
        (args['height'] as num).toDouble(),
      ),
      (args['ratio'] as num).toDouble(),
      weather,
    );
  });
  await bitmapChannel.invokeMethod<void>('ready');
}
