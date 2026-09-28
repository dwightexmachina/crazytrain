import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

import 'dart:ui' show Offset;

import '../audio/horn.dart';
import 'heightfield.dart';
import 'track.dart';

export 'heightfield.dart';
export 'track.dart' show Cell, Dir;

enum BuildingType {
  station('Station', 0, 0), // the main terminus: pays the lap formula
  stop('Station stop', 200, 10),
  depot('Cargo depot', 350, 6);

  final String label;
  final int price;
  final int bonus; // per pass of the adjacent track cell
  const BuildingType(this.label, this.price, this.bonus);
}

class Building {
  final Cell cell;
  final BuildingType type;
  Cell? trigger; // adjacent track cell that fires the bonus / payout
  Building(this.cell, this.type, [this.trigger]);
}

class Cow {
  Cell cell;
  double moveIn;
  Cow(this.cell, this.moveIn);
}

/// One train: its own traced route, position, cars and direction. The
/// second train runs the network in reverse, so facing switches route the
/// two independently — that's what makes passing loops work.
class Train {
  double s = 0; // position along [path], in steps
  int cars;
  final bool reversed;
  bool wrecked = false;
  int lapBonus = 0;
  List<PathStep>? path; // null = no closed route in this direction
  List<PathStep>? lastPath; // keeps a halted train visible
  Train({required this.cars, required this.reversed});
  List<PathStep>? get renderPath => path ?? lastPath;
}

enum Tool {
  none,
  track,
  stop,
  depot,
  bulldoze,
  raiseLand,
  lowerLand,
  levelLand,
  launchpad,
  switchTrack,
  tunnel,
  signal,
}

class Toast {
  final double px, py; // plane coords
  final String text;
  final bool big;
  double age = 0;
  Toast(this.px, this.py, this.text, {this.big = false});
}

/// One planned placement of a drag (or a building preview).
class Planned {
  final Cell cell;
  final TrackKind kind;
  final int cost; // 0 if identical track already there
  final bool bridge;
  final int? deckLevel; // bridge deck height over wet ground
  const Planned(this.cell, this.kind, this.cost,
      {this.bridge = false, this.deckLevel});
}

class TrackPlan {
  final List<Planned> pieces;
  final int cost;
  final bool truncatedByFunds;
  const TrackPlan(this.pieces, this.cost, this.truncatedByFunds);
  bool get isEmpty => pieces.isEmpty;
}

class Game extends ChangeNotifier {
  static const int startCols = 16, startRows = 12;
  static const int maxCols = 64, maxRows = 48;
  static const int expandStep = 4; // cells added per land deed
  static const int priceStraight = 10, priceCurve = 15, priceCar = 120;
  static const int priceBridge = 25; // surcharge for track over water
  static const int priceTerraformStep = 10; // per vertex-height-step moved
  static const int priceLaunchpad = 300; // per linked pair of pads
  static const int priceSwitch = 500; // converts a track piece to a turnout
  static const int priceTunnel = 400; // per bored portal pair
  static const int priceSignal = 150; // block signal on a track cell
  static const int priceSecondTrain = 1500; // opposite-direction engine
  static const int priceRerail = 250; // crane fee after a crash
  static const double tilesPerSecond = 2.2;

  final Map<Cell, TrackKind> board = {};
  final List<Building> buildings = [];
  final HeightField heights = HeightField(startCols, startRows);

  /// Bridge decks: rail crossing wet ground rides at this height (the bank
  /// grade it was built from) rather than on the submerged terrain.
  final Map<Cell, int> deck = {};

  /// Decorative trees: (x, y, scale) in plane coords, owned by the map.
  final List<(double, double, double)> trees = [];

  /// Launchpad cell -> its partner; every pair is stored in both directions.
  final Map<Cell, Cell> launchpads = {};
  Cell? pendingPad; // first pad of a pair being placed
  final Map<Cell, TrackSwitch> switches = {};
  Cell? pendingSwitch; // armed track piece awaiting its base-side tap

  /// Tunnel portal -> its partner; every pair is stored in both directions.
  final Map<Cell, Cell> tunnels = {};
  Cell? pendingTunnel; // first portal of a pair being placed
  final List<Cow> cows = [];
  final List<Train> trains = [Train(cars: 1, reversed: false)];
  final Set<Cell> signals = {};
  final Set<Cell> heldSignals = {}; // signals actively holding a train
  int cols = startCols, rows = startRows;
  int deeds = 0; // land deeds bought; each one raises the next deed's price
  int balance = 80;
  int speed = 1; // 0 = paused, 1, 2
  Tool tool = Tool.none;
  bool cowBlocked = false;

  // Legacy single-train accessors: the first train is the original one.
  double get s => trains.first.s;
  set s(double v) => trains.first.s = v;
  int get cars => trains.first.cars;
  set cars(int v) => trains.first.cars = v;
  List<PathStep>? get path => trains.first.path;
  List<PathStep>? get renderPath => trains.first.renderPath;

  final math.Random _rng = math.Random();

  /// Bumped whenever track/buildings/terrain change; the static board layer
  /// only re-rasterizes when this changes.
  int structureRev = 0;

  final List<Toast> toasts = [];

  Building get station => buildings.first;
  int get trackLength => path?.length ?? 0;

  int get projectedPayout {
    var sum = 0;
    for (final t in trains) {
      final p = t.path;
      if (p == null) continue;
      sum += t.cars * p.length;
      for (final b in buildings) {
        if (b.type.bonus > 0 &&
            b.trigger != null &&
            p.any((st) => st.cell == b.trigger)) {
          sum += b.type.bonus;
        }
      }
    }
    return sum;
  }

  /// The cell dips below the water table.
  bool isWater(Cell c) => heights.isWet(c);

  /// Cows wander only on dry, walkable land — no water, no launchpads,
  /// nothing steeper than a single step across the cell.
  bool _cowTerrain(Cell c) {
    if (isWater(c) || launchpads.containsKey(c) || tunnels.containsKey(c)) {
      return false;
    }
    final (a, b, d, e) = heights.corners(c);
    final lo = math.min(math.min(a, b), math.min(d, e));
    final hi = math.max(math.max(a, b), math.max(d, e));
    return hi - lo <= 1;
  }

  Game() {
    if (!_load()) _initialLayout();
    _rebuildPath();
  }

  void setTool(Tool t) {
    tool = tool == t ? Tool.none : t;
    pendingPad = null; // switching tools abandons half-placed pieces
    pendingSwitch = null;
    pendingTunnel = null;
    levelTarget = null;
    notifyListeners();
  }

  void setSpeed(int v) {
    speed = v;
    notifyListeners();
  }

  // ------------------------------------------------------------ setup

