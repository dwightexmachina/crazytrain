import 'dart:ui';

import 'track.dart';

/// Corner-based elevation: one integer height per vertex on a
/// (cols+1) x (rows+1) lattice. Cell (x,y) is bounded by vertices
/// (x,y), (x+1,y), (x+1,y+1), (x,y+1). Vertices that touch (8-way) never
/// differ by more than one step; edits cascade outward to keep that true,
/// SimCity-2000 style.
class HeightField {
  /// Terrain below this level is underwater; the plain (height 0) is dry.
  static const double waterLevel = -0.5;
  static const int minHeight = -3, maxHeight = 8;

  int cols, rows; // in cells
  List<int> _h;

  HeightField(this.cols, this.rows)
      : _h = List.filled((cols + 1) * (rows + 1), 0);

  int _idx(int vx, int vy) => vy * (cols + 1) + vx;

  int vAt(int vx, int vy) => _h[_idx(vx, vy)];

  void setVertex(int vx, int vy, int h) => _h[_idx(vx, vy)] = h;

  int minCorner(Cell c) {
    final (a, b, d, e) = corners(c);
    return [a, b, d, e].reduce((x, y) => x < y ? x : y);
  }

  /// Any part of the cell dips below the water table.
  bool isWet(Cell c) => minCorner(c) < waterLevel;

  List<int> toList() => List.of(_h);

  void loadFrom(List<int> values) {
    if (values.length == _h.length) _h = List.of(values);
  }

  void reset(int newCols, int newRows) {
    cols = newCols;
    rows = newRows;
    _h = List.filled((cols + 1) * (rows + 1), 0);
  }

  /// Corner heights of a cell: nw, ne, se, sw.
  (int, int, int, int) corners(Cell c) => (
        vAt(c.x, c.y),
        vAt(c.x + 1, c.y),
        vAt(c.x + 1, c.y + 1),
        vAt(c.x, c.y + 1),
      );

  bool isFlat(Cell c) {
    final (a, b, d, e) = corners(c);
    return a == b && b == d && d == e;
  }

  /// Height of a flat cell. (Its nw corner; only meaningful when flat.)
  int floorOf(Cell c) => vAt(c.x, c.y);

  double centerZ(Cell c) {
    final (a, b, d, e) = corners(c);
    return (a + b + d + e) / 4;
  }

  /// Bilinear ground height at a plane point.
  double zAt(Offset p) {
    final x = p.dx.clamp(0.0, cols.toDouble());
    final y = p.dy.clamp(0.0, rows.toDouble());
    final cx = x.floor().clamp(0, cols - 1), cy = y.floor().clamp(0, rows - 1);
    final u = x - cx, v = y - cy;
    return vAt(cx, cy) * (1 - u) * (1 - v) +
        vAt(cx + 1, cy) * u * (1 - v) +
        vAt(cx, cy + 1) * (1 - u) * v +
        vAt(cx + 1, cy + 1) * u * v;
  }

  /// Plan a one-step raise (delta 1) or lower (delta -1) of a vertex,
  /// cascading so no touching vertices end up more than one step apart.
  /// Returns the vertex-index -> new-height map, or null when the cascade
  /// would move a vertex for which [locked] is true.
  Map<int, int>? planStep(int vx, int vy, int delta,
      {required bool Function(int vx, int vy) locked}) {
    if (vx < 0 || vx > cols || vy < 0 || vy > rows) return null;
    if (locked(vx, vy)) return null;
    final target = vAt(vx, vy) + delta;
    if (target < minHeight || target > maxHeight) return null;
    final pending = <int, int>{_idx(vx, vy): target};
    int cur(int x, int y) => pending[_idx(x, y)] ?? vAt(x, y);
    final queue = [(vx, vy)];
    while (queue.isNotEmpty) {
      final (ux, uy) = queue.removeLast();
      final hu = cur(ux, uy);
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (dx == 0 && dy == 0) continue;
          final nx = ux + dx, ny = uy + dy;
          if (nx < 0 || nx > cols || ny < 0 || ny > rows) continue;
          final hn = cur(nx, ny);
          int? target;
          if (hu - hn > 1) target = hu - 1; // pull the neighbor up
          if (hn - hu > 1) target = hu + 1; // or drag it down
          if (target != null && target != hn) {
            if (locked(nx, ny)) return null;
            pending[_idx(nx, ny)] = target;
            queue.add((nx, ny));
          }
        }
      }
    }
    return pending;
  }

  /// Total height-steps a plan moves — the basis for terraform pricing.
  int stepsIn(Map<int, int> plan) {
    var sum = 0;
    plan.forEach((i, h) => sum += (h - _h[i]).abs());
    return sum;
  }

  void apply(Map<int, int> plan) => plan.forEach((i, h) => _h[i] = h);

  /// Grow the lattice for a land deed. Existing heights land at their old
  /// positions shifted by (dx, dy) — north/west deeds move the world — and
  /// new vertices replicate the old edge so the frontier joins smoothly.
  void expand(int newCols, int newRows, {int dx = 0, int dy = 0}) {
    final out = List.filled((newCols + 1) * (newRows + 1), 0);
    for (var y = 0; y <= newRows; y++) {
      for (var x = 0; x <= newCols; x++) {
        out[y * (newCols + 1) + x] =
            vAt((x - dx).clamp(0, cols), (y - dy).clamp(0, rows));
      }
    }
    cols = newCols;
    rows = newRows;
    _h = out;
  }
}
