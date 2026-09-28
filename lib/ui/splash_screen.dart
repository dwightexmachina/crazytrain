import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'palette.dart';

/// "Morning Line Poster": full-bleed sunrise splash. A big sun with slowly
/// turning rays climbs behind snow-capped hills while the train hits a
/// curve slightly too fast, cars fishtailing and notes puffing from the
/// stack. Dismissed by the button or any tap; that gesture also unlocks
/// audio for the riff (handled by the parent).
class SplashScreen extends StatefulWidget {
  final VoidCallback onDismiss;

  const SplashScreen({super.key, required this.onDismiss});

  @override
  State<SplashScreen> createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _rays = AnimationController(
      vsync: this, duration: const Duration(seconds: 26))
    ..repeat();
  late final AnimationController _bob = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400))
    ..repeat();
  late final AnimationController _notes = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2800))
    ..repeat();
  late final AnimationController _fade = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320), value: 1);

  bool _closing = false;

  @override
  void dispose() {
    _rays.dispose();
    _bob.dispose();
    _notes.dispose();
    _fade.dispose();
    super.dispose();
  }

  bool get _reduce => MediaQuery.of(context).disableAnimations;

  void close() {
    if (_closing) return;
    _closing = true;
    if (_reduce) {
      widget.onDismiss();
    } else {
      _fade.reverse().whenComplete(widget.onDismiss);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: close,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(
              painter: _PosterPainter(
                rays: _rays,
                bob: _bob,
                notes: _notes,
                still: _reduce,
              ),
            ),
            Column(
              children: [
                const Spacer(flex: 2),
                // Wordmark: terracotta fill with an ink outline.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Stack(
                      children: [
                        Text('CRAZY TRAIN', style: _wordmark(null)),
                        Text(
                          'CRAZY TRAIN',
                          style: _wordmark(Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 2
                            ..color = Pal.ink),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'AN OPEN-WORLD RAILWAY SANDBOX',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 6,
                    color: Pal.muted,
                  ),
                ),
                const Spacer(flex: 9),
                Material(
                  color: Pal.accent,
                  borderRadius: BorderRadius.circular(22),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(22),
                    onTap: close,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                      child: Text(
                        'TAP TO ROLL',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _wordmark(Paint? fg) => TextStyle(
        fontSize: 84,
        fontWeight: FontWeight.w900,
        letterSpacing: 2,
        color: fg == null ? Pal.accent : null,
        foreground: fg,
      );
}

class _PosterPainter extends CustomPainter {
  final Animation<double> rays, bob, notes;
  final bool still;
  _PosterPainter(
      {required this.rays,
      required this.bob,
      required this.notes,
      required this.still})
      : super(repaint: Listenable.merge([rays, bob, notes]));

  @override
  void paint(Canvas canvas, Size size) {
    // Designed in a 960x600 frame, scaled to cover.
    final s = math.max(size.width / 960, size.height / 600);
    canvas.save();
    canvas.translate(
        (size.width - 960 * s) / 2, (size.height - 600 * s) / 2);
    canvas.scale(s);
    final wob = still ? 0.0 : math.sin(bob.value * 2 * math.pi);

    // Sky.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 960, 600),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFF9EFDD), Color(0xFFF3DFC4), Color(0xFFEDD2AF)],
          stops: [0, 0.7, 1],
        ).createShader(const Rect.fromLTWH(0, 0, 960, 600)),
    );

    // Sun with slowly turning rays.
    const sunC = Offset(480, 470);
    if (!still) {
      final rayPaint = Paint()
        ..color = const Color(0xFFE8A87C).withValues(alpha: 0.28)
        ..strokeWidth = 26
        ..strokeCap = StrokeCap.round;
      final a0 = rays.value * 2 * math.pi / 6;
      for (var i = 0; i < 12; i++) {
        final a = a0 + i * math.pi / 6;
        canvas.drawLine(
          sunC + Offset.fromDirection(a, 250),
          sunC + Offset.fromDirection(a, 330),
          rayPaint,
        );
      }
    }
    canvas.drawCircle(sunC, 230,
        Paint()..color = const Color(0xFFE8A87C).withValues(alpha: 0.55));
    canvas.drawCircle(sunC, 170,
        Paint()..color = const Color(0xFFE19265).withValues(alpha: 0.65));

    // Hills with snow caps.
    void hill(double x0, double px, double x1, double py, Color c) {
      canvas.drawPath(
          Path()
            ..moveTo(x0, 470)
            ..lineTo(px, py)
            ..lineTo(x1, 470)
            ..close(),
          Paint()..color = c);
      final capW = (x1 - x0) * 0.11;
      canvas.drawPath(
          Path()
            ..moveTo(px - capW, py + 22)
            ..lineTo(px, py)
            ..lineTo(px + capW, py + 22)
            ..lineTo(px, py + 33)
            ..close(),
          Paint()..color = const Color(0xFFFDFCF8));
    }

    hill(0, 140, 260, 380, const Color(0xFFD9CBAE));
    hill(180, 330, 470, 350, const Color(0xFFCFC0A0));
    hill(620, 780, 930, 365, const Color(0xFFD9CBAE));

    // Ground.
    canvas.drawRect(const Rect.fromLTWH(0, 470, 960, 130),
        Paint()..color = Pal.ground);
    canvas.drawLine(const Offset(0, 470), const Offset(960, 470),
        Paint()
          ..color = Pal.grid
          ..strokeWidth = 2);

    // Swooping rail.
    final rail = Path()
      ..moveTo(-20, 560)
      ..cubicTo(240, 560, 300, 470, 480, 470)
      ..cubicTo(660, 470, 720, 560, 980, 560);
    canvas.drawPath(
        rail,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 26
          ..strokeCap = StrokeCap.round
          ..color = Pal.bed);
    // Ties + rails via path metrics.
    final metric = rail.computeMetrics().first;
    final tiePaint = Paint()
      ..color = Pal.tie
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    for (var d = 8.0; d < metric.length; d += 24) {
      final tan = metric.getTangentForOffset(d)!;
      final n = Offset(-tan.vector.dy, tan.vector.dx) /
          tan.vector.distance;
      canvas.drawLine(
          tan.position - n * 10, tan.position + n * 10, tiePaint);
    }
    final railPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    for (final side in const [-6.0, 6.0]) {
      final p = Path();
      var first = true;
      for (var d = 0.0; d < metric.length; d += 12) {
        final tan = metric.getTangentForOffset(d)!;
        final n = Offset(-tan.vector.dy, tan.vector.dx) /
            tan.vector.distance;
        final pt = tan.position + n * side;
        first ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
        first = false;
      }
      canvas.drawPath(p, railPaint);
    }

    // Speed lines.
    final speed = Paint()
      ..color = Pal.faint
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(120, 420 + wob), Offset(185, 418 + wob), speed);
    canvas.drawLine(Offset(96, 446 + wob * 1.4), Offset(176, 444 + wob * 1.4), speed);
    canvas.drawLine(Offset(130, 472 + wob), Offset(190, 470 + wob), speed);

    // The train: engine tilted into the curve, cars fishtailing behind.
    void box(List<Offset> pts, Color c) =>
        canvas.drawPath(Path()..addPolygon(pts, true), Paint()..color = c);

    void wheels(List<Offset> centers, double r) {
      for (final w in centers) {
        canvas.drawCircle(w, r, Paint()..color = Pal.stack.$3);
      }
    }

    // Engine.
    canvas.save();
    canvas.translate(400, 400 + wob * 3);
    canvas.rotate((-7 + wob * 1.5) * math.pi / 180);
    box(const [Offset(0, 40), Offset(70, 40), Offset(70, -6), Offset(0, -6)],
        Pal.engine.$1);
    box(const [Offset(70, 40), Offset(92, 28), Offset(92, -14), Offset(70, -6)],
        Pal.engine.$2);
    box(const [Offset(0, -6), Offset(70, -6), Offset(92, -14), Offset(20, -14)],
        Pal.cab.$1);
    box(const [Offset(6, -6), Offset(34, -6), Offset(34, -34), Offset(6, -34)],
        Pal.cab.$1);
    box(const [Offset(34, -6), Offset(46, -12), Offset(46, -38), Offset(34, -34)],
        Pal.engine.$2);
    canvas.drawRect(const Rect.fromLTWH(52, -30, 10, 24),
        Paint()..color = Pal.stack.$1);
    wheels(const [Offset(14, 40), Offset(40, 40), Offset(62, 40)], 9);
    canvas.restore();

    void car(double x, double y, double deg, (Color, Color, Color) cols,
        double wobMul) {
      canvas.save();
      canvas.translate(x, y + wob * wobMul);
      canvas.rotate((deg + wob * 3 * wobMul.sign) * math.pi / 180);
      box(const [Offset(0, 30), Offset(58, 30), Offset(58, -4), Offset(0, -4)],
          cols.$1);
      box(const [Offset(58, 30), Offset(76, 20), Offset(76, -12), Offset(58, -4)],
          cols.$2);
      box(const [Offset(0, -4), Offset(58, -4), Offset(76, -12), Offset(18, -12)],
          cols.$3);
      wheels(const [Offset(12, 32), Offset(44, 32)], 7);
      canvas.restore();
    }

    car(305, 428, 6, Pal.car, 1.4);
    car(212, 452, -12, Pal.engine2, -1.2);

    // Notes puffing from the stack, drifting upward.
    final tn = still ? 0.35 : notes.value;
    void note(String glyph, double x, double y, double phase, double deg) {
      final t = (tn + phase) % 1.0;
      final alpha = t < 0.15 ? t / 0.15 : (1 - t).clamp(0.0, 1.0);
      final tp = TextPainter(
        text: TextSpan(
          text: glyph,
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w900,
            color: Pal.ink.withValues(alpha: alpha * 0.85),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(x + 14 * math.sin((t + phase) * 6), y - t * 90);
      canvas.rotate(deg * math.pi / 180);
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    note('♪', 496, 350, 0.0, 14);
    note('♫', 536, 340, 0.4, -10);
    note('♪', 570, 356, 0.7, 22);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_PosterPainter old) => true;
}