  void _initialLayout() {
    board.clear();
    buildings.clear();
    deck.clear();
    trees.clear();
    launchpads.clear();
    pendingPad = null;
    switches.clear();
    pendingSwitch = null;
    tunnels.clear();
    pendingTunnel = null;
    cows.clear();
    cols = startCols;
    rows = startRows;
    deeds = 0;
    heights.reset(cols, rows);
    const x0 = 3, y0 = 3, x1 = 12, y1 = 8;
    for (var x = x0 + 1; x < x1; x++) {
      board[Cell(x, y0)] = TrackKind.ew;
      board[Cell(x, y1)] = TrackKind.ew;
    }
    for (var y = y0 + 1; y < y1; y++) {
      board[Cell(x0, y)] = TrackKind.ns;
      board[Cell(x1, y)] = TrackKind.ns;
    }
    board[const Cell(x0, y0)] = TrackKind.se;
    board[const Cell(x1, y0)] = TrackKind.sw;
    board[const Cell(x1, y1)] = TrackKind.nw;
    board[const Cell(x0, y1)] = TrackKind.ne;
    buildings.add(Building(const Cell(7, 9), BuildingType.station, const Cell(7, 8)));
    _generateTerrain();
    _spawnCows(2);
    balance = 80;
    trains
      ..clear()
      ..add(Train(cars: 1, reversed: false));
    signals.clear();
    heldSignals.clear();
  }

  bool _protectedCell(Cell c) =>
      board.containsKey(c) ||
      launchpads.containsKey(c) ||
      tunnels.containsKey(c) ||
      buildings.any((b) =>
          (b.cell.x - c.x).abs() <= 1 && (b.cell.y - c.y).abs() <= 1);

  void _generateTerrain() {
    _generateRiver();
    _carveBlobs(blobs: 2, minSize: 2, extraSize: 3);
    _generateHills(2 + (cols * rows) ~/ 96);
    _scatterTrees((cols * rows) ~/ 24);
  }

  /// Sprinkle trees on open ground, optionally inside a region.
  void _scatterTrees(int count,
      {int? xMin, int? xMax, int? yMin, int? yMax}) {
    final x0 = xMin ?? 0, x1 = xMax ?? cols - 1;
    final y0 = yMin ?? 0, y1 = yMax ?? rows - 1;
    var made = 0;
    var guard = 0;
    while (made < count && guard++ < count * 20) {
      final cell = Cell(
          x0 + _rng.nextInt(x1 - x0 + 1), y0 + _rng.nextInt(y1 - y0 + 1));
      if (_protectedCell(cell) ||
          isWater(cell) ||
          trees.any((t) => t.$1.floor() == cell.x && t.$2.floor() == cell.y)) {
        continue;
      }
      trees.add((
        cell.x + 0.3 + _rng.nextDouble() * 0.4,
        cell.y + 0.3 + _rng.nextDouble() * 0.4,
        0.7 + _rng.nextDouble() * 0.4,
      ));
      made++;
    }
  }

