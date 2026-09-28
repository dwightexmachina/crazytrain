import 'package:flutter/material.dart';

/// Morning Line: Scandinavian pastel. Pale sand board, chalky terracotta /
/// sage / dusty-blue volumes, whisper-soft shadows, ivory UI chrome.
abstract final class Pal {
  // Chrome.
  static const pageBg = Color(0xFFF6F3EA);
  static const chromeBg = Color(0xFFFBF8F1);
  static const chromeLine = Color(0xFFE6E0D2);
  static const chip = Color(0xFFF0EBE0);
  static const ink = Color(0xFF4A463E);
  static const muted = Color(0xFF8A8172);
  static const faint = Color(0xFFB0A794);
  static const accent = Color(0xFFD97757); // terracotta
  static const card = Colors.white;

  // Board.
  static const ground = Color(0xFFEDE7DA);
  static const grid = Color(0xFFDFD8C8);
  static const bed = Color(0xFFCBB79A);
  static const tie = Color(0xFFB5A283);
  static const rail = Colors.white;
  static const shadow = Color(0x12000000);
  static const ghostOk = Color(0x883E8E6B);
  static const ghostBad = Color(0x88C25B4A);
  static const hover = Color(0x33D97757);

  // Volumes: (top, left, right) per material.
  static const trunk = (Color(0xFFB08968), Color(0xFF8F6E4F), Color(0xFF9E7B5B));
  static const leaf = (Color(0xFFA8C4A2), Color(0xFF7FA379), Color(0xFF93B58D));
  static const depot = (Color(0xFFC6D3E3), Color(0xFF94A6BC), Color(0xFFACBDD1));
  static const depotRoof = (Color(0xFF8FA6C0), Color(0xFF6E839B), Color(0xFF7E94AE));
  static const station = (Color(0xFFF7F2E8), Color(0xFFD6CCB8), Color(0xFFE6DCC8));
  static const stationRoof = (Color(0xFFE8927C), Color(0xFFC06E5A), Color(0xFFD67F6A));
  static const stop = (Color(0xFFEFE6D2), Color(0xFFC9BCA0), Color(0xFFDCCFB6));
  static const stopRoof = (Color(0xFFB8A26E), Color(0xFF93804F), Color(0xFFA6915E));
  static const car = (Color(0xFF93AEC9), Color(0xFF6E88A3), Color(0xFF7F9AB6));
  static const engine = (Color(0xFFD98B7C), Color(0xFFB0685C), Color(0xFFC4786A));
  static const cab = (Color(0xFFE5A192), Color(0xFFB0685C), Color(0xFFC4786A));
  static const engine2 = (Color(0xFF8FB08A), Color(0xFF6E8C69), Color(0xFF7E9E79));
  static const cab2 = (Color(0xFFA5C2A0), Color(0xFF6E8C69), Color(0xFF7E9E79));
  static const car2 = (Color(0xFFD9C9A3), Color(0xFFB3A480), Color(0xFFC6B691));
  static const signalGo = Color(0xFF6F9E7C);
  static const signalStop = Color(0xFFC25B4A);
  static const stack = (Color(0xFF5B564C), Color(0xFF403C34), Color(0xFF4D473E));

  static const good = Color(0xFF6F9E7C);
  static const bad = Color(0xFFC25B4A);
  static const warn = Color(0xFFC98A2D);

  // Crazy Train terrain & critters.
  static const water = Color(0xFFB7D2DC);
  static const waterEdge = Color(0xFF9DBEC9);
  static const plank = Color(0xFFA98F6C);
  static const trestle = Color(0xFF8F7758);
  static const lever = (Color(0xFFD97757), Color(0xFFB35C42), Color(0xFFC4694C));
  static const pad = (Color(0xFFC9BCE0), Color(0xFFA091BC), Color(0xFFB4A6CE));
  static const padRing = Color(0xFFF7F4FC);
  static const rock = (Color(0xFFCFC8B8), Color(0xFFA69E8C), Color(0xFFBCB3A0));
  static const rockHigh = (Color(0xFFDAD4C6), Color(0xFFB2AA98), Color(0xFFC8C0AE));
  static const snow = (Color(0xFFFDFCF8), Color(0xFFD8D3C6), Color(0xFFEAE5D8));
  static const cowBody = (Color(0xFFF7F4EC), Color(0xFFD9D3C4), Color(0xFFE8E2D4));
  static const cowHead = (Color(0xFF8A6B52), Color(0xFF6E543F), Color(0xFF7C5F48));
}
