import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;

import 'package:trainmaker/main.dart';
import 'package:trainmaker/model/game.dart';
import 'package:trainmaker/model/track.dart';
import 'package:trainmaker/ui/board_view.dart';
import 'package:trainmaker/ui/painters.dart';

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
    test('sculpting raises a vertex, blocks rail and buildings, charges', () {
      final g = flatGame();
      g.balance = 1000;
      // Raise the vertex at (7,1): cells (6..7, 0..1) become sloped.
      expect(g.sculpt(const Cell(6, 1), const Offset(0.9, 0.2), 1), isNull);
      expect(g.heights.vAt(7, 1), 1);
      expect(g.balance, 1000 - Game.priceTerraformStep);
      expect(g.heights.isFlat(const Cell(6, 1)), isFalse);
      // Track stops at the slope, buildings refuse it.
      final plan = g.planTrack(const [Cell(4, 1), Cell(5, 1), Cell(6, 1)]);
      expect(plan.pieces.length, 2);
      expect(g.placeBuilding(BuildingType.stop, const Cell(6, 1)),
          'Needs flat ground');
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

    test('rail refuses uneven ground and level changes between plateaus', () {
      final g = flatGame();
      g.balance = 100000;
      // Build a one-step plateau covering cells around (5,1)..(6,1).
      for (final v in const [(5, 1), (6, 1), (5, 2), (6, 2)]) {
        g.sculpt(Cell(v.$1, v.$2), const Offset(0.2, 0.2), 1);
      }
      expect(g.heights.isFlat(const Cell(5, 1)), isTrue);
      expect(g.heights.floorOf(const Cell(5, 1)), 1);
      // A drag from ground level onto the plateau stops at the seam.
      final plan =
          g.planTrack(const [Cell(3, 1), Cell(4, 1), Cell(5, 1)]);
      expect(plan.pieces.length, lessThan(3));
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

  group('land deeds', () {
    test('east deed grows the board, charges, and escalates the price', () {
      final g = freshGame();
      g.newGame();
      g.balance = 5000;
      final c0 = g.cols;
      final p0 = g.deedPrice;
      expect(g.buyLand(east: true), isTrue);
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
      expect(g.buyLand(east: false), isTrue);
      expect(g.rows, Game.startRows + Game.expandStep);
      while (g.buyLand(east: true)) {}
      while (g.buyLand(east: false)) {}
      expect(g.cols, Game.maxCols);
      expect(g.rows, Game.maxRows);
      expect(g.canExpandEast, isFalse);
      expect(g.canExpandSouth, isFalse);
    });

    test('board size and deed count persist', () {
      final g = freshGame();
      g.newGame();
      g.balance = 5000;
      g.buyLand(east: true);
      g.buyLand(east: false);
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
    testWidgets('Esc deselects the active tool', (tester) async {
      web.window.localStorage.clear();
      await tester.pumpWidget(const TrainMakerApp());
      await tester.pump();
      final view =
          tester.widget<BoardView>(find.byType(BoardView));
      view.game.setTool(Tool.track);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(view.game.tool, Tool.none);
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
}
