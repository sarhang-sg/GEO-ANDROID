import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geo_android/weather/weather_model.dart';

class WeatherIcon extends CustomPainter {
  const WeatherIcon(this.sky, this.day);
  final Sky sky;
  final bool day;
  @override
  void paint(Canvas c, Size size) {
    final side = math.min(size.width, size.height);
    c.save();
    c.translate((size.width - side) / 2, (size.height - side) / 2);
    c.scale(side / 100);
    final p = Paint()..isAntiAlias = true;
    void sphere(Offset pos, double radius, List<Color> colors) {
      p.shader = ui.Gradient.radial(
        pos - Offset(radius * .34, radius * .36),
        radius * 1.62,
        colors,
        [0, .58, 1],
      );
      c.drawCircle(pos, radius, p);
      p.shader = null;
    }

    if (sky == Sky.unknown) {
      p.color = Colors.white54;
      c.drawCircle(const Offset(50, 50), 4, p);
      c.restore();
      return;
    }
    final clear = sky == Sky.clear || sky == Sky.heat;
    if (clear || sky == Sky.partly) {
      final at = clear ? const Offset(50, 47) : const Offset(63, 32);
      final radius = clear ? 23.0 : 17.0;
      if (day) {
        p.color = const Color(0xaaffd15a);
        p.strokeWidth = 3;
        p.strokeCap = StrokeCap.round;
        for (var i = 0; i < 12; i++) {
          final v = Offset(
            math.cos(i * math.pi / 6),
            math.sin(i * math.pi / 6),
          );
          c.drawLine(at + v * (radius + 5), at + v * (radius + 10), p);
        }
        sphere(at, radius, [
          const Color(0xfffffff0),
          const Color(0xffffd54e),
          const Color(0xffff873b),
        ]);
      } else {
        final moon = Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: at, radius: radius + 4)),
          Path()..addOval(
            Rect.fromCircle(
              center: at + Offset(radius * .60, -radius * .58),
              radius: radius,
            ),
          ),
        );
        p.shader = ui.Gradient.linear(
          at - const Offset(10, 20),
          at + const Offset(14, 24),
          [Colors.white, const Color(0xffa5c4ff)],
        );
        c.drawPath(moon, p);
        p.shader = null;
      }
    }
    if (!clear) {
      final cloud = Path()
        ..moveTo(25, 66)
        ..cubicTo(2, 64, 7, 43, 22, 42)
        ..cubicTo(23, 18, 54, 16, 62, 34)
        ..cubicTo(77, 28, 85, 39, 84, 45)
        ..cubicTo(101, 50, 92, 67, 78, 67)
        ..close();
      c.drawShadow(cloud, const Color(0x99144470), 5, true);
      p.shader = ui.Gradient.linear(
        const Offset(46, 25),
        const Offset(50, 69),
        [
          Colors.white,
          const Color(0xffd7eeff),
          sky == Sky.storm ? const Color(0xff807cae) : const Color(0xff7195cb),
        ],
        [0, .42, 1],
      );
      c.drawPath(cloud, p);
      p.shader = null;
      p.color = Colors.white70;
      p.style = PaintingStyle.stroke;
      p.strokeWidth = 1.2;
      c.drawPath(cloud, p);
      p.style = PaintingStyle.fill;
      if ([Sky.rain, Sky.lightRain, Sky.heavyRain, Sky.storm].contains(sky)) {
        p.strokeCap = StrokeCap.round;
        p.strokeWidth = 3;
        p.color = const Color(0xffaceaff);
        for (final x in [31.0, 47.0, 63.0]) {
          c.drawLine(Offset(x, 73), Offset(x - 4, 80), p);
        }
        if (sky == Sky.storm) {
          p.color = const Color(0xffffd761);
          c.drawPath(
            Path()
              ..moveTo(57, 57)
              ..lineTo(45, 76)
              ..lineTo(53, 75)
              ..lineTo(48, 88)
              ..lineTo(68, 66)
              ..lineTo(59, 67)
              ..close(),
            p,
          );
        }
      } else if ([Sky.snow, Sky.blizzard, Sky.frost].contains(sky)) {
        p.color = Colors.white;
        p.strokeWidth = 1.8;
        for (final x in [30.0, 50.0, 70.0]) {
          for (var i = 0; i < 3; i++) {
            final v =
                Offset(math.cos(i * math.pi / 3), math.sin(i * math.pi / 3)) *
                4;
            c.drawLine(Offset(x, 77) - v, Offset(x, 77) + v, p);
          }
        }
      } else if ([Sky.fog, Sky.dust, Sky.windy].contains(sky)) {
        p.color = sky == Sky.dust ? const Color(0xffffd99b) : Colors.white70;
        p.strokeWidth = 3;
        p.strokeCap = StrokeCap.round;
        c.drawLine(const Offset(18, 73), const Offset(70, 73), p);
        c.drawLine(const Offset(32, 80), const Offset(82, 80), p);
      }
    }
    c.restore();
  }

  @override
  bool shouldRepaint(WeatherIcon old) => old.sky != sky || old.day != day;
}

class WeatherGlass extends StatelessWidget {
  const WeatherGlass({
    super.key,
    required this.weather,
    required this.child,
    this.radius = 24,
    this.blur = true,
  });
  final WeatherModel weather;
  final Widget child;
  final double radius;
  final bool blur;
  @override
  Widget build(BuildContext context) {
    final colors = weather.colors;
    final night = [0, 7].contains(phase(weather.date.hour));
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colors.take(2).toList(),
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(.7, -.95),
                radius: 1.4,
                colors: [
                  colors.last.withValues(alpha: .56),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          if (blur)
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: const SizedBox.expand(),
            ),
          if (night) const CustomPaint(painter: _Stars()),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0x82101832),
                  const Color(0x85192340),
                  const Color(0x99121e35),
                ],
              ),
              border: Border.all(color: Colors.white24),
              borderRadius: BorderRadius.circular(radius),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Stars extends CustomPainter {
  const _Stars();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = Colors.white38;
    for (var i = 0; i < 27; i++) {
      canvas.drawCircle(
        Offset(
          ((i * 83 + 11) % 101) * size.width / 101,
          ((i * i * 7 + 9) % 89) * size.height / 89,
        ),
        i % 4 == 0 ? 1.2 : .65,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_Stars old) => false;
}
