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

  /// Earned stars, counting only missions the scenario still has — ids
  /// from retired missions linger in storage but never score.
  static int stars(String scenarioId) {
    final d = done(scenarioId);
    for (final sc in Scenarios.all) {
      if (sc.id == scenarioId) {
        return sc.missions.where((m) => d.contains(m.id)).length;
      }
    }
    return d.length;
  }

  static void markDone(String scenarioId, String missionId) {
    final all = _read();
    final set = {...?all[scenarioId]?.cast<String>(), missionId};
    all[scenarioId] = set.toList();
    web.window.localStorage.setItem(_key, jsonEncode(all));
  }

  // The LINE CLEAR celebration fires exactly once per scenario.
  static const _celebratedKey = 'ct_celebrated_v1';

  static bool celebrated(String scenarioId) {
    final raw = web.window.localStorage.getItem(_celebratedKey);
    if (raw == null) return false;
    try {
      return (jsonDecode(raw) as List).contains(scenarioId);
    } catch (_) {
      return false;
    }
  }

  static void markCelebrated(String scenarioId) {
    final raw = web.window.localStorage.getItem(_celebratedKey);
    var list = <dynamic>[];
    if (raw != null) {
      try {
        list = jsonDecode(raw) as List;
      } catch (_) {}
    }
    if (!list.contains(scenarioId)) list.add(scenarioId);
    web.window.localStorage.setItem(_celebratedKey, jsonEncode(list));
  }

  /// The first stop is always open; each later stop opens once the previous
  /// one has at least one star.
  static bool unlocked(int index) =>
      index == 0 || stars(Scenarios.all[index - 1].id) > 0;

  static void resetAll() {
    web.window.localStorage.removeItem(_key);
    web.window.localStorage.removeItem(_celebratedKey);
  }
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
    Scenario(
      id: 'ridge',
      name: 'WIDOWMAKER RIDGE',
      difficulty: 2,
      blurb: 'An impassable mountain wall splits the valleys — except at '
          'one high saddle. Climb the pass, or bore straight through.',
      facts: const ['START \$500', 'MAP 24×18', 'HIGH COUNTRY'],
      missions: [
        Mission(
            'link',
            'Link both valleys',
            (g) =>
                _routeVisits(g, (c) => c.x <= _ridgeWestMax) &&
                _routeVisits(g, (c) => c.x >= _ridgeEastMin)),
        Mission('summit', 'Serve the depot on the pass',
            (g) => _buildingServed(g, _ridgePassDepot)),
        Mission(
            'bore',
            'Send a train through a tunnel',
            (g) => g.trains.any(
                (t) => t.path?.any((st) => st.tunnelTo != null) ?? false)),
      ],
      build: _buildRidge,
    ),
    Scenario(
      id: 'archipelago',
      name: 'ARCHIPELAGO',
      difficulty: 3,
      blurb: 'Five islands, one lagoon, and almost no flat ground to '
          'spare. Bridge the narrows; fly the open water.',
      facts: const ['START \$600', 'MAP 28×18', 'OPEN WATER'],
      missions: [
        Mission('triad', 'Connect three islands',
            (g) => _islandsVisited(g) >= 3),
        Mission(
            'fullservice',
            'Serve a building on every island',
            (g) => _archIsles
                .skip(1) // the home island has only the terminus
                .every((isle) => _buildingServed(g, isle.building!))),
        Mission(
            'flotilla',
            'Run two trains at once, no wrecks',
            (g) =>
                g.trains.length >= 2 &&
                g.trains.every((t) => !t.wrecked && t.path != null)),
      ],
      build: _buildArchipelago,
    ),
    Scenario(
      id: 'switchback',
      name: 'SWITCHBACK PASS',
      difficulty: 3,
      blurb: 'A serpentine corridor between unclimbable walls — too tight '
          'to loop. Turntables, speed pads and nerve.',
      facts: const ['START \$700', 'MAP 24×16', 'SERPENTINE'],
      missions: [
        Mission('shuttle', 'Run a line off a turntable',
            (g) => _routeVisits(g, g.turntables.contains)),
        Mission(
            'flyer',
            'Clock a lap under 16s on 45+ track',
            (g) => g.lastLapSteps >= 45 && g.lastLapTime < 16),
        Mission(
            'convoy',
            'Bank 10 laps with two trains running, crash-free',
            (g) => g.dualLaps >= 10),
      ],
      build: _buildSwitchback,
    ),
    Scenario(
      id: 'folly',
      name: "TERRAFORMER'S FOLLY",
      difficulty: 3,
      blurb: 'Rumpled chaos split by a drowned scar. Blast it flat, loop '
          'it, or jump straight over.',
      facts: const ['START \$800', 'MAP 26×16', 'SCARRED LAND'],
      missions: [
        Mission('demolition', 'Reshape the world with 4 dynamite blasts',
            (g) => g.blastsFired >= 4),
        Mission('showman', 'Ride a loop-de-loop 5 times',
            (g) => g.loopsRidden >= 5),
        Mission('daredevil', 'Land 15 ramp jumps',
            (g) => g.jumpsMade >= 15),
      ],
      build: _buildFolly,
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
  Cell? trigger;
  for (final d in Dir.values) {
    final n = station.step(d);
    if (g.board.containsKey(n)) {
      trigger = n;
      break;
    }
  }
  g.buildings.add(Building(station, BuildingType.station, trigger));
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

/// Any traced route (including launchpad flights) touches the zone.
bool _routeVisits(Game g, bool Function(Cell) zone) {
  for (final tr in g.trains) {
    final p = tr.path;
    if (p == null) continue;
    for (final st in p) {
      if (zone(st.cell)) return true;
      final fly = st.flyTo;
      if (fly != null && zone(fly)) return true;
    }
  }
  return false;
}

/// The building at [at] exists, has a trigger, and some route passes it —
/// i.e. its bonus actually fires.
bool _buildingServed(Game g, Cell at) {
  for (final b in g.buildings) {
    if (b.cell != at) continue;
    final t = b.trigger;
    if (t == null) return false;
    return g.trains.any((tr) => tr.path?.any((st) => st.cell == t) ?? false);
  }
  return false;
}

// ---- Widowmaker Ridge: a 2-step wall, one saddle, one bore line.

const int _ridgeWestMax = 8; // west valley is x <= this
const int _ridgeEastMin = 15; // east valley is x >= this
const Cell _ridgePassDepot = Cell(11, 1);

void _buildRidge(Game g) {
  final rng = math.Random(7103);
  g.cols = 24;
  g.rows = 18;
  g.heights.reset(g.cols, g.rows);
  // The wall: vertex columns 11..13 rise 2/4/2, giving every face a
  // two-step jump no straight can climb — impassable, but borable
  // (portals sit flat at x=9 and x=14 with covered ground between).
  for (var vy = 0; vy <= g.rows; vy++) {
    g.heights.setVertex(11, vy, 2);
    g.heights.setVertex(12, vy, 4);
    g.heights.setVertex(13, vy, 2);
  }
  // The saddle: rows 1..3 drop the crest to a flat shelf at height 1,
  // reachable by ordinary one-step climbs from both sides.
  for (var vy = 1; vy <= 4; vy++) {
    g.heights.setVertex(11, vy, 1);
    g.heights.setVertex(12, vy, 1);
    g.heights.setVertex(13, vy, 1);
  }
  _hill(g, 4, 15, 2);
  _hill(g, 20, 15, 2);
  _loopWithStation(g, x0: 2, y0: 6, x1: 6, y1: 10, station: const Cell(4, 11));
  // The pass depot waits on the saddle shelf; the valley payouts wait east.
  g.buildings.add(Building(_ridgePassDepot, BuildingType.depot));
  g.buildings.add(Building(const Cell(18, 8), BuildingType.stop));
  g.buildings.add(Building(const Cell(20, 12), BuildingType.depot));
  _scatter(g, rng, 12, ok: (c) => c.x <= 8 || c.x >= 15);
  _dropCows(g, rng, 1);
  g.balance = 500;
}

// ---- Archipelago: five islands raised out of a drowned world.

class _Isle {
  final int x0, y0, x1, y1;
  final Cell? building;
  const _Isle(this.x0, this.y0, this.x1, this.y1, [this.building]);
  bool contains(Cell c) =>
      c.x >= x0 && c.x <= x1 && c.y >= y0 && c.y <= y1;
}

const List<_Isle> _archIsles = [
  _Isle(2, 6, 8, 11), // home — the terminus lives here
  _Isle(11, 4, 14, 8, Cell(12, 6)),
  _Isle(11, 12, 14, 15, Cell(12, 13)),
  _Isle(18, 2, 21, 5, Cell(19, 3)),
  _Isle(23, 10, 26, 14, Cell(24, 12)),
];

int _islandsVisited(Game g) {
  var n = 0;
  for (final isle in _archIsles) {
    if (_routeVisits(g, isle.contains)) n++;
  }
  return n;
}

void _buildArchipelago(Game g) {
  final rng = math.Random(7104);
  g.cols = 28;
  g.rows = 18;
  g.heights.reset(g.cols, g.rows);
  // Drown the world, then raise each island back to grade.
  for (var vx = 0; vx <= g.cols; vx++) {
    for (var vy = 0; vy <= g.rows; vy++) {
      g.heights.setVertex(vx, vy, -1);
    }
  }
  for (final isle in _archIsles) {
    for (var vx = isle.x0; vx <= isle.x1 + 1; vx++) {
      for (var vy = isle.y0; vy <= isle.y1 + 1; vy++) {
        g.heights.setVertex(vx, vy, 0);
      }
    }
  }
  _loopWithStation(g, x0: 3, y0: 7, x1: 7, y1: 10, station: const Cell(5, 6));
  for (final isle in _archIsles) {
    final b = isle.building;
    if (b == null) continue;
    final type =
        _archIsles.indexOf(isle).isEven ? BuildingType.depot : BuildingType.stop;
    g.buildings.add(Building(b, type));
  }
  _scatter(g, rng, 8, ok: (c) => _archIsles.any((i) => i.contains(c)));
  g.balance = 600;
}

// ---- Switchback Pass: a serpentine corridor between 3-step walls.

void _wallRow(Game g, int cellY, int x0, int x1) {
  for (var vx = x0; vx <= x1 + 1; vx++) {
    g.heights.setVertex(vx, cellY, 3);
    g.heights.setVertex(vx, cellY + 1, 3);
  }
}

void _buildSwitchback(Game g) {
  final rng = math.Random(7105);
  g.cols = 24;
  g.rows = 16;
  g.heights.reset(g.cols, g.rows);
  // Two wall bands force an S: south zone → east gap → middle zone →
  // west gap → north zone. Every wall face is a 3-step cliff.
  _wallRow(g, 10, 0, 18); // gap on the east
  _wallRow(g, 5, 5, 23); // gap on the west
  _loopWithStation(g, x0: 2, y0: 12, x1: 6, y1: 15, station: const Cell(7, 13));
  g.buildings.add(Building(const Cell(11, 7), BuildingType.stop));
  g.buildings.add(Building(const Cell(4, 2), BuildingType.depot));
  g.buildings.add(Building(const Cell(20, 2), BuildingType.stop));
  _scatter(g, rng, 10,
      ok: (c) => c.y != 5 && c.y != 10); // keep the walls bare
  _dropCows(g, rng, 2);
  g.balance = 700;
}

// ---- Terraformer's Folly: seeded chaos split by a drowned scar.

void _buildFolly(Game g) {
  final rng = math.Random(7106);
  g.cols = 26;
  g.rows = 16;
  g.heights.reset(g.cols, g.rows);
  // Rumple everything with seeded knolls and pits…
  for (var i = 0; i < 14; i++) {
    final vx = 1 + rng.nextInt(g.cols - 1);
    final vy = 1 + rng.nextInt(g.rows - 1);
    _hill(g, vx, vy, 1 + rng.nextInt(3));
  }
  for (var i = 0; i < 6; i++) {
    final vx = 1 + rng.nextInt(g.cols - 1);
    final vy = 1 + rng.nextInt(g.rows - 1);
    for (var dx = 0; dx <= 1; dx++) {
      for (var dy = 0; dy <= 1; dy++) {
        if (g.heights.vAt(vx + dx, vy + dy) <= 0) {
          g.heights.setVertex(vx + dx, vy + dy, -1);
        }
      }
    }
  }
  // …carve the scar: a drowned two-column gash down the middle…
  for (var vy = 0; vy <= g.rows; vy++) {
    g.heights.setVertex(12, vy, -3);
    g.heights.setVertex(13, vy, -3);
    g.heights.setVertex(14, vy, -3);
  }
  // …and press flat aprons for the starter loop and the far payouts.
  for (var vx = 1; vx <= 9; vx++) {
    for (var vy = 4; vy <= 11; vy++) {
      g.heights.setVertex(vx, vy, 0);
    }
  }
  for (var vx = 16; vx <= 23; vx++) {
    for (var vy = 2; vy <= 12; vy++) {
      g.heights.setVertex(vx, vy, 0);
    }
  }
  _loopWithStation(g, x0: 2, y0: 5, x1: 6, y1: 9, station: const Cell(4, 10));
  g.buildings.add(Building(const Cell(18, 4), BuildingType.stop));
  g.buildings.add(Building(const Cell(20, 10), BuildingType.depot));
  _scatter(g, rng, 8, ok: (c) => c.x <= 9 || c.x >= 16);
  g.balance = 800;
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
