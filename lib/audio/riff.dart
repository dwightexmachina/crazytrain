import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The splash riff: an original, galloping minor-key synth line written for
/// this game (not a rendition of any existing song). A palm-muted low
/// gallop chugs underneath while a detuned lead sings a short hook over
/// the top — four bars and out.
abstract final class Riff {
  static web.AudioContext? _ctx;
  static double _lastPlay = -10;

  // 138 BPM.
  static const _beat = 60.0 / 138.0;

  /// Try to start the riff. On a cold visit the context is suspended until
  /// the first user gesture (browser autoplay policy); we nudge it and, if
  /// it wakes shortly, play then — so a splash-mount attempt starts the
  /// music as early as the browser allows.
  static void play() {
    try {
      final ctx = _ctx ??= web.AudioContext();
      if (ctx.state != 'running') {
        // resume() resolves the moment the browser permits audio — on a
        // cold visit that's the first user gesture — and we play right then.
        ctx.resume().toDart.then((_) {
          try {
            if (ctx.state == 'running') _perform(ctx);
          } catch (_) {}
        });
        return;
      }
      _perform(ctx);
    } catch (_) {
      // No audio context (tests, odd browsers): the splash still works.
    }
  }

  static void _perform(web.AudioContext ctx) {
    final now = ctx.currentTime;
    if (now - _lastPlay < 4.0) return; // don't stack performances
    _lastPlay = now;
    final t0 = now + 0.05;

    final master = ctx.createGain();
    master.gain.setValueAtTime(0.5, t0);
    master.connect(ctx.destination);

    // ---- gallop bed: low fifths, chugging eighth + two sixteenths ----
    // Original progression: E5 | G5 A5 | C5 B5 | E5 with a D5-E5 kick.
    const e2 = 82.41, g2 = 98.0, a2 = 110.0, b2 = 123.47;
    const c3 = 130.81, d3 = 146.83;
    final barRoots = [
      [e2, e2, e2, e2],
      [g2, g2, a2, a2],
      [c3, c3, b2, b2],
      [e2, e2, d3, e2],
    ];
    final chugFilter = ctx.createBiquadFilter();
    chugFilter.type = 'lowpass';
    chugFilter.frequency.setValueAtTime(750, t0);
    chugFilter.connect(master);
    for (var bar = 0; bar < 4; bar++) {
      for (var beatIdx = 0; beatIdx < 4; beatIdx++) {
        final root = barRoots[bar][beatIdx];
        final beatT = t0 + (bar * 4 + beatIdx) * _beat;
        // gallop: one eighth, two sixteenths
        for (final (off, dur) in [
          (0.0, _beat * 0.42),
          (_beat * 0.50, _beat * 0.20),
          (_beat * 0.75, _beat * 0.20),
        ]) {
          _stab(ctx, chugFilter, root, beatT + off, dur, 0.30);
          _stab(ctx, chugFilter, root * 1.5, beatT + off, dur, 0.12);
        }
      }
    }

    // ---- lead hook: an original pentatonic line, detuned twin saws ----
    const e4 = 329.63, g4 = 392.0, a4 = 440.0, b4 = 493.88, d5 = 587.33;
    const e5 = 659.25;
    final lead = <(double, double, double)>[
      // (beat position, freq, beats held)
      (2.0, e4, 1.6), // pickup swell
      (4.0, g4, 0.9), (5.0, a4, 0.9), (6.0, b4, 1.8),
      (8.0, d5, 0.9), (9.0, b4, 0.7), (9.75, a4, 0.7), (10.5, g4, 1.2),
      (12.0, e4, 0.7), (12.75, b4, 0.7), (13.5, e5, 2.3),
    ];
    final leadFilter = ctx.createBiquadFilter();
    leadFilter.type = 'lowpass';
    leadFilter.frequency.setValueAtTime(2600, t0);
    leadFilter.connect(master);
    for (final (pos, freq, held) in lead) {
      _sing(ctx, leadFilter, freq, t0 + pos * _beat, held * _beat);
    }
  }

  /// One short, punchy chug stab.
  static void _stab(
    web.AudioContext ctx,
    web.AudioNode out,
    double freq,
    double t,
    double dur,
    double level,
  ) {
    final g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(level, t + 0.012);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    g.connect(out);
    final osc = ctx.createOscillator();
    osc.type = 'sawtooth';
    osc.frequency.setValueAtTime(freq, t);
    osc.connect(g);
    osc.start(t);
    osc.stop(t + dur + 0.02);
  }

  /// A sung lead note: two saws a few cents apart, soft attack, fades out.
  static void _sing(
    web.AudioContext ctx,
    web.AudioNode out,
    double freq,
    double t,
    double dur,
  ) {
    final g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(0.16, t + 0.05);
    g.gain.setValueAtTime(0.16, t + dur * 0.7);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    g.connect(out);
    for (final detune in const [0.9972, 1.0028]) {
      final osc = ctx.createOscillator();
      osc.type = 'sawtooth';
      osc.frequency.setValueAtTime(freq * detune, t);
      // A breath of downward drift at the tail, like easing off the key.
      osc.frequency.setValueAtTime(freq * detune, t + dur * 0.8);
      osc.frequency.linearRampToValueAtTime(freq * detune * 0.995, t + dur);
      osc.connect(g);
      osc.start(t);
      osc.stop(t + dur + 0.03);
    }
  }
}
