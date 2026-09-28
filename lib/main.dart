import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'audio/riff.dart';
import 'model/game.dart';
import 'ui/board_view.dart';
import 'ui/palette.dart';
import 'ui/panel.dart';
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
  final Game game = Game();
  bool _splash = true;

  @override
  Widget build(BuildContext context) {
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
              game.setTool(Tool.none),
          const CharacterActivator('+'): game.devGrant,
          const CharacterActivator('='): game.devGrant,
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Column(
                  children: [
                    TopBar(game: game),
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: BoardView(game: game)),
                          ShopPanel(game: game),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_splash)
                  SplashScreen(
                    onDismiss: () {
                      setState(() => _splash = false);
                      Riff.play(); // the dismissal tap unlocked audio
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
