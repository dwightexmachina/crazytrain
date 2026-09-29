import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:crazytrain/main.dart';
import 'package:crazytrain/model/game.dart';
import 'package:crazytrain/model/scenario.dart';
import 'package:crazytrain/model/track.dart';
import 'package:crazytrain/ui/board_view.dart';
import 'package:crazytrain/ui/painters.dart';

Game freshGame() {
  web.window.localStorage.clear();
  return Game();
}

/// A running game with no random terrain or elevation in the way.
Game flatGame() {
  final g = freshGame();
  g.newGame();
  g.heights.reset(g.cols, g.rows); // dry, flat plain — water is low ground now
  return g;
}

/// Boot the app, dismiss the splash, and board the sandbox from the map.
Future<void> enterSandbox(WidgetTester tester) async {
  web.window.localStorage.clear();
  await tester.pumpWidget(const TrainMakerApp());
  await tester.pump();
  await tester.tap(find.text('TAP TO ROLL'));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60)); // splash fade
  }
  await tester.tap(find.text('SANDBOX'));
  await tester.pump();
}

/// Sink one cell below the water table by hand.
void sink(Game g, Cell c) {
  for (final (vx, vy) in [(c.x, c.y), (c.x + 1, c.y), (c.x + 1, c.y + 1), (c.x, c.y + 1)]) {
    g.heights.setVertex(vx, vy, -1);
  }
}

