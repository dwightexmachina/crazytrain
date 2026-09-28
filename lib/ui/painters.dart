import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../model/game.dart';
import '../model/track.dart';
import 'iso.dart';
import 'palette.dart';

/// Screen height of one terrain step, in cell units.
const double kZStep = 0.42;

/// Screen transform: fits the whole board (plus slab + headroom for
/// buildings and peaks) into the given size. Plane coords are in cell units.
class IsoView {
  final double s; // px per cell unit
  final Offset o; // screen offset
  final Game game;
  const IsoView(this.s, this.o, this.game);

  factory IsoView.fit(Size size, Game game) {
    final cd = game.cols.toDouble(), rd = game.rows.toDouble();
    // Iso extents of the board rectangle.
    final w = Iso.kx * (cd + rd);
    final h = Iso.ky * (cd + rd);
    const headroom = 2.2; // building heights and peaks above, slab below
    final s = math.min(size.width * 0.95 / w, size.height * 0.9 / (h + headroom));
    final minX = Iso.kx * (0 - rd), maxX = Iso.kx * cd;
    final minY = 0.0, maxY = Iso.ky * (cd + rd);
    final o = Offset(
      size.width / 2 - (minX + maxX) / 2 * s,
      size.height / 2 - (minY + maxY) / 2 * s + 0.45 * s,
    );
    return IsoView(s, o, game);
  }

  /// The whole-board fit, then zoomed around the screen center and panned.
  factory IsoView.of(Size size, Game game, double zoom, Offset pan) {
    final base = IsoView.fit(size, game);
    final center = Offset(size.width, size.height) / 2;
    return IsoView(base.s * zoom, center + (base.o - center) * zoom + pan, game);
  }

  Offset pt(double x, double y, [double z = 0]) => o + Iso.p(x, y, z) * s;

  /// Ground screen point: plane position lifted by the terrain underneath.
  Offset gpt(double x, double y, [double dz = 0]) =>
      pt(x, y, game.heights.zAt(Offset(x, y)) * kZStep + dz);

  static bool _inTri(Offset p, Offset a, Offset b, Offset c) {
    double cross(Offset u, Offset v, Offset w) =>
        (v.dx - u.dx) * (w.dy - u.dy) - (v.dy - u.dy) * (w.dx - u.dx);
    final d1 = cross(p, a, b), d2 = cross(p, b, c), d3 = cross(p, c, a);
    final neg = d1 < 0 || d2 < 0 || d3 < 0;
    final pos = d1 > 0 || d2 > 0 || d3 > 0;
    return !(neg && pos);
  }

  /// Screen position -> cell on elevated terrain, or null when outside the
  /// board. Front-to-back search: the tile nearest the camera wins, so a
  /// hill's face claims taps over the cells it hides.
  Cell? cellAt(Offset screen) {
    final hf = game.heights;
    for (var sum = game.cols + game.rows - 2; sum >= 0; sum--) {
      final xMin = math.max(0, sum - game.rows + 1);
      final xMax = math.min(game.cols - 1, sum);
      for (var x = xMin; x <= xMax; x++) {
        final y = sum - x;
        final c = Cell(x, y);
        final (a, b, d, e) = hf.corners(c);
        final q0 = pt(x.toDouble(), y.toDouble(), a * kZStep);
        final q1 = pt(x + 1.0, y.toDouble(), b * kZStep);
        final q2 = pt(x + 1.0, y + 1.0, d * kZStep);
        final q3 = pt(x.toDouble(), y + 1.0, e * kZStep);
        if (_inTri(screen, q0, q1, q3) || _inTri(screen, q1, q2, q3)) {
          return c;
        }
      }
    }
    return null;
  }

  /// Approximate in-cell fraction (0..1, 0..1) of a screen point, using the
  /// cell's average height as the reference plane. Good enough to pick the
  /// nearest corner vertex for terraforming.
  Offset fracIn(Cell c, Offset screen) {
    final z = game.heights.centerZ(c) * kZStep;
    final p = Iso.unp((screen - o) / s + Offset(0, z));
    return Offset(
      (p.dx - c.x).clamp(0.0, 1.0),
      (p.dy - c.y).clamp(0.0, 1.0),
    );
  }
}

