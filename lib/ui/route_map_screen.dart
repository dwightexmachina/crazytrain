import 'package:flutter/material.dart';

import '../model/game.dart';
import '../model/scenario.dart';
import 'painters.dart';
import 'palette.dart';

/// Poster-style level select: the six scenarios are stops on a winding
/// railway line; the sandbox is a roundhouse on its own spur. Reached via
/// the splash screen, and from the in-game "route map" button.
class RouteMapScreen extends StatefulWidget {
  final void Function(Scenario scenario, {required bool resume}) onBoard;
  final VoidCallback onSandbox;
  const RouteMapScreen(
      {super.key, required this.onBoard, required this.onSandbox});

  @override
  State<RouteMapScreen> createState() => _RouteMapScreenState();
}

/// Normalized station positions on the 1060×640 poster canvas, in line
/// order (matching [Scenarios.all]).
const List<Offset> kStationPos = [
  Offset(105, 585),
  Offset(300, 498),
  Offset(545, 430),
  Offset(720, 330),
  Offset(600, 235),
  Offset(930, 148),
];
const Offset _roundhousePos = Offset(688, 584);
const Size _posterSize = Size(1060, 640);

class _RouteMapScreenState extends State<RouteMapScreen> {
  late int _sel;
  final Map<String, Game> _previews = {};

  @override
  void initState() {
    super.initState();
    _sel = _frontier();
  }

  /// The furthest unlocked stop — where the engine parks.
  int _frontier() {
    var f = 0;
    for (var i = 0; i < Scenarios.all.length; i++) {
      if (ScenarioProgress.unlocked(i)) f = i;
    }
    return f;
  }

  Game _preview(Scenario sc) =>
      _previews.putIfAbsent(sc.id, () => Game(scenario: sc, resume: false));

  @override
  Widget build(BuildContext context) {
    final frontier = _frontier();
    return Container(
      color: const Color(0xFFF6E7C9),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        double px(Offset p) => p.dx / _posterSize.width * w;
        double py(Offset p) => p.dy / _posterSize.height * h;
        return Stack(children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RouteMapPainter(
                stars: [
                  for (final sc in Scenarios.all)
                    ScenarioProgress.stars(sc.id)
                ],
                unlocked: [
                  for (var i = 0; i < Scenarios.all.length; i++)
                    ScenarioProgress.unlocked(i)
                ],
                frontier: frontier,
                selected: _sel,
              ),
            ),
          ),
          // Wordmark.
          Positioned(
            left: 0.04 * w,
            top: 0.042 * h,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CRAZY TRAIN',
                      style: TextStyle(
                        fontSize: (0.031 * w).clamp(20.0, 34.0),
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic,
                        letterSpacing: 1,
                        color: Pal.accent,
                        shadows: const [
                          Shadow(offset: Offset(-1, 1), color: Pal.ink),
                          Shadow(offset: Offset(1, 1), color: Pal.ink),
                          Shadow(offset: Offset(0, 2), color: Pal.ink),
                        ],
                      )),
                  const Text('CHOOSE YOUR LINE',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 3,
                          color: Pal.muted)),
                ]),
          ),
          // Station plates.
          for (var i = 0; i < Scenarios.all.length; i++)
            Positioned(
              left: px(kStationPos[i]),
              top: py(kStationPos[i]) + 15,
              child: FractionalTranslation(
                translation: const Offset(-0.5, 0),
                child: _StationPlate(
                  scenario: Scenarios.all[i],
                  stars: ScenarioProgress.stars(Scenarios.all[i].id),
                  locked: !ScenarioProgress.unlocked(i),
                  selected: _sel == i,
                  onTap: () => setState(() => _sel = i),
                ),
              ),
            ),
          // Sandbox roundhouse plate.
          Positioned(
            left: px(_roundhousePos),
            top: py(_roundhousePos) + 4,
            child: FractionalTranslation(
              translation: const Offset(-0.5, 0),
              child: _Plate(
                selected: false,
                locked: false,
                onTap: widget.onSandbox,
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.handyman_rounded, size: 12, color: Pal.ink),
                  SizedBox(width: 4),
                  Text('SANDBOX',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: Pal.ink)),
                ]),
              ),
            ),
          ),
          // Detail panel for the selected stop.
          Positioned(
            top: 0.035 * h,
            right: 0.024 * w,
            width: (0.27 * w).clamp(240.0, 320.0),
            child: _DetailPanel(
              scenario: Scenarios.all[_sel],
              index: _sel,
              locked: !ScenarioProgress.unlocked(_sel),
              preview:
                  Scenarios.all[_sel].playable ? _preview(Scenarios.all[_sel]) : null,
              onBoard: widget.onBoard,
            ),
          ),
        ]);
      }),
    );
  }
}

