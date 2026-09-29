import 'package:flutter/material.dart';

import '../model/game.dart';
import 'palette.dart';

// ------------------------------------------------------------ panel header
// The old 54px top bar, folded into three compact rows at the top of the
// shop panel: brand + reset, a full-width state chip, honk + speed.

class _SpeedControls extends StatelessWidget {
  final Game game;
  const _SpeedControls({required this.game});

  @override
  Widget build(BuildContext context) {
    Widget btn(int v, IconData icon, String tip) {
      final on = game.speed == v;
      return Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => game.setSpeed(v),
          child: Container(
            width: 31,
            height: 27,
            decoration: BoxDecoration(
              color: on ? Pal.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: on ? Colors.white : Pal.muted),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Pal.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(0, Icons.pause_rounded, 'Pause'),
        btn(1, Icons.play_arrow_rounded, 'Normal speed'),
        btn(2, Icons.fast_forward_rounded, 'Double speed'),
      ]),
    );
  }
}

// ---------------------------------------------------------------- shop

/// One entry in the compact icon grid, with its hover-popover content.
class _ShopItem {
  final IconData icon;
  final String title;
  final String desc;
  final String tag; // micro-label under the icon
  final String? chip; // price chip in the popover
  final bool chipMuted;
  final bool enabled;
  final bool selected;
  final bool danger;
  final VoidCallback? onTap;
  const _ShopItem({
    required this.icon,
    required this.title,
    required this.desc,
    required this.tag,
    this.chip,
    this.chipMuted = false,
    this.enabled = true,
    this.selected = false,
    this.danger = false,
    this.onTap,
  });
}

class ShopPanel extends StatefulWidget {
  final Game game;
  final VoidCallback? onExitToMap;
  const ShopPanel({super.key, required this.game, this.onExitToMap});

  @override
  State<ShopPanel> createState() => _ShopPanelState();
}

class _ShopPanelState extends State<ShopPanel> {
  final ScrollController _scroll = ScrollController();

  Game get game => widget.game;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _money(int p) =>
      p >= 1000 ? '\$${(p / 1000).toStringAsFixed(1)}k' : '\$$p';

  _ShopItem _toolItem({
    required Tool tool,
    required IconData icon,
    required String title,
    required String desc,
    required String tag,
    String? chip,
    bool enabled = true,
    bool danger = false,
  }) =>
      _ShopItem(
        icon: icon,
        title: title,
        desc: desc,
        tag: tag,
        chip: chip,
        enabled: enabled,
        danger: danger,
        selected: game.tool == tool,
        onTap: () => game.setTool(tool),
      );

  List<_ShopItem> _tools() => [
        _toolItem(
          tool: Tool.none,
          icon: Icons.near_me_rounded,
          title: 'Select',
          tag: 'SELECT',
          desc:
              'Flip switches by tapping them · drag to pan, scroll to zoom. Esc returns here.',
        ),
        _toolItem(
          tool: Tool.track,
          icon: Icons.route_rounded,
          title: 'Track',
          tag: '\$10+',
          chip: '\$10+',
          enabled: game.balance >= Game.priceStraight,
          desc:
              'Drag across the board. \$${Game.priceStraight} straight · \$${Game.priceCurve} curve · +\$${Game.priceBridge} bridge over water. Straights climb one step per cell.',
        ),
        _toolItem(
          tool: Tool.bulldoze,
          icon: Icons.construction_rounded,
          title: 'Bulldoze',
          tag: 'RAZE',
          danger: true,
          desc:
              'Remove track or buildings · 50% refund. Tap an engine (target ring) to scrap that train — your last train stays.',
        ),
      ];