// ---------------------------------------------------------------- helpers

void _face(Canvas c, Color color, List<Offset> pts) {
  final p = Path()..addPolygon(pts, true);
  c.drawPath(p, Paint()..color = color);
}

/// Iso box with footprint centered at plane (cx, cy), footprint w×d cell
/// units, height h cell units, sitting at base height z0 (cell units).
void drawBox(Canvas c, IsoView v, double cx, double cy, double w, double d,
    double h, (Color, Color, Color) col, [double z0 = 0]) {
  final x0 = cx - w / 2, x1 = cx + w / 2, y0 = cy - d / 2, y1 = cy + d / 2;
  final zt = z0 + h;
  _face(c, col.$1, [v.pt(x0, y0, zt), v.pt(x1, y0, zt), v.pt(x1, y1, zt), v.pt(x0, y1, zt)]);
  _face(c, col.$2, [v.pt(x0, y1, zt), v.pt(x1, y1, zt), v.pt(x1, y1, z0), v.pt(x0, y1, z0)]);
  _face(c, col.$3, [v.pt(x1, y0, zt), v.pt(x1, y1, zt), v.pt(x1, y1, z0), v.pt(x1, y0, z0)]);
}

void drawShadow(Canvas c, IsoView v, double cx, double cy, double r,
    [double z = 0]) {
  final center = v.pt(cx + 0.08, cy + 0.08, z);
  c.drawOval(
    Rect.fromCenter(center: center, width: 2 * Iso.kx * r * v.s, height: 2 * Iso.ky * r * v.s),
    Paint()..color = Pal.shadow,
  );
}

/// Center polyline connecting two edges of a cell, in plane coords.
List<Offset> connPolyline(Cell cell, Dir a, Dir b) {
  final step = PathStep(cell, a, b);
  final n = a.opposite == b ? 2 : 9;
  return [
    for (var i = 0; i < n; i++)
      Offset(cell.x.toDouble(), cell.y.toDouble()) +
          step.posInCell(i / (n - 1) * 0.9999, 1.0),
  ];
}

/// Center polyline of a track piece within its cell, in plane coords.
List<Offset> trackPolyline(Cell cell, TrackKind kind) {
  final dirs = kind.conn.toList();
  return connPolyline(cell, dirs[0], dirs[1]);
}