// ---------------------------------------------------------------- plates

class _Plate extends StatelessWidget {
  final Widget child;
  final bool selected;
  final bool locked;
  final VoidCallback? onTap;
  const _Plate(
      {required this.child,
      required this.selected,
      required this.locked,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    final border = selected ? Pal.accent : (locked ? Pal.faint : Pal.ink);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFFFDF1EA)
              : (locked ? const Color(0xFFEFE6CE) : Pal.chromeBg),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: border, width: 1.5),
          boxShadow: [BoxShadow(color: border, offset: const Offset(0, 2))],
        ),
        child: child,
      ),
    );
  }
}

class _StationPlate extends StatelessWidget {
  final Scenario scenario;
  final int stars;
  final bool locked;
  final bool selected;
  final VoidCallback onTap;
  const _StationPlate(
      {required this.scenario,
      required this.stars,
      required this.locked,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final total = scenario.missions.length;
    return _Plate(
      selected: selected,
      locked: locked,
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(scenario.name,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.3,
                color: locked ? Pal.muted : Pal.ink)),
        Row(mainAxisSize: MainAxisSize.min, children: [
          Text('●' * scenario.difficulty,
              style: const TextStyle(
                  fontSize: 8,
                  letterSpacing: 1,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFC98A2D))),
          if (!locked && total > 0) ...[
            const SizedBox(width: 5),
            Text('★' * stars + '☆' * (total - stars),
                style: const TextStyle(
                    fontSize: 8.5,
                    letterSpacing: 1,
                    fontWeight: FontWeight.w800,
                    color: Pal.accent)),
          ],
          if (locked) ...[
            const SizedBox(width: 5),
            const Icon(Icons.lock_rounded, size: 9, color: Pal.muted),
          ],
        ]),
      ]),
    );
  }
}

// ---------------------------------------------------------------- panel

class _DetailPanel extends StatelessWidget {
  final Scenario scenario;
  final int index;
  final bool locked;
  final Game? preview;
  final void Function(Scenario scenario, {required bool resume}) onBoard;
  const _DetailPanel(
      {required this.scenario,
      required this.index,
      required this.locked,
      required this.preview,
      required this.onBoard});

  @override
  Widget build(BuildContext context) {
    final done = ScenarioProgress.done(scenario.id);
    final hasSave = scenario.playable && Game.hasSaveFor(scenario.id);
    final playable = scenario.playable && !locked;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: Pal.chromeBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Pal.ink, width: 1.5),
        boxShadow: const [BoxShadow(color: Pal.ink, offset: Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Flexible(
                child: Text(scenario.name,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                        color: Pal.ink)),
              ),
              const SizedBox(width: 7),
              Text('●' * scenario.difficulty,
                  style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFC98A2D))),
            ]),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: AspectRatio(
            aspectRatio: 2.0,
            child: locked
                ? _placeholder(Icons.lock_rounded,
                    'Earn a star at the previous stop to unlock')
                : (preview == null
                    ? _placeholder(Icons.explore_rounded,
                        'Surveying in progress — coming soon')
                    : Container(
                        color: Pal.pageBg,
                        child: CustomPaint(
                          painter:
                              StaticBoardPainter(preview!, 1, Offset.zero, 0),
                        ),
                      )),
          ),
        ),
        const SizedBox(height: 7),
        Text(scenario.blurb,
            style: const TextStyle(
                fontSize: 10.5, height: 1.45, color: Pal.muted)),
        if (!locked && scenario.missions.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final m in scenario.missions)
            Container(
              margin: const EdgeInsets.only(bottom: 4),
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Pal.card,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Pal.chromeLine),
              ),
              child: Row(children: [
                Text('★',
                    style: TextStyle(
                        fontSize: 12,
                        color: done.contains(m.id)
                            ? Pal.accent
                            : Pal.accent.withValues(alpha: 0.25))),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(m.title,
                      style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: Pal.ink)),
                ),
                if (done.contains(m.id))
                  const Text('EARNED',
                      style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                          color: Pal.faint)),
              ]),
            ),
        ],
        if (scenario.facts.isNotEmpty && !locked) ...[
          const SizedBox(height: 4),
          Wrap(spacing: 5, runSpacing: 5, children: [
            for (final f in scenario.facts)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Pal.chip,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(f,
                    style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: Pal.muted)),
              ),
          ]),
        ],
        if (playable) ...[
          const SizedBox(height: 9),
          Row(children: [
            Expanded(
              child: _PosterButton(
                label: hasSave ? 'RESUME' : 'ALL ABOARD',
                primary: true,
                onTap: () => onBoard(scenario, resume: hasSave),
              ),
            ),
            if (hasSave) ...[
              const SizedBox(width: 6),
              _PosterButton(
                label: 'Start fresh',
                primary: false,
                onTap: () => onBoard(scenario, resume: false),
              ),
            ],
          ]),
        ],
      ]),
    );
  }

  Widget _placeholder(IconData icon, String text) => Container(
        color: Pal.chip,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 22, color: Pal.faint),
          const SizedBox(height: 5),
          Text(text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Pal.muted)),
        ]),
      );
}

