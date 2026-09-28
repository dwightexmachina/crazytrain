import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/game.dart';
import '../model/scenario.dart';
import 'palette.dart';

/// The one-time celebration when a scenario's final mission star latches:
/// a poster-style card over the dimmed, still-running board. ROUTE MAP
/// returns to the level screen; Keep building dismisses.
class LineClearOverlay extends StatelessWidget {
  final Game game;
  final VoidCallback onRouteMap;
  const LineClearOverlay(
      {super.key, required this.game, required this.onRouteMap});

  @override
  Widget build(BuildContext context) {
    final sc = game.scenario!;
    final idx = Scenarios.indexOf(sc.id);
    final next =
        idx >= 0 && idx + 1 < Scenarios.all.length ? Scenarios.all[idx + 1] : null;
    return Positioned.fill(
      child: ColoredBox(
        color: Pal.ink.withValues(alpha: 0.42),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              margin: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Pal.chromeBg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Pal.ink, width: 2),
                boxShadow:
                    const [BoxShadow(color: Pal.ink, offset: Offset(0, 6))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Stack(children: [
                  const Positioned(
                    left: 0,
                    right: 0,
                    top: -92,
                    child: IgnorePointer(
                      child: SizedBox(
                        height: 340,
                        child: CustomPaint(painter: _RayBurst()),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Transform.rotate(
                        angle: -0.044,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 7),
                          decoration: BoxDecoration(
                            color: Pal.accent,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Pal.ink, width: 2),
                            boxShadow: const [
                              BoxShadow(color: Pal.ink, offset: Offset(0, 3))
                            ],
                          ),
                          child: const Text('LINE CLEAR!',
                              style: TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  fontStyle: FontStyle.italic,
                                  letterSpacing: 1.5,
                                  color: Colors.white)),
                        ),
                      ),
                      const SizedBox(height: 13),
                      Text(sc.name,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.5,
                              color: Pal.muted)),
                      const _StarRow(),
                      const SizedBox(height: 4),
                      for (final m in sc.missions)
                        Container(
                          margin: const EdgeInsets.only(bottom: 5),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: Pal.card,
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(color: Pal.chromeLine),
                          ),
                          child: Row(children: [
                            const Text('✓',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Pal.good)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(m.title,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Pal.ink)),
                            ),
                          ]),
                        ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(children: [
                          const TextSpan(
                              text:
                                  'All contracts fulfilled — this stop is yours.\n'),
                          TextSpan(
                            text: next == null
                                ? "That's the whole line — for now."
                                : 'The line rolls on to ${next.name}.',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, color: Pal.ink),
                          ),
                        ]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 11.5, height: 1.5, color: Pal.muted),
                      ),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          flex: 16,
                          child: _ClearButton(
                            label: 'ROUTE MAP',
                            primary: true,
                            onTap: onRouteMap,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 10,
                          child: _ClearButton(
                            label: 'Keep building',
                            primary: false,
                            onTap: game.dismissLineClear,
                          ),
                        ),
                      ]),
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow();

  @override
  Widget build(BuildContext context) {
    Widget star(double size) => Text('★',
        style: TextStyle(
            fontSize: size,
            height: 1.05,
            color: Pal.accent,
            shadows: const [Shadow(offset: Offset(0, 2), color: Pal.ink)]));
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [star(40), const SizedBox(width: 6), star(52),
          const SizedBox(width: 6), star(40)],
    );
  }
}

class _ClearButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _ClearButton(
      {required this.label, required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: primary ? Pal.accent : Pal.chromeBg,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: Pal.ink, width: 2),
          boxShadow: const [BoxShadow(color: Pal.ink, offset: Offset(0, 3))],
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: primary ? 13.5 : 11.5,
                fontWeight: primary ? FontWeight.w900 : FontWeight.w800,
                letterSpacing: primary ? 1.5 : 0.2,
                color: primary ? Colors.white : Pal.ink)),
      ),
    );
  }
}

/// A soft sun-ray burst behind the banner and stars.
class _RayBurst extends CustomPainter {
  const _RayBurst();

  @override
  void paint(Canvas c, Size size) {
    final ctr = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = const Color(0x80F6E7C9);
    const wedge = 11 * math.pi / 180;
    const step = 30 * math.pi / 180;
    for (var a = 0.14; a < 2 * math.pi; a += step) {
      c.drawPath(
        Path()
          ..moveTo(ctr.dx, ctr.dy)
          ..arcTo(Rect.fromCircle(center: ctr, radius: 170), a, wedge, false)
          ..close(),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_RayBurst old) => false;
}