void _strokePolyline(Canvas c, IsoView v, List<Offset> plane, double width,
    Color color, double z) {
  final path = Path();
  for (var i = 0; i < plane.length; i++) {
    final p = v.pt(plane[i].dx, plane[i].dy, z);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  c.drawPath(
    path,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..color = color,
  );
}

/// Offset a plane polyline sideways by [d] cell units (for rails).
List<Offset> _offsetPolyline(List<Offset> pts, double d) {
  final out = <Offset>[];
  for (var i = 0; i < pts.length; i++) {
    final a = pts[math.max(0, i - 1)], b = pts[math.min(pts.length - 1, i + 1)];
    final t = b - a;
    final len = t.distance;
    final n = len == 0 ? Offset.zero : Offset(-t.dy, t.dx) / len;
    out.add(pts[i] + n * d);
  }
  return out;
}

void drawTrackCell(Canvas c, IsoView v, Cell cell, TrackKind kind,
    {double opacity = 1, bool bridge = false, double z = 0}) {
  drawTrackLine(c, v, trackPolyline(cell, kind),
      opacity: opacity, bridge: bridge, z: z);
}

void drawTrackLine(Canvas c, IsoView v, List<Offset> line,
    {double opacity = 1, bool bridge = false, double z = 0}) {
  Color fade(Color col) => col.withValues(alpha: col.a * opacity);
  if (bridge) {
    // Plank deck spanning the water, wider than the ballast bed.
    _strokePolyline(c, v, line, 0.52 * v.s, fade(Pal.plank), z);
  }
  _strokePolyline(c, v, line, 0.34 * v.s, fade(Pal.bed), z);
  // Ties.
  var dist = 0.12;
  var acc = 0.0;
  for (var i = 1; i < line.length; i++) {
    final seg = line[i] - line[i - 1];
    final segLen = seg.distance;
    while (dist <= acc + segLen) {
      final t = (dist - acc) / segLen;
      final p = line[i - 1] + seg * t;
      final dir = seg / segLen;
      final n = Offset(-dir.dy, dir.dx);
      _strokePolyline(c, v, [p - n * 0.20, p + n * 0.20], 0.055 * v.s, fade(Pal.tie), z);
      dist += 0.24;
    }
    acc += segLen;
  }
  // Rails.
  for (final side in const [-0.115, 0.115]) {
    _strokePolyline(c, v, _offsetPolyline(line, side), 0.045 * v.s, fade(Pal.rail), z);
  }
}

void drawSwitch(Canvas c, IsoView v, TrackSwitch sw,
    {bool bridge = false, double z = 0}) {
  // Inactive route ghosted underneath, thrown route at full strength.
  drawTrackLine(c, v, connPolyline(sw.cell, sw.base, sw.inactive),
      opacity: 0.3, bridge: bridge, z: z);
  drawTrackLine(c, v, connPolyline(sw.cell, sw.base, sw.active),
      opacity: 1, bridge: bridge, z: z);
  // Point lever in the cell corner: the tap target's visual anchor.
  drawBox(c, v, sw.cell.x + 0.82, sw.cell.y + 0.18, 0.12, 0.12, 0.16,
      Pal.lever, z);
}

void drawLaunchpad(Canvas c, IsoView v, Cell cell,
    {double opacity = 1, double z = 0}) {
  final cx = cell.x + 0.5, cy = cell.y + 0.5;
  Color fade(Color col) => col.withValues(alpha: col.a * opacity);
  drawBox(c, v, cx, cy, 0.84, 0.84, 0.07,
      (fade(Pal.pad.$1), fade(Pal.pad.$2), fade(Pal.pad.$3)), z);
  // Concentric landing rings on the pad's top face.
  for (final r in const [0.3, 0.16]) {
    c.drawOval(
      Rect.fromCenter(
          center: v.pt(cx, cy, z + 0.07),
          width: 2 * Iso.kx * r * v.s,
          height: 2 * Iso.ky * r * v.s),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.035 * v.s
        ..color = fade(Pal.padRing),
    );
  }
}

void drawBuilding(Canvas c, IsoView v, Building b, double z) {
  final cx = b.cell.x + 0.5, cy = b.cell.y + 0.5;
  switch (b.type) {
    case BuildingType.station:
      drawShadow(c, v, cx, cy, 0.52, z);
      drawBox(c, v, cx, cy, 0.86, 0.86, 0.34, Pal.station, z);
      drawBox(c, v, cx, cy, 0.98, 0.98, 0.14, Pal.stationRoof, z + 0.34);
    case BuildingType.stop:
      drawShadow(c, v, cx, cy, 0.44, z);
      drawBox(c, v, cx, cy, 0.72, 0.72, 0.26, Pal.stop, z);
      drawBox(c, v, cx, cy, 0.84, 0.84, 0.10, Pal.stopRoof, z + 0.26);
    case BuildingType.depot:
      drawShadow(c, v, cx, cy, 0.5, z);
      drawBox(c, v, cx, cy, 0.9, 0.78, 0.4, Pal.depot, z);
      drawBox(c, v, cx, cy, 1.0, 0.88, 0.12, Pal.depotRoof, z + 0.4);
  }
}

void drawCow(Canvas c, IsoView v, double cx, double cy, double z) {
  drawShadow(c, v, cx, cy, 0.22, z);
  drawBox(c, v, cx, cy, 0.34, 0.2, 0.16, Pal.cowBody, z + 0.05);
  drawBox(c, v, cx + 0.19, cy, 0.12, 0.14, 0.13, Pal.cowHead, z + 0.12);
}

void drawTree(Canvas c, IsoView v, double cx, double cy, double scale, double z) {
  drawShadow(c, v, cx, cy, 0.3 * scale, z);
  drawBox(c, v, cx, cy, 0.12 * scale, 0.12 * scale, 0.22 * scale, Pal.trunk, z);
  drawBox(c, v, cx, cy, 0.42 * scale, 0.42 * scale, 0.42 * scale, Pal.leaf,
      z + 0.2 * scale);
}

// ---------------------------------------------------------------- terrain

const _sand = (237, 231, 218), _rock = (199, 190, 172), _snow = (253, 252, 248);

(int, int, int) _lerpRgb((int, int, int) a, (int, int, int) b, double t) => (
      (a.$1 + (b.$1 - a.$1) * t).round(),
      (a.$2 + (b.$2 - a.$2) * t).round(),
      (a.$3 + (b.$3 - a.$3) * t).round(),
    );

const _wetSand = (214, 204, 182);

(int, int, int) _groundColor(double h) {
  if (h >= 5.5) return _snow;
  if (h >= 4.2) return _lerpRgb(_rock, _snow, math.min(1, (h - 4.2) / 1.3));
  if (h >= 2.4) return _lerpRgb(_sand, _rock, (h - 2.4) / 1.8);
  if (h < HeightField.waterLevel) return _wetSand; // submerged bed
  return _sand;
}

/// Lambert-ish shade for one terrain triangle (plane coords + height steps),
/// lit warmly from the northwest.
Color _shadeTri((int, int, int) base, List<(double, double, double)> tri) {
  final a = tri[0], b = tri[1], c = tri[2];
  final u = (b.$1 - a.$1, b.$2 - a.$2, (b.$3 - a.$3) * kZStep);
  final v = (c.$1 - a.$1, c.$2 - a.$2, (c.$3 - a.$3) * kZStep);
  var nx = u.$2 * v.$3 - u.$3 * v.$2;
  var ny = u.$3 * v.$1 - u.$1 * v.$3;
  var nz = u.$1 * v.$2 - u.$2 * v.$1;
  if (nz < 0) {
    nx = -nx;
    ny = -ny;
    nz = -nz;
  }
  final len = math.sqrt(nx * nx + ny * ny + nz * nz);
  const lx = -0.42, ly = -0.5, lz = 0.76;
  final dot = len == 0 ? 1.0 : (nx * lx + ny * ly + nz * lz) / len;
  // Normalized so perfectly flat ground renders the base color exactly.
  final f = (0.78 + 0.42 * math.max(0, dot)) / (0.78 + 0.42 * lz);
  int ch(int k) => math.min(255, (k * f).round());
  return Color.fromARGB(255, ch(base.$1), ch(base.$2), ch(base.$3));
}

// ---------------------------------------------------------------- static

const _treeSpots = [
  (1.5, 1.5, 1.0),
  (14.5, 2.5, 0.85),
  (1.5, 9.8, 0.9),
  (14.4, 10.4, 1.05),
  (5.5, 0.6, 0.7),
  (10.5, 10.6, 0.8),
];

class StaticBoardPainter extends CustomPainter {
  final Game game;
  final int rev;
  final double zoom;
  final Offset pan;
  StaticBoardPainter(this.game, this.zoom, this.pan) : rev = game.structureRev;

  @override
  void paint(Canvas c, Size size) {
    final v = IsoView.of(size, game, zoom, pan);
    final hf = game.heights;

    // Buildings and decorative trees by cell, for the interleaved pass.
    final buildingAt = <Cell, Building>{};
    for (final b in game.buildings) {
      buildingAt[b.cell] = b;
    }
    final treeAt = <Cell, (double, double, double)>{};
    for (final t in _treeSpots) {
      final cell = Cell(t.$1.floor(), t.$2.floor());
      if (game.board.containsKey(cell) ||
          game.isWater(cell) ||
          game.switches.containsKey(cell) ||
          game.launchpads.containsKey(cell) ||
          buildingAt.containsKey(cell)) {
        continue;
      }
      treeAt[cell] = t;
    }

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Pal.grid;

    // One back-to-front pass: ground, then whatever sits on the cell.
    for (var sum = 0; sum <= game.cols + game.rows - 2; sum++) {
      final xMin = math.max(0, sum - game.rows + 1);
      final xMax = math.min(game.cols - 1, sum);
      for (var x = xMin; x <= xMax; x++) {
        final y = sum - x;
        final cell = Cell(x, y);
        final (ha, hb, hd, he) = hf.corners(cell);
        final xd = x.toDouble(), yd = y.toDouble();
        final tri1 = [(xd, yd, ha.toDouble()), (xd + 1, yd, hb.toDouble()), (xd, yd + 1, he.toDouble())];
        final tri2 = [(xd + 1, yd, hb.toDouble()), (xd + 1, yd + 1, hd.toDouble()), (xd, yd + 1, he.toDouble())];
        for (final tri in [tri1, tri2]) {
          final th = (tri[0].$3 + tri[1].$3 + tri[2].$3) / 3;
          _face(c, _shadeTri(_groundColor(th), tri),
              [for (final p in tri) v.pt(p.$1, p.$2, p.$3 * kZStep)]);
        }

        final q0 = v.pt(xd, yd, ha * kZStep);
        final q1 = v.pt(xd + 1, yd, hb * kZStep);
        final q2 = v.pt(xd + 1, yd + 1, hd * kZStep);
        final q3 = v.pt(xd, yd + 1, he * kZStep);

        // Water table: a surface polygon clipped to the shoreline, computed
        // where the terrain crosses the water level along each tile edge.
        const wl = HeightField.waterLevel;
        if (hf.minCorner(cell) < wl) {
          final wz = wl * kZStep;
          final ring = [
            (xd, yd, ha), (xd + 1, yd, hb), (xd + 1, yd + 1, hd), (xd, yd + 1, he),
          ];
          final wPts = <Offset>[];
          for (var i = 0; i < 4; i++) {
            final p0 = ring[i], p1 = ring[(i + 1) % 4];
            if (p0.$3 < wl) wPts.add(v.pt(p0.$1, p0.$2, wz));
            if ((p0.$3 < wl) != (p1.$3 < wl)) {
              final t = (wl - p0.$3) / (p1.$3 - p0.$3);
              wPts.add(v.pt(p0.$1 + (p1.$1 - p0.$1) * t,
                  p0.$2 + (p1.$2 - p0.$2) * t, wz));
            }
          }
          if (wPts.length >= 3) {
            _face(c, Pal.water.withValues(alpha: 0.9), wPts);
          }
          if (hf.centerZ(cell) < wl) {
            c.drawOval(
              Rect.fromCenter(
                  center: v.pt(x + 0.38, y + 0.42, wz),
                  width: 0.34 * v.s,
                  height: 0.12 * v.s),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.2
                ..color = Pal.waterEdge,
            );
          }
        }

        // Grid on the surface.
        c.drawPath(Path()..addPolygon([q0, q1, q2, q3], true), gridPaint);

        // Structures riding this cell. Rail over water sits on its deck.
        final flatZ = ha * kZStep;
        final railZ = (game.deck[cell] ?? ha) * kZStep;
        final piece = game.board[cell];
        if (piece != null) {
          drawTrackCell(c, v, cell, piece,
              bridge: game.isWater(cell), z: railZ);
        }
        final sw = game.switches[cell];
        if (sw != null) drawSwitch(c, v, sw, bridge: game.isWater(cell), z: railZ);
        if (game.launchpads.containsKey(cell)) {
          drawLaunchpad(c, v, cell, z: flatZ);
        }
        final b = buildingAt[cell];
        if (b != null) drawBuilding(c, v, b, flatZ);
        final t = treeAt[cell];
        if (t != null) {
          drawTree(c, v, t.$1, t.$2, t.$3, hf.centerZ(cell) * kZStep);
        }
      }
    }

    // Slab skirts along the south and east edges, following the terrain lip.
    const slabZ = -0.6;
    final south = <Offset>[
      for (var x = 0; x <= game.cols; x++)
        v.pt(x.toDouble(), game.rows.toDouble(), hf.vAt(x, game.rows) * kZStep),
    ];
    _face(c, const Color(0xFFDCD3C0), [
      ...south,
      v.pt(game.cols.toDouble(), game.rows.toDouble(), slabZ),
      v.pt(0, game.rows.toDouble(), slabZ),
    ]);
    final east = <Offset>[
      for (var y = game.rows; y >= 0; y--)
        v.pt(game.cols.toDouble(), y.toDouble(), hf.vAt(game.cols, y) * kZStep),
    ];
    _face(c, const Color(0xFFE5DCCA), [
      ...east,
      v.pt(game.cols.toDouble(), 0, slabZ),
      v.pt(game.cols.toDouble(), game.rows.toDouble(), slabZ),
    ]);
  }

  @override
  bool shouldRepaint(StaticBoardPainter old) =>
      old.rev != game.structureRev || old.zoom != zoom || old.pan != pan;
}

// ---------------------------------------------------------------- dynamic

class DynamicPainter extends CustomPainter {
  final Game game;
  final ValueNotifier<TrackPlan?> plan;
  final ValueNotifier<Cell?> hover;
  final ValueNotifier<double> zoom;
  final ValueNotifier<Offset> pan;
  DynamicPainter(this.game, this.plan, this.hover, this.zoom, this.pan)
      : super(repaint: Listenable.merge([game, plan, hover, zoom, pan]));

  @override
  void paint(Canvas c, Size size) {
    final v = IsoView.of(size, game, zoom.value, pan.value);
    final hf = game.heights;

    // Hover cell highlight (build tools only), draped over the terrain.
    final h = hover.value;
    if (h != null && game.tool != Tool.none) {
      final color = game.tool == Tool.bulldoze ? Pal.ghostBad : Pal.hover;
      final (a, b, d, e) = hf.corners(h);
      _face(c, color, [
        v.pt(h.x.toDouble(), h.y.toDouble(), a * kZStep),
        v.pt(h.x + 1.0, h.y.toDouble(), b * kZStep),
        v.pt(h.x + 1.0, h.y + 1.0, d * kZStep),
        v.pt(h.x.toDouble(), h.y + 1.0, e * kZStep),
      ]);
    }

    // Drag ghost. Bridge pieces preview at their deck grade.
    final pl = plan.value;
    if (pl != null) {
      for (final p in pl.pieces) {
        final z = p.deckLevel != null
            ? p.deckLevel!.toDouble()
            : (game.deck[p.cell]?.toDouble() ?? hf.centerZ(p.cell));
        drawTrackCell(c, v, p.cell, p.kind,
            opacity: 0.55, bridge: p.bridge, z: z * kZStep);
      }
    }

    // Armed first pad of a launchpad pair.
    final pending = game.pendingPad;
    if (pending != null) {
      drawLaunchpad(c, v, pending,
          opacity: 0.55, z: hf.centerZ(pending) * kZStep);
    }

    // Armed track piece awaiting its switch base-side tap.
    final ps = game.pendingSwitch;
    if (ps != null) {
      final (a, b, d, e) = hf.corners(ps);
      _face(c, Pal.ghostOk, [
        v.pt(ps.x.toDouble(), ps.y.toDouble(), a * kZStep),
        v.pt(ps.x + 1.0, ps.y.toDouble(), b * kZStep),
        v.pt(ps.x + 1.0, ps.y + 1.0, d * kZStep),
        v.pt(ps.x.toDouble(), ps.y + 1.0, e * kZStep),
      ]);
    }

    _drawTrain(c, v);
    _drawToasts(c, v, size);
  }

  void _drawTrain(Canvas c, IsoView v) {
    final hf = game.heights;
    final items = <(double, void Function())>[];
    for (final cow in game.cows) {
      final px = cow.cell.x + 0.5, py = cow.cell.y + 0.5;
      final z = hf.centerZ(cow.cell) * kZStep;
      items.add((px + py, () => drawCow(c, v, px, py, z)));
    }
    final path = game.renderPath;
    if (path == null) {
      items.sort((a, b) => a.$1.compareTo(b.$1));
      for (final it in items) {
        it.$2();
      }
      return;
    }
    final len = path.length.toDouble();
    final vehicles = <(double, bool)>[]; // (s, isEngine)
    vehicles.add((game.s, true));
    for (var i = 0; i < game.cars; i++) {
      var cs = game.s - 0.85 * (i + 1);
      while (cs < 0) {
        cs += len;
      }
      vehicles.add((cs, false));
    }
    // Compute plane position + heading for each, then depth sort.
    for (final (sPos, isEngine) in vehicles) {
      final idx = sPos.floor() % path.length;
      final t = sPos - sPos.floorToDouble();
      final st = path[idx];
      final local = st.posInCell(t, 1.0);
      final px = st.cell.x + local.dx, py = st.cell.y + local.dy;
      final heading = st.headingAt(t, 1.0);
      // Ground level under this vehicle; airborne steps lerp pad-to-pad
      // and add the launch arc on top.
      double railGround(Cell cell) =>
          game.deck[cell]?.toDouble() ?? hf.centerZ(cell);
      double groundZ;
      final fly = st.flyTo;
      if (fly != null) {
        final za = railGround(st.cell), zb = railGround(fly);
        groundZ = (za + (zb - za) * t) * kZStep;
      } else {
        groundZ = railGround(st.cell) * kZStep;
      }
      final z = groundZ + st.flightZ(t);
      final horiz = math.cos(heading).abs() > math.sin(heading).abs();
      final w = horiz ? 0.68 : 0.34, d = horiz ? 0.34 : 0.68;
      items.add((px + py, () {
        drawShadow(c, v, px, py, st.flyTo != null ? 0.2 : 0.3, groundZ);
        if (isEngine) {
          drawBox(c, v, px, py, w, d, 0.3, Pal.engine, 0.04 + z);
          // Cab at the rear, stack at the front (visual only).
          final back = Offset.fromDirection(heading, -0.16);
          final front = Offset.fromDirection(heading, 0.2);
          drawBox(c, v, px + back.dx, py + back.dy, horiz ? 0.3 : 0.3,
              horiz ? 0.3 : 0.3, 0.2, Pal.cab, 0.34 + z);
          drawBox(c, v, px + front.dx, py + front.dy, 0.1, 0.1, 0.16,
              Pal.stack, 0.34 + z);
        } else {
          drawBox(c, v, px, py, w * 0.94, d * 0.94, 0.26, Pal.car, 0.04 + z);
        }
      }));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
  }

  void _drawToasts(Canvas c, IsoView v, Size size) {
    for (final t in game.toasts) {
      final k = (t.age / 1.8).clamp(0.0, 1.0);
      final rise = 18 + 26 * k;
      final alpha = k < 0.7 ? 1.0 : (1 - (k - 0.7) / 0.3);
      final pos = v.gpt(t.px, t.py, 0.5) - Offset(0, rise);
      final tp = TextPainter(
        text: TextSpan(
          text: t.text,
          style: TextStyle(
            fontSize: t.big ? 17 : 13,
            fontWeight: FontWeight.w800,
            color: Pal.good.withValues(alpha: alpha),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Soft chip behind the text.
      final r = RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: pos, width: tp.width + 14, height: tp.height + 6),
        const Radius.circular(9),
      );
      c.drawRRect(r, Paint()..color = Colors.white.withValues(alpha: 0.85 * alpha));
      tp.paint(c, pos - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(DynamicPainter old) => true;
}