class _PosterButton extends StatelessWidget {
  final String label;
  final bool primary;
  final VoidCallback onTap;
  const _PosterButton(
      {required this.label, required this.primary, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: primary ? Pal.accent : Pal.chromeBg,
          borderRadius: BorderRadius.circular(10),
          border: primary ? null : Border.all(color: Pal.ink, width: 1.5),
          boxShadow: const [BoxShadow(color: Pal.ink, offset: Offset(0, 2))],
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: primary ? 12 : 10.5,
                fontWeight: FontWeight.w900,
                letterSpacing: primary ? 1.5 : 0.3,
                color: primary ? Colors.white : Pal.ink)),
      ),
    );
  }
}

// ---------------------------------------------------------------- painter

class _RouteMapPainter extends CustomPainter {
  final List<int> stars;
  final List<bool> unlocked;
  final int frontier;
  final int selected;
  _RouteMapPainter(
      {required this.stars,
      required this.unlocked,
      required this.frontier,
      required this.selected});

  static const _ink = Pal.ink;

  @override
  void paint(Canvas c, Size size) {
    c.save();
    c.scale(size.width / _posterSize.width, size.height / _posterSize.height);

    _sky(c);
    _sun(c);
    _bands(c);
    _vignettes(c);
    _spurAndRoundhouse(c);
    _line(c);
    _stations(c);
    _engine(c, kStationPos[frontier]);

    c.restore();
  }

