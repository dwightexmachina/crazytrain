import 'package:flutter/material.dart';

import '../model/game.dart';
import 'palette.dart';

// ---------------------------------------------------------------- top bar

class TopBar extends StatelessWidget {
  final Game game;
  const TopBar({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: Pal.chromeBg,
        border: Border(bottom: BorderSide(color: Pal.chromeLine)),
      ),
      child: ListenableBuilder(
        listenable: game,
        builder: (context, _) {
          final broken = game.path == null;
          return Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: Pal.accent,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.train_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 10),
              const Text('Crazy Train',
                  style: TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w800, color: Pal.ink)),
              const SizedBox(width: 16),
              if (broken)
                _chip('Track broken — train halted', Pal.bad, filled: true)
              else if (game.cowBlocked)
                _chip('MOO — cow on the line!', Pal.warn, filled: true)
              else if (game.speed == 0)
                _chip('Paused', Pal.muted)
              else
                _chip('Running', Pal.good),
              const Spacer(),
              Tooltip(
                message: 'Honk! Shoos cows near the engine',
                child: Material(
                  color: Pal.accent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: game.honk,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: Row(children: [
                        Icon(Icons.campaign_rounded,
                            size: 17, color: Colors.white),
                        SizedBox(width: 5),
                        Text('Honk',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              _SpeedControls(game: game),
              const SizedBox(width: 12),
              IconButton(
                tooltip: 'Start over',
                icon: const Icon(Icons.replay_rounded, color: Pal.muted),
                onPressed: () => _confirmReset(context),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _chip(String text, Color color, {bool filled = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: filled ? color.withValues(alpha: 0.12) : Pal.chip,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(text,
            style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
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
}

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
            width: 34,
            height: 30,
            decoration: BoxDecoration(
              color: on ? Pal.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 17, color: on ? Colors.white : Pal.muted),
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
      child: Row(children: [
        btn(0, Icons.pause_rounded, 'Pause'),
        btn(1, Icons.play_arrow_rounded, 'Normal speed'),
        btn(2, Icons.fast_forward_rounded, 'Double speed'),
      ]),
    );
  }
}

// ---------------------------------------------------------------- shop

class ShopPanel extends StatefulWidget {
  final Game game;
  const ShopPanel({super.key, required this.game});

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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
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
          padding: const EdgeInsets.all(14),
          children: [
            _balanceCard(),
            const SizedBox(height: 10),
            _trainCard(),
            const SizedBox(height: 16),
            _toolTile(
              tool: Tool.none,
              icon: Icons.near_me_rounded,
              title: 'Select',
              subtitle:
                  'Flip switches by tapping them · drag to pan, scroll to zoom. Esc returns here.',
              enabled: true,
            ),
            const SizedBox(height: 14),
            _sectionLabel('BUILD'),
            _toolTile(
              tool: Tool.track,
              icon: Icons.route_rounded,
              title: 'Track',
              subtitle:
                  'Drag across the board. \$${Game.priceStraight} straight · \$${Game.priceCurve} curve · +\$${Game.priceBridge} bridge over water',
              enabled: game.balance >= Game.priceStraight,
            ),
            _buyTile(
              icon: Icons.directions_railway_rounded,
              title: 'Train car',
              subtitle: 'Adds a car · bigger payouts',
              price: Game.priceCar,
              onBuy: game.buyCar,
            ),
            _toolTile(
              tool: Tool.stop,
              icon: Icons.home_work_rounded,
              title: BuildingType.stop.label,
              subtitle:
                  '\$${BuildingType.stop.price} · +\$${BuildingType.stop.bonus} each pass. Tap beside track.',
              enabled: game.balance >= BuildingType.stop.price,
            ),
            _toolTile(
              tool: Tool.depot,
              icon: Icons.warehouse_rounded,
              title: BuildingType.depot.label,
              subtitle:
                  '\$${BuildingType.depot.price} · +\$${BuildingType.depot.bonus} each pass. Tap beside track.',
              enabled: game.balance >= BuildingType.depot.price,
            ),
            _toolTile(
              tool: Tool.launchpad,
              icon: Icons.rocket_launch_rounded,
              title: 'Launchpad',
              subtitle:
                  '\$${Game.priceLaunchpad} a pair · the train flies between pads. Tap two cells.',
              enabled: game.balance >= Game.priceLaunchpad,
            ),
            _toolTile(
              tool: Tool.switchTrack,
              icon: Icons.alt_route_rounded,
              title: 'Switch',
              subtitle:
                  '\$${Game.priceSwitch} · fork the line. Tap track, then the side to branch from.',
              enabled: game.balance >= Game.priceSwitch,
            ),
            const SizedBox(height: 14),
            _sectionLabel('EXPAND'),
            if (game.canExpandEast)
              _buyTile(
                icon: Icons.east_rounded,
                title: 'Land deed · east',
                subtitle:
                    '+${Game.expandStep} columns of frontier · price rises per deed',
                price: game.deedPrice,
                onBuy: () => game.buyLand(east: true),
              )
            else
              _lockedTile(
                icon: Icons.east_rounded,
                title: 'Land deed · east',
                subtitle: 'Frontier fully claimed',
              ),
            if (game.canExpandSouth)
              _buyTile(
                icon: Icons.south_rounded,
                title: 'Land deed · south',
                subtitle:
                    '+${Game.expandStep} rows of frontier · price rises per deed',
                price: game.deedPrice,
                onBuy: () => game.buyLand(east: false),
              )
            else
              _lockedTile(
                icon: Icons.south_rounded,
                title: 'Land deed · south',
                subtitle: 'Frontier fully claimed',
              ),
            const SizedBox(height: 14),
            _sectionLabel('TERRAFORM'),
            _toolTile(
              tool: Tool.raiseLand,
              icon: Icons.terrain_rounded,
              title: 'Raise land',
              subtitle:
                  '\$${Game.priceTerraformStep} per step · sculpt hills & peaks. Drag to paint.',
              enabled: game.balance >= Game.priceTerraformStep,
            ),
            _toolTile(
              tool: Tool.lowerLand,
              icon: Icons.south_west_rounded,
              title: 'Lower land',
              subtitle:
                  '\$${Game.priceTerraformStep} per step · carve valleys & basins',
              enabled: game.balance >= Game.priceTerraformStep,
            ),
            const SizedBox(height: 14),
            _sectionLabel('DEMOLISH'),
            _toolTile(
              tool: Tool.bulldoze,
              icon: Icons.construction_rounded,
              title: 'Bulldoze',
              subtitle: 'Remove track or buildings · 50% refund',
              enabled: true,
              danger: true,
            ),
            const SizedBox(height: 14),
            _hintCard(),
          ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 2),
        child: Text(s,
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.4,
                color: Pal.faint)),
      );

  Widget _balanceCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Pal.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Pal.chromeLine),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('BALANCE',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: Pal.faint)),
            const SizedBox(height: 2),
            Text('\$${game.balance}',
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, color: Pal.ink)),
            const SizedBox(height: 6),
            Text(
              game.path == null
                  ? 'No payout — loop is broken'
                  : '≈ \$${game.projectedPayout} per lap',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: game.path == null ? Pal.bad : Pal.good),
            ),
          ],
        ),
      );

  Widget _trainCard() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Pal.chip,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.train_rounded, size: 18, color: Pal.muted),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${game.cars} car${game.cars == 1 ? '' : 's'} · ${game.trackLength} track',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: Pal.ink),
              ),
            ),
          ],
        ),
      );

  Widget _tileShell({
    required Widget child,
    required bool enabled,
    bool selected = false,
    bool danger = false,
    VoidCallback? onTap,
  }) {
    final borderColor = selected
        ? (danger ? Pal.bad : Pal.accent)
        : Pal.chromeLine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? (danger
                ? Pal.bad.withValues(alpha: 0.07)
                : Pal.accent.withValues(alpha: 0.08))
            : Pal.card,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor, width: selected ? 1.6 : 1),
            ),
            child: Opacity(opacity: enabled ? 1 : 0.45, child: child),
          ),
        ),
      ),
    );
  }

  Widget _tileRow(IconData icon, String title, String subtitle,
      {Widget? trailing, Color? iconColor}) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Pal.chip,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 18, color: iconColor ?? Pal.muted),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: Pal.ink)),
              const SizedBox(height: 1),
              Text(subtitle,
                  style: const TextStyle(
                      fontSize: 11, height: 1.25, color: Pal.muted)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 6), trailing],
      ],
    );
  }

  Widget _toolTile({
    required Tool tool,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool enabled,
    bool danger = false,
  }) {
    final selected = game.tool == tool;
    return _tileShell(
      enabled: enabled,
      selected: selected,
      danger: danger,
      onTap: () => game.setTool(tool),
      child: _tileRow(icon, title, subtitle,
          iconColor: selected ? (danger ? Pal.bad : Pal.accent) : null,
          trailing: selected
              ? Icon(Icons.check_circle_rounded,
                  size: 18, color: danger ? Pal.bad : Pal.accent)
              : null),
    );
  }

  Widget _buyTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required int price,
    required bool Function() onBuy,
  }) {
    final enabled = game.balance >= price;
    return _tileShell(
      enabled: enabled,
      onTap: () => onBuy(),
      child: _tileRow(icon, title, subtitle,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: enabled ? Pal.accent : Pal.chip,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('\$$price',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: enabled ? Colors.white : Pal.faint)),
          )),
    );
  }

  Widget _lockedTile(
      {required IconData icon, required String title, required String subtitle}) {
    return _tileShell(
      enabled: false,
      child: _tileRow(icon, title, subtitle,
          trailing: const Icon(Icons.lock_rounded, size: 15, color: Pal.faint)),
    );
  }

  Widget _hintCard() {
    final String hint = switch (game.tool) {
      Tool.track =>
        'Drag across the board to lay track. Corners become curves automatically. Straights climb one step per cell; curves need flat ground. Trains slow uphill and speed downhill.',
      Tool.stop || Tool.depot =>
        'Tap an empty cell next to your track. It pays its bonus every time the train passes.',
      Tool.bulldoze => 'Tap or drag over track and buildings to remove them.',
      Tool.raiseLand =>
        'Tap or drag to lift the ground one step at a time. Neighboring land follows so hills stay smooth — raise a riverbed to drain it.',
      Tool.lowerLand =>
        'Tap or drag to carve downward. Dig below the waterline and water floods in — that\'s how you make rivers and lakes. Track over water needs a bridge (+\$${Game.priceBridge}).',
      Tool.launchpad =>
        'Tap two clear cells to link a pad pair. Run track up to a pad and the train takes off, flies to its partner, and rolls on — rivers and mountains no object.',
      Tool.switchTrack =>
        'Tap a track piece, then an empty side: that side becomes the junction. Trains entering the junction side follow the thrown route; with no tool selected, tap a switch to flip it. Use two switches to build an alternate line.',
      Tool.none =>
        'Select mode: tap a switch to flip it, drag to pan, scroll to zoom. Pick a tool to build — Esc brings you back here. The train pays every full lap: cars × track length, plus stop bonuses. Honk at cows blocking the line!',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Pal.chip,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(hint,
          style: const TextStyle(fontSize: 11.5, height: 1.45, color: Pal.muted)),
    );
  }
}