  List<_ShopItem> _build() => [
        _ShopItem(
          icon: Icons.directions_railway_rounded,
          title: 'Train car',
          tag: '\$${Game.priceCar}',
          chip: '\$${Game.priceCar}',
          enabled: game.balance >= Game.priceCar,
          desc:
              'Adds a car to your shorter train · bigger payouts every lap.',
          onTap: game.buyCar,
        ),
        if (game.trains.length == 1)
          _ShopItem(
            icon: Icons.tram_rounded,
            title: 'Second train',
            tag: '\$1.5k',
            chip: '\$${Game.priceSecondTrain}',
            enabled: game.balance >= Game.priceSecondTrain,
            desc:
                'A second engine running the opposite direction — double the laps. Buy, then tap your line where it should start. Give it signals, or enjoy the fireworks.',
            onTap: () => game.armSecondTrain(),
          )
        else
          const _ShopItem(
            icon: Icons.tram_rounded,
            title: 'Second train',
            tag: 'OWNED',
            chip: 'owned',
            chipMuted: true,
            enabled: false,
            desc:
                'Your opposite-direction train is on the rails. New cars go to the shorter train.',
          ),
        _toolItem(
          tool: Tool.signal,
          icon: Icons.traffic_rounded,
          title: 'Signal',
          tag: '\$${Game.priceSignal}',
          chip: '\$${Game.priceSignal}',
          enabled: game.balance >= Game.priceSignal,
          desc:
              'Tap track to plant a block signal: a train waits there while the stretch ahead (to the next signal) is occupied. Tap a signal to remove it.',
        ),
        _toolItem(
          tool: Tool.speedPad,
          icon: Icons.bolt_rounded,
          title: 'Speed pad',
          tag: '\$${Game.priceSpeedPad}',
          chip: '\$${Game.priceSpeedPad}',
          enabled: game.balance >= Game.priceSpeedPad,
          desc:
              'A booster strip on straight track: crossing it doubles the train\'s speed for a couple of seconds. Loops need one for a run-up. Tap a pad to remove it.',
        ),
        _toolItem(
          tool: Tool.loopDeLoop,
          icon: Icons.all_inclusive_rounded,
          title: 'Loop-de-loop',
          tag: '\$${Game.priceLoop}',
          chip: '\$${Game.priceLoop}',
          enabled: game.balance >= Game.priceLoop,
          desc:
              'A vertical 360° on flat straight track. Trains need momentum: without an active speed boost they stall short of the hoop. Tap a loop to remove it.',
        ),
        _toolItem(
          tool: Tool.jumpRamp,
          icon: Icons.trending_up_rounded,
          title: 'Jump ramp',
          tag: '\$${Game.priceRamp}',
          chip: '\$${Game.priceRamp}',
          enabled: game.balance >= Game.priceRamp,
          desc:
              'One-way launcher: tap a clear cell, then a neighbor to aim. The train flies three cells and must land on aligned track — over water, chasms, even other lines. Tap a ramp to remove it.',
        ),
        _toolItem(
          tool: Tool.turntable,
          icon: Icons.sync_rounded,
          title: 'Turntable',
          tag: '\$${Game.priceTurntable}',
          chip: '\$${Game.priceTurntable}',
          enabled: game.balance >= Game.priceTurntable,
          desc:
              'A spinning platform at a line\'s end: trains roll on, turn around, and head back. Cap both ends of a dead-end line and it runs out-and-back — no loop needed.',
        ),
        _toolItem(
          tool: Tool.stop,
          icon: Icons.home_work_rounded,
          title: BuildingType.stop.label,
          tag: '\$${BuildingType.stop.price}',
          chip: '\$${BuildingType.stop.price}',
          enabled: game.balance >= BuildingType.stop.price,
          desc:
              '+\$${BuildingType.stop.bonus} each pass. Tap beside track — uneven ground levels automatically (\$${Game.priceTerraformStep} a step).',
        ),
        _toolItem(
          tool: Tool.depot,
          icon: Icons.warehouse_rounded,
          title: BuildingType.depot.label,
          tag: '\$${BuildingType.depot.price}',
          chip: '\$${BuildingType.depot.price}',
          enabled: game.balance >= BuildingType.depot.price,
          desc:
              '+\$${BuildingType.depot.bonus} each pass. Tap beside track — levels its site if needed.',
        ),
        _toolItem(
          tool: Tool.launchpad,
          icon: Icons.rocket_launch_rounded,
          title: 'Launchpad',
          tag: '\$${Game.priceLaunchpad}',
          chip: '\$${Game.priceLaunchpad}',
          enabled: game.balance >= Game.priceLaunchpad,
          desc:
              'A pair of pads — the train flies between them. Tap two clear, flat cells.',
        ),
        _toolItem(
          tool: Tool.switchTrack,
          icon: Icons.alt_route_rounded,
          title: 'Switch',
          tag: '\$${Game.priceSwitch}',
          chip: '\$${Game.priceSwitch}',
          enabled: game.balance >= Game.priceSwitch,
          desc:
              'Fork the line. Tap flat track, then the side the junction should face. Tap it later (in Select) to flip routes.',
        ),
        _toolItem(
          tool: Tool.tunnel,
          icon: Icons.looks_rounded,
          title: 'Tunnel',
          tag: '\$${Game.priceTunnel}',
          chip: '\$${Game.priceTunnel}',
          enabled: game.balance >= Game.priceTunnel,
          desc:
              'Bore under a mountain: tap two flat cells in line on opposite flanks, at matching height, with high ground the whole way between.',
        ),
      ];

