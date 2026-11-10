import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
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
  text,
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
      border: Border.all(color: Colors.white30),
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
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) {
      final w = c.maxWidth, h = c.maxHeight;
      final small = w < 200 || h < 58;
      final large = !small && h >= 158 && w >= 215;
      final head = small ? h * .29 : h * .24;
      final hero = small
          ? h - head
          : large
          ? h * .30
          : h * .46;
      final city = weather.city.isEmpty
          ? weather.t('شار هەڵبژێرە', 'اختر مدينة', 'Choose city')
          : weather.city;
      final reading = weather.temp == null ? '—' : '${weather.temp!.round()}°';
      final pad = math.min(w * .045, 14.0);
      return WeatherGlass(
        weather: weather,
        radius: math.min(22.0, h * .17),
        blur: false,
        child: Stack(
          children: [
            Positioned(
              right: pad,
              left: small ? pad : w * .40,
              top: 1,
              height: head - 1,
              child: Align(
                alignment: Alignment.centerRight,
                child: label(
                  city,
                  math.min(head * .56, 17.0),
                  weight: FontWeight.w700,
                ),
              ),
            ),
            if (!small)
              Positioned(
                left: pad,
                top: 1,
                width: w * .34,
                height: h * .30,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          label(
                            weather.clock(weather.date),
                            20,
                            weight: FontWeight.bold,
                          ),
                          const SizedBox(width: 6),
                          label(
                            '${weather.date.day}/${weather.date.month}',
                            10,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              right: pad,
              left: small ? pad : w * .17,
              top: head,
              height: hero,
              child: Align(
                alignment: small ? Alignment.center : Alignment.centerRight,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      glyph(
                        weather.sky,
                        weather.day,
                        math.min(hero * .95, 65.0),
                      ),
                      label(
                        reading,
                        math.min(39.0, hero * .60),
                        weight: FontWeight.w700,
                      ),
                      if (!small)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: label(
                            skyName(weather.sky, weather.day, weather.lang),
                            math.min(14.0, w * .038),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (small && weather.stale)
              Positioned(
                left: 3,
                top: 2,
                child: Icon(
                  Icons.history,
                  size: math.min(11.0, h * .12),
                  color: Colors.white,
                ),
              ),
            if (large)
              Positioned(
                left: pad,
                right: pad,
                top: h * .54,
                height: h * .28,
                child: Row(
                  children: [
                    for (final hour in weather.hours.take(5))
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              label(weather.hourLabel(hour.at), 9),
                              glyph(weatherSky(hour.code), hour.day, 17),
                              label('${hour.temp.round()}°', 11),
                            ],
                          ),
                        ),
                      ),
                    if (weather.hours.isEmpty)
                      Expanded(child: label(weather.status, 10)),
                  ],
                ),
              ),
            if (!small)
              Positioned(
                left: 4,
                bottom: 2,
                width: 72,
                height: math.min(35.0, h * .27),
                child: const Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Icon(Icons.my_location, size: 17, color: Colors.white),
                      Icon(Icons.refresh, size: 19, color: Colors.white),
                    ],
                  ),
                ),
              ),
            if (!small)
              Positioned(
                left: 80,
                right: pad,
                bottom: 2,
                height: large ? h * .18 : h * .28,
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (large)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (weather.wind != null)
                              GlassBadge(
                                '${weather.wind!.round()} km/h',
                                size: 9,
                              ),
                            if (weather.pm != null)
                              GlassBadge(
                                'PM2.5 ${weather.pm!.round()} µg/m³',
                                size: 9,
                              ),
                            if (weather.aqi != null)
                              GlassBadge(
                                'AQI ${weather.aqi!.round()}',
                                size: 9,
                              ),
                          ],
                        ),
                      if (weather.stale || !weather.hasData)
                        label(weather.status, 9),
                      label('Open-Meteo  ·  Developer: Sarhang Salah', 9),
                    ],
                  ),
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
    'NAVKurdArabic': 'uniqaidar_money_heist_002',
    'NAVKurdLatin': 'red_hat_display_variable',
  }.entries)
    (FontLoader(entry.key)..addFont(
          rootBundle.load('android/app/src/main/res/font/${entry.value}.ttf'),
        ))
        .load(),
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
  final widget = MediaQuery(
    data: MediaQueryData(
      size: size,
      devicePixelRatio: ratio,
      textScaler: TextScaler.noScaling,
    ),
    child: Localizations(
      locale: const Locale('ckb'),
      delegates: const [DefaultWidgetsLocalizations.delegate],
      child: Directionality(
        textDirection: TextDirection.rtl,
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
    root.layout(BoxConstraints.tight(size));
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
    final weather = WeatherModel(object(args['weather']), 'ku', DateTime.now());
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
