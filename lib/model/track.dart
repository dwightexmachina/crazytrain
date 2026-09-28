import 'dart:ui';

/// Grid direction. n = row-1, s = row+1, e = col+1, w = col-1.
enum Dir {
  n(0, -1),
  e(1, 0),
  s(0, 1),
  w(-1, 0);

  final int dx, dy;
  const Dir(this.dx, this.dy);

  Dir get opposite => switch (this) {
        Dir.n => Dir.s,
        Dir.s => Dir.n,
        Dir.e => Dir.w,
        Dir.w => Dir.e,
      };
}

/// A track piece occupies one cell and connects exactly two edges.
enum TrackKind {
  ew({Dir.e, Dir.w}),
  ns({Dir.n, Dir.s}),
  ne({Dir.n, Dir.e}),
  nw({Dir.n, Dir.w}),
  se({Dir.s, Dir.e}),
  sw({Dir.s, Dir.w});

  final Set<Dir> conn;
  const TrackKind(this.conn);

  bool get isCurve => conn.length == 2 && !identical(this, ew) && !identical(this, ns);

  static TrackKind? fromDirs(Dir a, Dir b) {
    for (final k in TrackKind.values) {
      if (k.conn.contains(a) && k.conn.contains(b)) return k;
    }
    return null;
  }
}

/// A turnout occupying one cell. The [base] leg is the point end: a train
/// entering via [base] exits through the [active] branch, and a train
/// entering via either branch trails through and merges onto [base].
class TrackSwitch {
  final Cell cell;
  final Dir base;
  final Dir branchA, branchB;
  bool useB;
  TrackSwitch(this.cell, this.base, this.branchA, this.branchB,
      {this.useB = false});

  Dir get active => useB ? branchB : branchA;
  Dir get inactive => useB ? branchA : branchB;
}

/// Integer cell coordinate.
class Cell {
  final int x, y;
  const Cell(this.x, this.y);

  Cell step(Dir d) => Cell(x + d.dx, y + d.dy);

  @override
  bool operator ==(Object other) =>
      other is Cell && other.x == x && other.y == y;
  @override
  int get hashCode => x * 397 ^ y;
  @override
  String toString() => '$x,$y';

  static Cell parse(String s) {
    final p = s.split(',');
    return Cell(int.parse(p[0]), int.parse(p[1]));
  }
}

/// One step of the train's loop: the cell plus which edges it enters/exits.
/// A step with [flyTo] set is airborne: the train launches from [cell]'s
/// center and lands on [flyTo]'s center, keeping its heading.
class PathStep {
  final Cell cell;
  final Dir entry; // edge the train enters through
  final Dir exit; // edge it leaves through
  final Cell? flyTo;
  const PathStep(this.cell, this.entry, this.exit, {this.flyTo});

  /// Flight arc height (in cell units) at fraction t of an airborne step.
  double flightZ(double t) {
    final to = flyTo;
    if (to == null) return 0;
    final dist = ((to.x - cell.x).abs() + (to.y - cell.y).abs()).toDouble();
    final peak = (0.35 + 0.06 * dist).clamp(0.35, 1.1);
    return 4 * peak * t * (1 - t);
  }

  /// Position within the cell at fraction t in [0,1), in plane units
  /// relative to the cell's top-left corner (cell size = [size]).
  /// Straights interpolate edge-midpoint to edge-midpoint; curves follow a
  /// quarter circle around the corner shared by the two edges.
  Offset posInCell(double t, double size) {
    final h = size / 2;
    final to = flyTo;
    if (to != null) {
      final a = Offset(h, h);
      final b = Offset(
          h + (to.x - cell.x) * size, h + (to.y - cell.y) * size);
      return Offset.lerp(a, b, t)!;
    }
    Offset edgeMid(Dir d) => switch (d) {
          Dir.n => Offset(h, 0),
          Dir.s => Offset(h, size),
          Dir.e => Offset(size, h),
          Dir.w => Offset(0, h),
        };
    final a = edgeMid(entry), b = edgeMid(exit);
    if (entry.opposite == exit) {
      return Offset.lerp(a, b, t)!;
    }
    // Curve: circle center is the corner adjacent to both edges.
    final center = Offset(
      (entry == Dir.e || exit == Dir.e) ? size : 0,
      (entry == Dir.s || exit == Dir.s) ? size : 0,
    );
    // Angles of the two edge midpoints around the center; sweep the quarter.
    double ang(Offset p) => (p - center).direction;
    final a0 = ang(a);
    var a1 = ang(b);
    // Shortest quarter sweep.
    while (a1 - a0 > 3.15) {
      a1 -= 6.2832;
    }
    while (a0 - a1 > 3.15) {
      a1 += 6.2832;
    }
    final theta = a0 + (a1 - a0) * t;
    return center + Offset.fromDirection(theta, h);
  }

  /// Travel direction (plane-space angle) at fraction t.
  double headingAt(double t, double size) {
    const eps = 0.02;
    final p0 = posInCell((t - eps).clamp(0, 1), size);
    final p1 = posInCell((t + eps).clamp(0, 1), size);
    return (p1 - p0).direction;
  }
}

/// Walk the track from [start] leaving via [startExit]; returns the loop as
/// path steps if it closes back onto [start], else null (broken track).
///
/// [pads] maps each launchpad cell to its partner (both directions). Rolling
/// onto a pad adds three steps — ride on, fly to the partner, roll off — and
/// the walk continues from the partner in the same travel direction.
/// [switches] maps a cell to its turnout; routing follows the switch state.
List<PathStep>? traceLoop(Map<Cell, TrackKind> board, Cell start, Dir startExit,
    {Map<Cell, Cell> pads = const {},
    Map<Cell, TrackSwitch> switches = const {}}) {
  final steps = <PathStep>[];
  var cell = start;
  var exit = startExit;
  // With switches a loop may cross a cell more than once; bound by states.
  final maxHops = 4 * (board.length + pads.length + switches.length) + 4;
  for (var i = 0; i <= maxHops; i++) {
    final next = cell.step(exit);
    final partner = pads[next];
    if (partner != null) {
      final entry = exit.opposite;
      steps.add(PathStep(next, entry, exit)); // ride onto the pad
      steps.add(PathStep(next, entry, exit, flyTo: partner)); // airborne
      steps.add(PathStep(partner, entry, exit)); // roll off the partner
      cell = partner;
      continue; // heading unchanged
    }
    final sw = switches[next];
    if (sw != null) {
      final entry = exit.opposite;
      final Dir out;
      if (entry == sw.base) {
        out = sw.active; // point end: follow the thrown route
      } else if (entry == sw.branchA || entry == sw.branchB) {
        out = sw.base; // trailing move: always merges onto the base
      } else {
        return null; // hit the switch on an unconnected side
      }
      steps.add(PathStep(next, entry, out));
      cell = next;
      exit = out;
      continue;
    }
    final piece = board[next];
    if (piece == null) return null;
    final entry = exit.opposite;
    if (!piece.conn.contains(entry)) return null;
    final nextExit = piece.conn.firstWhere((d) => d != entry);
    steps.add(PathStep(next, entry, nextExit));
    if (next == start) return steps;
    cell = next;
    exit = nextExit;
  }
  return null; // shouldn't happen on a finite board
}