  List<_ShopItem> _terraform() => [
        _toolItem(
          tool: Tool.raiseLand,
          icon: Icons.terrain_rounded,
          title: 'Raise land',
          tag: '\$10/st',
          chip: '\$${Game.priceTerraformStep} / step',
          enabled: game.balance >= Game.priceTerraformStep,
          desc:
              'Sculpt hills & peaks. Drag to paint; neighbors follow so slopes stay smooth.',
        ),
        _toolItem(
          tool: Tool.lowerLand,
          icon: Icons.front_loader,
          title: 'Lower land',
          tag: '\$10/st',
          chip: '\$${Game.priceTerraformStep} / step',
          enabled: game.balance >= Game.priceTerraformStep,
          desc:
              'Carve valleys & basins. Dig below the waterline and water floods in — track over water needs a bridge (+\$${Game.priceBridge}).',
        ),
        _toolItem(
          tool: Tool.levelLand,
          icon: Icons.iron,
          title: 'Level land',
          tag: '\$10/st',
          chip: '\$${Game.priceTerraformStep} / step',
          enabled: game.balance >= Game.priceTerraformStep,
          desc:
              'Match the grade: press a tile, then drag — everything you cross is leveled to it.',
        ),
      ];

  _ShopItem _deedItem(Dir side, IconData icon, String label, String unit) {
    if (!game.canGrow(side)) {
      return _ShopItem(
        icon: icon,
        title: 'Land deed · $label',
        tag: 'MAX',
        chip: 'claimed',
        chipMuted: true,
        enabled: false,
        desc: 'Frontier fully claimed — the map is at its $label limit.',
      );
    }
    return _ShopItem(
      icon: icon,
      title: 'Land deed · $label',
      tag: _money(game.deedPrice),
      chip: '\$${game.deedPrice}',
      enabled: game.balance >= game.deedPrice,
      desc:
          '+${Game.expandStep} $unit of frontier, with fresh hills, water and trees. Price rises per deed.',
      onTap: () => game.buyLand(side),
    );
  }

