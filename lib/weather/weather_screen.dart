import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geo_android/weather/weather_art.dart';
import 'package:geo_android/weather/weather_model.dart';
import 'package:geo_android/weather/weather_widget.dart';
import 'package:lottie/lottie.dart';
import 'package:permission_handler/permission_handler.dart';

const weatherChannel = MethodChannel('navkurd/weather');
Future<void> weatherPrompts(
  BuildContext context,
  MethodChannel channel, {
  String lang = 'ku',
}) async {
  try {
    final options =
        await channel.invokeMapMethod<String, bool>('prompts') ?? {};
    if (!context.mounted) return;
    Future<bool> ask(String title, String text, String yes) async =>
        (await showAdaptiveDialog<bool>(
          context: context,
          builder: (c) => AlertDialog.adaptive(
            title: Text(title),
            content: Text(text),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: Text(word(lang, 'ئێستا نا', 'ليس الآن', 'Not now')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(yes),
              ),
            ],
          ),
        )) ??
        false;
    if (options['notify'] == true &&
        await ask(
          word(lang, 'ئاگادارکردنەوە', 'الإشعارات', 'Weather notifications'),
          word(
            lang,
            notificationsCopy,
            'اسمح بالإشعارات لتصلك تنبيهات تغير الطقس والمخاطر.',
            'Allow notifications to hear about weather changes and hazards.',
          ),
          word(lang, 'بەردەوام بە', 'متابعة', 'Continue'),
        )) {
      await Permission.notification.request();
    }
    if (context.mounted &&
        options['battery'] == true &&
        await ask(
          word(lang, 'نوێکردنەوەی ویجێت', 'تحديث الأداة', 'Background updates'),
          word(
            lang,
            'ئەگەر ویجێتەکە دوا بکەوێت، لە ڕێکخستنەکانی باتری سنووری NAV KURD لاببە.',
            'إذا تأخرت تحديثات الأداة، ارفع قيود البطارية عن NAV KURD.',
            'If widget updates arrive late, open battery settings and set NAV KURD to unrestricted.',
          ),
          word(lang, 'ڕێکخستنەکان', 'الإعدادات', 'Open settings'),
        )) {
      await channel.invokeMethod<bool>('settings');
    }
  } on PlatformException {
    /* The user can change permissions in Android settings. */
  }
}

Future<void> startWeatherScreen() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    unawaited(_record(details.exception));
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(_record(error));
    return true;
  };
  ErrorWidget.builder = (_) => const ColoredBox(
    color: Color(0xff223657),
    child: Center(
      child: Text(
        'لە هەوڵی پەیوەندیکردندایە...',
        textDirection: TextDirection.rtl,
        style: TextStyle(color: Colors.white, fontSize: 15),
      ),
    ),
  );
  runApp(const _WeatherApp());
}

Future<void> _record(Object e) async {
  try {
    await weatherChannel.invokeMethod<void>('report', e.runtimeType.toString());
  } on PlatformException {
    return;
  }
}

class _WeatherApp extends StatelessWidget {
  const _WeatherApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.dark,
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xff81d9f8),
      fontFamily: 'NAVKurdArabic',
      scaffoldBackgroundColor: const Color(0xff172b45),
    ),
    builder: (context, child) =>
        MediaQuery.withClampedTextScaling(maxScaleFactor: 1.2, child: child!),
    home: const _WeatherScreen(),
  );
}

class _WeatherScreen extends StatefulWidget {
  const _WeatherScreen();
  @override
  State<_WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<_WeatherScreen>
    with WidgetsBindingObserver {
  String route = 'details', lang = 'ku', query = '';
  Map<String, dynamic> data = {};
  List<Map<String, dynamic>> cities = [];
  int generation = 0;
  bool busy = true;
  Timer? timer;
  final hourlyAnchor = GlobalKey();
  WeatherModel get weather => WeatherModel(data, lang, DateTime.now());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    weatherChannel.setMethodCallHandler((call) async {
      if (call.method == 'route' && mounted) _show(call.arguments as String);
    });
    timer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    unawaited(_boot());
  }

