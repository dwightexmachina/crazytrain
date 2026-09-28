import 'dart:convert';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import 'game.dart';
import 'track.dart';

/// One contract goal inside a scenario. [check] is polled against the live
/// game; once true the star is earned and persists forever.
class Mission {
  final String id;
  final String title;
  final bool Function(Game g) check;
  const Mission(this.id, this.title, this.check);
}

/// A pre-generated map with its contracts. [build] lays out the whole world
/// (size, heights, starter loop, buildings, cows, trees, balance) on a game
/// whose collections have already been cleared; scenarios without a builder
/// appear on the route map but can't be boarded yet.
class Scenario {
  final String id;
  final String name;
  final int difficulty; // 1..3 pips
  final String blurb;
  final List<String> facts; // chips like 'START $400'
  final List<Mission> missions;
  final void Function(Game g)? build;
  const Scenario({
    required this.id,
    required this.name,
    required this.difficulty,
    required this.blurb,
    this.facts = const [],
    this.missions = const [],
    this.build,
  });
  bool get playable => build != null;
}

/// Earned mission stars, persisted independently of any map save so they
/// survive Start over.
class ScenarioProgress {
  static const _key = 'ct_progress_v1';

  static Map<String, List<dynamic>> _read() {
    final raw = web.window.localStorage.getItem(_key);
    if (raw == null) return {};
    try {
      return Map<String, List<dynamic>>.from(jsonDecode(raw) as Map);
    } catch (_) {
      return {};
    }
  }

  static Set<String> done(String scenarioId) =>
      {...?_read()[scenarioId]?.cast<String>()};

  static int stars(String scenarioId) => done(scenarioId).length;

  static void markDone(String scenarioId, String missionId) {
    final all = _read();
    final set = {...?all[scenarioId]?.cast<String>(), missionId};
    all[scenarioId] = set.toList();
    web.window.localStorage.setItem(_key, jsonEncode(all));
  }

  /// The first stop is always open; each later stop opens once the previous
  /// one has at least one star.
  static bool unlocked(int index) =>
      index == 0 || stars(Scenarios.all[index - 1].id) > 0;

  static void resetAll() => web.window.localStorage.removeItem(_key);
}

// ------------------------------------------------------------ the line

class Scenarios {
  static final List<Scenario> all = [
    Scenario(
      id: 'prairie',
      name: 'PRAIRIE JUNCTION',
      difficulty: 1,
      blurb:
          'Open grassland, gentle knolls, and an unusual number of cows. '
          'Learn the trade where the land is kind.',
      facts: const ['START \$300', 'MAP 20×14', 'COW COUNTRY'],
      missions: [
        Mission('nest-egg', 'Bank \$2,000', (g) => g.balance >= 2000),
        Mission(
            'developer',
            'Build a station stop and a cargo depot',
            (g) =>
                g.buildings.any((b) => b.type == BuildingType.stop) &&
                g.buildings.any((b) => b.type == BuildingType.depot)),
        Mission('cowboy', 'Shoo 3 cows with the horn',
            (g) => g.cowsShooed >= 3),
      ],
      build: _buildPrairie,
    ),
    Scenario(
      id: 'gorge',
      name: 'THE GORGE',
      difficulty: 2,
      blurb:
          'A canyon river splits the world — every payout building sits on '
          'the far bank. Bridge it, ramp it, or fly it.',
      facts: const ['START \$400', 'MAP 24×16', 'BRIDGE COUNTRY'],
      missions: [
        Mission('span', 'Connect both banks', _gorgeSpansBanks),
        Mission('twice', 'Cross the gorge in two places',
            (g) => _gorgeCrossings(g) >= 2),
        Mission('tycoon', 'Earn \$500 in a single lap',
            (g) => g.bestLapPayout >= 500),
      ],
      build: _buildGorge,
    ),
    const Scenario(
      id: 'ridge',
      name: 'WIDOWMAKER RIDGE',
      difficulty: 2,
      blurb: 'A mountain wall with a single saddle — climb it, or bore '
          'straight through.',
    ),
    const Scenario(
      id: 'archipelago',
      name: 'ARCHIPELAGO',
      difficulty: 3,
      blurb: 'Five islands, one lagoon, and almost no flat ground to spare.',
    ),
    const Scenario(
      id: 'switchback',
      name: 'SWITCHBACK PASS',
      difficulty: 3,
      blurb: 'One narrow valley, two trains, zero room for error.',
    ),
    const Scenario(
      id: 'folly',
      name: "TERRAFORMER'S FOLLY",
      difficulty: 3,
      blurb: 'Nothing is flat, the low ground is flooded, and the budget '
          'is unsympathetic.',
    ),
  ];