  List<_ShopItem> _expand() => [
        _deedItem(Dir.n, Icons.north_rounded, 'north', 'rows'),
        _deedItem(Dir.s, Icons.south_rounded, 'south', 'rows'),
        _deedItem(Dir.e, Icons.east_rounded, 'east', 'columns'),
        _deedItem(Dir.w, Icons.west_rounded, 'west', 'columns'),
      ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 234,
      decoration: const BoxDecoration(
        color: Pal.chromeBg,
        border: Border(left: BorderSide(color: Pal.chromeLine)),
      ),
      child: ListenableBuilder(
        listenable: game,
        builder: (context, _) => Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(12),
            children: [
              _brandRow(context),
              const SizedBox(height: 8),
              _statusChip(),
              const SizedBox(height: 8),
              _controlsRow(),
              const SizedBox(height: 10),
              _balanceCard(),
              if (game.scenario != null) ...[
                const SizedBox(height: 8),
                _missionsCard(),
              ],
              const SizedBox(height: 12),
              _sectionLabel('TOOLS'),
              _grid(_tools()),
              const SizedBox(height: 10),
              _sectionLabel('BUILD'),
              _grid(_build()),
              const SizedBox(height: 10),
              _sectionLabel('TERRAFORM'),
              _grid(_terraform()),
              const SizedBox(height: 10),
              _sectionLabel('EXPAND'),
              _grid(_expand()),
              const SizedBox(height: 12),
              _hintCard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _grid(List<_ShopItem> items) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final it in items) _ShopTile(item: it)],
      );

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 2),
        child: Text(s,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.3,
                color: Pal.faint)),
      );

  Widget _brandRow(BuildContext context) => Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: Pal.accent,
              borderRadius: BorderRadius.circular(7),
            ),
            child:
                const Icon(Icons.train_rounded, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(game.scenario?.name ?? 'Crazy Train',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: game.scenario == null ? 15.5 : 12.5,
                    fontWeight: FontWeight.w800,
                    color: Pal.ink)),
          ),
          if (widget.onExitToMap != null)
            Tooltip(
              message: 'Route map',
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: widget.onExitToMap,
                child: const SizedBox(
                  width: 26,
                  height: 26,
                  child: Icon(Icons.map_rounded, size: 16, color: Pal.faint),
                ),
              ),
            ),
          Tooltip(
            message: 'Start over',
            child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: () => _confirmReset(context),
              child: const SizedBox(
                width: 26,
                height: 26,
                child:
                    Icon(Icons.replay_rounded, size: 17, color: Pal.faint),
              ),
            ),
          ),
        ],
      );

  Widget _statusChip() {
    final broken = game.path == null;
    final (String text, Color color, bool filled) = switch (true) {
      _ when game.trains.any((t) => t.wrecked) => (
          'CRASH — tap the wreck · \$${Game.priceRerail}',
          Pal.bad,
          true
        ),
      _ when game.placingTrain => (
          'Tap your line to place the train',
          Pal.warn,
          true
        ),
      _ when broken => ('Track broken — train halted', Pal.bad, true),
      _ when game.loopStalled => (
          'Stalled at the loop — needs a speed-pad run-up',
          Pal.warn,
          true
        ),
      _ when game.cowBlocked => ('MOO — cow on the line!', Pal.warn, true),
      _ when game.speed == 0 => ('Paused', Pal.muted, false),
      _ => ('Running', Pal.good, true),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: filled ? color.withValues(alpha: 0.13) : Pal.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w800, color: color)),
    );
  }

  Widget _controlsRow() => Row(
        children: [
          Expanded(
            child: Tooltip(
              message: 'Honk! Shoos cows near the engine',
              child: Material(
                color: Pal.accent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: game.honk,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.campaign_rounded,
                            size: 16, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Honk',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _SpeedControls(game: game),
        ],
      );

  void _confirmReset(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.chromeBg,
        title: const Text('Start over?'),
        content: const Text(
            'This wipes your railway and money and rebuilds the starter loop.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Pal.bad),
            onPressed: () {
              game.newGame();
              Navigator.pop(ctx);
            },
            child: const Text('Start over'),
          ),
        ],
      ),
    );
  }

  Widget _balanceCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Pal.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Pal.chromeLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BALANCE',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    color: Pal.faint)),
            Text('\$${game.balance}',
                style: const TextStyle(
                    fontSize: 23, fontWeight: FontWeight.w800, color: Pal.ink)),
            Text(
              game.path == null
                  ? 'No payout — loop is broken'
                  : '≈ \$${game.projectedPayout} per lap',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: game.path == null ? Pal.bad : Pal.good),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                const Icon(Icons.train_rounded, size: 14, color: Pal.muted),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    '${game.trains.length} train${game.trains.length == 1 ? '' : 's'} · '
                    '${game.cars} car${game.cars == 1 ? '' : 's'} · '
                    '${game.trackLength} track',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Pal.muted),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _missionsCard() {
    final sc = game.scenario!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Pal.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Pal.chromeLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('MISSIONS',
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.3,
                  color: Pal.faint)),
          const SizedBox(height: 4),
          for (final m in sc.missions)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('★',
                      style: TextStyle(
                          fontSize: 12,
                          height: 1.1,
                          color: game.missionsDone.contains(m.id)
                              ? Pal.accent
                              : Pal.accent.withValues(alpha: 0.25))),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(m.title,
                        style: TextStyle(
                            fontSize: 10.5,
                            height: 1.3,
                            fontWeight: FontWeight.w700,
                            color: game.missionsDone.contains(m.id)
                                ? Pal.faint
                                : Pal.ink)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _hintCard() {
    final String hint = switch (game.tool) {
      Tool.track =>
        'Drag across the board to lay track. Corners become curves automatically. Straights climb one step per cell; curves need flat ground. Trains slow uphill and speed downhill.',
      Tool.stop || Tool.depot =>
        'Tap an empty cell next to your track. Uneven ground is leveled automatically (\$${Game.priceTerraformStep} per step). It pays its bonus every time the train passes.',
      Tool.bulldoze =>
        'Tap or drag over track and buildings to remove them. A red target ring means you\'re aiming at a train\'s engine: tapping scraps that train for half its value (drags never scrap).',
      Tool.raiseLand =>
        'Tap or drag to lift the ground one step at a time. Neighboring land follows so hills stay smooth — raise a riverbed to drain it.',
      Tool.lowerLand =>
        'Tap or drag to carve downward. Dig below the waterline and water floods in — that\'s how you make rivers and lakes. Track over water needs a bridge (+\$${Game.priceBridge}).',
      Tool.levelLand =>
        'Press a tile to set the grade, then drag: every cell you cross is raised or carved to match it. Cells pinned under track or buildings are skipped.',
      Tool.launchpad =>
        'Tap two clear cells to link a pad pair. Run track up to a pad and the train takes off, flies to its partner, and rolls on — rivers and mountains no object.',
      Tool.switchTrack =>
        'Tap a track piece, then an empty side: that side becomes the junction. Trains entering the junction side follow the thrown route; with no tool selected, tap a switch to flip it. Use two switches to build an alternate line.',
      Tool.tunnel =>
        'Tap two flat cells in a straight line, at the same height, with the mountain between them. Run track up to each portal — the train dives through. Mind your sculpting: strip the cover and the bore collapses.',
      Tool.signal =>
        'Tap track to place a signal; tap a signal to remove it. Trains hold at a red while the block ahead — up to the next signal — is occupied. Build a passing loop with two switches, signal both ends, and opposite trains will take turns. If they crash, tap the wreck to pay the crane (\$${Game.priceRerail}).',
      Tool.speedPad =>
        'Tap straight track to lay a booster strip: crossing it gives the train a burst of double speed. Chain pads for a longer surge — loops need the momentum. Tap a pad to remove it (half refund).',
      Tool.loopDeLoop =>
        'Tap flat straight track to raise a loop-de-loop. A train only makes it around with an active speed boost — lay a speed pad a cell or two before the hoop (or under a stalled train to send it through).',
      Tool.jumpRamp =>
        'Tap a clear flat cell to arm the ramp, then tap a neighboring cell to aim it. Run track into the ramp\'s tail: the train launches three cells forward and needs aligned track waiting at the landing spot. Ramps are one-way — a reversed train can\'t use them.',
      Tool.turntable =>
        'Tap a clear flat cell at the end of a line: track auto-connects into the table, and trains bounce off it back the way they came. Two turntables make an out-and-back line — the station still pays each full round trip.',
      Tool.dynamite => 'Coming soon.',
      Tool.none =>
        'Select mode: tap a switch to flip it, drag to pan, scroll to zoom. Pick a tool to build — Esc brings you back here. The train pays every full lap: cars × track length, plus stop bonuses. Honk at cows blocking the line!',
    };
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Pal.chip,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(hint,
          style: const TextStyle(fontSize: 10.5, height: 1.45, color: Pal.muted)),
    );
  }
}

