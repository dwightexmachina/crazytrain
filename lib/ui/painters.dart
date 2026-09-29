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
  final int rot; // camera rotation in 90° steps, 0..3
  const IsoView(this.s, this.o, this.game, this.rot);

  factory IsoView.fit(Size size, Game game, {int rot = 0}) {
    // View-space extents swap on odd rotations.
    final cd = (rot.isOdd ? game.rows : game.cols).toDouble();
    final rd = (rot.isOdd ? game.cols : game.rows).toDouble();
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
    return IsoView(s, o, game, rot);
  }

  /// The whole-board fit, then zoomed around the screen center and panned.
  factory IsoView.of(Size size, Game game, double zoom, Offset pan,
      {int rot = 0}) {
    final base = IsoView.fit(size, game, rot: rot);
    final center = Offset(size.width, size.height) / 2;
    return IsoView(
        base.s * zoom, center + (base.o - center) * zoom + pan, game, rot);
  }

  /// World plane -> view plane: the board turned in 90° steps.
  Offset viewXY(double x, double y) => switch (rot & 3) {
        1 => Offset(game.rows - y, x),
        2 => Offset(game.cols - x, game.rows - y),
        3 => Offset(y, game.cols - x),
        _ => Offset(x, y),
      };

  Offset _worldXY(Offset v) => switch (rot & 3) {
        1 => Offset(v.dy, game.rows - v.dx),
        2 => Offset(game.cols - v.dx, game.rows - v.dy),
        3 => Offset(game.cols - v.dy, v.dx),
        _ => v,
      };

  /// Painter's depth: larger is nearer the camera in the current rotation.
  double depthKey(double x, double y) {
    final w = viewXY(x, y);
    return w.dx + w.dy;
  }

  Offset pt(double x, double y, [double z = 0]) {
    final w = viewXY(x, y);
    return o + Iso.p(w.dx, w.dy, z) * s;
  }

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
  /// board. Of every cell whose quad contains the point, the one nearest the
  /// camera wins, so a hill's face claims taps over the cells it hides.
  Cell? cellAt(Offset screen) {
    final hf = game.heights;
    Cell? best;
    var bestKey = double.negativeInfinity;
    for (var x = 0; x < game.cols; x++) {
      for (var y = 0; y < game.rows; y++) {
        final c = Cell(x, y);
        final key = depthKey(x + 0.5, y + 0.5);
        if (key <= bestKey) continue;
        final (a, b, d, e) = hf.corners(c);
        final q0 = pt(x.toDouble(), y.toDouble(), a * kZStep);
        final q1 = pt(x + 1.0, y.toDouble(), b * kZStep);
        final q2 = pt(x + 1.0, y + 1.0, d * kZStep);
        final q3 = pt(x.toDouble(), y + 1.0, e * kZStep);
        if (_inTri(screen, q0, q1, q3) || _inTri(screen, q1, q2, q3)) {
          best = c;
          bestKey = key;
        }
      }
    }
    return best;
  }

  /// Approximate in-cell fraction (0..1, 0..1) of a screen point, using the
  /// cell's average height as the reference plane. Good enough to pick the
  /// nearest corner vertex for terraforming.
  Offset fracIn(Cell c, Offset screen) {
    final z = game.heights.centerZ(c) * kZStep;
    final p = _worldXY(Iso.unp((screen - o) / s + Offset(0, z)));
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
/// The two side faces toward the camera depend on the view rotation.
void drawBox(Canvas c, IsoView v, double cx, double cy, double w, double d,
    double h, (Color, Color, Color) col, [double z0 = 0]) {
  final x0 = cx - w / 2, x1 = cx + w / 2, y0 = cy - d / 2, y1 = cy + d / 2;
  final zt = z0 + h;
  _face(c, col.$1, [v.pt(x0, y0, zt), v.pt(x1, y0, zt), v.pt(x1, y1, zt), v.pt(x0, y1, zt)]);
  List<Offset> wall(String f) => switch (f) {
        'y0' => [v.pt(x0, y0, zt), v.pt(x1, y0, zt), v.pt(x1, y0, z0), v.pt(x0, y0, z0)],
        'y1' => [v.pt(x0, y1, zt), v.pt(x1, y1, zt), v.pt(x1, y1, z0), v.pt(x0, y1, z0)],
        'x0' => [v.pt(x0, y0, zt), v.pt(x0, y1, zt), v.pt(x0, y1, z0), v.pt(x0, y0, z0)],
        _ => [v.pt(x1, y0, zt), v.pt(x1, y1, zt), v.pt(x1, y1, z0), v.pt(x1, y0, z0)],
      };
  // (view-southwest face, view-southeast face) per rotation step.
  final (sw, se) = switch (v.rot & 3) {
    1 => ('x1', 'y0'),
    2 => ('y0', 'x0'),
    3 => ('x0', 'y1'),
    _ => ('y1', 'x1'),
  };
  _face(c, col.$2, wall(sw));
  _face(c, col.$3, wall(se));
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

/// Cumulative arc-length fraction (0..1) of each polyline point.
List<double> _arcFractions(List<Offset> pts) {
  final acc = List<double>.filled(pts.length, 0);
  var total = 0.0;
  for (var i = 1; i < pts.length; i++) {
    total += (pts[i] - pts[i - 1]).distance;
    acc[i] = total;
  }
  if (total == 0) return acc;
  return [for (final a in acc) a / total];
}

void _strokePolyline(Canvas c, IsoView v, List<Offset> plane, double width,
    Color color, double z0, [double? z1]) {
  final zEnd = z1 ?? z0;
  final fr = z0 == zEnd ? null : _arcFractions(plane);
  final path = Path();
  for (var i = 0; i < plane.length; i++) {
    final z = fr == null ? z0 : z0 + (zEnd - z0) * fr[i];
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

/// The polyline starts at the first conn-dir edge; [z] is the rail height
/// there and [zEnd] (default: same) at the far edge, so straights can climb.
void drawTrackCell(Canvas c, IsoView v, Cell cell, TrackKind kind,
    {double opacity = 1, bool bridge = false, double z = 0, double? zEnd}) {
  drawTrackLine(c, v, trackPolyline(cell, kind),
      opacity: opacity, bridge: bridge, z: z, zEnd: zEnd);
}

void drawTrackLine(Canvas c, IsoView v, List<Offset> line,
    {double opacity = 1, bool bridge = false, double z = 0, double? zEnd}) {
  final z1 = zEnd ?? z;
  Color fade(Color col) => col.withValues(alpha: col.a * opacity);
  if (bridge) {
    // Plank deck spanning the water, wider than the ballast bed.
    _strokePolyline(c, v, line, 0.52 * v.s, fade(Pal.plank), z, z1);
  }
  _strokePolyline(c, v, line, 0.34 * v.s, fade(Pal.bed), z, z1);
  // Ties.
  final fr = _arcFractions(line);
  var total = 0.0;
  for (var i = 1; i < line.length; i++) {
    total += (line[i] - line[i - 1]).distance;
  }
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
      final tieZ = total == 0
          ? z
          : z + (z1 - z) * ((fr[i - 1] + (fr[i] - fr[i - 1]) * t));
      _strokePolyline(
          c, v, [p - n * 0.20, p + n * 0.20], 0.055 * v.s, fade(Pal.tie), tieZ);
      dist += 0.24;
    }
    acc += segLen;
  }
  // Rails.
  for (final side in const [-0.115, 0.115]) {
    _strokePolyline(
        c, v, _offsetPolyline(line, side), 0.045 * v.s, fade(Pal.rail), z, z1);
  }
}

/// Trestle posts from a bridge deck down to the terrain (or riverbed).
void drawTrestles(Canvas c, IsoView v, Cell cell, TrackKind kind, double deckZ) {
  final line = trackPolyline(cell, kind);
  final hf = v.game.heights;
  for (final t in const [0.3, 0.7]) {
    final i = ((line.length - 1) * t).round();
    final p = line[i];
    final groundZ =
        math.min(hf.zAt(p), HeightField.waterLevel - 0.35) * kZStep;
    if (deckZ - groundZ < 0.12) continue;
    final seg = line[math.min(i + 1, line.length - 1)] -
        line[math.max(0, i - 1)];
    final len = seg.distance;
    final n = len == 0 ? Offset.zero : Offset(-seg.dy, seg.dx) / len;
    for (final side in const [-0.15, 0.15]) {
      final q = p + n * side;
      final a = v.pt(q.dx, q.dy, deckZ);
      final b = v.pt(q.dx, q.dy, groundZ);
      c.drawLine(
          a,
          b,
          Paint()
            ..color = Pal.trestle
            ..strokeWidth = 0.06 * v.s
            ..strokeCap = StrokeCap.round);
    }
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

/// A tunnel portal: a track stub running into a framed dark mouth on the
/// side of the cell that faces its partner.
void drawPortal(Canvas c, IsoView v, Cell cell, Cell partner, double z) {
  final axis = axisDir(cell, partner);
  if (axis == null) return;
  drawTrackLine(c, v, connPolyline(cell, axis, axis.opposite), z: z);
  final along = axis == Dir.e || axis == Dir.w;
  final cx = cell.x +
      switch (axis) { Dir.e => 0.93, Dir.w => 0.07, _ => 0.5 };
  final cy = cell.y +
      switch (axis) { Dir.s => 0.93, Dir.n => 0.07, _ => 0.5 };
  // Stone frame, then the dark bore mouth inset toward the partner.
  drawBox(c, v, cx, cy, along ? 0.14 : 0.7, along ? 0.7 : 0.14, 0.52,
      Pal.rock, z);
  drawBox(c, v, cx, cy, along ? 0.1 : 0.46, along ? 0.46 : 0.1, 0.42,
      Pal.stack, z);
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

/// Trees that actually render: those not hidden under water or structures.
Map<Cell, (double, double, double)> _visibleTrees(Game game) {
  final buildingCells = {for (final b in game.buildings) b.cell};
  final out = <Cell, (double, double, double)>{};
  for (final t in game.trees) {
    final cell = Cell(t.$1.floor(), t.$2.floor());
    if (game.board.containsKey(cell) ||
        game.isWater(cell) ||
        game.switches.containsKey(cell) ||
        game.launchpads.containsKey(cell) ||
        buildingCells.contains(cell)) {
      continue;
    }
    out[cell] = t;
  }
  return out;
}

class StaticBoardPainter extends CustomPainter {
  final Game game;
  final int rev;
  final double zoom;
  final Offset pan;
  final int rot;
  StaticBoardPainter(this.game, this.zoom, this.pan, this.rot)
      : rev = game.structureRev;

  @override
  void paint(Canvas c, Size size) {
    final v = IsoView.of(size, game, zoom, pan, rot: rot);
    final hf = game.heights;

    // Buildings and decorative trees by cell, for the interleaved pass.
    final buildingAt = <Cell, Building>{};
    for (final b in game.buildings) {
      buildingAt[b.cell] = b;
    }
    final treeAt = _visibleTrees(game);

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Pal.grid;

    // One back-to-front pass in VIEW order: ground, then whatever sits on
    // the cell. The order depends on the camera rotation.
    final cells = <Cell>[
      for (var x = 0; x < game.cols; x++)
        for (var y = 0; y < game.rows; y++) Cell(x, y),
    ]..sort((a, b) => v
        .depthKey(a.x + 0.5, a.y + 0.5)
        .compareTo(v.depthKey(b.x + 0.5, b.y + 0.5)));
    // Viewport culling: cells whose quad lies entirely off-canvas draw
    // nothing. The top margin leaves room for structures above the ground.
    final cullPad = v.s * 1.2;
    final cullRect = Rect.fromLTRB(
        -cullPad, -cullPad, size.width + cullPad, size.height + cullPad);
    for (final cell in cells) {
      {
        final x = cell.x, y = cell.y;
        final (ha, hb, hd, he) = hf.corners(cell);
        final xd = x.toDouble(), yd = y.toDouble();
        final c0 = v.pt(xd, yd, ha * kZStep);
        final c1 = v.pt(xd + 1, yd, hb * kZStep);
        final c2 = v.pt(xd + 1, yd + 1, hd * kZStep);
        final c3 = v.pt(xd, yd + 1, he * kZStep);
        final minX = math.min(math.min(c0.dx, c1.dx), math.min(c2.dx, c3.dx));
        final maxX = math.max(math.max(c0.dx, c1.dx), math.max(c2.dx, c3.dx));
        final minY = math.min(math.min(c0.dy, c1.dy), math.min(c2.dy, c3.dy));
        final maxY = math.max(math.max(c0.dy, c1.dy), math.max(c2.dy, c3.dy));
        if (maxX < cullRect.left ||
            minX > cullRect.right ||
            maxY < cullRect.top ||
            minY > cullRect.bottom) {
          continue;
        }
        final tri1 = [(xd, yd, ha.toDouble()), (xd + 1, yd, hb.toDouble()), (xd, yd + 1, he.toDouble())];
        final tri2 = [(xd + 1, yd, hb.toDouble()), (xd + 1, yd + 1, hd.toDouble()), (xd, yd + 1, he.toDouble())];
        for (final tri in [tri1, tri2]) {
          final th = (tri[0].$3 + tri[1].$3 + tri[2].$3) / 3;
          // Shade in VIEW space so slopes relight as the camera rotates.
          final viewTri = [
            for (final p in tri)
              (v.viewXY(p.$1, p.$2).dx, v.viewXY(p.$1, p.$2).dy, p.$3),
          ];
          _face(c, _shadeTri(_groundColor(th), viewTri),
              [for (final p in tri) v.pt(p.$1, p.$2, p.$3 * kZStep)]);
        }

        final q0 = c0, q1 = c1, q2 = c2, q3 = c3;

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

        // Structures riding this cell. Rail follows its edge grades; decks
        // span water on trestles.
        final flatZ = ha * kZStep;
        final railZ = (game.deck[cell] ?? ha) * kZStep;
        final piece = game.board[cell];
        if (piece != null) {
          final dirs = piece.conn.toList();
          final zA = game.railEdgeZ(cell, dirs[0]) * kZStep;
          final zB = game.railEdgeZ(cell, dirs[1]) * kZStep;
          if (game.isWater(cell)) drawTrestles(c, v, cell, piece, zA);
          drawTrackCell(c, v, cell, piece,
              bridge: game.isWater(cell), z: zA, zEnd: zB);
        }
        final sw = game.switches[cell];
        if (sw != null) drawSwitch(c, v, sw, bridge: game.isWater(cell), z: railZ);
        if (game.launchpads.containsKey(cell)) {
          drawLaunchpad(c, v, cell, z: flatZ);
        }
        final portalTo = game.tunnels[cell];
        if (portalTo != null) drawPortal(c, v, cell, portalTo, flatZ);
        final b = buildingAt[cell];
        if (b != null) drawBuilding(c, v, b, flatZ);
        final t = treeAt[cell];
        if (t != null) {
          drawTree(c, v, t.$1, t.$2, t.$3, hf.centerZ(cell) * kZStep);
        }
      }
    }

    // Slab skirts along the two camera-facing board edges: which world
    // edges those are depends on the rotation.
    const slabZ = -0.6;
    void skirt(String edge, Color color) {
      final pts = <Offset>[];
      Offset first, last;
      switch (edge) {
        case 'south':
          for (var x = 0; x <= game.cols; x++) {
            pts.add(v.pt(x.toDouble(), game.rows.toDouble(),
                hf.vAt(x, game.rows) * kZStep));
          }
          first = v.pt(game.cols.toDouble(), game.rows.toDouble(), slabZ);
          last = v.pt(0, game.rows.toDouble(), slabZ);
        case 'north':
          for (var x = 0; x <= game.cols; x++) {
            pts.add(v.pt(x.toDouble(), 0, hf.vAt(x, 0) * kZStep));
          }
          first = v.pt(game.cols.toDouble(), 0, slabZ);
          last = v.pt(0, 0, slabZ);
        case 'east':
          for (var y = 0; y <= game.rows; y++) {
            pts.add(v.pt(game.cols.toDouble(), y.toDouble(),
                hf.vAt(game.cols, y) * kZStep));
          }
          first = v.pt(game.cols.toDouble(), game.rows.toDouble(), slabZ);
          last = v.pt(game.cols.toDouble(), 0, slabZ);
        default: // west
          for (var y = 0; y <= game.rows; y++) {
            pts.add(v.pt(0, y.toDouble(), hf.vAt(0, y) * kZStep));
          }
          first = v.pt(0, game.rows.toDouble(), slabZ);
          last = v.pt(0, 0, slabZ);
      }
      _face(c, color, [...pts, first, last]);
    }

    final (swEdge, seEdge) = switch (rot & 3) {
      1 => ('east', 'north'),
      2 => ('north', 'west'),
      3 => ('west', 'south'),
      _ => ('south', 'east'),
    };
    skirt(swEdge, const Color(0xFFDCD3C0));
    skirt(seEdge, const Color(0xFFE5DCCA));
  }

  @override
  bool shouldRepaint(StaticBoardPainter old) =>
      old.rev != game.structureRev ||
      old.zoom != zoom ||
      old.pan != pan ||
      old.rot != rot;
}

// ---------------------------------------------------------------- dynamic

class DynamicPainter extends CustomPainter {
  final Game game;
  final ValueNotifier<TrackPlan?> plan;
  final ValueNotifier<Cell?> hover;
  final ValueNotifier<double> zoom;
  final ValueNotifier<Offset> pan;
  final ValueNotifier<int> rot;
  DynamicPainter(this.game, this.plan, this.hover, this.zoom, this.pan, this.rot)
      : super(repaint: Listenable.merge([game, plan, hover, zoom, pan, rot]));

  @override
  void paint(Canvas c, Size size) {
    final v = IsoView.of(size, game, zoom.value, pan.value, rot: rot.value);
    final hf = game.heights;

    List<Offset> cellQuad(Cell q) {
      final (a, b, d, e) = hf.corners(q);
      return [
        v.pt(q.x.toDouble(), q.y.toDouble(), a * kZStep),
        v.pt(q.x + 1.0, q.y.toDouble(), b * kZStep),
        v.pt(q.x + 1.0, q.y + 1.0, d * kZStep),
        v.pt(q.x.toDouble(), q.y + 1.0, e * kZStep),
      ];
    }

    // Hover cell highlight (build tools only), draped over the terrain.
    // Placement tools tint by validity: green would take, red would refuse.
    final h = hover.value;
    if (h != null && game.tool != Tool.none) {
      final scrapTarget =
          game.tool == Tool.bulldoze ? game.trainEngineAt(h) : null;
      final color = switch (game.tool) {
        Tool.bulldoze => Pal.ghostBad,
        Tool.stop || Tool.depot =>
          game.buildingSiteError(h) == null ? Pal.ghostOk : Pal.ghostBad,
        Tool.launchpad =>
          game.padSiteError(h) == null ? Pal.ghostOk : Pal.ghostBad,
        Tool.tunnel when game.pendingTunnel == null =>
          game.portalSiteError(h) == null ? Pal.ghostOk : Pal.ghostBad,
        Tool.speedPad => game.speedPads.contains(h) ||
                (game.board[h] != null && !game.board[h]!.isCurve)
            ? Pal.ghostOk
            : Pal.ghostBad,
        Tool.loopDeLoop =>
          game.loops.contains(h) || game.loopSiteError(h) == null
              ? Pal.ghostOk
              : Pal.ghostBad,
        Tool.jumpRamp when game.pendingRamp == null =>
          game.ramps.containsKey(h) || game.rampSiteError(h) == null
              ? Pal.ghostOk
              : Pal.ghostBad,
        Tool.jumpRamp => // aiming: neighbors of the armed ramp are valid
          ((h.x - game.pendingRamp!.x).abs() +
                      (h.y - game.pendingRamp!.y).abs()) ==
                  1
              ? Pal.ghostOk
              : Pal.ghostBad,
        _ => Pal.hover,
      };
      _face(c, color, cellQuad(h));
      // Bulldozing an engine scraps the TRAIN, not the track: lock a red
      // target ring onto it so the difference is unmistakable.
      if (scrapTarget != null && game.trains.length > 1) {
        final z = (game.deck[h]?.toDouble() ?? hf.centerZ(h)) * kZStep;
        final center = v.pt(h.x + 0.5, h.y + 0.5, z + 0.15);
        for (final r in const [0.46, 0.3]) {
          c.drawOval(
            Rect.fromCenter(
                center: center,
                width: 2 * Iso.kx * r * v.s,
                height: 2 * Iso.ky * r * v.s),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.6
              ..color = Pal.bad,
          );
        }
      }
    }

    // Drag ghost. Bridges preview at deck grade, straights at their slope.
    final pl = plan.value;
    if (pl != null) {
      for (final p in pl.pieces) {
        final double za, zb;
        if (p.deckLevel != null) {
          za = zb = p.deckLevel!.toDouble();
        } else {
          final dirs = p.kind.conn.toList();
          za = game.railEdgeZ(p.cell, dirs[0]);
          zb = game.railEdgeZ(p.cell, dirs[1]);
        }
        drawTrackCell(c, v, p.cell, p.kind,
            opacity: 0.55,
            bridge: p.bridge,
            z: za * kZStep,
            zEnd: zb * kZStep);
      }
    }

    // Armed first pad of a launchpad pair.
    final pending = game.pendingPad;
    if (pending != null) {
      drawLaunchpad(c, v, pending,
          opacity: 0.55, z: hf.centerZ(pending) * kZStep);
    }

    // Placing the second train: its route glows, hover shows the spot.
    if (game.placingTrain) {
      final route = game.spawnCells;
      final guide = Pal.ghostOk.withValues(alpha: 0.18);
      for (final rc in route) {
        _face(c, guide, cellQuad(rc));
      }
      final target = hover.value;
      if (target != null) {
        _face(c, route.contains(target) ? Pal.ghostOk : Pal.ghostBad,
            cellQuad(target));
      }
    }

    // Boring a tunnel: faint guides along the armed portal's row and
    // column, and a live bore preview to the hovered cell — green when the
    // link would take, red when it wouldn't.
    final portal = game.pendingTunnel;
    if (portal != null && game.tool == Tool.tunnel) {
      final guide = Pal.accent.withValues(alpha: 0.10);
      for (var x = 0; x < game.cols; x++) {
        if (x != portal.x) _face(c, guide, cellQuad(Cell(x, portal.y)));
      }
      for (var y = 0; y < game.rows; y++) {
        if (y != portal.y) _face(c, guide, cellQuad(Cell(portal.x, y)));
      }
      final target = hover.value;
      if (target != null && target != portal &&
          axisDir(portal, target) != null) {
        final ok = game.boreError(portal, target) == null;
        final tint = ok ? Pal.ghostOk : Pal.ghostBad;
        final dx = (target.x - portal.x).sign, dy = (target.y - portal.y).sign;
        var cur = portal;
        while (true) {
          _face(c, tint, cellQuad(cur));
          if (cur == target) break;
          cur = Cell(cur.x + dx, cur.y + dy);
        }
      }
    }

    // Armed track piece awaiting its switch base-side tap, or an armed
    // first tunnel portal.
    for (final ps in [game.pendingSwitch, game.pendingTunnel,
        game.pendingRamp]) {
      if (ps == null) continue;
      _face(c, Pal.ghostOk, cellQuad(ps));
    }

    // Switch side picker: with a piece armed, its free sides (valid base
    // taps) glow green; its connected legs tint red.
    final armed = game.pendingSwitch;
    if (armed != null) {
      final piece = game.board[armed];
      if (piece != null) {
        for (final d in Dir.values) {
          final n = armed.step(d);
          if (n.x < 0 || n.x >= game.cols || n.y < 0 || n.y >= game.rows) {
            continue;
          }
          _face(c, piece.conn.contains(d) ? Pal.ghostBad : Pal.ghostOk,
              cellQuad(n));
        }
      }
    }

    // Launchpad landing hint: track entering a pad heading d exits its
    // partner still heading d — highlight the far-side cell where rail
    // must continue, whenever that connection is missing.
    final effBoard = {
      ...game.board,
      for (final p in pl?.pieces ?? const <Planned>[]) p.cell: p.kind,
    };
    game.launchpads.forEach((padA, padB) {
      for (final d in Dir.values) {
        final feeder = effBoard[padA.step(d.opposite)];
        if (feeder == null || !feeder.conn.contains(d)) continue;
        final exitCell = padB.step(d);
        if (exitCell.x < 0 ||
            exitCell.x >= game.cols ||
            exitCell.y < 0 ||
            exitCell.y >= game.rows) {
          continue;
        }
        final landing = effBoard[exitCell];
        if (landing != null && landing.conn.contains(d.opposite)) continue;
        _face(c, Pal.ghostOk, cellQuad(exitCell));
      }
    });

    _drawTrain(c, v);
    _drawToasts(c, v, size);
  }

  void _drawTrain(Canvas c, IsoView v) {
    final hf = game.heights;
    final items = <(double, void Function())>[];
    final actors = <(double, double)>[]; // plane positions of moving things
    for (final cow in game.cows) {
      final px = cow.cell.x + 0.5, py = cow.cell.y + 0.5;
      final z = hf.centerZ(cow.cell) * kZStep;
      actors.add((px, py));
      items.add((v.depthKey(px, py), () => drawCow(c, v, px, py, z)));
    }
    for (final (ti, tr) in game.trains.indexed) {
      final path = tr.renderPath;
      if (path == null || path.isEmpty) continue;
      final len = path.length.toDouble();
      final engineCols = ti == 0 ? Pal.engine : Pal.engine2;
      final cabCols = ti == 0 ? Pal.cab : Pal.cab2;
      final carCols = ti == 0 ? Pal.car : Pal.car2;
      final vehicles = <(double, bool)>[(tr.s, true)]; // (s, isEngine)
      for (var i = 0; i < tr.cars; i++) {
        var cs = tr.s - 0.85 * (i + 1);
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
        if (st.tunnelTo != null) continue; // underground: unseen till out
        final local = st.posInCell(t, 1.0);
        final px = st.cell.x + local.dx, py = st.cell.y + local.dy;
        final heading = st.headingAt(t, 1.0);
        // Ground level under this vehicle; airborne steps lerp pad-to-pad
        // and add the launch arc on top.
        double groundZ;
        final fly = st.flyTo;
        if (fly != null) {
          double padZ(Cell cell) =>
              game.deck[cell]?.toDouble() ?? hf.centerZ(cell);
          final za = padZ(st.cell), zb = padZ(fly);
          groundZ = (za + (zb - za) * t) * kZStep;
        } else {
          // Rail height interpolates entry-edge to exit-edge.
          final za = game.railEdgeZ(st.cell, st.entry);
          final zb = game.railEdgeZ(st.cell, st.exit);
          groundZ = (za + (zb - za) * t) * kZStep;
        }
        var z = groundZ + st.flightZ(t);
        // Riding a loop-de-loop: climb around the inside of the hoop.
        if (game.loops.contains(st.cell) &&
            st.flyTo == null &&
            st.tunnelTo == null) {
          z += 0.42 * (1 - math.cos(2 * math.pi * t));
        }
        final horiz = math.cos(heading).abs() > math.sin(heading).abs();
        final w = horiz ? 0.68 : 0.34, d = horiz ? 0.34 : 0.68;
        actors.add((px, py));
        items.add((v.depthKey(px, py), () {
          drawShadow(c, v, px, py, st.flyTo != null ? 0.2 : 0.3, groundZ);
          if (isEngine) {
            drawBox(c, v, px, py, w, d, 0.3, engineCols, 0.04 + z);
            // Cab at the rear, stack at the front (visual only).
            final back = Offset.fromDirection(heading, -0.16);
            final front = Offset.fromDirection(heading, 0.2);
            drawBox(c, v, px + back.dx, py + back.dy, horiz ? 0.3 : 0.3,
                horiz ? 0.3 : 0.3, 0.2, cabCols, 0.34 + z);
            drawBox(c, v, px + front.dx, py + front.dy, 0.1, 0.1, 0.16,
                Pal.stack, 0.34 + z);
            if (tr.wrecked) {
              final m = v.pt(px, py, z + 1.0);
              final paint = Paint()
                ..color = Pal.bad
                ..strokeWidth = 3
                ..strokeCap = StrokeCap.round;
              c.drawLine(
                  m + const Offset(-7, -7), m + const Offset(7, 7), paint);
              c.drawLine(
                  m + const Offset(-7, 7), m + const Offset(7, -7), paint);
            }
          } else {
            drawBox(c, v, px, py, w * 0.94, d * 0.94, 0.26, carCols, 0.04 + z);
          }
        }));
      }
    }

    // Speed pads: paired chevrons flat on the rail bed along the track axis.
    for (final pc in game.speedPads) {
      final kind = game.board[pc];
      if (kind == null) continue;
      final z = (game.deck[pc]?.toDouble() ?? hf.centerZ(pc)) * kZStep + 0.02;
      final ew = kind.conn.contains(Dir.e) || kind.conn.contains(Dir.w);
      final paint = Paint()..color = const Color(0xCC5BA8D9);
      for (final t in [0.32, 0.58]) {
        final (cx, cy) = (pc.x + (ew ? t : 0.5), pc.y + (ew ? 0.5 : t));
        Offset at(double a, double b) => v.pt(
            cx + (ew ? a : b), cy + (ew ? b : a), z);
        final path = Path()
          ..moveTo(at(-0.06, -0.16).dx, at(-0.06, -0.16).dy)
          ..lineTo(at(0.12, 0).dx, at(0.12, 0).dy)
          ..lineTo(at(-0.06, 0.16).dx, at(-0.06, 0.16).dy)
          ..lineTo(at(0.02, 0).dx, at(0.02, 0).dy)
          ..close();
        c.drawPath(path, paint);
      }
    }

    // Loop-de-loops: a vertical hoop rising off the rail bed, drawn in the
    // travel plane so trains climb around its inside.
    for (final lc in game.loops) {
      final kind = game.board[lc];
      if (kind == null) continue;
      final ew = kind.conn.contains(Dir.e) || kind.conn.contains(Dir.w);
      final zBase = hf.centerZ(lc) * kZStep;
      final cx = lc.x + 0.5, cy = lc.y + 0.5;
      items.add((v.depthKey(cx, cy) + 0.02, () {
        final ring = Path();
        for (var i = 0; i <= 28; i++) {
          final th = i / 28 * 2 * math.pi;
          final a = 0.40 * math.sin(th);
          final p = v.pt(cx + (ew ? a : 0), cy + (ew ? 0 : a),
              zBase + 0.45 * (1 - math.cos(th)));
          i == 0 ? ring.moveTo(p.dx, p.dy) : ring.lineTo(p.dx, p.dy);
        }
        c.drawPath(
            ring,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeCap = StrokeCap.round
              ..strokeWidth = 0.1 * v.s
              ..color = Pal.bed);
        c.drawPath(
            ring,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.028 * v.s
              ..color = Colors.white);
      }));
    }

    // Jump ramps: a rising wedge aimed along the firing direction.
    void drawRamp(Cell rc, Dir dir, {bool ghost = false}) {
      final z = (hf.centerZ(rc)) * kZStep;
      final (dx, dy) = switch (dir) {
        Dir.n => (0.0, -1.0),
        Dir.s => (0.0, 1.0),
        Dir.e => (1.0, 0.0),
        Dir.w => (-1.0, 0.0),
      };
      final cx = rc.x + 0.5, cy = rc.y + 0.5;
      items.add((v.depthKey(cx, cy) + 0.01, () {
        final along = dx.abs() > 0;
        // Low tail, tall lip: reads as a wedge pointing the flight way.
        drawBox(c, v, cx - dx * 0.22, cy - dy * 0.22,
            along ? 0.3 : 0.62, along ? 0.62 : 0.3, 0.1, Pal.stop, z);
        drawBox(c, v, cx + dx * 0.05, cy + dy * 0.05,
            along ? 0.3 : 0.62, along ? 0.62 : 0.3, 0.24, Pal.stop, z);
        drawBox(c, v, cx + dx * 0.3, cy + dy * 0.3,
            along ? 0.24 : 0.62, along ? 0.62 : 0.24, 0.4, Pal.stopRoof, z);
      }));
    }

    for (final e in game.ramps.entries) {
      drawRamp(e.key, e.value);
    }

    // Block signals: a mast with a lamp — red while it's holding a train.
    for (final sc in game.signals) {
      final zBase = (game.deck[sc]?.toDouble() ?? hf.centerZ(sc)) * kZStep;
      final px = sc.x + 0.82, py = sc.y + 0.82;
      items.add((v.depthKey(px, py), () {
        drawBox(c, v, px, py, 0.07, 0.07, 0.42, Pal.stack, zBase);
        final lamp = v.pt(px, py, zBase + 0.5);
        c.drawCircle(
            lamp,
            0.055 * v.s,
            Paint()
              ..color = game.heldSignals.contains(sc)
                  ? Pal.signalStop
                  : Pal.signalGo);
        c.drawCircle(
            lamp,
            0.055 * v.s,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.4
              ..color = Colors.white);
      }));
    }
    // The dynamic layer always composites over the static one, so any tree
    // or building near a moving actor re-enters THIS pass: depth order then
    // decides who covers whom, instead of layer order.
    final near = <Cell>{};
    for (final (ax, ay) in actors) {
      final cx = ax.floor(), cy = ay.floor();
      for (var dx = -2; dx <= 2; dx++) {
        for (var dy = -2; dy <= 2; dy++) {
          near.add(Cell(cx + dx, cy + dy));
        }
      }
    }
    if (near.isNotEmpty) {
      final treeAt = _visibleTrees(game);
      final buildingAt = {for (final b in game.buildings) b.cell: b};
      for (final cell in near) {
        final t = treeAt[cell];
        if (t != null) {
          items.add((v.depthKey(t.$1, t.$2),
              () => drawTree(c, v, t.$1, t.$2, t.$3, hf.centerZ(cell) * kZStep)));
        }
        final b = buildingAt[cell];
        if (b != null) {
          items.add((v.depthKey(b.cell.x + 0.5, b.cell.y + 0.5),
              () => drawBuilding(c, v, b, hf.floorOf(b.cell) * kZStep)));
        }
      }
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
