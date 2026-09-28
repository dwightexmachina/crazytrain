import 'package:web/web.dart' as web;

/// Tiny Web Audio train whistle: two-tone chord with a soft envelope.
abstract final class Horn {
  static web.AudioContext? _ctx;

  static void play() {
    final ctx = _ctx ??= web.AudioContext();
    if (ctx.state == 'suspended') ctx.resume();
    final t0 = ctx.currentTime;
    final gain = ctx.createGain();
    gain.gain.setValueAtTime(0.0001, t0);
    gain.gain.exponentialRampToValueAtTime(0.22, t0 + 0.03);
    gain.gain.setValueAtTime(0.22, t0 + 0.28);
    gain.gain.exponentialRampToValueAtTime(0.0001, t0 + 0.5);
    gain.connect(ctx.destination);
    for (final f in const [311.1, 466.2]) {
      final osc = ctx.createOscillator();
      osc.type = 'triangle';
      osc.frequency.setValueAtTime(f, t0);
      osc.frequency.linearRampToValueAtTime(f * 0.97, t0 + 0.5);
      osc.connect(gain);
      osc.start(t0);
      osc.stop(t0 + 0.55);
    }
  }
}