  Future<void> _boot() async {
    try {
      final start =
          await weatherChannel.invokeMethod<String>('route') ?? 'details';
      final language =
          await weatherChannel.invokeMethod<String>('language') ?? 'ku';
      final list =
          jsonDecode(await rootBundle.loadString('assets/weather/cities.json'))
              as List;
      if (!mounted) return;
      setState(() {
        lang = language;
        route = start;
        cities = list.map(object).toList();
      });
      final cached = await weatherChannel.invokeMethod<String>('snapshot');
      if (mounted && cached != null && generation == 0) {
        setState(() => data = object(jsonDecode(cached)));
      }
      if (mounted && generation == 0) await _load(false);
      if (mounted) {
        _scroll();
        unawaited(weatherPrompts(context, weatherChannel, lang: lang));
      }
    } catch (e) {
      await _record(e);
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _load(bool force, {Map<String, dynamic>? selection}) async {
    final seq = ++generation;
    setState(() => busy = true);
    try {
      final result = await weatherChannel.invokeMethod<String>(
        selection == null ? 'load' : 'choose',
        selection == null ? force : jsonEncode(selection),
      );
      if (!mounted || seq != generation) return;
      setState(() {
        data = result == null ? {} : object(jsonDecode(result));
        if (selection != null) route = 'details';
      });
    } catch (e) {
      await _record(e);
      if (mounted && seq == generation) {
        setState(() => data = {...data, 'stale': true});
      }
    } finally {
      if (mounted && seq == generation) setState(() => busy = false);
    }
  }

  void _scroll() {
    if (route == 'forecast') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = hourlyAnchor.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 280),
          );
        }
      });
    }
  }

  void _show(String next) {
    if (!mounted) return;
    setState(() {
      route = next;
      query = '';
    });
    _scroll();
  }

  Future<void> _back() async {
    if (route == 'cities') {
      _show('details');
      return;
    }
    await weatherChannel.invokeMethod<void>('back');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && !busy) unawaited(_load(false));
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    weatherChannel.setMethodCallHandler(null);
    super.dispose();
  }

  Widget action(IconData icon, String name, VoidCallback f) =>
      _WeatherButton(icon: icon, name: name, act: f);
  @override
  Widget build(BuildContext context) {
    final m = weather;
    final rtl = lang != 'en';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (p, _) {
        if (!p) unawaited(_back());
      },
      child: Directionality(
        textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          body: WeatherGlass(
            weather: m,
            radius: 0,
            child: SafeArea(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                child: route == 'cities' ? _picker(m) : _details(m),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _picker(WeatherModel m) {
    final q = query.trim().toLowerCase();
    String localName(Map<String, dynamic> c) =>
        ((lang == 'ku' ? null : c[lang]) as String?)?.trim().isNotEmpty == true
        ? c[lang] as String
        : c['name'] as String;
    final matches = cities
        .where(
          (c) => [
            c['name'],
            c['ar'],
            c['en'],
          ].any((v) => v.toString().toLowerCase().contains(q)),
        )
        .toList();
    return Column(
      key: const ValueKey('cities'),
      children: [
        ListTile(
          leading: action(
            Icons.arrow_back,
            m.t('گەڕانەوە', 'عودة', 'Back'),
            () => _show('details'),
          ),
          title: label(m.t('شار هەڵبژێرە', 'اختر مدينة', 'Choose city'), 22),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: (v) => setState(() => query = v),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: m.t('ناوی شار', 'اسم المدينة', 'City name'),
              filled: true,
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.my_location),
          title: label(
            m.t('شوێنی ئێستام', 'موقعي الحالي', 'Use my location'),
            16,
          ),
          onTap: () async {
            unawaited(HapticFeedback.selectionClick());
            if (!(await Permission.locationWhenInUse.request()).isGranted ||
                !mounted) {
              return;
            }
            final seq = ++generation;
            setState(() => busy = true);
            try {
              final value = await weatherChannel.invokeMethod<String>('gps');
              if (mounted && seq == generation && value != null) {
                setState(() {
                  data = object(jsonDecode(value));
                  route = 'details';
                });
              }
            } on PlatformException {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      m.t(
                        'شوێنی ئێستا بەردەست نییە',
                        'الموقع غير متاح',
                        'Location unavailable',
                      ),
                    ),
                  ),
                );
              }
            } finally {
              if (mounted && seq == generation) setState(() => busy = false);
            }
          },
        ),
        Expanded(
          child: ListView.builder(
            itemCount: matches.length,
            itemBuilder: (ctx, i) => ListTile(
              title: label(localName(matches[i]), 17),
              subtitle: label(matches[i]['en'].toString(), 12),
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                unawaited(_load(true, selection: matches[i]));
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _details(WeatherModel m) {
    final city = m.city.isEmpty
        ? m.t('شار هەڵبژێرە', 'اختر مدينة', 'Choose city')
        : m.city;
    final animate = !MediaQuery.disableAnimationsOf(context);
    final wet = [
      Sky.rain,
      Sky.lightRain,
      Sky.heavyRain,
      Sky.storm,
    ].contains(m.sky);
    final asset = wet
        ? 'rain'
        : m.sky == Sky.clear && m.day
        ? 'rays'
        : 'mist';
    return ListView(
      key: const ValueKey('detail'),
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 32),
      children: [
        Row(
          children: [
            action(
              Icons.arrow_back,
              m.t('نەخشە', 'الخريطة', 'Map'),
              () => unawaited(_back()),
            ),
            Expanded(
              child: TextButton(
                onPressed: () {
                  unawaited(HapticFeedback.selectionClick());
                  _show('cities');
                },
                child: label(city, 22, weight: FontWeight.bold),
              ),
            ),
            action(Icons.refresh, m.t('نوێکردنەوە', 'تحديث', 'Refresh'), () {
              if (!busy) unawaited(_load(true));
            }),
          ],
        ),
        Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 150,
            height: 138,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (animate && m.hasData)
                  Lottie.asset(
                    'assets/weather/$asset.json',
                    repeat: true,
                    frameRate: FrameRate(24),
                    fit: BoxFit.contain,
                  ),
                Center(child: glyph(m.sky, m.day, 106)),
              ],
            ),
          ),
        ),
        Center(
          child: label(
            m.temp == null ? '—' : '${m.temp!.round()}°',
            62,
            weight: FontWeight.bold,
          ),
        ),
        Center(child: label(skyName(m.sky, m.day, lang), 24)),
        if (m.advice != null) Center(child: label(m.advice!, 14)),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 5,
          children: [
            GlassBadge(m.seasonName),
            GlassBadge(m.phaseName),
            if (m.hasData) GlassBadge(m.thermal),
          ],
        ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: label(m.status, 12),
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        if (m.extreme != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: const Color(0xbb70253c),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Text(m.extreme!, style: ink(16)),
          ),
        if (!m.stale && (m.sky == Sky.storm || m.sky == Sky.heavyRain))
          label(
            m.t(
              floodCopy,
              'احتمال سيول وأمطار غزيرة',
              'Heavy rain and possible flooding',
            ),
            14,
          ),
        if (!m.stale && (m.sky == Sky.dust || (m.aqi ?? 0) > 60))
          label(
            m.t(
              dustCopy,
              'تنبيه: غبار أو تراجع جودة الهواء',
              'Dust or poor air quality advisory',
            ),
            14,
          ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            if (m.wind != null)
              GlassBadge(
                '${m.t("با", "الرياح", "Wind")}  ${m.wind!.round()} km/h',
              ),
            if (m.pm != null) GlassBadge('PM2.5  ${m.pm!.round()} µg/m³'),
            if (m.aqi != null) GlassBadge('AQI  ${m.aqi!.round()}'),
          ],
        ),
        const SizedBox(height: 20),
        Container(
          key: hourlyAnchor,
          child: label(
            m.t('پێشبینیی ٢٤ کاتژمێر', 'توقعات ٢٤ ساعة', '24-hour forecast'),
            18,
            weight: FontWeight.bold,
          ),
        ),
        if (m.hours.isNotEmpty)
          SizedBox(
            height: 112,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: m.hours.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (_, i) {
                final hour = m.hours[i];
                return _tile(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      label(m.hourLabel(hour.at), 12),
                      glyph(weatherSky(hour.code), hour.day, 34),
                      label('${hour.temp.round()}°', 17),
                    ],
                  ),
                );
              },
            ),
          ),
        if (m.days.isNotEmpty) ...[
          const SizedBox(height: 15),
          label(
            m.t('پێشبینیی حەوت ڕۆژ', 'توقعات سبعة أيام', 'Seven-day forecast'),
            18,
            weight: FontWeight.bold,
          ),
          for (final d in m.days)
            if (number(d['at']) != null &&
                number(d['low']) != null &&
                number(d['high']) != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: glyph(
                  weatherSky(number(d['code'])?.toInt() ?? -1),
                  true,
                  36,
                ),
                title: label(_weekday(m, number(d['at'])!.toInt()), 16),
                trailing: label(
                  '${number(d["low"])!.round()}° / ${number(d["high"])!.round()}°',
                  16,
                ),
              ),
        ],
        const SizedBox(height: 20),
        Center(child: label('Open-Meteo  ·  Developer: Sarhang Salah', 11)),
      ],
    );
  }

  String _weekday(WeatherModel m, int at) {
    final i =
        m
            .local(DateTime.fromMillisecondsSinceEpoch(at * 1000, isUtc: true))
            .weekday -
        1;
    return (lang == 'en'
        ? const [
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
            'Sunday',
          ]
        : lang == 'ar'
        ? const [
            'الاثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
            'الأحد',
          ]
        : const [
            'دووشەممە',
            'سێشەممە',
            'چوارشەممە',
            'پێنجشەممە',
            'هەینی',
            'شەممە',
            'یەکشەممە',
          ])[i];
  }

  Widget _tile(Widget child) => Container(
    constraints: const BoxConstraints(minWidth: 72),
    padding: const EdgeInsets.symmetric(horizontal: 8),
    decoration: BoxDecoration(
      color: const Color(0x55213b54),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: Colors.white24),
    ),
    child: child,
  );
}

class _WeatherButton extends StatefulWidget {
  const _WeatherButton({
    required this.icon,
    required this.name,
    required this.act,
  });
  final IconData icon;
  final String name;
  final VoidCallback act;
  @override
  State<_WeatherButton> createState() => _WeatherButtonState();
}

class _WeatherButtonState extends State<_WeatherButton> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => setState(() => pressed = true),
    onPointerUp: (_) => setState(() => pressed = false),
    onPointerCancel: (_) => setState(() => pressed = false),
    child: AnimatedScale(
      scale: pressed ? 0.91 : 1,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutBack,
      child: IconButton(
        tooltip: widget.name,
        onPressed: () {
          HapticFeedback.selectionClick();
          widget.act();
        },
        icon: Icon(widget.icon, color: Colors.white),
      ),
    ),
  );
}