  /// Sink one cell below the water table, if all four corners sit on the
  /// plain, are unlocked, and have no elevated neighbors.
  bool _carveCell(Cell c) {
    final vs = [
      (c.x, c.y), (c.x + 1, c.y), (c.x + 1, c.y + 1), (c.x, c.y + 1),
    ];
    for (final (vx, vy) in vs) {
      final h = heights.vAt(vx, vy);
      if (h > 0 || h < -1 || _lockedVertex(vx, vy)) return false;
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final nx = vx + dx, ny = vy + dy;
          if (nx < 0 || nx > cols || ny < 0 || ny > rows) continue;
          if (heights.vAt(nx, ny) > 0) return false;
        }
      }
    }
    for (final (vx, vy) in vs) {
      heights.setVertex(vx, vy, -1);
    }
    return true;
  }

  /// Raise peaks and short ridges with the terraform cascade. The vertex
  /// lock keeps them away from track, buildings and bridges automatically.
  void _generateHills(int count) {
    var made = 0;
    var guard = 0;
    int raiseTimes(int vx, int vy, int times) {
      var done = 0;
      for (var i = 0; i < times; i++) {
        final plan = heights.planStep(vx, vy, 1, locked: _lockedVertex);
        if (plan == null) break;
        heights.apply(plan);
        done++;
      }
      return done;
    }

    while (made < count && guard++ < 80) {
      final vx = 1 + _rng.nextInt(cols - 1);
      final vy = 1 + _rng.nextInt(rows - 1);
      final steps = 2 + _rng.nextInt(3);
      final raised = raiseTimes(vx, vy, steps);
      if (raised < 2) continue; // a one-step nub isn't a hill; try elsewhere
      // Half the time, grow the peak into a short ridge.
      if (_rng.nextBool()) {
        final dx = _rng.nextBool() ? 1 : -1;
        final along = _rng.nextBool();
        raiseTimes(vx + (along ? dx : 0), vy + (along ? 0 : dx),
            math.max(1, raised - 1));
      }
      made++;
    }
  }

  /// A meandering carved channel from the top edge to the bottom, kept in a
  /// three-column band beside the starter loop.
  void _generateRiver() {
    final left = _rng.nextBool();
    final xMin = left ? 0 : cols - 3, xMax = left ? 2 : cols - 1;
    var x = xMin + _rng.nextInt(xMax - xMin + 1);
    void dig(Cell c) {
      if (!_protectedCell(c)) _carveCell(c);
    }

    for (var y = 0; y < rows; y++) {
      dig(Cell(x, y));
      // Widen the channel here and there so it reads as a river valley.
      if (_rng.nextInt(3) == 0 && x + 1 <= xMax) dig(Cell(x + 1, y));
      if (_rng.nextInt(3) == 0) {
        final nx = x + (_rng.nextBool() ? 1 : -1);
        if (nx >= xMin && nx <= xMax) {
          x = nx;
          dig(Cell(x, y));
        }
      }
    }
  }

  /// Carves [blobs] random basins. Seeds land inside the optional region
  /// (defaults to the whole board); growth may wander past it.
  void _carveBlobs(
      {required int blobs,
      required int minSize,
      required int extraSize,
      int? xMin,
      int? xMax,
      int? yMin,
      int? yMax}) {
    final x0 = xMin ?? 0, x1 = xMax ?? cols - 1;
    final y0 = yMin ?? 0, y1 = yMax ?? rows - 1;
    var made = 0;
    var guard = 0;
    while (made < blobs && guard++ < 200) {
      final seed = Cell(
          x0 + _rng.nextInt(x1 - x0 + 1), y0 + _rng.nextInt(y1 - y0 + 1));
      if (_protectedCell(seed) || isWater(seed) || !_carveCell(seed)) {
        continue;
      }
      final size = minSize + _rng.nextInt(extraSize);
      var cur = seed;
      var carved = 1;
      var grow = 0;
      while (carved < size && grow++ < 12) {
        final d = Dir.values[_rng.nextInt(4)];
        final n = cur.step(d);
        if (!inBounds(n) || _protectedCell(n)) continue;
        if (isWater(n) || _carveCell(n)) {
          carved++;
          cur = n;
        }
      }
      made++;
    }
  }

  void _spawnCows(int n) {
    var guard = 0;
    while (n > 0 && guard++ < 200) {
      final c = Cell(_rng.nextInt(cols), _rng.nextInt(rows));
      if (board.containsKey(c) ||
          !_cowTerrain(c) ||
          _cellBlocked(c) ||
          cows.any((k) => k.cell == c)) {
        continue;
      }
      cows.add(Cow(c, 2 + _rng.nextDouble() * 3));
      n--;
    }
  }

  void newGame() {
    _initialLayout();
    _rebuildPath();
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------ path

  void _rebuildPath() {
    structureRev++;
    final trigger = station.trigger;
    for (final tr in trains) {
      List<PathStep>? p;
      if (trigger != null && board.containsKey(trigger)) {
        final kind = board[trigger]!;
        // The second train prefers the opposite direction around the loop.
        final dirs = tr.reversed
            ? [kind.conn.last, kind.conn.first]
            : [kind.conn.first, kind.conn.last];
        p = traceLoop(board, trigger, dirs[0],
                pads: launchpads, tunnels: tunnels, switches: switches) ??
            traceLoop(board, trigger, dirs[1],
                pads: launchpads, tunnels: tunnels, switches: switches);
      }
      // Keep the train where it stands when the route re-forms around it.
      final old = tr.path;
      if (p != null && old != null && old.isNotEmpty) {
        final cur = old[tr.s.floor() % old.length];
        final frac = tr.s - tr.s.floorToDouble();
        final ni =
            p.indexWhere((st) => st.cell == cur.cell && st.entry == cur.entry);
        tr.s = ni >= 0 ? ni + frac : 0;
      }
      tr.path = p;
      if (p != null) {
        tr.lastPath = p;
        if (tr.s >= p.length) tr.s = 0;
      } else if (tr.lastPath != null && tr.s >= tr.lastPath!.length) {
        tr.s = 0;
      }
    }
    // Re-resolve building triggers (their track may have been bulldozed).
    for (final b in buildings) {
      if (b.trigger != null && !board.containsKey(b.trigger)) b.trigger = null;
      b.trigger ??= _adjacentTrack(b.cell);
    }
  }

  Cell? _adjacentTrack(Cell c) {
    for (final d in Dir.values) {
      final n = c.step(d);
      if (board.containsKey(n)) return n;
    }
    return null;
  }

  // ------------------------------------------------------------ laying track

  bool inBounds(Cell c) => c.x >= 0 && c.x < cols && c.y >= 0 && c.y < rows;

  bool _cellBlocked(Cell c) => buildings.any((b) => b.cell == c);

  int _piecePrice(TrackKind kind, Cell c) =>
      (kind.isCurve ? priceCurve : priceStraight) +
      (isWater(c) ? priceBridge : 0);

  /// The two lattice vertices bounding a cell's [d] edge.
  ((int, int), (int, int)) _edgeVerts(Cell c, Dir d) => switch (d) {
        Dir.n => ((c.x, c.y), (c.x + 1, c.y)),
        Dir.s => ((c.x, c.y + 1), (c.x + 1, c.y + 1)),
        Dir.e => ((c.x + 1, c.y), (c.x + 1, c.y + 1)),
        Dir.w => ((c.x, c.y), (c.x, c.y + 1)),
      };

  /// Height of a cell edge when it's level, else null (side-slope).
  int? _edgeLevel(Cell c, Dir d) {
    final (a, b) = _edgeVerts(c, d);
    final h1 = heights.vAt(a.$1, a.$2), h2 = heights.vAt(b.$1, b.$2);
    return h1 == h2 ? h1 : null;
  }

  /// Rail height at a cell's [d] edge: the bridge deck when present, else
  /// the terrain edge midpoint. Drives train z and track rendering.
  double railEdgeZ(Cell c, Dir d) {
    final dk = deck[c];
    if (dk != null) return dk.toDouble();
    final (a, b) = _edgeVerts(c, d);
    return (heights.vAt(a.$1, a.$2) + heights.vAt(b.$1, b.$2)) / 2;
  }

  /// Time cost of one path step: climbing is slow, descending is quick.
  double stepCost(PathStep st) {
    if (st.flyTo != null || st.tunnelTo != null) return 1;
    final g = railEdgeZ(st.cell, st.exit) - railEdgeZ(st.cell, st.entry);
    if (g > 0.01) return 1.35;
    if (g < -0.01) return 0.75;
    return 1;
  }

  /// Edges of [c] with a connector on the far side ready to join new track
  /// at matching rail height: open track ends, switch legs, a tunnel
  /// portal's outward mouth, or any side of a launchpad.
  Set<Dir> connectionOffers(Cell c) {
    final out = <Dir>{};
    for (final d in Dir.values) {
      final n = c.step(d);
      if (!inBounds(n)) continue;
      final myEdge = _edgeLevel(c, d);
      if (myEdge == null) continue; // a side-sloped edge can't host a joint
      final back = d.opposite;
      final double theirs;
      final piece = board[n];
      final sw = switches[n];
      final partner = tunnels[n];
      if (piece != null) {
        if (!piece.conn.contains(back)) continue;
        theirs = railEdgeZ(n, back);
      } else if (sw != null) {
        if (back != sw.base && back != sw.branchA && back != sw.branchB) {
          continue;
        }
        theirs = railEdgeZ(n, back);
      } else if (partner != null) {
        if (back != axisDir(n, partner)!.opposite) continue; // mouth side only
        theirs = heights.floorOf(n).toDouble();
      } else if (launchpads.containsKey(n)) {
        theirs = heights.floorOf(n).toDouble();
      } else {
        continue;
      }
      if ((theirs - myEdge).abs() > 0.01) continue;
      out.add(d);
    }
    return out;
  }

  /// Orientation for a drag endpoint ([leg] = its one known direction) or a
  /// single tap ([leg] null): snap toward adjacent connectors when a valid
  /// piece results, else fall back to the drag axis (or EW for a tap).
  TrackKind _endpointKind(Cell c, Dir? leg) {
    final offers = connectionOffers(c);
    if (leg != null) {
      final ahead = leg.opposite; // straight through, continuing the motion
      if (offers.contains(ahead)) return TrackKind.fromDirs(leg, ahead)!;
      for (final d in offers) {
        final k = leg == d ? null : TrackKind.fromDirs(leg, d);
        if (k != null) return k; // curve into the connector
      }
      return (leg == Dir.e || leg == Dir.w) ? TrackKind.ew : TrackKind.ns;
    }
    final list = offers.toList();
    for (var i = 0; i < list.length; i++) {
      for (var j = i + 1; j < list.length; j++) {
        final k = TrackKind.fromDirs(list[i], list[j]);
        if (k != null) return k; // join two connectors in one tap
      }
    }
    if (list.isNotEmpty) {
      return (list.first == Dir.e || list.first == Dir.w)
          ? TrackKind.ew
          : TrackKind.ns;
    }
    return TrackKind.ew;
  }

  /// Convert a dragged cell sequence into placeable pieces with auto-curves.
  TrackPlan planTrack(List<Cell> drag) {
    final cells = <Cell>[];
    for (final c in drag) {
      if (cells.isEmpty || cells.last != c) cells.add(c);
    }
    final pieces = <Planned>[];
    var cost = 0;
    var truncated = false;
    int? prevExit; // rail height where the previous cell hands over
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (!inBounds(c) ||
          _cellBlocked(c) ||
          launchpads.containsKey(c) ||
          tunnels.containsKey(c) ||
          switches.containsKey(c)) {
        break;
      }
      Dir? toPrev = i > 0 ? _dirBetween(c, cells[i - 1]) : null;
      Dir? toNext = i < cells.length - 1 ? _dirBetween(c, cells[i + 1]) : null;
      if (i > 0 && toPrev == null) break; // non-adjacent jump: stop
      TrackKind kind;
      if (toPrev != null && toNext != null) {
        final k = TrackKind.fromDirs(toPrev, toNext);
        if (k == null) break; // pointer doubled back onto itself
        kind = k;
      } else {
        // Endpoints and taps snap toward whatever wants to connect.
        kind = _endpointKind(c, toPrev ?? toNext);
      }

      // Grade rules: bridges deck flat over water at the grade they were
      // entered from; curves need flat ground; straights may climb one step
      // per cell along their axis, never across a side-slope.
      final wet = isWater(c);
      final int entryH, exitH;
      if (wet) {
        final lvl = deck[c] ?? prevExit;
        if (lvl == null) break; // can't begin a bridge over open water
        entryH = exitH = lvl;
      } else if (kind.isCurve) {
        if (!heights.isFlat(c)) break;
        entryH = exitH = heights.floorOf(c);
      } else {
        final dirs = kind.conn.toList();
        final entryDir = toPrev ?? dirs.firstWhere((d) => d != toNext);
        final exitDir = dirs.firstWhere((d) => d != entryDir);
        final eIn = _edgeLevel(c, entryDir), eOut = _edgeLevel(c, exitDir);
        if (eIn == null || eOut == null) break; // side-slope under the rail
        if ((eIn - eOut).abs() > 1) break; // too steep to climb
        entryH = eIn;
        exitH = eOut;
      }
      if (prevExit != null && entryH != prevExit) break; // grade mismatch
      prevExit = exitH;

      final existing = board[c];
      if (existing != null) {
        if (existing == kind) {
          pieces.add(Planned(c, kind, 0)); // pass over matching track free
          continue;
        }
        break; // conflicting track: stop the run here
      }
      final price = _piecePrice(kind, c);
      if (cost + price > balance) {
        truncated = true;
        break;
      }
      cost += price;
      pieces.add(Planned(c, kind, price,
          bridge: wet, deckLevel: wet ? entryH : null));
    }
    return TrackPlan(pieces, cost, truncated);
  }

  Dir? _dirBetween(Cell from, Cell to) {
    for (final d in Dir.values) {
      if (from.step(d) == to) return d;
    }
    return null;
  }

  void commitTrack(TrackPlan plan) {
    if (plan.isEmpty || plan.cost > balance) return;
    for (final p in plan.pieces) {
      board[p.cell] = p.kind;
      final d = p.deckLevel;
      if (d != null) deck[p.cell] = d;
    }
    balance -= plan.cost;
    _rebuildPath();
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------ buildings

  List<(int, int)> _cornersOf(Cell c) => [
        (c.x, c.y), (c.x + 1, c.y), (c.x + 1, c.y + 1), (c.x, c.y + 1),
      ];

  /// Why [c] can't take a building (ignoring money and the auto-flatten,
  /// which is attempted on placement); drives the hover tint.
  String? buildingSiteError(Cell c) {
    if (!inBounds(c)) return 'Out of bounds';
    if (isWater(c)) return "Can't build on water";
    if (board.containsKey(c) ||
        _cellBlocked(c) ||
        launchpads.containsKey(c) ||
        tunnels.containsKey(c) ||
        switches.containsKey(c)) {
      return 'Cell occupied';
    }
    if (_adjacentTrack(c) == null) return 'Must touch track';
    return null;
  }

  String? placeBuilding(BuildingType type, Cell c) {
    final site = buildingSiteError(c);
    if (site != null) return site;
    final trigger = _adjacentTrack(c)!;
    // Auto-flatten an uneven site, priced like the terraform tools. All or
    // nothing: if any corner can't reach the target, restore and refuse.
    var flatCost = 0;
    List<int>? snapshot;
    if (!heights.isFlat(c)) {
      snapshot = heights.toList();
      final target = heights.centerZ(c).round();
      var steps = 0;
      var ok = true;
      for (final (vx, vy) in _cornersOf(c)) {
        var guard = 0;
        while (ok && heights.vAt(vx, vy) != target && guard++ < 12) {
          final delta = heights.vAt(vx, vy) < target ? 1 : -1;
          final plan = heights.planStep(vx, vy, delta, locked: _lockedVertex);
          if (plan == null) {
            ok = false;
          } else {
            steps += heights.stepsIn(plan);
            heights.apply(plan);
          }
        }
      }
      if (!ok || !heights.isFlat(c)) {
        heights.loadFrom(snapshot);
        return "Can't level this ground";
      }
      flatCost = steps * priceTerraformStep;
      _collapseBrokenTunnels();
    }
    if (balance < type.price + flatCost) {
      if (snapshot != null) heights.loadFrom(snapshot);
      return 'Not enough money';
    }
    balance -= type.price + flatCost;
    if (flatCost > 0 && toasts.length < 6) {
      toasts.add(Toast(c.x + 0.5, c.y - 0.3, 'Leveled −\$$flatCost'));
    }
    buildings.add(Building(c, type, trigger));
    structureRev++;
    _save();
    notifyListeners();
    return null;
  }

  /// Dev cheat: free money, bound to the "+" key.
  void devGrant([int amount = 200]) {
    balance += amount;
    _save();
    notifyListeners();
  }

  bool buyCar() {
    if (balance < priceCar) return false;
    balance -= priceCar;
    // The shorter train gets the new car.
    trains.reduce((a, b) => a.cars <= b.cars ? a : b).cars++;
    _save();
    notifyListeners();
    return true;
  }

  bool buySecondTrain() {
    if (trains.length > 1 || balance < priceSecondTrain) return false;
    balance -= priceSecondTrain;
    final t = Train(cars: 1, reversed: true);
    trains.add(t);
    _rebuildPath();
    final len = t.path?.length.toDouble();
    if (len != null && len > 0) {
      t.s = len / 2; // start on the far side of the loop
    }
    _save();
    notifyListeners();
    return true;
  }

  /// Place a block signal on a track cell, or tap an existing one to
  /// remove it (half refund). Trains stop at a signal while the block
  /// beyond it — up to the next signal — is occupied by the other train.
  String? tapSignal(Cell c) {
    if (!inBounds(c)) return 'Out of bounds';
    if (signals.contains(c)) {
      signals.remove(c);
      balance += priceSignal ~/ 2;
      structureRev++;
      _save();
      notifyListeners();
      return null;
    }
    if (!board.containsKey(c)) return 'Signals sit on track';
    if (balance < priceSignal) return 'Not enough money';
    balance -= priceSignal;
    signals.add(c);
    structureRev++;
    _save();
    notifyListeners();
    return null;
  }

  // ------------------------------------------------------------ terraform (elevation)

  /// A vertex is locked when a structure occupies one of its incident cells:
  /// terrain under track, buildings, pads and switches never moves. Water is
  /// just low ground now, so it sculpts freely — that's how you drain it.
  bool _lockedVertex(int vx, int vy) {
    for (var dx = -1; dx <= 0; dx++) {
      for (var dy = -1; dy <= 0; dy++) {
        final c = Cell(vx + dx, vy + dy);
        if (!inBounds(c)) continue;
        if (board.containsKey(c) ||
            switches.containsKey(c) ||
            launchpads.containsKey(c) ||
            tunnels.containsKey(c) ||
            _cellBlocked(c)) {
          return true;
        }
      }
    }
    return false;
  }

  /// The level tool's reference grade, set by the cell first pressed.
  int? levelTarget;

  void armLevel(Cell c) {
    if (!inBounds(c)) return;
    levelTarget =
        heights.isFlat(c) ? heights.floorOf(c) : heights.centerZ(c).round();
  }

  /// Drive every corner of [c] to [levelTarget], cascading and charging per
  /// height-step like the other terraform tools. All or nothing per cell:
  /// a cell that can't fully reach the grade is left untouched.
  String? levelTo(Cell c) {
    final target = levelTarget;
    if (target == null) return null;
    if (!inBounds(c)) return 'Out of bounds';
    if (heights.isFlat(c) && heights.floorOf(c) == target) return null;
    final snapshot = heights.toList();
    var steps = 0;
    var ok = true;
    for (final (vx, vy) in _cornersOf(c)) {
      var guard = 0;
      while (ok && heights.vAt(vx, vy) != target && guard++ < 16) {
        final delta = heights.vAt(vx, vy) < target ? 1 : -1;
        final plan = heights.planStep(vx, vy, delta, locked: _lockedVertex);
        if (plan == null) {
          ok = false;
        } else {
          steps += heights.stepsIn(plan);
          heights.apply(plan);
        }
      }
    }
    final cost = steps * priceTerraformStep;
    if (!ok || !heights.isFlat(c) || cost > balance) {
      heights.loadFrom(snapshot);
      return !ok || !heights.isFlat(c)
          ? "Can't level under track or buildings"
          : 'Not enough money';
    }
    balance -= cost;
    _collapseBrokenTunnels();
    structureRev++;
    _save();
    notifyListeners();
    return null;
  }

  /// Raise (delta 1) or lower (delta -1) the cell corner nearest [frac],
  /// cascading neighbors and charging per height-step moved.
  String? sculpt(Cell c, Offset frac, int delta) {
    if (!inBounds(c)) return 'Out of bounds';
    final vx = c.x + (frac.dx > 0.5 ? 1 : 0);
    final vy = c.y + (frac.dy > 0.5 ? 1 : 0);
    final plan = heights.planStep(vx, vy, delta, locked: _lockedVertex);
    if (plan == null) return "Can't reshape under track or buildings";
    final cost = heights.stepsIn(plan) * priceTerraformStep;
    if (cost > balance) return 'Not enough money';
    balance -= cost;
    heights.apply(plan);
    _collapseBrokenTunnels();
    structureRev++;
    _save();
    notifyListeners();
    return null;
  }

  // ------------------------------------------------------------ land deeds

  int get deedPrice => 400 + 200 * deeds;

  bool canGrow(Dir side) => (side == Dir.e || side == Dir.w)
      ? cols + expandStep <= maxCols
      : rows + expandStep <= maxRows;

  /// North/west deeds put new land before the origin, so everything that
  /// exists slides over by the expansion step.
  void _shiftWorld(int dx, int dy) {
    if (dx == 0 && dy == 0) return;
    Cell mv(Cell c) => Cell(c.x + dx, c.y + dy);
    final b2 = {for (final e in board.entries) mv(e.key): e.value};
    board
      ..clear()
      ..addAll(b2);
    final d2 = {for (final e in deck.entries) mv(e.key): e.value};
    deck
      ..clear()
      ..addAll(d2);
    final p2 = {for (final e in launchpads.entries) mv(e.key): mv(e.value)};
    launchpads
      ..clear()
      ..addAll(p2);
    final t2 = {for (final e in tunnels.entries) mv(e.key): mv(e.value)};
    tunnels
      ..clear()
      ..addAll(t2);
    final s2 = <Cell, TrackSwitch>{};
    switches.forEach((k, sw) {
      final c = mv(k);
      s2[c] = TrackSwitch(c, sw.base, sw.branchA, sw.branchB, useB: sw.useB);
    });
    switches
      ..clear()
      ..addAll(s2);
    final nb = [
      for (final b in buildings)
        Building(mv(b.cell), b.type,
            b.trigger == null ? null : mv(b.trigger!)),
    ];
    buildings
      ..clear()
      ..addAll(nb);
    for (final cow in cows) {
      cow.cell = mv(cow.cell);
    }
    final nt = [for (final t in trees) (t.$1 + dx, t.$2 + dy, t.$3)];
    trees
      ..clear()
      ..addAll(nt);
    toasts.clear();
    pendingPad = null;
    pendingSwitch = null;
    pendingTunnel = null;
  }

  /// Buy a strip of frontier on any side. The new land gets a sprinkle of
  /// fresh terrain to tame.
  bool buyLand(Dir side) {
    if (!canGrow(side)) return false;
    if (balance < deedPrice) return false;
    balance -= deedPrice;
    deeds++;
    final dx = side == Dir.w ? expandStep : 0;
    final dy = side == Dir.n ? expandStep : 0;
    if (side == Dir.e || side == Dir.w) {
      cols += expandStep;
    } else {
      rows += expandStep;
    }
    heights.expand(cols, rows, dx: dx, dy: dy);
    _shiftWorld(dx, dy);
    final (xMin, xMax, yMin, yMax) = switch (side) {
      Dir.e => (cols - expandStep, cols - 1, 0, rows - 1),
      Dir.w => (0, expandStep - 1, 0, rows - 1),
      Dir.s => (0, cols - 1, rows - expandStep, rows - 1),
      Dir.n => (0, cols - 1, 0, expandStep - 1),
    };
    _carveBlobs(
        blobs: 1, minSize: 2, extraSize: 3,
        xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax);
    _scatterTrees((xMax - xMin + 1) * (yMax - yMin + 1) ~/ 24,
        xMin: xMin, xMax: xMax, yMin: yMin, yMax: yMax);
    _generateHills(1 + expandStep ~/ 4);
    _rebuildPath();
    _save();
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ launchpads

  /// Why [c] can't host a launchpad, or null when it can. Also drives the
  /// hover tint while the tool is active.
  String? padSiteError(Cell c) {
    if (!inBounds(c)) return 'Out of bounds';
    if (launchpads.containsKey(c)) return 'Already a launchpad';
    if (board.containsKey(c) || switches.containsKey(c)) {
      return 'Remove the track first';
    }
    if (_cellBlocked(c) || tunnels.containsKey(c)) return 'Cell occupied';
    if (isWater(c)) return "Can't float on water";
    if (!heights.isFlat(c)) return 'Needs flat ground';
    return null;
  }

  /// Two-tap placement: first tap arms a pad, second tap links the pair.
  /// Tapping the armed pad again cancels it. Returns an error, or null.
  String? tapLaunchpad(Cell c) {
    if (!inBounds(c)) return 'Out of bounds';
    if (pendingPad == c) {
      pendingPad = null;
      notifyListeners();
      return null;
    }
    final site = padSiteError(c);
    if (site != null) return site;
    if (balance < priceLaunchpad) return 'Not enough money';
    final first = pendingPad;
    if (first == null) {
      pendingPad = c;
      notifyListeners();
      return null;
    }
    balance -= priceLaunchpad;
    launchpads[first] = c;
    launchpads[c] = first;
    pendingPad = null;
    _rebuildPath();
    _save();
    notifyListeners();
    return null;
  }

  // ------------------------------------------------------------ tunnels

  /// The bore between portals [a] and [b] (exclusive) stays underground:
  /// every intermediate cell must ride at least half a step above the
  /// portal grade and never dip below it.
  bool _boreCovered(Cell a, Cell b) {
    final lvl = heights.floorOf(a);
    final dx = (b.x - a.x).sign, dy = (b.y - a.y).sign;
    var mid = Cell(a.x + dx, a.y + dy);
    while (mid != b) {
      if (heights.minCorner(mid) < lvl || heights.centerZ(mid) < lvl + 0.5) {
        return false;
      }
      mid = Cell(mid.x + dx, mid.y + dy);
    }
    return true;
  }

  /// Why [c] can't host a tunnel portal; drives the hover tint too.
  String? portalSiteError(Cell c) {
    if (tunnels.containsKey(c)) return 'Already a tunnel portal';
    if (board.containsKey(c) || switches.containsKey(c)) {
      return 'Remove the track first';
    }
    if (_cellBlocked(c) || launchpads.containsKey(c)) return 'Cell occupied';
    if (isWater(c)) return "Can't bore from water";
    if (!heights.isFlat(c)) return 'Portals need flat ground';
    return null;
  }

  /// Why a bore from [from] to [to] is impossible, or null when it's valid.
  /// Drives both placement and the live preview line.
  String? boreError(Cell from, Cell to) {
    final site = portalSiteError(to);
    if (site != null) return site;
    if (axisDir(from, to) == null) return 'Portals must line up';
    final dist = (to.x - from.x).abs() + (to.y - from.y).abs();
    if (dist < 2) return 'Too close — nothing to bore through';
    if (heights.floorOf(to) != heights.floorOf(from)) {
      return 'Portal heights must match';
    }
    if (!_boreCovered(from, to)) return 'No mountain to bore through';
    return null;
  }

  /// Two-tap placement: first tap arms a portal, second tap bores to it.
  /// Tapping the armed portal again cancels. Returns an error, or null.
  String? tapTunnel(Cell c) {
    if (!inBounds(c)) return 'Out of bounds';
    final first = pendingTunnel;
    if (first == c) {
      pendingTunnel = null;
      notifyListeners();
      return null;
    }
    if (balance < priceTunnel) return 'Not enough money';
    if (first == null) {
      final site = portalSiteError(c);
      if (site != null) return site;
      pendingTunnel = c;
      notifyListeners();
      return null;
    }
    final err = boreError(first, c);
    if (err != null) return err;
    balance -= priceTunnel;
    tunnels[first] = c;
    tunnels[c] = first;
    pendingTunnel = null;
    _rebuildPath();
    _save();
    notifyListeners();
    return null;
  }

  /// Sculpting can strip the ground off a bore; when it does, the tunnel
  /// caves in.
  void _collapseBrokenTunnels() {
    final seen = <Cell>{};
    final broken = <Cell>[];
    tunnels.forEach((a, b) {
      if (seen.contains(a)) return;
      seen.add(a);
      seen.add(b);
      if (!_boreCovered(a, b)) broken.add(a);
    });
    for (final a in broken) {
      final b = tunnels.remove(a)!;
      tunnels.remove(b);
      if (toasts.length < 6) {
        toasts.add(Toast(a.x + 0.5, a.y - 0.3, 'Tunnel collapsed!', big: true));
      }
    }
    if (broken.isNotEmpty) _rebuildPath();
  }

  // ------------------------------------------------------------ switches

  /// Two-tap placement: first tap arms an existing track piece, second tap
  /// picks the free side that becomes the junction's base leg. Tapping the
  /// armed piece again cancels.
  String? tapSwitch(Cell c) {
    if (!inBounds(c)) return 'Out of bounds';
    final first = pendingSwitch;
    if (first == c) {
      pendingSwitch = null;
      notifyListeners();
      return null;
    }
    if (first == null) {
      if (switches.containsKey(c)) return 'Already a switch';
      if (!board.containsKey(c)) return 'Tap an existing track piece';
      if (!heights.isFlat(c) && !deck.containsKey(c)) {
        return 'Switches need flat ground';
      }
      if (balance < priceSwitch) return 'Not enough money';
      pendingSwitch = c;
      notifyListeners();
      return null;
    }
    final d = _dirBetween(first, c);
    if (d == null) return 'Tap a cell beside the armed track piece';
    final piece = board[first]!;
    if (piece.conn.contains(d)) return 'The junction must face a free side';
    if (balance < priceSwitch) return 'Not enough money';
    balance -= priceSwitch;
    final legs = piece.conn.toList();
    switches[first] = TrackSwitch(first, d, legs[0], legs[1]);
    board.remove(first);
    pendingSwitch = null;
    _rebuildPath();
    _save();
    notifyListeners();
    return null;
  }

  /// Flip a turnout's points (no-op on non-switch cells).
  void toggleSwitch(Cell c) {
    final sw = switches[c];
    if (sw == null) return;
    sw.useB = !sw.useB;
    _rebuildPath();
    if (toasts.length < 6) {
      toasts.add(
          Toast(c.x + 0.5, c.y - 0.3, path == null ? 'No route!' : 'Switched'));
    }
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------ bulldoze

  void bulldoze(Cell c) {
    final portal = tunnels[c];
    if (portal != null) {
      tunnels.remove(c);
      tunnels.remove(portal);
      balance += priceTunnel ~/ 2;
      _rebuildPath();
      _save();
      notifyListeners();
      return;
    }
    if (switches.containsKey(c)) {
      switches.remove(c);
      balance += priceSwitch ~/ 2;
      _rebuildPath();
      _save();
      notifyListeners();
      return;
    }
    final partner = launchpads[c];
    if (partner != null) {
      launchpads.remove(c);
      launchpads.remove(partner);
      balance += priceLaunchpad ~/ 2;
      _rebuildPath();
      _save();
      notifyListeners();
      return;
    }
    final bIdx = buildings.indexWhere((b) => b.cell == c);
    if (bIdx > 0) {
      // main station (index 0) is not removable
      balance += buildings[bIdx].type.price ~/ 2;
      buildings.removeAt(bIdx);
      _rebuildPath();
      _save();
      notifyListeners();
      return;
    }
    final piece = board[c];
    if (piece != null) {
      board.remove(c);
      deck.remove(c);
      signals.remove(c);
      balance += _piecePrice(piece, c) ~/ 2;
      _rebuildPath();
      _save();
      notifyListeners();
    }
  }

  // ------------------------------------------------------------ whistle

  Cell? get engineCell {
    final p = renderPath;
    if (p == null || p.isEmpty) return null;
    return p[s.floor() % p.length].cell;
  }

  /// Toot the horn; any cow near the engine bolts somewhere far away.
  void honk() {
    Horn.play();
    final eng = engineCell;
    if (eng != null) {
      for (final cow in cows) {
        final near =
            (cow.cell.x - eng.x).abs() <= 2 && (cow.cell.y - eng.y).abs() <= 2;
        if (near) _relocateCow(cow, eng);
      }
    }
    notifyListeners();
  }

  void _relocateCow(Cow cow, Cell awayFrom) {
    for (var i = 0; i < 40; i++) {
      final c = Cell(_rng.nextInt(cols), _rng.nextInt(rows));
      final far = (c.x - awayFrom.x).abs() + (c.y - awayFrom.y).abs() >= 5;
      if (far &&
          !board.containsKey(c) &&
          _cowTerrain(c) &&
          !_cellBlocked(c)) {
        cow.cell = c;
        toasts.add(Toast(c.x + 0.5, c.y - 0.3, 'Moo?'));
        return;
      }
    }
  }

  // ------------------------------------------------------------ cows

  void _updateCows(double dt) {
    for (final cow in cows) {
      cow.moveIn -= dt;
      // Catch up step by step when a tick covers a long gap (throttled tab).
      var guard = 0;
      while (cow.moveIn <= 0 && guard++ < 40) {
        cow.moveIn += 2.2 + _rng.nextDouble() * 2.5;
        _stepCow(cow);
      }
    }
  }

  void _stepCow(Cow cow) {
    final d = Dir.values[_rng.nextInt(4)];
    final n = cow.cell.step(d);
    if (inBounds(n) &&
        _cowTerrain(n) &&
        !_cellBlocked(n) &&
        !cows.any((k) => k != cow && k.cell == n)) {
      cow.cell = n;
    }
    // A wandering cow crosses rails briskly instead of parking on them.
    if (board.containsKey(cow.cell) && cow.moveIn > 0.8) cow.moveIn = 0.8;
  }

  bool _cowAt(Cell c) => cows.any((k) => k.cell == c);

  // ------------------------------------------------------------ simulation

  /// Cells under a train's engine and cars, sampled along its path.
  Set<Cell> occupiedBy(Train tr) {
    final p = tr.renderPath;
    if (p == null || p.isEmpty) return const {};
    final out = <Cell>{};
    final len = p.length.toDouble();
    final tail = 0.85 * tr.cars + 0.6;
    for (var d = 0.0; d <= tail; d += 0.4) {
      var pos = tr.s - d;
      while (pos < 0) {
        pos += len;
      }
      out.add(p[pos.floor() % p.length].cell);
    }
    return out;
  }

  /// The block a signal at path index [entryIdx] protects for [tr]: cells
  /// ahead until the next signal (or twelve cells). Occupied by another
  /// train means hold.
  bool _blockOccupied(Train tr, int entryIdx) {
    final p = tr.path!;
    final others = <Cell>{};
    for (final o in trains) {
      if (!identical(o, tr)) others.addAll(occupiedBy(o));
    }
    if (others.isEmpty) return false;
    var idx = entryIdx;
    for (var i = 0; i < 12; i++) {
      final cell = p[idx % p.length].cell;
      if (others.contains(cell)) return true;
      if (i > 0 && signals.contains(cell)) break; // next signal ends the block
      idx++;
    }
    return false;
  }

  void _advance(Train tr, double dt) {
    final p = tr.path;
    if (p == null || tr.wrecked) return;
    final len = p.length;
    // Advance cell by cell so bonuses and payouts fire even when a single
    // tick covers several cells (throttled/background tabs catch up).
    var adv = dt * tilesPerSecond * speed;
    var paidOut = false;
    while (adv > 0) {
      final idx = tr.s.floor();
      final nextIdx = (idx + 1) % len;
      final nextCell = p[nextIdx].cell;
      if (_cowAt(nextCell)) {
        cowBlocked = true;
        tr.s = math.min(tr.s, idx + 0.94); // pull up short of the cow
        break;
      }
      if (signals.contains(nextCell) && _blockOccupied(tr, nextIdx)) {
        heldSignals.add(nextCell);
        tr.s = math.min(tr.s, idx + 0.94); // held at the red
        break;
      }
      // Grades stretch or shrink the time a step takes.
      final f = stepCost(p[idx % len]);
      final toBoundary = idx + 1 - tr.s;
      if (adv < toBoundary * f) {
        tr.s += adv / f;
        break;
      }
      tr.s += toBoundary;
      adv -= toBoundary * f;
      if (tr.s >= len) {
        tr.s = 0;
        final payout = tr.cars * len + tr.lapBonus;
        balance += payout;
        tr.lapBonus = 0;
        paidOut = true;
        final st = station.cell;
        if (toasts.length < 6) {
          toasts.add(Toast(st.x + 0.5, st.y - 0.6, '+\$$payout', big: true));
        }
      }
      // s sits exactly on a cell boundary: the train just entered this cell.
      final cell = p[tr.s.floor() % len].cell;
      for (final b in buildings) {
        if (b.type.bonus > 0 && b.trigger == cell) {
          tr.lapBonus += b.type.bonus;
          if (toasts.length < 6) {
            toasts.add(
                Toast(b.cell.x + 0.5, b.cell.y - 0.4, '+\$${b.type.bonus}'));
          }
        }
      }
    }
    if (paidOut) _save();
  }

  void _detectCrash() {
    if (trains.length < 2) return;
    final a = trains[0], b = trains[1];
    if (a.wrecked || b.wrecked) return;
    final hit = occupiedBy(a).intersection(occupiedBy(b));
    if (hit.isEmpty) return;
    a.wrecked = true;
    b.wrecked = true;
    final at = hit.first;
    toasts.add(Toast(at.x + 0.5, at.y - 0.4, 'CRASH!', big: true));
  }

  /// Tap a wreck (Select mode) to pay the crane and get both trains moving
  /// again, separated so they don't immediately re-collide.
  String? tapWreck(Cell c) {
    if (!trains.any((t) => t.wrecked)) return null;
    final hit = trains.any((t) => t.wrecked && occupiedBy(t).contains(c));
    if (!hit) return null;
    if (balance < priceRerail) return 'Not enough money';
    balance -= priceRerail;
    for (final t in trains) {
      t.wrecked = false;
    }
    if (trains.length > 1) {
      final t2 = trains[1];
      final len = t2.path?.length.toDouble();
      if (len != null && len > 0) t2.s = (t2.s + len / 2) % len;
    }
    if (toasts.length < 6) {
      toasts.add(Toast(c.x + 0.5, c.y - 0.4, 'Re-railed −\$$priceRerail'));
    }
    _save();
    notifyListeners();
    return null;
  }

  void tick(double dt) {
    var dirty = false;
    for (final t in toasts) {
      t.age += dt;
    }
    if (toasts.isNotEmpty) {
      toasts.removeWhere((t) => t.age > 1.8);
      dirty = true;
    }
    if (speed > 0) {
      _updateCows(dt);
      dirty = true;
    }
    cowBlocked = false;
    heldSignals.clear();
    if (speed > 0) {
      // With two trains, a large catch-up tick could step them through each
      // other between crash checks: slice to at most half a cell per slice.
      var slices = 1;
      if (trains.length > 1) {
        slices = (dt * tilesPerSecond * speed * 2).ceil().clamp(1, 240);
      }
      final sdt = dt / slices;
      for (var i = 0; i < slices; i++) {
        for (final tr in trains) {
          _advance(tr, sdt);
        }
        _detectCrash();
        if (trains.length > 1 && trains.every((t) => t.wrecked)) break;
      }
      dirty = true;
    }
    if (dirty) notifyListeners();
  }

  // ------------------------------------------------------------ persistence

  static const _key = 'ct_save_v3';
  static const _legacyKeys = ['ct_save_v2', 'ct_save_v1'];

  void _save() {
    final data = {
      'board': {for (final e in board.entries) e.key.toString(): e.value.index},
      'buildings': [
        for (final b in buildings)
          {'x': b.cell.x, 'y': b.cell.y, 't': b.type.index},
      ],
      'deck': {for (final e in deck.entries) e.key.toString(): e.value},
      'trees': [for (final t in trees) '${t.$1}|${t.$2}|${t.$3}'],
      'cows': [for (final k in cows) k.cell.toString()],
      'pads': [
        // Each pair once; the map holds both directions.
        for (final e in launchpads.entries)
          if (e.key.toString().compareTo(e.value.toString()) < 0)
            '${e.key}|${e.value}',
      ],
      'tunnels': [
        for (final e in tunnels.entries)
          if (e.key.toString().compareTo(e.value.toString()) < 0)
            '${e.key}|${e.value}',
      ],
      'switches': [
        for (final s in switches.values)
          {
            'c': s.cell.toString(),
            'b': s.base.index,
            'a1': s.branchA.index,
            'a2': s.branchB.index,
            'u': s.useB,
          },
      ],
      'signals': [for (final c in signals) c.toString()],
      'trains': [
        for (final t in trains) {'cars': t.cars, 'rev': t.reversed},
      ],
      'cols': cols,
      'rows': rows,
      'deeds': deeds,
      'heights': heights.toList(),
      'balance': balance,
      'cars': cars,
    };
    web.window.localStorage.setItem(_key, jsonEncode(data));
    for (final k in _legacyKeys) {
      web.window.localStorage.removeItem(k);
    }
  }

  bool _load() {
    var raw = web.window.localStorage.getItem(_key);
    final fromLegacy = raw == null;
    for (final k in _legacyKeys) {
      raw ??= web.window.localStorage.getItem(k);
    }
    if (raw == null) return false;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      board.clear();
      (data['board'] as Map<String, dynamic>).forEach((k, v) {
        board[Cell.parse(k)] = TrackKind.values[v as int];
      });
      buildings.clear();
      for (final b in (data['buildings'] as List)) {
        final t = b['t'] as int;
        if (t >= BuildingType.values.length) continue; // from older versions
        buildings.add(
            Building(Cell(b['x'] as int, b['y'] as int), BuildingType.values[t]));
      }
      if (buildings.isEmpty || buildings.first.type != BuildingType.station) {
        return false;
      }
      // Legacy object-terrain: mountains rise into the heightfield, water
      // cells carve below the table (both after heights load, below).
      final legacyMountains = <Cell>[];
      final legacyWater = <Cell>[];
      final terr = data['terrain'] as Map<String, dynamic>?;
      if (terr != null) {
        terr.forEach((k, v) {
          if (v == 'mountain') legacyMountains.add(Cell.parse(k));
          if (v == 'water') legacyWater.add(Cell.parse(k));
        });
      } else if (data['deck'] == null) {
        // v1 save: ponds were a bare cell list.
        for (final c in (data['ponds'] as List? ?? [])) {
          legacyWater.add(Cell.parse(c as String));
        }
      }
      deck.clear();
      (data['deck'] as Map<String, dynamic>? ?? {}).forEach((k, v) {
        deck[Cell.parse(k)] = v as int;
      });
      trees.clear();
      for (final t in (data['trees'] as List? ?? [])) {
        final p = (t as String).split('|');
        trees.add((
          double.parse(p[0]),
          double.parse(p[1]),
          double.parse(p[2]),
        ));
      }
      cows.clear();
      for (final c in (data['cows'] as List? ?? [])) {
        cows.add(Cow(Cell.parse(c as String), 2 + _rng.nextDouble() * 3));
      }
      while (cows.length > 3) {
        cows.removeLast(); // older versions could leave a whole herd behind
      }
      launchpads.clear();
      for (final p in (data['pads'] as List? ?? [])) {
        final ends = (p as String).split('|');
        final a = Cell.parse(ends[0]), b = Cell.parse(ends[1]);
        launchpads[a] = b;
        launchpads[b] = a;
      }
      tunnels.clear();
      for (final p in (data['tunnels'] as List? ?? [])) {
        final ends = (p as String).split('|');
        final a = Cell.parse(ends[0]), b = Cell.parse(ends[1]);
        tunnels[a] = b;
        tunnels[b] = a;
      }
      switches.clear();
      for (final s in (data['switches'] as List? ?? [])) {
        final cell = Cell.parse(s['c'] as String);
        switches[cell] = TrackSwitch(
          cell,
          Dir.values[s['b'] as int],
          Dir.values[s['a1'] as int],
          Dir.values[s['a2'] as int],
          useB: s['u'] as bool? ?? false,
        );
      }
      cols = (data['cols'] as int? ?? startCols).clamp(startCols, maxCols);
      rows = (data['rows'] as int? ?? startRows).clamp(startRows, maxRows);
      deeds = data['deeds'] as int? ?? 0;
      heights.reset(cols, rows);
      final hs = data['heights'] as List?;
      if (hs != null) heights.loadFrom([for (final h in hs) h as int]);
      // Legacy mountains rise into the heightfield, best effort: each corner
      // climbs toward 2 unless a structure locks the cascade.
      for (final mc in legacyMountains) {
        for (final (vx, vy) in [
          (mc.x, mc.y),
          (mc.x + 1, mc.y),
          (mc.x + 1, mc.y + 1),
          (mc.x, mc.y + 1),
        ]) {
          var guard = 0;
          while (heights.vAt(vx, vy) < 2 && guard++ < 4) {
            final p = heights.planStep(vx, vy, 1, locked: _lockedVertex);
            if (p == null) break;
            heights.apply(p);
          }
        }
      }
      // Legacy water cells sink one step below their old floor; any track
      // that crossed them becomes a bridge deck at the old grade.
      final waterFloors = {
        for (final wc in legacyWater)
          if (inBounds(wc)) wc: heights.floorOf(wc),
      };
      waterFloors.forEach((wc, f) {
        for (final (vx, vy) in [
          (wc.x, wc.y),
          (wc.x + 1, wc.y),
          (wc.x + 1, wc.y + 1),
          (wc.x, wc.y + 1),
        ]) {
          heights.setVertex(vx, vy, math.min(heights.vAt(vx, vy), f - 1));
        }
        if (board.containsKey(wc) || switches.containsKey(wc)) deck[wc] = f;
      });
      // Saves from before trees were map-owned get a fresh scatter.
      if (data['trees'] == null) _scatterTrees((cols * rows) ~/ 24);
      balance = data['balance'] as int;
      signals.clear();
      for (final c in (data['signals'] as List? ?? [])) {
        signals.add(Cell.parse(c as String));
      }
      trains
        ..clear()
        ..addAll([
          for (final t in (data['trains'] as List? ?? []))
            Train(cars: t['cars'] as int, reversed: t['rev'] as bool),
        ]);
      if (trains.isEmpty) {
        trains.add(Train(cars: data['cars'] as int, reversed: false));
      }
      for (final b in buildings) {
        b.trigger = _adjacentTrack(b.cell);
      }
      if (board.isEmpty) return false;
      if (fromLegacy) {
        _save(); // migrate to the current key right away
        for (final k in _legacyKeys) {
          web.window.localStorage.removeItem(k);
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
