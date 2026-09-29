import 'dart:js_interop';
import 'dart:math' as math;

import 'package:web/web.dart' as web;

import '../model/game.dart';

/// Synthesized, diegetic sound effects — no music, ever. The game model
/// pushes event names into [Game.sfx]; the board's ticker calls [pump]
/// each frame to drain them and to keep the chuff loop scheduled. Audio
/// stays silent until [warm] runs from a user gesture (browser rule).
abstract final class Sfx {
  static web.AudioContext? _ctx;
  static web.GainNode? _master;
  static web.AudioBuffer? _noise;
  static double _nextChuff = 0;
  static final math.Random _rng = math.Random();

  static bool muted =
      web.window.localStorage.getItem('ct_mute') == '1';

  static void toggleMuted() {
    muted = !muted;
    web.window.localStorage.setItem('ct_mute', muted ? '1' : '0');
    _master?.gain.value = muted ? 0 : 1;
  }

  /// Create/resume the context. Call from a pointer gesture.
  static void warm() {
    try {
      final ctx = _ctx ??= web.AudioContext();
      if (ctx.state == 'suspended') ctx.resume();
      if (_master == null) {
        _master = ctx.createGain()
          ..gain.value = muted ? 0 : 1;
        _master!.connect(ctx.destination);
      }
    } catch (_) {}
  }

  /// Drain the game's queued events and keep the chuff scheduled.
  static void pump(Game g) {
    final ctx = _ctx;
    if (ctx == null || _master == null) {
      g.sfx.clear(); // not woken yet: drop silently
      return;
    }
    try {
      for (final e in g.sfx) {
        _play(ctx, e);
      }
      g.sfx.clear();
      _chuff(ctx, g);
    } catch (_) {
      g.sfx.clear();
    }
  }

  // ------------------------------------------------------------ plumbing

  static web.AudioBuffer _noiseBuf(web.AudioContext ctx) {
    if (_noise != null) return _noise!;
    final n = (ctx.sampleRate * 0.3).toInt();
    final buf = ctx.createBuffer(1, n, ctx.sampleRate);
    final d = buf.getChannelData(0).toDart;
    for (var i = 0; i < n; i++) {
      d[i] = _rng.nextDouble() * 2 - 1;
    }
    return _noise = buf;
  }

  /// One enveloped oscillator: [f0]→[f1] Hz over [dur]s at [gain].
  static void _tone(web.AudioContext ctx, String type, double f0, double f1,
      double dur, double gain,
      {double at = 0}) {
    final t0 = ctx.currentTime + at;
    final g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + 0.015);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    g.connect(_master!);
    final o = ctx.createOscillator();
    o.type = type;
    o.frequency.setValueAtTime(f0, t0);
    o.frequency.exponentialRampToValueAtTime(math.max(20, f1), t0 + dur);
    o.connect(g);
    o.start(t0);
    o.stop(t0 + dur + 0.05);
  }

  /// A filtered noise burst: band [freq] Hz wide-ish, [dur]s at [gain].
  static void _hiss(web.AudioContext ctx, double freq, double dur, double gain,
      {double at = 0, String filter = 'bandpass', double? sweepTo}) {
    final t0 = ctx.currentTime + at;
    final src = ctx.createBufferSource();
    src.buffer = _noiseBuf(ctx);
    src.loop = true;
    final f = ctx.createBiquadFilter();
    f.type = filter;
    f.frequency.setValueAtTime(freq, t0);
    if (sweepTo != null) {
      f.frequency.exponentialRampToValueAtTime(sweepTo, t0 + dur);
    }
    final g = ctx.createGain();
    g.gain.setValueAtTime(0.0001, t0);
    g.gain.exponentialRampToValueAtTime(gain, t0 + 0.02);
    g.gain.exponentialRampToValueAtTime(0.0001, t0 + dur);
    src.connect(f);
    f.connect(g);
    g.connect(_master!);
    src.start(t0);
    src.stop(t0 + dur + 0.05);
  }

  // ------------------------------------------------------------ effects

  static void _play(web.AudioContext ctx, String e) {
    switch (e) {
      case 'payout': // cash ding, two rising notes
        _tone(ctx, 'sine', 880, 880, 0.18, 0.10);
        _tone(ctx, 'sine', 1175, 1175, 0.22, 0.10, at: 0.07);
      case 'plow': // a light ding and an indignant moo
        _tone(ctx, 'sine', 660, 660, 0.12, 0.08);
        _tone(ctx, 'sawtooth', 180, 110, 0.28, 0.07, at: 0.05);
      case 'crash': // clatter and a thud
        _hiss(ctx, 900, 0.4, 0.28, filter: 'lowpass');
        _tone(ctx, 'sine', 95, 40, 0.45, 0.30);
      case 'boom': // dynamite: deep noise + pitch drop
        _hiss(ctx, 300, 0.5, 0.35, filter: 'lowpass');
        _tone(ctx, 'sine', 70, 28, 0.55, 0.35);
      case 'launch': // whoosh sweeping up
        _hiss(ctx, 400, 0.38, 0.16, sweepTo: 2600);
      case 'tunnel': // two hollow blips
        _tone(ctx, 'triangle', 220, 200, 0.10, 0.10);
        _tone(ctx, 'triangle', 180, 165, 0.12, 0.08, at: 0.13);
      case 'loop': // whoop up and over
        _tone(ctx, 'sine', 400, 820, 0.24, 0.12);
        _tone(ctx, 'sine', 820, 420, 0.24, 0.12, at: 0.24);
      case 'rerail': // crane clank, twice
        _tone(ctx, 'square', 150, 140, 0.07, 0.10);
        _tone(ctx, 'square', 130, 120, 0.08, 0.09, at: 0.11);
      case 'clear': // LINE CLEAR: three ascending dings
        _tone(ctx, 'triangle', 523, 523, 0.2, 0.12);
        _tone(ctx, 'triangle', 659, 659, 0.2, 0.12, at: 0.13);
        _tone(ctx, 'triangle', 784, 784, 0.3, 0.13, at: 0.26);
    }
  }

  /// The working-engine chuff: short noise ticks scheduled just ahead,
  /// paced by the lead train's actual speed (doubled under boost).
  static void _chuff(web.AudioContext ctx, Game g) {
    final now = ctx.currentTime;
    final tr = g.trains.first;
    final running = g.speed > 0 &&
        tr.path != null &&
        !tr.wrecked &&
        !g.cowBlocked &&
        !g.loopStalled;
    if (!running || muted) {
      _nextChuff = math.max(_nextChuff, now);
      return;
    }
    final rate =
        2.4 * g.speed * (tr.boost > 0 ? 2 : 1); // chuffs per second
    if (_nextChuff < now) _nextChuff = now;
    while (_nextChuff < now + 0.2) {
      _hiss(ctx, 700 + _rng.nextDouble() * 300, 0.06, 0.05,
          at: _nextChuff - now);
      _nextChuff += 1 / rate;
    }
  }
}