void main() {
  group('planTrack', () {
    test('row drag lays EW straights, corners become curves', () {
      final g = flatGame();
      // Empty area above the starter loop: row 1.
      final plan = g.planTrack(const [Cell(4, 1), Cell(5, 1), Cell(6, 1)]);
      expect(plan.pieces.length, 3);
      expect(plan.pieces.every((p) => p.kind == TrackKind.ew), isTrue);
      expect(plan.cost, 30);

      final l = g.planTrack(
          const [Cell(4, 1), Cell(5, 1), Cell(5, 2), Cell(5, 2)]);
      expect(l.pieces[1].kind, TrackKind.sw); // corner: entered W, exits S
      expect(l.cost, 10 + 15 + 10);
    });

    test('drag endpoint on a column lays NS, matching track is free', () {
      final g = freshGame();
      g.newGame();
      g.bulldoze(const Cell(3, 4)); // knock a hole in the left column
      expect(g.path, isNull);
      final plan = g.planTrack(const [Cell(3, 4), Cell(3, 5)]);
      expect(plan.pieces.first.kind, TrackKind.ns);
      expect(plan.pieces.first.cost, 10);
      expect(plan.pieces.last.cost, 0); // existing matching piece
      g.commitTrack(plan);
      expect(g.path, isNotNull);
      expect(g.path!.length, 28);
    });

    test('bridge decks carry the bank grade over water, with surcharge', () {
      final g = flatGame();
      g.balance = 1000;
      sink(g, const Cell(5, 1));
      // Cells sharing the sunken corners are wet too.
      expect(g.isWater(const Cell(5, 1)), isTrue);
      expect(g.isWater(const Cell(4, 1)), isTrue);
      expect(g.isWater(const Cell(6, 1)), isTrue);
      final plan = g.planTrack(
          const [Cell(3, 1), Cell(4, 1), Cell(5, 1), Cell(6, 1)]);
      expect(plan.pieces.length, 4);
      expect(plan.cost, 10 + 35 + 35 + 35);
      expect(plan.pieces[1].bridge, isTrue);
      expect(plan.pieces[2].deckLevel, 0); // deck holds the bank grade
      g.commitTrack(plan);
      expect(g.deck[const Cell(5, 1)], 0);
      expect(g.deck.containsKey(const Cell(3, 1)), isFalse); // dry approach
      // A drag can't begin over open water.
      final fromWater = g.planTrack(const [Cell(5, 0), Cell(6, 0)]);
      expect(fromWater.isEmpty, isTrue);
    });
  });

  group('water table', () {
    test('lowering land floods it; raising the bed drains it', () {
      final g = flatGame();
      g.balance = 1000;
      const cell = Cell(6, 1);
      expect(g.isWater(cell), isFalse);
      expect(g.sculpt(cell, const Offset(0.2, 0.2), -1), isNull); // vertex (6,1)
      expect(g.isWater(cell), isTrue);
      expect(g.isWater(const Cell(5, 0)), isTrue); // shares the sunken corner
      expect(g.sculpt(cell, const Offset(0.2, 0.2), 1), isNull);
      expect(g.isWater(cell), isFalse);
    });

    test('new maps generate water below the table and some elevation', () {
      final g = freshGame();
      g.newGame();
      expect(g.heights.toList().any((h) => h < 0), isTrue);
      expect(g.heights.toList().any((h) => h > 0), isTrue);
    });
  });

  group('heightfield', () {
    test('sculpting raises a vertex, blocks side-sloped rail, charges', () {
      final g = flatGame();
      g.balance = 1000;
      // Raise the vertex at (7,1): cells (6..7, 0..1) become sloped.
      expect(g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), 1), isNull);
      expect(g.heights.vAt(7, 1), 1);
      expect(g.balance, 1000 - Game.priceTerraformStep);
      expect(g.heights.isFlat(const Cell(6, 1)), isFalse);
      // The lone vertex makes (6,1) side-sloped: rail stops short of it.
      final plan = g.planTrack(const [Cell(4, 1), Cell(5, 1), Cell(6, 1)]);
      expect(plan.pieces.length, 2);
      // Lowering it back flattens the ground again.
      expect(g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), -1), isNull);
      expect(g.heights.isFlat(const Cell(6, 1)), isTrue);
    });

    test('the cascade smooths tall peaks and prices every moved step', () {
      final g = flatGame();
      g.balance = 100000;
      // Vertex (8,0): the board's top edge, two clear vertices from any track.
      const frac = Offset(0.2, 0.2);
      expect(g.sculpt(const Cell(8, 0), frac, 1), isNull);
      expect(g.sculpt(const Cell(8, 0), frac, 1), isNull);
      expect(g.heights.vAt(8, 0), 2);
      expect(g.heights.vAt(7, 0), 1); // ring pulled up by the second step
      final before = g.balance;
      expect(g.sculpt(const Cell(8, 0), frac, 1), isNull); // drags two rings
      expect(g.heights.vAt(8, 0), 3);
      expect(g.heights.vAt(7, 1), 2);
      expect(g.heights.vAt(6, 0), 1);
      // The whole cascade was priced, not just the primary vertex.
      expect(before - g.balance, greaterThan(Game.priceTerraformStep));
    });

    test('terrain under track never moves; water sculpts freely', () {
      final g = flatGame();
      g.balance = 1000;
      final trackCell = g.board.keys.first;
      expect(g.sculpt(trackCell, const Offset(0.2, 0.2), 1),
          "Can't reshape under track or buildings");
      // Open water is just low ground — raising its bed is allowed.
      sink(g, const Cell(1, 1));
      expect(g.sculpt(const Cell(1, 1), const Offset(0.2, 0.2), 1), isNull);
    });

    test('straight rail climbs a one-step ramp onto a plateau', () {
      final g = flatGame();
      g.balance = 100000;
      // Build a one-step plateau covering cells around (5,1)..(6,1).
      for (final v in const [(5, 1), (6, 1), (5, 2), (6, 2)]) {
        g.sculpt(Cell(v.$1, v.$2), const Offset(0.2, 0.2), 1);
      }
      expect(g.heights.isFlat(const Cell(5, 1)), isTrue);
      expect(g.heights.floorOf(const Cell(5, 1)), 1);
      // Flat approach, graded ramp cell, flat summit: all three lay.
      final plan =
          g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(5, 1)]);
      expect(plan.pieces.length, 3);
      g.commitTrack(plan);
      // The ramp's rail rises from its west edge to its east edge.
      expect(g.railEdgeZ(const Cell(4, 1), Dir.w), 0);
      expect(g.railEdgeZ(const Cell(4, 1), Dir.e), 1);
      // Climbing costs time; coasting down gives it back; flat is neutral.
      expect(g.stepCost(PathStep(const Cell(4, 1), Dir.w, Dir.e)), 1.35);
      expect(g.stepCost(PathStep(const Cell(4, 1), Dir.e, Dir.w)), 0.75);
      expect(g.stepCost(PathStep(const Cell(3, 1), Dir.w, Dir.e)), 1);
      // A graded piece can't become a switch.
      expect(g.tapSwitch(const Cell(4, 1)), 'Switches need flat ground');
    });

    test('curves, side-slopes and cliffs refuse rail', () {
      final g = flatGame();
      g.balance = 100000;
      for (final v in const [(5, 1), (6, 1), (5, 2), (6, 2)]) {
        g.sculpt(Cell(v.$1, v.$2), const Offset(0.2, 0.2), 1);
      }
      // A curve landing on the ramp cell breaks the run.
      final curve = g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(4, 2)]);
      expect(curve.pieces.length, 1);
      // Travelling across the slope (side-slope under the rail) refuses.
      final side = g.planTrack(const [Cell(4, 0), Cell(5, 0), Cell(6, 0)]);
      expect(side.isEmpty, isTrue);
      // A two-step cliff is too steep to climb.
      g.heights.setVertex(9, 1, 2);
      g.heights.setVertex(9, 2, 2);
      final cliff = g.planTrack(const [Cell(7, 1), Cell(8, 1)]);
      expect(cliff.pieces.length, 1);
    });

    test('level tool matches dragged cells to the pressed grade', () {
      final g = flatGame();
      g.balance = 100000;
      // A one-step plateau at (5..6, 1..2).
      for (final vtx in const [(5, 1), (6, 1), (5, 2), (6, 2)]) {
        g.sculpt(Cell(vtx.$1, vtx.$2), const Offset(0.2, 0.2), 1);
      }
      // Press flat ground: grade 0. Level the plateau cell down to it.
      g.armLevel(const Cell(3, 1));
      expect(g.levelTarget, 0);
      final before = g.balance;
      expect(g.levelTo(const Cell(5, 1)), isNull);
      expect(g.heights.isFlat(const Cell(5, 1)), isTrue);
      expect(g.heights.floorOf(const Cell(5, 1)), 0);
      expect(before - g.balance, greaterThan(0));
      // Press the remaining raised ground and pull flat land up to it.
      g.armLevel(const Cell(1, 8));
      expect(g.levelTarget, 0);
      // Leveling a cell pinned by track fails cleanly and rolls back.
      g.levelTarget = 1;
      final snapshot = g.heights.toList();
      final trackCell = g.board.keys.first;
      expect(g.levelTo(trackCell), "Can't level under track or buildings");
      expect(g.heights.toList(), snapshot);
    });

    test('v2 mountains migrate into raised peaks', () {
      web.window.localStorage.clear();
      web.window.localStorage.setItem(
        'ct_save_v2',
        '{"board":{"4,1":0,"5,1":0},'
            '"buildings":[{"x":4,"y":2,"t":0}],'
            '"terrain":{"9,8":"mountain","2,2":"water"},'
            '"cows":[],"balance":500,"cars":1}',
      );
      final g = Game();
      // The water cell sank below the table...
      expect(g.isWater(const Cell(2, 2)), isTrue);
      expect(g.heights.vAt(2, 2), -1);
      // ...and the mountain rose into the heightfield.
      expect(g.heights.vAt(9, 8), 2);
      expect(g.heights.vAt(10, 9), 2);
    });

    test('heights persist across reload', () {
      final g = flatGame();
      g.balance = 1000;
      expect(g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), 1), isNull);
      final saved = g.heights.toList();
      expect(saved.any((h) => h > 0), isTrue);
      final g2 = Game();
      expect(g2.heights.toList(), saved);
    });
  });

  group('launchpads', () {
    test('traceLoop flies the gap between a linked pad pair', () {
      // Rectangle loop 2..8 x 2..6 with the top edge broken at x=4..6;
      // pads at (4,2) and (6,2) fly the train over the hole at (5,2).
      final board = <Cell, TrackKind>{};
      for (var x = 3; x <= 7; x++) {
        board[Cell(x, 2)] = TrackKind.ew;
        board[Cell(x, 6)] = TrackKind.ew;
      }
      for (var y = 3; y <= 5; y++) {
        board[Cell(2, y)] = TrackKind.ns;
        board[Cell(8, y)] = TrackKind.ns;
      }
      board[const Cell(2, 2)] = TrackKind.se;
      board[const Cell(8, 2)] = TrackKind.sw;
      board[const Cell(8, 6)] = TrackKind.nw;
      board[const Cell(2, 6)] = TrackKind.ne;
      board.remove(const Cell(4, 2));
      board.remove(const Cell(5, 2));
      board.remove(const Cell(6, 2));

      expect(traceLoop(board, const Cell(3, 2), Dir.e), isNull);

      final pads = {
        const Cell(4, 2): const Cell(6, 2),
        const Cell(6, 2): const Cell(4, 2),
      };
      final path = traceLoop(board, const Cell(3, 2), Dir.e, pads: pads);
      expect(path, isNotNull);
      final flight = path!.where((s) => s.flyTo != null).toList();
      expect(flight.length, 1);
      expect(flight.single.cell, const Cell(4, 2));
      expect(flight.single.flyTo, const Cell(6, 2));
      expect(flight.single.flightZ(0.5), greaterThan(0));
      expect(flight.single.flightZ(0), 0);
    });

    test('site validators drive placement tints', () {
      final g = flatGame();
      g.balance = 1000;
      // Building: needs dry, clear ground beside track.
      expect(g.buildingSiteError(const Cell(7, 2)), isNull); // beside loop
      expect(g.buildingSiteError(const Cell(1, 1)), 'Must touch track');
      expect(g.buildingSiteError(g.board.keys.first), 'Cell occupied');
      // Pad: clear flat ground anywhere.
      expect(g.padSiteError(const Cell(1, 1)), isNull);
      expect(g.padSiteError(g.board.keys.first), 'Remove the track first');
      sink(g, const Cell(1, 8));
      expect(g.padSiteError(const Cell(1, 8)), "Can't float on water");
      // Portal: same idea.
      expect(g.portalSiteError(const Cell(9, 1)), isNull);
      expect(g.portalSiteError(const Cell(1, 8)), "Can't bore from water");
    });

    test('two-tap placement links a pair and charges once', () {
      final g = flatGame();
      g.balance = 1000;
      expect(g.tapLaunchpad(const Cell(4, 1)), isNull);
      expect(g.pendingPad, const Cell(4, 1));
      expect(g.balance, 1000); // armed, not yet charged
      expect(g.tapLaunchpad(const Cell(9, 1)), isNull);
      expect(g.pendingPad, isNull);
      expect(g.balance, 1000 - Game.priceLaunchpad);
      expect(g.launchpads[const Cell(4, 1)], const Cell(9, 1));
      expect(g.launchpads[const Cell(9, 1)], const Cell(4, 1));
      // Occupied cells refuse pads; tapping the armed pad cancels it.
      expect(g.tapLaunchpad(const Cell(4, 1)), 'Already a launchpad');
      expect(g.tapLaunchpad(g.board.keys.first), 'Remove the track first');
    });

    test('bulldozing one pad removes the pair with a half refund', () {
      final g = flatGame();
      g.balance = 1000;
      g.tapLaunchpad(const Cell(4, 1));
      g.tapLaunchpad(const Cell(9, 1));
      final before = g.balance;
      g.bulldoze(const Cell(9, 1));
      expect(g.launchpads, isEmpty);
      expect(g.balance, before + Game.priceLaunchpad ~/ 2);
    });

    test('pad pairs persist across reload', () {
      final g = flatGame();
      g.balance = 1000;
      g.tapLaunchpad(const Cell(4, 1));
      g.tapLaunchpad(const Cell(9, 1));
      final g2 = Game();
      expect(g2.launchpads[const Cell(4, 1)], const Cell(9, 1));
      expect(g2.launchpads[const Cell(9, 1)], const Cell(4, 1));
    });
  });

  group('switches', () {
    // Rectangle loop 2..8 x 2..6 with turnouts at (5,2) and (5,6) and a
    // connecting column at x=5: flipping the bottom switch picks between
    // the west return and a dead-end wander east.
    Map<Cell, TrackKind> rectWithGap() {
      final board = <Cell, TrackKind>{};
      for (var x = 3; x <= 7; x++) {
        board[Cell(x, 2)] = TrackKind.ew;
        board[Cell(x, 6)] = TrackKind.ew;
      }
      for (var y = 3; y <= 5; y++) {
        board[Cell(2, y)] = TrackKind.ns;
        board[Cell(8, y)] = TrackKind.ns;
        board[Cell(5, y)] = TrackKind.ns;
      }
      board[const Cell(2, 2)] = TrackKind.se;
      board[const Cell(8, 2)] = TrackKind.sw;
      board[const Cell(8, 6)] = TrackKind.nw;
      board[const Cell(2, 6)] = TrackKind.ne;
      board.remove(const Cell(5, 2));
      board.remove(const Cell(5, 6));
      return board;
    }

    test('routing: trailing merges, thrown route picks the exit', () {
      final board = rectWithGap();
      final sw1 = TrackSwitch(const Cell(5, 2), Dir.s, Dir.e, Dir.w);
      final sw2 = TrackSwitch(const Cell(5, 6), Dir.n, Dir.e, Dir.w);
      final switches = {sw1.cell: sw1, sw2.cell: sw2};

      // Points at branch E: the walk wanders and never closes.
      expect(traceLoop(board, const Cell(3, 2), Dir.e, switches: switches),
          isNull);

      // Throw the bottom switch to branch W: the loop closes in 14 steps.
      sw2.useB = true;
      final path =
          traceLoop(board, const Cell(3, 2), Dir.e, switches: switches);
      expect(path, isNotNull);
      expect(path!.length, 14);
      // The trailing move into sw1 merged onto its base leg (south).
      final atSw1 = path.firstWhere((s) => s.cell == const Cell(5, 2));
      expect(atSw1.exit, Dir.s);
    });

    test('two-tap placement converts track, charges, and validates sides',
        () {
      final g = flatGame();
      g.balance = 1000;
      const target = Cell(5, 3); // ew piece on the starter loop's top edge
      expect(g.board[target], TrackKind.ew);
      expect(g.tapSwitch(target), isNull);
      expect(g.pendingSwitch, target);
      // Connected side and non-adjacent taps are rejected, pad stays armed.
      expect(g.tapSwitch(const Cell(6, 3)), 'The junction must face a free side');
      expect(g.tapSwitch(const Cell(9, 9)), 'Tap a cell beside the armed track piece');
      expect(g.pendingSwitch, target);
      // Free side completes the turnout.
      expect(g.tapSwitch(const Cell(5, 2)), isNull);
      expect(g.balance, 1000 - Game.priceSwitch);
      expect(g.board.containsKey(target), isFalse);
      final sw = g.switches[target]!;
      expect(sw.base, Dir.n);
      expect({sw.branchA, sw.branchB}, {Dir.e, Dir.w});
      // The old through-route is gone, so the starter loop is broken.
      expect(g.path, isNull);
    });

    test('toggle flips the points; bulldoze refunds half', () {
      final g = flatGame();
      g.balance = 1000;
      g.tapSwitch(const Cell(5, 3));
      g.tapSwitch(const Cell(5, 2));
      final sw = g.switches[const Cell(5, 3)]!;
      expect(sw.useB, isFalse);
      g.toggleSwitch(const Cell(5, 3));
      expect(sw.useB, isTrue);
      final before = g.balance;
      g.bulldoze(const Cell(5, 3));
      expect(g.switches, isEmpty);
      expect(g.balance, before + Game.priceSwitch ~/ 2);
    });

    test('switches persist with their state', () {
      final g = flatGame();
      g.balance = 1000;
      g.tapSwitch(const Cell(5, 3));
      g.tapSwitch(const Cell(5, 2));
      g.toggleSwitch(const Cell(5, 3));
      final g2 = Game();
      final sw = g2.switches[const Cell(5, 3)]!;
      expect(sw.base, Dir.n);
      expect(sw.useB, isTrue);
    });
  });

  group('auto-flatten & generation', () {
    test('buildings level an uneven site and charge for the earthworks', () {
      final g = flatGame();
      g.balance = 1000;
      // Vertex (7,2) is free ground; raising it makes cell (7,2) uneven.
      expect(g.sculpt(const Cell(6, 1), const Offset(0.9, 0.9), 1), isNull);
      expect(g.heights.vAt(7, 2), 1);
      expect(g.heights.isFlat(const Cell(7, 2)), isFalse);
      final before = g.balance;
      // (7,2) touches the starter loop's top edge at (7,3).
      expect(g.placeBuilding(BuildingType.stop, const Cell(7, 2)), isNull);
      expect(g.heights.isFlat(const Cell(7, 2)), isTrue);
      expect(before - g.balance,
          BuildingType.stop.price + Game.priceTerraformStep);
      expect(g.buildings.any((b) => b.cell == const Cell(7, 2)), isTrue);
    });

    test('flattening refuses when a locked corner must move, and restores',
        () {
      final g = flatGame();
      g.balance = 1000;
      // Vertex (7,3) belongs to track cells: hand-raise it so the site is
      // uneven but only fixable by moving locked ground.
      g.heights.setVertex(7, 3, 1);
      final snapshot = g.heights.toList();
      final before = g.balance;
      expect(g.placeBuilding(BuildingType.stop, const Cell(7, 2)),
          "Can't level this ground");
      expect(g.heights.toList(), snapshot);
      expect(g.balance, before);
    });

    test('new maps grow taller hills and map-owned trees that persist', () {
      final g = freshGame();
      g.newGame();
      expect(g.heights.toList().any((h) => h >= 2), isTrue);
      expect(g.trees, isNotEmpty);
      final treesBefore = List.of(g.trees);
      final g2 = Game();
      expect(g2.trees, treesBefore);
    });
  });

  group('land deeds', () {
    test('east deed grows the board, charges, and escalates the price', () {
      final g = freshGame();
      g.newGame();
      g.balance = 5000;
      final c0 = g.cols;
      final p0 = g.deedPrice;
      expect(g.buyLand(Dir.e), isTrue);
      expect(g.cols, c0 + Game.expandStep);
      expect(g.rows, Game.startRows);
      expect(g.balance, 5000 - p0);
      expect(g.deedPrice, greaterThan(p0));
      // The frontier is buildable.
      g.heights.reset(g.cols, g.rows);
      final plan =
          g.planTrack([Cell(c0, 1), Cell(c0 + 1, 1), Cell(c0 + 2, 1)]);
      expect(plan.pieces.length, 3);
    });

    test('south deed grows rows; expansion caps at the max size', () {
      final g = freshGame();
      g.newGame();
      g.balance = 1000000;
      expect(g.buyLand(Dir.s), isTrue);
      expect(g.rows, Game.startRows + Game.expandStep);
      while (g.buyLand(Dir.e)) {}
      while (g.buyLand(Dir.s)) {}
      expect(g.cols, Game.maxCols);
      expect(g.rows, Game.maxRows);
      expect(g.canGrow(Dir.e), isFalse);
      expect(g.canGrow(Dir.w), isFalse);
      expect(g.canGrow(Dir.s), isFalse);
      expect(g.canGrow(Dir.n), isFalse);
    });

    test('north and west deeds shift the whole world intact', () {
      final g = flatGame();
      g.balance = 100000;
      g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), 1); // vertex (7,1)
      final station0 = g.station.cell;
      final trackCell = g.board.keys.first;
      final kind = g.board[trackCell];
      expect(g.path, isNotNull);
      expect(g.buyLand(Dir.w), isTrue);
      expect(g.cols, Game.startCols + Game.expandStep);
      expect(g.board[Cell(trackCell.x + 4, trackCell.y)], kind);
      expect(g.station.cell, Cell(station0.x + 4, station0.y));
      // The sculpted vertex moved along (fresh frontier terrain may pile
      // its own cascade on top, so at-least rather than exactly).
      expect(g.heights.vAt(7 + 4, 1), greaterThanOrEqualTo(1));
      expect(g.path, isNotNull); // the loop survived the move
      expect(g.buyLand(Dir.n), isTrue);
      expect(g.station.cell, Cell(station0.x + 4, station0.y + 4));
      expect(g.path, isNotNull);
    });

    test('board size and deed count persist', () {
      final g = freshGame();
      g.newGame();
      g.balance = 5000;
      g.buyLand(Dir.e);
      g.buyLand(Dir.s);
      final g2 = Game();
      expect(g2.cols, Game.startCols + Game.expandStep);
      expect(g2.rows, Game.startRows + Game.expandStep);
      expect(g2.deeds, 2);
      expect(g2.deedPrice, g.deedPrice);
    });
  });

  group('persistence', () {
    test('v1 save migrates: ponds sink below the table, key upgrades', () {
      web.window.localStorage.clear();
      web.window.localStorage.setItem(
        'ct_save_v1',
        '{"board":{"4,1":0,"5,1":0},'
            '"buildings":[{"x":4,"y":2,"t":0}],'
            '"ponds":["5,1","8,8"],"cows":[],"balance":123,"cars":2}',
      );
      final g = Game();
      expect(g.isWater(const Cell(5, 1)), isTrue);
      expect(g.isWater(const Cell(8, 8)), isTrue);
      // The old plank bridge at (5,1) kept its grade as a deck.
      expect(g.deck[const Cell(5, 1)], 0);
      expect(g.balance, 123);
      expect(g.cars, 2);
      expect(web.window.localStorage.getItem('ct_save_v1'), isNull);
      expect(web.window.localStorage.getItem('ct_save_v3'), isNotNull);
    });

    test('round-trip preserves water and decks', () {
      final g = flatGame();
      sink(g, const Cell(5, 1));
      g.commitTrack(
          g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(5, 1), Cell(6, 1)]));
      expect(g.deck, isNotEmpty);
      final g2 = Game(); // loads what commitTrack saved
      expect(g2.heights.toList(), g.heights.toList());
      expect(g2.deck, g.deck);
      expect(g2.isWater(const Cell(5, 1)), isTrue);
    });
  });

  group('sim', () {
    test('train pays cars x track per lap', () {
      final g = freshGame();
      g.newGame();
      g.cows.clear();
      final before = g.balance;
      g.speed = 1;
      g.tick(28 / Game.tilesPerSecond + 0.1); // one full lap
      expect(g.balance, before + 28);
    });

    test('cow on the line halts the train; honk shoos it', () {
      final g = freshGame();
      g.newGame();
      g.cows.clear();
      final target = g.path![3].cell;
      final cow = Cow(target, 9999);
      g.cows.add(cow);
      g.tick(5);
      expect(g.cowBlocked, isTrue);
      expect(g.s, lessThan(4));
      final blockedS = g.s;
      g.tick(3);
      expect(g.s, blockedS); // pinned behind the cow
      g.honk(); // engine is adjacent: cow bolts far away
      expect(cow.cell, isNot(target));
      g.tick(1);
      expect(g.cowBlocked, isFalse);
      expect(g.s, greaterThan(blockedS));
    });
  });

  group('tool selection', () {
    testWidgets('splash shows on boot and a tap rolls to the route map',
        (tester) async {
      web.window.localStorage.clear();
      await tester.pumpWidget(const TrainMakerApp());
      await tester.pump();
      expect(find.text('CRAZY TRAIN'), findsWidgets); // wordmark layers
      await tester.tap(find.text('TAP TO ROLL'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60)); // fade out
      }
      expect(find.text('TAP TO ROLL'), findsNothing);
      expect(find.text('CHOOSE YOUR LINE'), findsOneWidget);
    });

    testWidgets('Esc deselects the active tool', (tester) async {
      await enterSandbox(tester);
      final view =
          tester.widget<BoardView>(find.byType(BoardView));
      view.game.setTool(Tool.track);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(view.game.tool, Tool.none);
    });

    testWidgets('the "=" / "+" dev cheat grants money by character',
        (tester) async {
      await enterSandbox(tester);
      final game = tester.widget<BoardView>(find.byType(BoardView)).game;
      final before = game.balance;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.equal, character: '=');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
      expect(game.balance, before + 200);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.equal, character: '+');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.equal);
      expect(game.balance, before + 400);
    });
  });

  group('tunnels', () {
    /// A one-cell ridge between (5,1) and (8,1): vertices (7,1),(7,2) raised.
    Game ridgeGame() {
      final g = flatGame();
      g.balance = 100000;
      g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), 1); // vertex (7,1)
      g.sculpt(const Cell(6, 1), const Offset(0.9, 0.9), 1); // vertex (7,2)
      return g;
    }

    test('two-tap boring links portals through covered ground', () {
      final g = ridgeGame();
      final before = g.balance;
      expect(g.tapTunnel(const Cell(5, 1)), isNull);
      expect(g.pendingTunnel, const Cell(5, 1));
      expect(g.tapTunnel(const Cell(8, 1)), isNull);
      expect(g.tunnels[const Cell(5, 1)], const Cell(8, 1));
      expect(g.tunnels[const Cell(8, 1)], const Cell(5, 1));
      expect(before - g.balance, Game.priceTunnel);
    });

    test('boring validates alignment, spacing and cover', () {
      final g = ridgeGame();
      g.tapTunnel(const Cell(5, 1));
      expect(g.tapTunnel(const Cell(9, 0)), 'Portals must line up');
      expect(g.tapTunnel(const Cell(6, 1)), 'Portals need flat ground');
      expect(g.tapTunnel(const Cell(3, 1)),
          'No mountain to bore through'); // open ground west of the portal
      // boreError powers the live preview: green means it would link.
      expect(g.boreError(const Cell(5, 1), const Cell(8, 1)), isNull);
      expect(g.boreError(const Cell(5, 1), const Cell(9, 0)), isNotNull);
    });

    test('traceLoop dives through a portal pair, sideways entry derails', () {
      final board = <Cell, TrackKind>{};
      for (var x = 3; x <= 7; x++) {
        board[Cell(x, 2)] = TrackKind.ew;
        board[Cell(x, 6)] = TrackKind.ew;
      }
      for (var y = 3; y <= 5; y++) {
        board[Cell(2, y)] = TrackKind.ns;
        board[Cell(8, y)] = TrackKind.ns;
      }
      board[const Cell(2, 2)] = TrackKind.se;
      board[const Cell(8, 2)] = TrackKind.sw;
      board[const Cell(8, 6)] = TrackKind.nw;
      board[const Cell(2, 6)] = TrackKind.ne;
      board.remove(const Cell(4, 2));
      board.remove(const Cell(5, 2));
      board.remove(const Cell(6, 2));
      final bores = {
        const Cell(4, 2): const Cell(6, 2),
        const Cell(6, 2): const Cell(4, 2),
      };
      final path = traceLoop(board, const Cell(3, 2), Dir.e, tunnels: bores);
      expect(path, isNotNull);
      expect(path!.where((s) => s.tunnelTo != null).length, 1);
      // Approaching a portal perpendicular to its axis breaks the loop.
      final sideways = {
        const Cell(4, 2): const Cell(4, 5),
        const Cell(4, 5): const Cell(4, 2),
      };
      expect(traceLoop(board, const Cell(3, 2), Dir.e, tunnels: sideways),
          isNull);
    });

    test('stripping the cover collapses the tunnel', () {
      final g = ridgeGame();
      g.tapTunnel(const Cell(5, 1));
      g.tapTunnel(const Cell(8, 1));
      expect(g.tunnels, isNotEmpty);
      // Lower the ridge back down: the bore loses its roof.
      g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), -1);
      g.sculpt(const Cell(6, 1), const Offset(0.9, 0.9), -1);
      expect(g.tunnels, isEmpty);
    });

    test('drag endpoints snap into portal mouths and track ends', () {
      final g = ridgeGame();
      g.tapTunnel(const Cell(5, 1));
      g.tapTunnel(const Cell(8, 1));
      // Approaching the west portal from the north: the endpoint curves
      // east into its mouth instead of defaulting to a NS straight.
      final toPortal = g.planTrack(const [Cell(4, 0), Cell(4, 1)]);
      expect(toPortal.pieces.last.kind, TrackKind.ne);
      // A lone tap beside the mouth aligns to it.
      final tap = g.planTrack(const [Cell(4, 1)]);
      expect(tap.pieces.single.kind, TrackKind.ew);
      // Plain track connects the same way: build a NS stub, then a drag
      // ending beside its open end curves into it...
      g.commitTrack(g.planTrack(const [Cell(11, 0), Cell(11, 1)]));
      final joint = g.planTrack(const [Cell(9, 2), Cell(10, 2), Cell(11, 2)]);
      expect(joint.pieces.last.kind, TrackKind.nw);
      // ...and a tap below the stub aligns NS rather than the EW default.
      final below = g.planTrack(const [Cell(11, 2)]);
      expect(below.pieces.single.kind, TrackKind.ns);
    });

    test('portal pairs persist across reload', () {
      final g = ridgeGame();
      g.tapTunnel(const Cell(5, 1));
      g.tapTunnel(const Cell(8, 1));
      final g2 = Game();
      expect(g2.tunnels[const Cell(5, 1)], const Cell(8, 1));
    });
  });

  group('second train & signals', () {
    test('second train traces the loop in reverse and both trains pay', () {
      final g = flatGame();
      g.balance = 5000;
      g.cows.clear();
      expect(g.buySecondTrain(), isTrue);
      expect(g.trains.length, 2);
      final t1 = g.trains[0], t2 = g.trains[1];
      expect(t2.path, isNotNull);
      // Same circuit, opposite direction: step 0's exits disagree.
      expect(t1.path!.first.exit, isNot(t2.path!.first.exit));
      expect(t2.s, t2.path!.length / 2); // spawns across the loop
      g.speed = 1;
      g.tick(28 / Game.tilesPerSecond + 0.2); // one full lap for both
      // Opposite trains on a plain loop must meet head-on and crash.
      expect(g.trains.every((t) => t.wrecked), isTrue);
      // Tap the wreck: pays the crane, re-rails, separates.
      final wreckCell = g.occupiedBy(t1).first;
      final bal = g.balance;
      expect(g.tapWreck(wreckCell), isNull);
      expect(g.balance, bal - Game.priceRerail);
      expect(g.trains.any((t) => t.wrecked), isFalse);
    });

    test('a signal holds a train while the block ahead is occupied', () {
      final g = flatGame();
      g.balance = 5000;
      g.cows.clear();
      g.speed = 1;
      // Park a phantom second train ahead on the loop, then signal the
      // boundary: train 1 must stop at the red instead of rear-ending it.
      g.buySecondTrain();
      final t1 = g.trains[0], t2 = g.trains[1];
      t2.wrecked = true; // hold it still as the obstacle
      final p1 = t1.path!;
      // Choose a signal three steps ahead of train 1; park t2 just beyond.
      final sigCell = p1[3].cell;
      g.signals.add(sigCell);
      // Park the obstacle inside the signal's block, on train 1's frame.
      t2.lastPath = p1;
      t2.path = p1;
      t2.s = 5.0;
      g.tick(10); // plenty of time to reach the signal
      expect(t1.s, lessThan(3.0)); // held before entering the signal cell
      expect(g.heldSignals.contains(sigCell), isTrue);
      expect(t1.wrecked, isFalse);
      // Clear the block: the obstacle vanishes, the train proceeds.
      g.trains.removeLast();
      g.tick(2);
      expect(t1.s, greaterThan(3.0));
    });

    test('armed second train spawns where the line is tapped', () {
      final g = flatGame();
      g.balance = 5000;
      expect(g.armSecondTrain(), isNull);
      expect(g.placingTrain, isTrue);
      expect(g.spawnCells, isNotEmpty);
      expect(g.placeSecondTrain(const Cell(1, 1)), 'Tap a cell on the line');
      final spot = g.spawnCells.first;
      expect(g.placeSecondTrain(spot), isNull);
      expect(g.placingTrain, isFalse);
      expect(g.trains.length, 2);
      expect(g.balance, 5000 - Game.priceSecondTrain);
      final t2 = g.trains[1];
      expect(t2.path![t2.s.floor() % t2.path!.length].cell, spot);
    });

    test('bulldozing an engine scraps the train, but never the last one', () {
      final g = flatGame();
      g.balance = 5000;
      g.cows.clear();
      g.speed = 0;
      // The last train is protected.
      final t1Engine = g.trainEngineAt(g.path!.first.cell) == null
          ? g.path![g.s.floor() % g.path!.length].cell
          : g.path!.first.cell;
      final only = g.trains.length;
      g.bulldoze(g.path![g.s.floor() % g.path!.length].cell);
      expect(g.trains.length, only);
      // With two trains, tapping the second engine scraps it with refund.
      g.buySecondTrain();
      final t2 = g.trains[1];
      t2.cars = 3;
      final engineCell = t2.renderPath![t2.s.floor() % t2.renderPath!.length].cell;
      final bal = g.balance;
      g.bulldoze(engineCell);
      expect(g.trains.length, 1);
      expect(g.balance,
          bal + Game.priceSecondTrain ~/ 2 + 3 * (Game.priceCar ~/ 2));
      // Drags never scrap.
      g.buySecondTrain();
      final t3 = g.trains[1];
      final e3 = t3.renderPath![t3.s.floor() % t3.renderPath!.length].cell;
      g.bulldoze(e3, scrapTrains: false);
      expect(g.trains.length, 2);
      expect(t1Engine, isNotNull);
    });

    test('signals toggle on track only and persist', () {
      final g = flatGame();
      g.balance = 1000;
      expect(g.tapSignal(const Cell(1, 1)), 'Signals sit on track');
      final trackCell = g.board.keys.first;
      expect(g.tapSignal(trackCell), isNull);
      expect(g.signals.contains(trackCell), isTrue);
      final g2 = Game();
      expect(g2.signals.contains(trackCell), isTrue);
      expect(g2.trains.length, 1);
      // Removing refunds half.
      final bal = g.balance;
      expect(g.tapSignal(trackCell), isNull);
      expect(g.balance, bal + Game.priceSignal ~/ 2);
    });
  });

  group('camera', () {
    test('cellAt round-trips cell centers under every rotation', () {
      final g = flatGame();
      g.balance = 1000;
      // Include some elevation so picking isn't trivially planar.
      g.sculpt(const Cell(8, 0), const Offset(0.2, 0.2), 1);
      const size = Size(900, 700);
      for (var rot = 0; rot < 4; rot++) {
        final v = IsoView.fit(size, g, rot: rot);
        for (final cell in const [Cell(0, 0), Cell(5, 3), Cell(15, 11)]) {
          final z = g.heights.centerZ(cell) * kZStep;
          final screen = v.pt(cell.x + 0.5, cell.y + 0.5, z);
          expect(v.cellAt(screen), cell, reason: 'rot $rot, $cell');
        }
      }
    });
  });

  group('board pointer input', () {
    testWidgets('a fast drag lays track including the very first cell',
        (tester) async {
      final g = flatGame();
      g.cows.clear();
      g.speed = 0;
      g.setTool(Tool.track);
      const size = Size(800, 600);
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: BoardView(game: g)),
      ));
      await tester.pump();
      final v = IsoView.fit(size, g);
      Offset center(int x, int y) => v.pt(x + 0.5, y + 0.5);
      // Row 1 is empty in the starter layout.
      final gesture = await tester.startGesture(center(4, 1));
      await gesture.moveTo(center(8, 1)); // one large jump, like a fast mouse
      await gesture.up();
      await tester.pump();
      for (var x = 4; x <= 8; x++) {
        expect(g.board[Cell(x, 1)], TrackKind.ew,
            reason: 'cell ($x,1) should be laid');
      }
    });
  });

  group('scenarios', () {
    Game scenarioGame(String id) {
      web.window.localStorage.clear();
      return Game(scenario: Scenarios.byId(id), resume: false);
    }

    test('prairie builds a running world with cows and knolls', () {
      final g = scenarioGame('prairie');
      expect(g.cols, 20);
      expect(g.rows, 14);
      expect(g.path, isNotNull, reason: 'starter loop must close');
      expect(g.cows.length, 4);
      expect(g.balance, 300);
      expect(
          [for (var x = 0; x < g.cols; x++)
            for (var y = 0; y < g.rows; y++) Cell(x, y)]
              .any(g.isWater),
          isTrue,
          reason: 'the watering hole should be wet');
    });

    test('gorge builds a wet canyon with far-bank buildings', () {
      final g = scenarioGame('gorge');
      expect(g.path, isNotNull);
      // Canyon is wet the whole way down the middle.
      for (var y = 0; y < g.rows; y++) {
        expect(g.isWater(Cell(11, y)) || g.isWater(Cell(12, y)), isTrue,
            reason: 'row $y should hold water');
      }
      // Both bonus buildings wait on the east bank.
      expect(
          g.buildings
              .where((b) => b.type != BuildingType.station)
              .every((b) => b.cell.x >= 15),
          isTrue);
      // Starter loop stays dry on the west bank.
      expect(g.path!.every((st) => st.cell.x <= 8), isTrue);
    });

    test('missions latch as stars and persist across Start over', () {
      final g = scenarioGame('prairie');
      expect(g.checkMissions(), isFalse);
      g.balance = 2500;
      g.cowsShooed = 3;
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, containsAll(['nest-egg', 'cowboy']));
      expect(ScenarioProgress.stars('prairie'), 2);
      g.newGame(); // Start over rebuilds the map…
      expect(g.balance, 300);
      expect(g.cowsShooed, 0);
      // …but earned stars survive in a fresh game instance.
      final again = Game(scenario: Scenarios.byId('prairie'), resume: false);
      expect(again.missionsDone, containsAll(['nest-egg', 'cowboy']));
    });

    test('gorge bank missions read the traced route', () {
      final g = scenarioGame('gorge');
      expect(g.missionsDone, isEmpty);
      expect(g.checkMissions(), isFalse);
      g.balance = 5000;
      // Rewire the loop the way a player would: knock out its east column,
      // then drag one detour across the canyon and back — over at y=4,
      // around the east bank, home at y=9.
      for (var y = 4; y <= 9; y++) {
        g.bulldoze(Cell(7, y));
      }
      final detour = g.planTrack([
        for (var x = 6; x <= 16; x++) Cell(x, 4),
        for (var y = 5; y <= 9; y++) Cell(16, y),
        for (var x = 15; x >= 6; x--) Cell(x, 9),
      ]);
      expect(detour.isEmpty, isFalse, reason: 'detour must be plannable');
      expect(detour.truncatedByFunds, isFalse);
      g.commitTrack(detour);
      expect(g.path, isNotNull, reason: 'loop must close over the gorge');
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, contains('span'));
      expect(g.missionsDone, contains('twice'),
          reason: 'out at y=5 and back at y=8 are two distinct crossings');
    });

    test('scenario saves live in their own slot, sandbox untouched', () {
      web.window.localStorage.clear();
      final sandbox = Game();
      sandbox.newGame();
      final sandboxRaw = web.window.localStorage.getItem('ct_save_v3');
      expect(sandboxRaw, isNotNull);
      final g = Game(scenario: Scenarios.byId('prairie'), resume: false);
      g.saveNow();
      expect(Game.hasSaveFor('prairie'), isTrue);
      expect(web.window.localStorage.getItem('ct_save_v3'), sandboxRaw,
          reason: 'scenario play must not touch the sandbox save');
      final resumed = Game(scenario: Scenarios.byId('prairie'));
      expect(resumed.cols, 20);
      expect(resumed.balance, 300);
    });

    test('ridge wall is impassable except the saddle, and borable', () {
      final g = scenarioGame('ridge');
      expect(g.path, isNotNull);
      g.balance = 100000;
      // A straight shot across the wall mid-map dies on the two-step faces…
      final blocked = g.planTrack([for (var x = 8; x <= 15; x++) Cell(x, 9)]);
      expect(blocked.pieces.length, lessThan(4));
      // …but the router discovers the saddle up north on its own.
      final route = g.routeTrack(const Cell(7, 9), const Cell(16, 9));
      expect(route, isNotNull);
      expect(route!.any((c) => c.y <= 3), isTrue,
          reason: 'crosses via the pass');
      // And the wall takes a bore at portal grade.
      expect(g.boreError(const Cell(9, 9), const Cell(14, 9)), isNull);
    });

    test('ridge missions: link, summit depot, and the budget', () {
      final g = scenarioGame('ridge');
      g.balance = 100000;
      for (var y = 6; y <= 10; y++) {
        g.bulldoze(Cell(6, y));
      }
      // One detour: over the saddle at y=2 past the pass depot, a taste of
      // the east valley, and back through the saddle again at y=3 — the
      // wall's only crossing works both ways.
      final detour = g.planTrack([
        const Cell(5, 6),
        for (var y = 6; y >= 2; y--) Cell(6, y),
        for (var x = 7; x <= 16; x++) Cell(x, 2),
        const Cell(16, 3),
        for (var x = 15; x >= 7; x--) Cell(x, 3),
        for (var y = 4; y <= 10; y++) Cell(7, y),
        const Cell(6, 10),
        const Cell(5, 10),
      ]);
      expect(detour.truncatedByFunds, isFalse);
      g.commitTrack(detour);
      expect(g.path, isNotNull, reason: 'loop must close over the pass');
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, containsAll(['link', 'summit']));
      expect(g.missionsDone.contains('bore'), isFalse,
          reason: 'the saddle route never goes underground');
    });

    test('ridge bore mission: a loop through the tunnel earns the star', () {
      final g = scenarioGame('ridge');
      g.balance = 100000;
      expect(g.tapTunnel(const Cell(9, 9)), isNull);
      expect(g.tapTunnel(const Cell(14, 9)), isNull);
      for (var y = 6; y <= 10; y++) {
        g.bulldoze(Cell(6, y));
      }
      // Out over the saddle, down the east flank into the east portal…
      g.commitTrack(g.planTrack([
        const Cell(5, 6),
        for (var y = 6; y >= 3; y--) Cell(6, y),
        for (var x = 7; x <= 15; x++) Cell(x, 3),
        for (var y = 4; y <= 9; y++) Cell(15, y),
      ]));
      // …and home from the west portal's mouth.
      g.commitTrack(g.planTrack([
        for (var x = 8; x >= 6; x--) Cell(x, 9),
        const Cell(6, 10),
        const Cell(5, 10),
      ]));
      expect(g.path, isNotNull, reason: 'loop must close through the bore');
      expect(g.path!.any((st) => st.tunnelTo != null), isTrue);
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, containsAll(['link', 'bore']));
    });

    test('archipelago builds five dry islands in a wet lagoon', () {
      final g = scenarioGame('archipelago');
      expect(g.path, isNotNull);
      expect(g.isWater(const Cell(9, 8)), isTrue); // strait east of home
      expect(g.isWater(const Cell(12, 6)), isFalse); // isle B ground
      expect(g.buildings.length, 5); // terminus + one per outer island
      expect(g.cows, isEmpty);
    });

    test('archipelago missions: three islands and the flotilla', () {
      final g = scenarioGame('archipelago');
      g.balance = 100000;
      for (var y = 7; y <= 10; y++) {
        g.bulldoze(Cell(7, y));
      }
      // The return leg enters the bottom edge from the north, so its
      // corner must be rebuilt as a curve rather than kept as a straight.
      g.bulldoze(const Cell(6, 10));
      // Bridge east to isle B, south to isle C, and back home.
      final detour = g.planTrack([
        const Cell(6, 7),
        for (var x = 7; x <= 13; x++) Cell(x, 7),
        for (var y = 8; y <= 14; y++) Cell(13, y),
        for (var x = 12; x >= 6; x--) Cell(x, 14),
        for (var y = 13; y >= 10; y--) Cell(6, y),
      ]);
      expect(detour.truncatedByFunds, isFalse);
      g.commitTrack(detour);
      expect(g.path, isNotNull);
      g.armSecondTrain();
      expect(g.placeSecondTrain(const Cell(5, 7)), isNull);
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, containsAll(['triad', 'flotilla']));
      expect(g.missionsDone.contains('fullservice'), isFalse,
          reason: 'the far islands are still unserved');
    });

    test('switchback: serpentine walls, turntable and pace missions', () {
      final g = scenarioGame('switchback');
      expect(g.path, isNotNull);
      g.balance = 100000;
      // The wall band is unclimbable: a straight north shot dies on it.
      final blocked =
          g.planTrack([for (var y = 13; y >= 8; y--) Cell(9, y)]);
      expect(blocked.pieces.length, lessThan(4));
      // But the router snakes the corridor: south zone to the north zone
      // must thread the east gap and the west gap in turn.
      final route = g.routeTrack(const Cell(9, 13), const Cell(9, 2));
      expect(route, isNotNull);
      expect(route!.any((c) => c.x >= 19 && c.y >= 6 && c.y <= 9), isTrue,
          reason: 'threads the east gap');
      // Missions: raze the loop entirely and run a turntable shuttle past
      // the station's south side instead.
      expect(g.checkMissions(), isFalse);
      for (final cell in g.board.keys.toList()) {
        g.bulldoze(cell, scrapTrains: false);
      }
      expect(g.board, isEmpty);
      expect(g.tapTurntable(const Cell(2, 14)), isNull);
      expect(g.tapTurntable(const Cell(11, 14)), isNull);
      g.commitTrack(
          g.planTrack([for (var x = 3; x <= 10; x++) Cell(x, 14)]));
      expect(g.path, isNotNull, reason: 'shuttle line closes');
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, contains('shuttle'));
      // Pace + convoy latch off their counters.
      g.lastLapSteps = 50;
      g.lastLapTime = 14.5;
      g.dualLaps = 10;
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone, containsAll(['flyer', 'convoy']));
    });

    test('folly: a drowned scar and item-counter missions', () {
      final g = scenarioGame('folly');
      expect(g.path, isNotNull);
      // The scar runs wet down the middle of the map.
      for (var y = 0; y < g.rows; y++) {
        expect(g.isWater(Cell(12, y)) || g.isWater(Cell(13, y)), isTrue,
            reason: 'scar row $y');
      }
      expect(g.checkMissions(), isFalse);
      g.blastsFired = 4;
      g.loopsRidden = 5;
      g.jumpsMade = 15;
      expect(g.checkMissions(), isTrue);
      expect(g.missionsDone,
          containsAll(['demolition', 'showman', 'daredevil']));
      expect(g.lineClearPending, isTrue,
          reason: 'all three stars fire the celebration');
    });

    test('dual-lap streak counts and resets on a crash', () {
      final g = flatGame();
      g.cows.clear();
      g.balance = 100000;
      g.armSecondTrain();
      expect(g.placeSecondTrain(g.path![10].cell), isNull);
      final before = g.dualLaps;
      for (var i = 0; i < 60 && g.dualLaps == before; i++) {
        g.tick(0.5);
        if (g.trains.any((t) => t.wrecked)) break;
      }
      // Either a lap banked with both running, or they crashed and reset.
      if (g.trains.any((t) => t.wrecked)) {
        expect(g.dualLaps, 0);
      } else {
        expect(g.dualLaps, greaterThan(before));
      }
    });

    test('retired mission ids in storage never score stars', () {
      web.window.localStorage.clear();
      ScenarioProgress.markDone('ridge', 'thrift'); // a retired mission
      ScenarioProgress.markDone('ridge', 'link');
      expect(ScenarioProgress.stars('ridge'), 1,
          reason: 'only missions the scenario still has count');
    });

    test('the final star fires LINE CLEAR exactly once', () {
      final g = scenarioGame('prairie');
      g.balance = 2500;
      g.cowsShooed = 3;
      expect(g.checkMissions(), isTrue);
      expect(g.lineClearPending, isFalse,
          reason: 'developer mission is still open');
      g.buildings.add(Building(const Cell(1, 1), BuildingType.stop));
      g.buildings.add(Building(const Cell(1, 3), BuildingType.depot));
      expect(g.checkMissions(), isTrue);
      expect(g.lineClearPending, isTrue);
      g.dismissLineClear();
      // A fresh boarding of the cleared scenario never replays it.
      final again = Game(scenario: Scenarios.byId('prairie'), resume: false);
      expect(again.checkMissions(), isFalse);
      expect(again.lineClearPending, isFalse);
    });

    test('the line unlocks stop by stop', () {
      web.window.localStorage.clear();
      expect(ScenarioProgress.unlocked(0), isTrue);
      expect(ScenarioProgress.unlocked(1), isFalse);
      ScenarioProgress.markDone('prairie', 'nest-egg');
      expect(ScenarioProgress.unlocked(1), isTrue);
      expect(ScenarioProgress.unlocked(2), isFalse);
    });
  });

  group('track routing', () {
    test('routes a clean straight line between anchor and target', () {
      final g = flatGame();
      g.balance = 10000;
      final route = g.routeTrack(const Cell(4, 1), const Cell(9, 1));
      expect(route, isNotNull);
      expect(route!.length, 6);
      expect(route.every((c) => c.y == 1), isTrue, reason: 'no wiggles');
      final plan = g.planTrack(route);
      expect(plan.pieces.length, 6, reason: 'planTrack accepts every cell');
      expect(plan.pieces.every((p) => p.kind == TrackKind.ew), isTrue);
    });

    test('bends once for an L, never staircases', () {
      final g = flatGame();
      g.balance = 10000;
      final route = g.routeTrack(const Cell(4, 0), const Cell(9, 2))!;
      final plan = g.planTrack(route);
      expect(plan.pieces.length, route.length);
      final curves = plan.pieces.where((p) => p.kind.isCurve).length;
      expect(curves, 1, reason: 'one clean bend, not a staircase');
    });

    test('detours around a building blocking the straight line', () {
      final g = flatGame();
      g.balance = 10000;
      g.buildings.add(Building(const Cell(6, 1), BuildingType.stop));
      final route = g.routeTrack(const Cell(4, 1), const Cell(9, 1))!;
      expect(route.contains(const Cell(6, 1)), isFalse);
      expect(route.first, const Cell(4, 1));
      expect(route.last, const Cell(9, 1));
      final plan = g.planTrack(route);
      expect(plan.pieces.length, route.length);
    });

    test('a blocked target has no route', () {
      final g = flatGame();
      g.buildings.add(Building(const Cell(9, 1), BuildingType.stop));
      expect(g.routeTrack(const Cell(4, 1), const Cell(9, 1)), isNull);
      expect(g.routeTrack(const Cell(4, 1), const Cell(4, 1)),
          [const Cell(4, 1)],
          reason: 'anchor alone still previews as a tap');
    });

    test('a bridge gap can be closed from either end or the gap itself', () {
      final g = flatGame();
      g.balance = 100000;
      for (final x in [5, 6, 7]) {
        sink(g, Cell(x, 1));
      }
      // Two bridge stubs reach in from both banks; (6,1) is the wet gap.
      g.commitTrack(g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(5, 1)]));
      g.commitTrack(g.planTrack(const [Cell(9, 1), Cell(8, 1), Cell(7, 1)]));
      expect(g.deck[const Cell(5, 1)], 0);
      expect(g.deck[const Cell(7, 1)], 0);
      // Tapping the gap alone inherits the neighboring deck grade.
      final tap = g.planTrack(const [Cell(6, 1)]);
      expect(tap.pieces, hasLength(1));
      expect(tap.pieces.single.bridge, isTrue);
      expect(tap.pieces.single.deckLevel, 0);
      // Routing end to end covers the whole crossing.
      final route = g.routeTrack(const Cell(5, 1), const Cell(7, 1));
      expect(route, const [Cell(5, 1), Cell(6, 1), Cell(7, 1)]);
      final plan = g.planTrack(route!);
      expect(plan.pieces.length, 3);
      g.commitTrack(plan);
      expect(g.board[const Cell(6, 1)], TrackKind.ew);
    });

    test('anchoring on an existing curve end routes out along its legs', () {
      final g = flatGame();
      g.balance = 100000;
      g.commitTrack(g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(4, 2)]));
      expect(g.board[const Cell(4, 1)]!.isCurve, isTrue);
      // The old router modeled the anchor as a bare straight, so pressing
      // on a curve end (the screenshot's hairpin) found no route at all.
      final route = g.routeTrack(const Cell(4, 1), const Cell(7, 1));
      expect(route, isNotNull);
      final plan = g.planTrack(route!);
      expect(plan.pieces.length, route.length);
      expect(plan.pieces.first.cost, 0, reason: 'rides the curve for free');
    });

    test('routing into existing track arrives at an open connection', () {
      final g = flatGame();
      g.balance = 100000;
      g.commitTrack(g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(4, 2)]));
      // Target the curve itself: it only connects w and s, so the straight
      // shot along row 1 (arriving from the east) must be rejected and the
      // route has to come around through the adjoining track at (3,1).
      final route = g.routeTrack(const Cell(7, 1), const Cell(4, 1))!;
      expect(route[route.length - 2], const Cell(3, 1),
          reason: 'locks onto the open leg, never rams the closed corner');
      final plan = g.planTrack(route);
      expect(plan.pieces.length, route.length);
    });

    test('routes bridge across the gorge and the plan prices it', () {
      web.window.localStorage.clear();
      final g = Game(scenario: Scenarios.byId('gorge'), resume: false);
      g.balance = 10000;
      final route = g.routeTrack(const Cell(8, 2), const Cell(16, 2))!;
      final plan = g.planTrack(route);
      expect(plan.pieces.length, route.length,
          reason: 'the whole crossing must be buildable');
      expect(plan.pieces.any((p) => p.bridge), isTrue);
    });
  });

  group('speed pads & lap timer', () {
    test('pads place on straights only and toggle off with refund', () {
      final g = flatGame();
      g.balance = 1000;
      expect(g.tapSpeedPad(const Cell(5, 3)), isNull); // top edge straight
      expect(g.speedPads, contains(const Cell(5, 3)));
      expect(g.balance, 850);
      expect(g.tapSpeedPad(const Cell(3, 3)), isNotNull); // corner curve
      expect(g.tapSpeedPad(const Cell(5, 5)), isNotNull); // empty ground
      expect(g.tapSpeedPad(const Cell(5, 3)), isNull); // toggle off
      expect(g.balance, 850 + Game.priceSpeedPad ~/ 2);
      expect(g.speedPads, isEmpty);
    });

    test('crossing a pad doubles ground covered while the burst lasts', () {
      final g = flatGame();
      g.balance = 1000;
      final padCell = g.path![2].cell;
      g.tapSpeedPad(padCell);
      // Walk the train up to just before the pad, then measure one second.
      g.s = 1.2;
      g.tick(0.5); // crosses into the pad cell, boost arms
      expect(g.trains.first.boost, greaterThan(0));
      final before = g.s;
      g.tick(0.5);
      final boosted = g.s - before;
      expect(boosted, greaterThan(0.5 * Game.tilesPerSecond * 1.5),
          reason: 'burst should cover well over normal distance');
    });

    test('lap timer records from the second full lap on', () {
      final g = flatGame();
      final lapLen = g.path!.length; // 28 steps at 2.2/s ≈ 12.7 sim-s
      // First lap is partial by definition: no record.
      for (var i = 0; i < 40 && !g.trains.first.lapValid; i++) {
        g.tick(0.5);
      }
      expect(g.trains.first.lapValid, isTrue);
      expect(g.bestLapTime, isNull, reason: 'first lap never records');
      final clock0 = g.trains.first.lapClock;
      for (var i = 0; i < 80 && g.bestLapTime == null; i++) {
        g.tick(0.5);
      }
      expect(g.bestLapTime, isNotNull);
      expect(g.bestLapTime!, greaterThan(lapLen / Game.tilesPerSecond - 2));
      expect(g.bestLapTime!, lessThan(lapLen / Game.tilesPerSecond + 4));
      expect(clock0, lessThan(g.bestLapTime!),
          reason: 'clock was mid-lap when validity latched');
    });
  });

  group('loop-de-loop', () {
    test('placement wants flat straight dry track; toggles off', () {
      final g = flatGame();
      g.balance = 2000;
      expect(g.tapLoop(const Cell(5, 3)), isNull);
      expect(g.loops, contains(const Cell(5, 3)));
      expect(g.tapLoop(const Cell(3, 3)), isNotNull); // curve
      expect(g.tapLoop(const Cell(5, 5)), isNotNull); // no track
      sink(g, const Cell(9, 1));
      expect(g.tapLoop(const Cell(9, 1)), isNotNull); // water
      expect(g.tapLoop(const Cell(5, 3)), isNull); // remove
      expect(g.loops, isEmpty);
      expect(g.balance, 2000 - Game.priceLoop + Game.priceLoop ~/ 2);
    });

    test('trains stall without boost, ride through with one', () {
      final g = flatGame();
      g.balance = 2000;
      final loopIdx = List.generate(g.path!.length, (i) => i).firstWhere(
          (i) =>
              i >= 3 &&
              g.board[g.path![i].cell] != null &&
              !g.board[g.path![i].cell]!.isCurve);
      final loopCell = g.path![loopIdx].cell;
      expect(g.tapLoop(loopCell), isNull);
      g.s = loopIdx - 1.5; // rolling toward the hoop
      for (var i = 0; i < 6; i++) {
        g.tick(0.4);
      }
      expect(g.loopStalled, isTrue);
      expect(g.s, lessThan(loopIdx.toDouble()), reason: 'held short of it');
      expect(g.loopsRidden, 0);
      // A speed pad under the waiting train sends it through.
      final waitCell = g.path![g.s.floor()].cell;
      expect(g.tapSpeedPad(waitCell), isNull);
      for (var i = 0; i < 6; i++) {
        g.tick(0.4);
      }
      expect(g.s, greaterThan(loopIdx + 1.0));
      expect(g.loopsRidden, 1);
      expect(g.loopStalled, isFalse);
    });
  });

  group('jump ramp', () {
    test('arm-and-aim placement, cancel, and removal', () {
      final g = flatGame();
      g.balance = 2000;
      expect(g.tapRamp(const Cell(5, 1)), isNull); // arm
      expect(g.pendingRamp, const Cell(5, 1));
      expect(g.tapRamp(const Cell(5, 1)), isNull); // tap again = cancel
      expect(g.pendingRamp, isNull);
      g.tapRamp(const Cell(5, 1));
      expect(g.tapRamp(const Cell(9, 9)), isNotNull); // aim must be adjacent
      expect(g.tapRamp(const Cell(6, 1)), isNull); // aim east
      expect(g.ramps[const Cell(5, 1)], Dir.e);
      expect(g.balance, 2000 - Game.priceRamp);
      expect(g.tapRamp(const Cell(5, 1)), isNull); // tap existing = remove
      expect(g.ramps, isEmpty);
      expect(g.balance, 2000 - Game.priceRamp + Game.priceRamp ~/ 2);
    });

    test('a ramp flies the loop three cells onto aligned track', () {
      final g = flatGame();
      g.balance = 100000;
      // Break the loop's top edge and bridge the hole with a jump:
      // track runs 3..4, ramp at (5,3), flight over (6,3),(7,3), landing
      // on existing track at (8,3).
      g.bulldoze(const Cell(5, 3));
      g.bulldoze(const Cell(6, 3));
      g.bulldoze(const Cell(7, 3));
      g.tapRamp(const Cell(5, 3));
      g.tapRamp(const Cell(6, 3)); // aim east
      expect(g.path, isNotNull, reason: 'flight re-closes the loop');
      final flight =
          g.path!.where((st) => st.flyTo != null).toList();
      expect(flight, hasLength(1));
      expect(flight.single.cell, const Cell(5, 3));
      expect(flight.single.flyTo, const Cell(8, 3));
      // Riding it counts a jump.
      final before = g.jumpsMade;
      for (var i = 0; i < 40 && g.jumpsMade == before; i++) {
        g.tick(0.5);
      }
      expect(g.jumpsMade, greaterThan(before));
    });

    test('ramps are one-way: a backwards trace breaks the line', () {
      final g = flatGame();
      g.balance = 100000;
      g.bulldoze(const Cell(5, 3));
      g.bulldoze(const Cell(6, 3));
      g.bulldoze(const Cell(7, 3));
      g.tapRamp(const Cell(7, 3));
      g.tapRamp(const Cell(6, 3)); // aims WEST — against loop direction…
      // …which serves one direction and breaks the other: the loop still
      // traces for whichever heading hits the ramp from behind.
      final fwd = traceLoop(g.board, g.station.trigger!,
          g.board[g.station.trigger!]!.conn.first,
          pads: g.launchpads,
          tunnels: g.tunnels,
          switches: g.switches,
          ramps: g.ramps);
      final rev = traceLoop(g.board, g.station.trigger!,
          g.board[g.station.trigger!]!.conn.last,
          pads: g.launchpads,
          tunnels: g.tunnels,
          switches: g.switches,
          ramps: g.ramps);
      expect((fwd == null) != (rev == null), isTrue,
          reason: 'exactly one direction survives a one-way ramp');
    });
  });

  group('turntable', () {
    test('two turntables run an out-and-back line that pays', () {
      final g = flatGame();
      g.balance = 100000;
      // Strip the loop down to its bottom edge (the station's segment)…
      for (var x = 3; x <= 12; x++) {
        g.bulldoze(Cell(x, 3));
      }
      for (var y = 4; y <= 8; y++) {
        g.bulldoze(Cell(3, y));
        g.bulldoze(Cell(12, y));
      }
      expect(g.path, isNull, reason: 'a bare stub has no route');
      // …and cap both ends.
      expect(g.tapTurntable(const Cell(3, 8)), isNull);
      expect(g.tapTurntable(const Cell(12, 8)), isNull);
      expect(g.path, isNotNull, reason: 'capped ends close the palindrome');
      final bounces = g.path!.where((st) => st.entry == st.exit).toList();
      expect(bounces, hasLength(2), reason: 'one spin at each end');
      // Round trips pay like laps.
      final before = g.balance;
      for (var i = 0; i < 80 && g.balance == before; i++) {
        g.tick(0.5);
      }
      expect(g.balance, greaterThan(before));
      // Removing a table breaks the route again.
      expect(g.tapTurntable(const Cell(3, 8)), isNull);
      expect(g.path, isNull);
    });

    test('placement respects sites and refuses occupied ground', () {
      final g = flatGame();
      g.balance = 2000;
      expect(g.tapTurntable(const Cell(5, 3)), isNotNull); // on track
      sink(g, const Cell(9, 1));
      expect(g.tapTurntable(const Cell(9, 1)), isNotNull); // water
      expect(g.tapTurntable(const Cell(5, 1)), isNull); // clear ground
      expect(g.turntables, contains(const Cell(5, 1)));
      expect(g.rampSiteError(const Cell(5, 1)), isNotNull,
          reason: 'other items must not stack on a table');
    });
  });

  group('supporting cast', () {
    test('dynamite craters open ground but not under structures', () {
      final g = flatGame();
      g.balance = 1000;
      expect(g.blast(const Cell(6, 5)), isNull); // open interior ground
      expect(g.blastsFired, 1);
      expect(g.balance, 900);
      expect(g.isWater(const Cell(6, 5)), isTrue, reason: 'crater floods');
      expect(g.isWater(const Cell(7, 6)), isTrue, reason: '2×2 blast');
      // Under the starter loop, track pins its vertices: nothing to blast
      // right on the rails, and a near miss leaves the rails dry.
      final onTrack = g.blast(const Cell(4, 3));
      if (onTrack == null) {
        expect(g.path, isNotNull, reason: 'rails survive a near blast');
      }
      expect(g.board[const Cell(4, 3)], isNotNull);
    });

    test('cow catcher plows cows for a toll instead of stopping', () {
      final g = flatGame();
      g.balance = 1000;
      g.cows.clear();
      final aheadIdx = (g.s.floor() + 2) % g.path!.length;
      g.cows.add(Cow(g.path![aheadIdx].cell, 999));
      g.tick(1.0);
      expect(g.cowBlocked, isTrue, reason: 'without the catcher: blocked');
      g.buyCowCatcher();
      expect(g.cowCatcher, isTrue);
      final tollBefore = g.balance;
      var plowed = false;
      for (var i = 0; i < 20 && !plowed; i++) {
        g.tick(0.5);
        plowed = g.cowsPlowed > 0;
      }
      expect(plowed, isTrue);
      expect(g.balance, greaterThanOrEqualTo(tollBefore + 5));
      expect(g.cowBlocked, isFalse);
    });

    test('Grand Terminal doubles the lap formula', () {
      final g = flatGame();
      g.cows.clear();
      final plain = g.projectedPayout;
      g.balance = 2000;
      g.buyGrandTerminal();
      expect(g.grandTerminal, isTrue);
      expect(g.projectedPayout, plain * 2);
      g.buyGrandTerminal(); // idempotent
      expect(g.balance, 2000 - Game.priceGrandTerminal);
    });
  });

  group('reverse train', () {
    test('flipping keeps the engine in place and the loop closed', () {
      final g = flatGame();
      g.s = 5.3;
      final tr = g.trains.first;
      final cellBefore = g.engineCell;
      expect(tr.reversed, isFalse);
      expect(g.reverseTrain(tr), isNull);
      expect(tr.reversed, isTrue);
      expect(g.path, isNotNull);
      expect(g.engineCell, cellBefore, reason: 'no teleporting');
      final frac = tr.s - tr.s.floorToDouble();
      expect(frac, closeTo(0.7, 0.05), reason: 'mirrored within the cell');
      // Flip back works too.
      expect(g.reverseTrain(tr), isNull);
      expect(tr.reversed, isFalse);
    });

    test('one-way ramp routes refuse the flip', () {
      final g = flatGame();
      g.balance = 100000;
      g.bulldoze(const Cell(5, 3));
      g.bulldoze(const Cell(6, 3));
      g.bulldoze(const Cell(7, 3));
      g.tapRamp(const Cell(5, 3));
      g.tapRamp(const Cell(6, 3)); // one-way east jump closes the loop
      expect(g.path, isNotNull);
      final tr = g.trains.first;
      final wasReversed = tr.reversed;
      expect(g.reverseTrain(tr), isNotNull, reason: 'flip must refuse');
      expect(tr.reversed, wasReversed);
      expect(g.path, isNotNull, reason: 'the working direction survives');
    });

    test('wrecked trains must be re-railed before reversing', () {
      final g = flatGame();
      g.trains.first.wrecked = true;
      expect(g.reverseTrain(g.trains.first), isNotNull);
      expect(g.trains.first.reversed, isFalse);
    });
  });

  group('save throttling', () {
    test('payout saves coalesce to one per window', () {
      final g = flatGame();
      g.cows.clear();
      final len = g.path!.length.toDouble();
      // First payout saves immediately (fresh counter)…
      g.s = len - 0.5;
      g.tick(0.4);
      final raw1 = web.window.localStorage.getItem('ct_save_v3');
      expect(raw1, isNotNull);
      // …a second payout inside the window is deferred…
      g.s = len - 0.5;
      g.tick(0.4);
      expect(web.window.localStorage.getItem('ct_save_v3'), raw1,
          reason: 'inside the window: no new write');
      // …and flushes once the window passes.
      g.tick(3.1);
      expect(web.window.localStorage.getItem('ct_save_v3'), isNot(raw1));
    });

    test('explicit actions still save instantly', () {
      final g = flatGame();
      g.cows.clear();
      g.s = g.path!.length - 0.5;
      g.tick(0.4); // payout: save + fresh window
      g.balance = 5000;
      g.commitTrack(g.planTrack(const [Cell(4, 1), Cell(5, 1)]));
      final raw = web.window.localStorage.getItem('ct_save_v3')!;
      expect(raw.contains('"balance":${g.balance}'), isTrue,
          reason: 'building writes through immediately');
    });
  });

  group('route map', () {
    Future<void> toMap(WidgetTester tester) async {
      await tester.pumpWidget(const TrainMakerApp());
      await tester.pump();
      await tester.tap(find.text('TAP TO ROLL'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
    }

    testWidgets('locked stops show as locked, first stop boards',
        (tester) async {
      web.window.localStorage.clear();
      await toMap(tester);
      // Prairie is the frontier: its panel is open with ALL ABOARD.
      expect(find.text('ALL ABOARD'), findsOneWidget);
      // The Gorge is locked: tapping its plate shows the locked panel.
      await tester.tap(find.text('THE GORGE'));
      await tester.pump();
      expect(find.text('ALL ABOARD'), findsNothing);
      expect(find.textContaining('Earn a star at the previous stop'),
          findsOneWidget);
      // Boarding Prairie Junction lands in its scenario game.
      await tester.tap(find.text('PRAIRIE JUNCTION'));
      await tester.pump();
      await tester.tap(find.text('ALL ABOARD'));
      await tester.pump();
      final game = tester.widget<BoardView>(find.byType(BoardView)).game;
      expect(game.scenario?.id, 'prairie');
      expect(find.text('MISSIONS'), findsOneWidget);
    });

    testWidgets('route map button exits via confirm and keeps the save',
        (tester) async {
      web.window.localStorage.clear();
      await toMap(tester);
      await tester.tap(find.text('ALL ABOARD'));
      await tester.pump();
      expect(find.byType(BoardView), findsOneWidget);
      // The board ticker never settles, so pump fixed frames instead.
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 80));
        }
      }

      await tester.tap(find.byIcon(Icons.map_rounded));
      await settle();
      expect(find.text('Return to the route map?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await settle();
      expect(find.byType(BoardView), findsOneWidget, reason: 'cancel stays');
      await tester.tap(find.byIcon(Icons.map_rounded));
      await settle();
      await tester.tap(find.text('Route map'));
      await settle();
      expect(find.text('CHOOSE YOUR LINE'), findsOneWidget);
      expect(Game.hasSaveFor('prairie'), isTrue);
      // Its panel now offers to resume the world in progress.
      expect(find.text('RESUME'), findsOneWidget);
      expect(find.text('Start fresh'), findsOneWidget);
    });

    testWidgets('LINE CLEAR appears on the final star and routes to the map',
        (tester) async {
      web.window.localStorage.clear();
      ScenarioProgress.markDone('prairie', 'developer');
      ScenarioProgress.markDone('prairie', 'cowboy');
      await toMap(tester);
      // Two stars have already unlocked The Gorge, so select Prairie first.
      await tester.tap(find.text('PRAIRIE JUNCTION'));
      await tester.pump();
      await tester.tap(find.text('ALL ABOARD'));
      await tester.pump();
      final game = tester.widget<BoardView>(find.byType(BoardView)).game;
      game.balance = 2500; // satisfies the last open mission
      game.tick(1.1); // mission poll runs once a second
      await tester.pump();
      expect(find.text('LINE CLEAR!'), findsOneWidget);
      expect(find.textContaining('THE GORGE'), findsOneWidget);
      await tester.tap(find.text('ROUTE MAP'));
      await tester.pump();
      expect(find.text('CHOOSE YOUR LINE'), findsOneWidget);
      expect(find.text('LINE CLEAR!'), findsNothing);
    });

    testWidgets('every stop can be selected by tapping its plate',
        (tester) async {
      web.window.localStorage.clear();
      await toMap(tester);
      for (final sc in Scenarios.all) {
        // Plates come before the panel in the tree: .first is the plate.
        await tester.tap(find.text(sc.name).first);
        await tester.pump();
        expect(find.text(sc.name), findsAtLeastNWidgets(2),
            reason: '${sc.name}: plate tap must open its panel — if this '
                'fails the plate is buried under the detail panel');
      }
    });

    testWidgets('the roundhouse boards the sandbox', (tester) async {
      await enterSandbox(tester);
      final game = tester.widget<BoardView>(find.byType(BoardView)).game;
      expect(game.scenario, isNull);
      expect(find.text('MISSIONS'), findsNothing);
    });
  });
}