  static Scenario byId(String id) => all.firstWhere((s) => s.id == id);
  static int indexOf(String id) => all.indexWhere((s) => s.id == id);
}

// ------------------------------------------------------------ builders

void _loopWithStation(Game g,
    {required int x0,
    required int y0,
    required int x1,
    required int y1,
    required Cell station}) {
  for (var x = x0 + 1; x < x1; x++) {
    g.board[Cell(x, y0)] = TrackKind.ew;
    g.board[Cell(x, y1)] = TrackKind.ew;
  }
  for (var y = y0 + 1; y < y1; y++) {
    g.board[Cell(x0, y)] = TrackKind.ns;
    g.board[Cell(x1, y)] = TrackKind.ns;
  }
  g.board[Cell(x0, y0)] = TrackKind.se;
  g.board[Cell(x1, y0)] = TrackKind.sw;
  g.board[Cell(x1, y1)] = TrackKind.nw;
  g.board[Cell(x0, y1)] = TrackKind.ne;
  g.buildings.add(Building(
      station, BuildingType.station, Cell(station.x, station.y - 1)));
}

void _scatter(Game g, math.Random rng, int count,
    {required bool Function(Cell) ok}) {
  var made = 0, guard = 0;
  while (made < count && guard++ < count * 30) {
    final c = Cell(rng.nextInt(g.cols), rng.nextInt(g.rows));
    if (!ok(c) ||
        g.board.containsKey(c) ||
        g.heights.isWet(c) ||
        g.buildings.any((b) =>
            (b.cell.x - c.x).abs() <= 1 && (b.cell.y - c.y).abs() <= 1) ||
        g.trees.any((t) => t.$1.floor() == c.x && t.$2.floor() == c.y)) {
      continue;
    }
    g.trees.add((
      c.x + 0.3 + rng.nextDouble() * 0.4,
      c.y + 0.3 + rng.nextDouble() * 0.4,
      0.7 + rng.nextDouble() * 0.4,
    ));
    made++;
  }
}

void _dropCows(Game g, math.Random rng, int count) {
  var made = 0, guard = 0;
  while (made < count && guard++ < count * 40) {
    final c = Cell(rng.nextInt(g.cols), rng.nextInt(g.rows));
    if (g.board.containsKey(c) ||
        g.heights.isWet(c) ||
        g.buildings.any((b) =>
            (b.cell.x - c.x).abs() <= 1 && (b.cell.y - c.y).abs() <= 1) ||
        g.cows.any((k) => k.cell == c)) {
      continue;
    }
    final (a, b, d, e) = g.heights.corners(c);
    if (math.max(math.max(a, b), math.max(d, e)) -
            math.min(math.min(a, b), math.min(d, e)) >
        1) {
      continue;
    }
    g.cows.add(Cow(c, 2 + rng.nextDouble() * 3));
    made++;
  }
}

void _hill(Game g, int vx, int vy, int steps) {
  for (var i = 0; i < steps; i++) {
    final plan = g.heights.planStep(vx, vy, 1, locked: (_, _) => false);
    if (plan == null) return;
    g.heights.apply(plan);
  }
}

// ---- Prairie Junction: flat, friendly, bovine.