// ---------------------------------------------------------------- tile

class _ShopTile extends StatefulWidget {
  final _ShopItem item;
  const _ShopTile({required this.item});

  @override
  State<_ShopTile> createState() => _ShopTileState();
}

class _ShopTileState extends State<_ShopTile> {
  final OverlayPortalController _pop = OverlayPortalController();
  final LayerLink _link = LayerLink();
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final it = widget.item;
    final Color accent = it.danger ? Pal.bad : Pal.accent;
    final Color border = it.selected
        ? accent
        : _hover
            ? accent
            : Pal.chromeLine;
    final Color iconColor = it.selected
        ? accent
        : _hover
            ? Pal.ink
            : Pal.muted;
    return CompositedTransformTarget(
      link: _link,
      child: OverlayPortal(
        controller: _pop,
        overlayChildBuilder: (context) => Align(
          alignment: Alignment.topLeft,
          child: CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.centerLeft,
            followerAnchor: Alignment.centerRight,
            offset: const Offset(-12, 0),
            child: _Popover(item: it),
          ),
        ),
        child: MouseRegion(
          onEnter: (_) {
            setState(() => _hover = true);
            _pop.show();
          },
          onExit: (_) {
            setState(() => _hover = false);
            _pop.hide();
          },
          child: GestureDetector(
            onLongPressStart: (_) => _pop.show(),
            onLongPressEnd: (_) => _pop.hide(),
            child: Opacity(
              opacity: it.enabled ? 1 : 0.42,
              child: Material(
                color: it.selected
                    ? accent.withValues(alpha: 0.10)
                    : Pal.card,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: it.enabled ? it.onTap : null,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: border, width: it.selected ? 1.6 : 1),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(it.icon, size: 20, color: iconColor),
                        const SizedBox(height: 1),
                        Text(it.tag,
                            style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.2,
                                color: it.selected ? accent : Pal.faint)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Popover extends StatelessWidget {
  final _ShopItem item;
  const _Popover({required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Pal.card,
      elevation: 8,
      shadowColor: Pal.ink.withValues(alpha: 0.3),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 196,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Pal.chromeLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(item.title,
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: Pal.ink)),
                ),
                if (item.chip != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: item.chipMuted ? Pal.chip : Pal.accent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text(item.chip!,
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color:
                                item.chipMuted ? Pal.faint : Colors.white)),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(item.desc,
                style: const TextStyle(
                    fontSize: 10.5, height: 1.45, color: Pal.muted)),
          ],
        ),
      ),
    );
  }
}
