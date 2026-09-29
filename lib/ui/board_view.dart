import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../model/game.dart';
import 'painters.dart';
import 'palette.dart';

/// The isometric board: static cached layer + dynamic layer, plus all
/// pointer handling (drag-to-lay track, tap-place buildings, bulldoze).
class BoardView extends StatefulWidget {
  final Game game;
  const BoardView({super.key, required this.game});

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final Stopwatch _clock = Stopwatch();

  final List<Cell> _dragCells = []; // holds just the drag's anchor cell
  Cell? _routeTarget; // last routed hover cell, to skip repeat work
  final ValueNotifier<TrackPlan?> _plan = ValueNotifier(null);
  final BoardPictureCache _boardCache = BoardPictureCache();
  int _follow = -1; // train index the camera follows; -1 = free camera
  final ValueNotifier<Cell?> _hover = ValueNotifier(null);

  // Camera: whole-board fit at zoom 1, scroll/pinch to zoom, drag (no tool)
  // to pan, 90°-step rotation.
  final ValueNotifier<double> _zoom = ValueNotifier(1);
  final ValueNotifier<Offset> _pan = ValueNotifier(Offset.zero);
  final ValueNotifier<int> _rot = ValueNotifier(0);
  bool _panning = false;
  Offset? _lastPanPos;
  double _pzStartZoom = 1;
  Offset _pzLastPan = Offset.zero;

