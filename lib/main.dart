import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'model/game.dart';
import 'model/scenario.dart';
import 'ui/board_view.dart';
import 'ui/line_clear.dart';
import 'ui/palette.dart';
import 'ui/panel.dart';
import 'ui/route_map_screen.dart';
import 'ui/splash_screen.dart';

void main() {
  runApp(const TrainMakerApp());
}

class TrainMakerApp extends StatefulWidget {
  const TrainMakerApp({super.key});

  @override
  State<TrainMakerApp> createState() => _TrainMakerAppState();
}

class _TrainMakerAppState extends State<TrainMakerApp> {
  Game? game; // null = route map is showing
  bool _splash = true;

  void _board(Scenario sc, {required bool resume}) {
    final g = Game(scenario: sc, resume: resume);
    if (!resume) g.saveNow(); // a fresh start claims the slot immediately
    setState(() => game = g);
  }

  void _confirmExitToMap(BuildContext context) {
    final g = game;
    if (g == null) return;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Pal.chromeBg,
        title: const Text('Return to the route map?'),
        content: const Text('Your railway is saved and will be waiting.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              g.saveNow();
              Navigator.pop(ctx);
              setState(() => game = null);
            },
            child: const Text('Route map'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    return MaterialApp(
      title: 'Crazy Train',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: Pal.pageBg,
        colorScheme: ColorScheme.fromSeed(seedColor: Pal.accent),
        fontFamily: 'Roboto',
      ),
      home: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              game?.setTool(Tool.none),
          const CharacterActivator('+'): () => game?.devGrant(),
          const CharacterActivator('='): () => game?.devGrant(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                if (g == null)
                  RouteMapScreen(
                    onBoard: _board,
                    onSandbox: () => setState(() => game = Game()),
                  )
                else
                  Builder(builder: (context) {
                    return ListenableBuilder(
                      listenable: g,
                      builder: (context, _) => Stack(
                        fit: StackFit.expand,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                child: BoardView(
                                    key: ValueKey(g.scenario?.id ?? 'sandbox'),
                                    game: g),
                              ),
                              ShopPanel(
                                  game: g,
                                  onExitToMap: () =>
                                      _confirmExitToMap(context)),
                            ],
                          ),
                          if (g.lineClearPending)
                            LineClearOverlay(
                              game: g,
                              onRouteMap: () {
                                g.dismissLineClear();
                                g.saveNow();
                                setState(() => game = null);
                              },
                            ),
                        ],
                      ),
                    );
                  }),
                if (_splash)
                  SplashScreen(
                    onDismiss: () => setState(() => _splash = false),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