void _buildPrairie(Game g) {
  final rng = math.Random(7101);
  g.cols = 20;
  g.rows = 14;
  g.heights.reset(g.cols, g.rows);
  // A watering hole in the southeast corner.
  for (final c in const [Cell(16, 10), Cell(17, 10), Cell(16, 11)]) {
    for (final (vx, vy) in [
      (c.x, c.y), (c.x + 1, c.y), (c.x + 1, c.y + 1), (c.x, c.y + 1),
    ]) {
      g.heights.setVertex(vx, vy, -1);
    }
  }
  // Two gentle knolls well clear of the loop.
  _hill(g, 16, 3, 2);
  _hill(g, 3, 12, 2);
  _loopWithStation(g, x0: 3, y0: 3, x1: 12, y1: 8, station: const Cell(7, 9));
  _scatter(g, rng, 10, ok: (_) => true);
  _dropCows(g, rng, 4);
  g.balance = 300;
}

// ---- The Gorge: a carved canyon down the middle of the map.

const int _gorgeWestMax = 8; // west bank is x <= this
const int _gorgeEastMin = 15; // east bank is x >= this

bool _inGorgeZone(Cell c) => c.x > _gorgeWestMax && c.x < _gorgeEastMin;

void _buildGorge(Game g) {
  final rng = math.Random(7102);
  g.cols = 24;
  g.rows = 16;
  g.heights.reset(g.cols, g.rows);
  // Riverbed: cells x 11..12 the whole way, bulging to 10..13 mid-map.
  for (var y = 0; y < g.rows; y++) {
    final bulge = y >= 6 && y <= 9;
    final xa = bulge ? 10 : 11, xb = bulge ? 13 : 12;
    for (var x = xa; x <= xb; x++) {
      for (final (vx, vy) in [(x, y), (x + 1, y), (x + 1, y + 1), (x, y + 1)]) {
        if (g.heights.vAt(vx, vy) > -1) g.heights.setVertex(vx, vy, -1);
      }
    }
  }
  // Deepen the centerline into a V so it reads as a canyon, not a puddle.
  for (var vy = 0; vy <= g.rows; vy++) {
    g.heights.setVertex(12, vy, -2);
  }
  // East-bank hills frame the payout country.
  _hill(g, 21, 2, 3);
  _hill(g, 17, 14, 2);
  _loopWithStation(g, x0: 2, y0: 4, x1: 7, y1: 9, station: const Cell(4, 10));
  // Every bonus building waits on the far bank.
  g.buildings.add(Building(const Cell(18, 4), BuildingType.stop));
  g.buildings.add(Building(const Cell(20, 11), BuildingType.depot));
  _scatter(g, rng, 12, ok: (c) => !_inGorgeZone(c));
  _dropCows(g, rng, 2);
  g.balance = 400;
}

bool _gorgeSpansBanks(Game g) {
  var west = false, east = false;
  for (final tr in g.trains) {
    final p = tr.path;
    if (p == null) continue;
    for (final st in p) {
      if (st.cell.x <= _gorgeWestMax) west = true;
      if (st.cell.x >= _gorgeEastMin) east = true;
      final fly = st.flyTo;
      if (fly != null) {
        if (fly.x <= _gorgeWestMax) west = true;
        if (fly.x >= _gorgeEastMin) east = true;
      }
    }
  }
  return west && east;
}

/// Distinct places a route crosses the canyon: maximal runs of path steps
/// inside the gorge zone (keyed by the cells they ride) plus launchpad
/// flights whose endpoints sit on opposite banks.
int _gorgeCrossings(Game g) {
  final sites = <String>{};
  for (final tr in g.trains) {
    final p = tr.path;
    if (p == null) continue;
    final run = <Cell>[];
    void flush() {
      if (run.isEmpty) return;
      final key =
          (run.map((c) => c.toString()).toList()..sort()).join(',');
      sites.add(key);
      run.clear();
    }

    for (final st in p) {
      if (_inGorgeZone(st.cell)) {
        run.add(st.cell);
      } else {
        flush();
      }
      final fly = st.flyTo;
      if (fly != null &&
          ((st.cell.x <= _gorgeWestMax && fly.x >= _gorgeEastMin) ||
              (st.cell.x >= _gorgeEastMin && fly.x <= _gorgeWestMax))) {
        sites.add('fly:${st.cell}>$fly');
      }
    }
    flush();
  }
  return sites.length;
}