  void _sky(Canvas c) {
    final r = Offset.zero & _posterSize;
    c.drawRect(
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFFF9EFDC),
            Color(0xFFF6E7C9),
            Color(0xFFF2E3C4),
            Color(0xFFEFE6CE),
          ],
          stops: [0, 0.34, 0.55, 1],
        ).createShader(r),
    );
  }

  void _sun(Canvas c) {
    const ctr = Offset(905, 99);
    final ray = Paint()
      ..color = const Color(0xFFEFC98A)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in [
      (const Offset(905, 18), const Offset(905, -30)),
      (const Offset(963, 42), const Offset(998, 8)),
      (const Offset(846, 42), const Offset(812, 8)),
      (const Offset(987, 99), const Offset(1035, 99)),
      (const Offset(823, 99), const Offset(775, 99)),
      (const Offset(963, 156), const Offset(998, 190)),
      (const Offset(846, 156), const Offset(812, 190)),
    ]) {
      c.drawLine(a, b, ray);
    }
    c.drawCircle(ctr, 46, Paint()..color = const Color(0xFFEFB35C));
    c.drawCircle(
        ctr,
        46,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _ink);
  }

  void _bands(Canvas c) {
    final b1 = Path()
      ..moveTo(0, 470)
      ..quadraticBezierTo(140, 430, 300, 462)
      ..quadraticBezierTo(470, 490, 640, 452)
      ..quadraticBezierTo(850, 415, 1060, 470)
      ..lineTo(1060, 640)
      ..lineTo(0, 640)
      ..close();
    c.drawPath(b1, Paint()..color = const Color(0xCCE7D9AE));
    final b2 = Path()
      ..moveTo(0, 540)
      ..quadraticBezierTo(200, 500, 430, 532)
      ..quadraticBezierTo(700, 565, 1060, 528)
      ..lineTo(1060, 640)
      ..lineTo(0, 640)
      ..close();
    c.drawPath(b2, Paint()..color = const Color(0xE6DFCF9E));
  }

  void _vignettes(Canvas c) {
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _ink;
    // Prairie tufts.
    final tuft = Paint()
      ..color = const Color(0xFFA9A25B)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (final (x, y) in [(70.0, 590.0), (180.0, 606.0)]) {
      c.drawLine(Offset(x, y), Offset(x, y - 12), tuft);
      c.drawLine(Offset(x + 8, y), Offset(x + 8, y - 16), tuft);
      c.drawLine(Offset(x + 16, y), Offset(x + 16, y - 11), tuft);
    }
    // Gorge: a river slot dropping off the bottom edge.
    final gorge = Path()
      ..moveTo(255, 640)
      ..lineTo(300, 470)
      ..lineTo(330, 470)
      ..lineTo(305, 640)
      ..close();
    c.drawPath(gorge, Paint()..color = const Color(0xFF7FA8C9));
    c.drawPath(gorge, stroke);
    // Ridge: snow-capped peaks.
    final peak1 = Path()
      ..moveTo(470, 402)
      ..lineTo(520, 300)
      ..lineTo(570, 402)
      ..close();
    c.drawPath(peak1, Paint()..color = const Color(0xFFB49A7E));
    c.drawPath(peak1, stroke);
    final snow = Path()
      ..moveTo(505, 330)
      ..lineTo(520, 300)
      ..lineTo(535, 330)
      ..lineTo(520, 342)
      ..close();
    c.drawPath(snow, Paint()..color = Colors.white);
    c.drawPath(snow, stroke);
    final peak2 = Path()
      ..moveTo(535, 402)
      ..lineTo(585, 322)
      ..lineTo(635, 402)
      ..close();
    c.drawPath(peak2, Paint()..color = const Color(0xFFC2A98C));
    c.drawPath(peak2, stroke);
    // Archipelago lagoon.
    void island(Offset ctr, double rx, double ry, Color fill) {
      final rect = Rect.fromCenter(
          center: ctr, width: rx * 2, height: ry * 2);
      c.drawOval(rect, Paint()..color = fill);
      c.drawOval(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = _ink);
    }

    island(const Offset(745, 425), 78, 30, const Color(0xFF7FA8C9));
    island(const Offset(720, 420), 15, 7, const Color(0xFFA9C083));
    island(const Offset(762, 432), 12, 6, const Color(0xFFA9C083));
    island(const Offset(788, 416), 10, 5, const Color(0xFFA9C083));
    // Switchback valley walls.
    final wall = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 9;
    c.drawPath(
        Path()
          ..moveTo(500, 275)
          ..quadraticBezierTo(540, 241, 596, 253),
        wall..color = const Color(0xCCB49A7E));
    c.drawPath(
        Path()
          ..moveTo(485, 205)
          ..quadraticBezierTo(531, 175, 589, 185),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 9
          ..color = const Color(0xCCC2A98C));
    // Folly nubs.
    final nub = Paint()..color = const Color(0xFFC2A98C);
    final nubStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = _ink;
    for (final (x, w2, h2) in [(820.0, 14.0, 22.0), (850.0, 11.0, 17.0), (878.0, 13.0, 20.0)]) {
      final p = Path()
        ..moveTo(x, 172)
        ..lineTo(x + w2, 172 - h2)
        ..lineTo(x + w2 * 2, 172)
        ..close();
      c.drawPath(p, nub);
      c.drawPath(p, nubStroke);
    }
  }

  /// Curve segments of the line; stations sit at segment boundaries (the
  /// last stop takes two segments via a waypoint). [_segmentsTo] maps a
  /// station index to how many segments reach it.
  static const _segs = [
    // (c1, c2, to)
    (Offset(190, 560), Offset(220, 520), Offset(300, 498)),
    (Offset(380, 476), Offset(470, 452), Offset(545, 430)),
    (Offset(620, 408), Offset(690, 380), Offset(720, 330)),
    (Offset(750, 280), Offset(660, 260), Offset(600, 235)),
    (Offset(540, 210), Offset(700, 175), Offset(790, 165)),
    (Offset(880, 155), Offset(890, 152), Offset(930, 148)),
  ];
  static const _segmentsTo = [0, 1, 2, 3, 4, 6];

  Path _routePath({int? toStation}) {
    final count = toStation == null ? _segs.length : _segmentsTo[toStation];
    final p = Path()..moveTo(kStationPos[0].dx, kStationPos[0].dy);
    for (var i = 0; i < count; i++) {
      final (c1, c2, to) = _segs[i];
      p.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, to.dx, to.dy);
    }
    return p;
  }

  void _dashAlong(Canvas c, Path path, Paint paint,
      {required double dash, required double gap}) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        c.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  void _line(Canvas c) {
    final full = _routePath();
    // Faded rails all the way to the last stop…
    c.drawPath(
        full,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5
          ..color = const Color(0xFFE3D5B4));
    // …vivid ties + twin rails only as far as the frontier.
    final vivid = _routePath(toStation: frontier);
    _dashAlong(
        c,
        vivid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 13
          ..color = _ink.withValues(alpha: 0.85),
        dash: 3,
        gap: 14);
    c.drawPath(
        vivid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 5
          ..color = Pal.muted);
    c.drawPath(
        vivid,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 1.6
          ..color = Pal.chromeBg);
  }

  void _spurAndRoundhouse(Canvas c) {
    final spur = Path()
      ..moveTo(170, 568)
      ..cubicTo(300, 590, 520, 610, 640, 596);
    _dashAlong(
        c,
        spur,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 4
          ..color = Pal.muted.withValues(alpha: 0.8),
        dash: 7,
        gap: 7);
    c.save();
    c.translate(_roundhousePos.dx - 38, _roundhousePos.dy - 40);
    final house = Path()
      ..moveTo(0, 40)
      ..lineTo(0, 14)
      ..arcToPoint(const Offset(76, 14), radius: const Radius.circular(38))
      ..lineTo(76, 40)
      ..close();
    c.drawPath(house, Paint()..color = const Color(0xFFC97F62));
    c.drawPath(
        house,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _ink);
    final door = Paint()..color = _ink;
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(14, 22, 14, 18), const Radius.circular(2)),
        door);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(48, 22, 14, 18), const Radius.circular(2)),
        door);
    c.drawRect(const Rect.fromLTWH(30, 2, 7, 12), door);
    c.restore();
  }

  void _stations(Canvas c) {
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..color = _ink;
    for (var i = 0; i < kStationPos.length; i++) {
      final p = kStationPos[i];
      final cleared = stars[i] > 0;
      final open = unlocked[i];
      final fill = cleared
          ? const Color(0xFF6F9E7C)
          : (i == frontier
              ? Pal.accent
              : (open ? Pal.chromeBg : const Color(0xFFEFE6CE)));
      if (i == selected) {
        c.drawCircle(
            p,
            16,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5
              ..color = Pal.accent.withValues(alpha: 0.55));
      }
      c.drawCircle(p, open ? 11 : 10, Paint()..color = fill);
      c.drawCircle(p, open ? 11 : 10, outline);
      if (cleared) {
        final check = Path()
          ..moveTo(p.dx - 5, p.dy)
          ..lineTo(p.dx - 1, p.dy + 4)
          ..lineTo(p.dx + 6, p.dy - 5);
        c.drawPath(
            check,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 3
              ..color = Pal.chromeBg);
      } else if (!open) {
        // Padlock.
        final grey = Paint()..color = Pal.muted;
        c.drawRRect(
            RRect.fromRectAndRadius(
                Rect.fromCenter(
                    center: Offset(p.dx, p.dy + 1.5), width: 9, height: 7),
                const Radius.circular(1.5)),
            grey);
        c.drawArc(
            Rect.fromCenter(
                center: Offset(p.dx, p.dy - 2), width: 6, height: 7),
            3.14159,
            3.14159,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = Pal.muted);
      }
    }
  }

  void _engine(Canvas c, Offset at) {
    c.save();
    c.translate(at.dx - 52, at.dy - 40);
    c.rotate(-0.14);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = _ink;
    // Body + cab.
    final body = RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 10, 44, 20), const Radius.circular(4));
    c.drawRRect(body, Paint()..color = const Color(0xFFC25B4A));
    c.drawRRect(body, stroke);
    final cab = RRect.fromRectAndRadius(
        const Rect.fromLTWH(30, -6, 16, 18), const Radius.circular(3));
    c.drawRRect(cab, Paint()..color = Pal.accent);
    c.drawRRect(cab, stroke);
    final dark = Paint()..color = _ink;
    c.drawCircle(const Offset(10, 32), 6, dark);
    c.drawCircle(const Offset(32, 32), 6, dark);
    c.drawRRect(
        RRect.fromRectAndRadius(
            const Rect.fromLTWH(2, 2, 7, 10), const Radius.circular(2)),
        dark);
    // Puffs.
    final puff = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = Pal.muted;
    c.drawCircle(const Offset(-2, -8), 4, puff);
    c.drawCircle(const Offset(-8, -18), 6, puff);
    c.restore();
  }

  @override
  bool shouldRepaint(_RouteMapPainter old) =>
      old.selected != selected ||
      old.frontier != frontier ||
      old.stars.toString() != stars.toString() ||
      old.unlocked.toString() != unlocked.toString();
}
