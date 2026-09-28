import 'dart:ui';

/// Isometric projection (2:1). Plane coordinates are in "board units";
/// one grid cell is [Iso.cell] units on a side.
abstract final class Iso {
  static const double cell = 40;
  static const double kx = 0.7071;
  static const double ky = 0.3536;

  /// Plane (x, y, height z) -> screen. Origin chosen by the painter.
  static Offset p(double x, double y, [double z = 0]) =>
      Offset(kx * (x - y), ky * (x + y) - z);

  /// Screen -> plane (assumes z = 0). Inverse of [p].
  static Offset unp(Offset s) {
    final a = s.dx / kx; // x - y
    final b = s.dy / ky; // x + y
    return Offset((a + b) / 2, (b - a) / 2);
  }
}