  Game get game => widget.game;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration now) {
    // Wall-clock dt: in a throttled/background tab frames arrive rarely, and
    // the railway should keep earning across the gap (capped at one minute).
    final dt = _clock.elapsedMicroseconds / 1e6;
    _clock
      ..reset()
      ..start();
    game.tick(dt.clamp(0.0, 60.0));
    _updateFollow();
  }

  /// Follow-cam: glide the pan so the followed engine stays centered.
  void _updateFollow() {
    if (_follow < 0) return;
    if (_follow >= game.trains.length) {
      setState(() => _follow = -1);
      return;
    }
    final tr = game.trains[_follow];
    final p = tr.renderPath;
    final size = context.size;
    if (p == null || p.isEmpty || size == null) return;
    final v = _view(size);
    final st = p[tr.s.floor() % p.length];
    final local = st.posInCell(tr.s - tr.s.floorToDouble(), 1.0);
    final target = v.gpt(st.cell.x + local.dx, st.cell.y + local.dy);
    final center = Offset(size.width / 2, size.height / 2);
    final delta = center - target;
    if (delta.distance > 0.5) {
      _pan.value = _clampPan(_pan.value + delta * 0.12);
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _plan.dispose();
    _hover.dispose();
    _zoom.dispose();
    _pan.dispose();
    _rot.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ pointer
  //
  // Raw pointer events (not GestureDetector): pan recognizers eat the drag
  // slop, so a fast drag's first cell would be skipped.

  Offset? _downPos;
  bool _pointerActive = false;

  IsoView _view(Size size) =>
      IsoView.of(size, game, _zoom.value, _pan.value, rot: _rot.value);

  // Last sculpted vertex, so drag-sculpting fires once per vertex.
  (int, int)? _lastSculpt;

  String? _sculpt(Offset local, int delta, {bool force = false}) {
    final view = _view(context.size!);
    final c = view.cellAt(local);
    if (c == null) return null;
    final frac = view.fracIn(c, local);
    final vert = (c.x + (frac.dx > 0.5 ? 1 : 0), c.y + (frac.dy > 0.5 ? 1 : 0));
    if (!force && vert == _lastSculpt) return null;
    _lastSculpt = vert;
    return game.sculpt(c, frac, delta);
  }

  Cell? _cellAt(Offset local) => _view(context.size!).cellAt(local);

  Offset _clampPan(Offset p) {
    // Fully zoomed out the whole board is visible — nothing to pan; the
    // reachable range grows with zoom.
    final size = context.size!;
    final limX = size.width * 0.65 * (_zoom.value - 1);
    final limY = size.height * 0.65 * (_zoom.value - 1);
    return Offset(p.dx.clamp(-limX, limX), p.dy.clamp(-limY, limY));
  }

  /// Zoom to [target], keeping the plane point under [cursor] fixed.
  void _applyZoom(double target, Offset cursor) {
    final size = context.size!;
    final oldZoom = _zoom.value;
    final newZoom = target.clamp(1.0, 4.0);
    if (newZoom == oldZoom) return;
    final base = IsoView.fit(size, game, rot: _rot.value);
    final center = Offset(size.width, size.height) / 2;
    final oldO = center + (base.o - center) * oldZoom + _pan.value;
    final planePx = (cursor - oldO) / (base.s * oldZoom); // iso px per s=1
    var pan =
        cursor - center - (base.o - center) * newZoom - planePx * (base.s * newZoom);
    if (newZoom <= 1.001) pan = Offset.zero; // fully zoomed out: recenter
    _zoom.value = newZoom;
    _pan.value = _clampPan(pan);
    _hover.value = _cellAt(cursor);
  }

  void _onScroll(PointerScrollEvent e) =>
      _applyZoom(_zoom.value * math.exp(-e.scrollDelta.dy / 400), e.localPosition);

  void _rotate(int dir) {
    _rot.value = (_rot.value + dir) & 3;
    _pan.value = Offset.zero; // recenter: a spun world off-screen disorients
  }

  void _pointerDown(Offset local) {
    _pointerActive = true;
    _downPos = local;
    if (game.tool == Tool.none) {
      _panning = true;
      _lastPanPos = local;
      if (_follow >= 0) setState(() => _follow = -1); // manual pan wins
      return;
    }
    if (game.tool == Tool.raiseLand || game.tool == Tool.lowerLand) {
      _maybeNotice(
          _sculpt(local, game.tool == Tool.raiseLand ? 1 : -1, force: true));
      return;
    }
    if (game.tool == Tool.levelLand) {
      final c = _cellAt(local);
      if (c != null) {
        game.armLevel(c); // the pressed tile sets the grade to match
        _maybeNotice(game.levelTo(c));
      }
      return;
    }
    final c = _cellAt(local);
    if (c == null) return;
    switch (game.tool) {
      case Tool.track:
        _dragCells
          ..clear()
          ..add(c);
        _routeTarget = c;
        _plan.value = game.planTrack(_dragCells);
      case Tool.bulldoze:
        game.bulldoze(c);
      case Tool.launchpad:
        _maybeNotice(game.tapLaunchpad(c));
      case Tool.switchTrack:
        _maybeNotice(game.tapSwitch(c));
      case Tool.tunnel:
        _maybeNotice(game.tapTunnel(c));
      case Tool.signal:
        _maybeNotice(game.tapSignal(c));
      case Tool.speedPad:
        _maybeNotice(game.tapSpeedPad(c));
      case Tool.loopDeLoop:
        _maybeNotice(game.tapLoop(c));
      case Tool.jumpRamp:
        _maybeNotice(game.tapRamp(c));
      case Tool.turntable:
        _maybeNotice(game.tapTurntable(c));
      case Tool.dynamite:
        _maybeNotice(game.blast(c));
      case Tool.stop ||
            Tool.depot ||
            Tool.raiseLand ||
            Tool.lowerLand ||
            Tool.levelLand ||
            Tool.none:
        break;
    }
  }

  void _pointerMove(Offset local) {
    if (!_pointerActive) return;
    if (_panning) {
      _pan.value = _clampPan(_pan.value + (local - _lastPanPos!));
      _lastPanPos = local;
      return;
    }
    final c = _cellAt(local);
    _hover.value = c;
    if (c == null) return;
    // Drag-painting tools: apply silently, skipping cells that reject.
    switch (game.tool) {
      case Tool.bulldoze:
        game.bulldoze(c, scrapTrains: false); // drags raze, taps scrap
        return;
      case Tool.raiseLand:
        _sculpt(local, 1);
        return;
      case Tool.lowerLand:
        _sculpt(local, -1);
        return;
      case Tool.levelLand:
        game.levelTo(c);
        return;
      case Tool.track ||
            Tool.stop ||
            Tool.depot ||
            Tool.launchpad ||
            Tool.switchTrack ||
            Tool.tunnel ||
            Tool.signal ||
            Tool.speedPad ||
            Tool.loopDeLoop ||
            Tool.jumpRamp ||
            Tool.turntable ||
            Tool.dynamite ||
            Tool.none:
        break;
    }
    if (game.tool != Tool.track || _dragCells.isEmpty) return;
    // Rubber-band routing: only the anchor and the current cell matter —
    // the game routes the cheapest legal line between them, and the ghost
    // shows exactly what release would build.
    if (c == _routeTarget) return;
    _routeTarget = c;
    final anchor = _dragCells.first;
    final route = game.routeTrack(anchor, c);
    _plan.value = game.planTrack(route ?? [anchor]);
  }

  void _pointerUp(Offset local) {
    if (!_pointerActive) return;
    _pointerActive = false;
    _panning = false;
    _lastPanPos = null;
    _lastSculpt = null;
    game.levelTarget = null; // each level drag re-arms from its press
    final plan = _plan.value;
    _dragCells.clear();
    _routeTarget = null;
    _plan.value = null;
    switch (game.tool) {
      case Tool.track:
        if (plan != null && !plan.isEmpty) {
          game.commitTrack(plan);
          if (plan.truncatedByFunds) {
            _notice('Ran out of money — track laid up to what you could afford.');
          }
        }
      case Tool.stop || Tool.depot:
        // Buildings place on tap: ignore if the pointer travelled far.
        final down = _downPos;
        if (down != null && (local - down).distance < 14) {
          final c = _cellAt(down);
          if (c != null) {
            _place(game.tool == Tool.stop ? BuildingType.stop : BuildingType.depot, c);
          }
        }
      case Tool.none:
        // A pan that never moved is a tap: flip a switch under it.
        final down = _downPos;
        if (down != null && (local - down).distance < 14) {
          final cell = _cellAt(down);
          if (cell != null) {
            if (game.placingTrain) {
              _maybeNotice(game.placeSecondTrain(cell));
            } else if (game.trains.any((t) => t.wrecked)) {
              _maybeNotice(game.tapWreck(cell));
            } else {
              final engine = game.trainEngineAt(cell);
              if (engine != null) {
                _maybeNotice(game.reverseTrain(engine));
              } else {
                game.toggleSwitch(cell);
              }
            }
          }
        }
      case Tool.bulldoze ||
            Tool.raiseLand ||
            Tool.lowerLand ||
            Tool.levelLand ||
            Tool.launchpad ||
            Tool.switchTrack ||
            Tool.tunnel ||
            Tool.signal ||
            Tool.speedPad ||
            Tool.loopDeLoop ||
            Tool.jumpRamp ||
            Tool.turntable ||
            Tool.dynamite:
        break;
    }
    _downPos = null;
  }

  void _place(BuildingType type, Cell c) {
    _maybeNotice(game.placeBuilding(type, c));
  }

  void _maybeNotice(String? err) {
    if (err != null) _notice(err);
  }

  Offset _screenCenter() {
    final size = context.size!;
    return Offset(size.width / 2, size.height / 2);
  }

  Widget _camBtn(IconData icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: Material(
          color: Pal.chromeBg,
          shape: const CircleBorder(side: BorderSide(color: Pal.chromeLine)),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 34,
              height: 34,
              child: Icon(icon, size: 18, color: Pal.muted),
            ),
          ),
        ),
      );

  void _notice(String msg) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        width: 340,
        duration: const Duration(seconds: 2),
      ));
  }

  // ------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onHover: (e) => _hover.value = _cellAt(e.localPosition),
      onExit: (_) => _hover.value = null,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _pointerDown(e.localPosition),
        onPointerMove: (e) => _pointerMove(e.localPosition),
        onPointerUp: (e) => _pointerUp(e.localPosition),
        onPointerCancel: (e) => _pointerUp(e.position),
        onPointerSignal: (e) {
          if (e is PointerScrollEvent) {
            _onScroll(e);
          } else if (e is PointerScaleEvent) {
            // Browser trackpad pinch arrives as a scale signal.
            _applyZoom(_zoom.value * e.scale, e.localPosition);
          }
        },
        onPointerPanZoomStart: (e) {
          _pzStartZoom = _zoom.value;
          _pzLastPan = Offset.zero;
        },
        onPointerPanZoomUpdate: (e) {
          // Desktop trackpad gesture stream: two-finger pan + pinch zoom.
          final d = e.pan - _pzLastPan;
          _pzLastPan = e.pan;
          _pan.value = _clampPan(_pan.value + d);
          _applyZoom(_pzStartZoom * e.scale, e.localPosition);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: ListenableBuilder(
                listenable: Listenable.merge([game, _zoom, _pan, _rot]),
                builder: (context, child) => CustomPaint(
                  painter: CachedBoardPainter(
                      game, _zoom.value, _pan.value, _rot.value, _boardCache),
                  isComplex: true,
                  willChange: false,
                ),
              ),
            ),
            RepaintBoundary(
              child: CustomPaint(
                painter: DynamicPainter(game, _plan, _hover, _zoom, _pan, _rot),
                willChange: true,
              ),
            ),
            Positioned(
              left: 12,
              bottom: 12,
              child: Column(
                children: [
                  _camBtn(Icons.add_rounded, 'Zoom in',
                      () => _applyZoom(_zoom.value * 1.3, _screenCenter())),
                  const SizedBox(height: 6),
                  _camBtn(Icons.remove_rounded, 'Zoom out',
                      () => _applyZoom(_zoom.value / 1.3, _screenCenter())),
                  const SizedBox(height: 6),
                  _camBtn(Icons.rotate_left_rounded, 'Rotate left',
                      () => _rotate(-1)),
                  const SizedBox(height: 6),
                  _camBtn(
                      _follow >= 0
                          ? Icons.my_location_rounded
                          : Icons.location_searching_rounded,
                      _follow >= 0
                          ? 'Following train ${_follow + 1} — tap to cycle'
                          : 'Follow a train',
                      () => setState(() {
                            _follow =
                                _follow + 1 >= game.trains.length ? -1 : _follow + 1;
                          })),
                  const SizedBox(height: 6),
                  _camBtn(Icons.rotate_right_rounded, 'Rotate right',
                      () => _rotate(1)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
