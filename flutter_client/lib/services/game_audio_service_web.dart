import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:web/web.dart';

import '../state/session.dart';

enum GameAudioCue {
  explore,
  fight,
  rest,
  loot,
  fire,
  hit,
  miss,
  reload,
  pause,
  victory,
  defeat,
}

class GameAudioService {
  GameAudioService._();

  static final GameAudioService instance = GameAudioService._();

  static const int _sampleRate = 22050;
  static const double _musicVolumeDefault = 0.72;
  static const double _musicVolumeReduced = 0.42;
  static const double _sfxVolumeDefault = 0.92;
  static const double _sfxVolumeReduced = 0.54;

  Session? _session;
  void Function()? _sessionListener;
  bool _musicPrepared = false;
  bool _musicRunning = false;
  bool _disposed = false;
  int _effectCursor = 0;

  String? _battleLoopSource;
  final Map<GameAudioCue, String> _cueSources = {};
  HTMLAudioElement? _musicElement;
  final List<HTMLAudioElement> _effectElements = List.generate(4, (_) => HTMLAudioElement());

  double get _musicVolume =>
      _session?.reduceMusicVolumeEnabled == true ? _musicVolumeReduced : _musicVolumeDefault;

  double get _effectVolume =>
      _session?.reduceSfxVolumeEnabled == true ? _sfxVolumeReduced : _sfxVolumeDefault;

  Future<void> attachSession(Session session) async {
    if (identical(_session, session)) {
      await _syncWithSession();
      return;
    }

    if (_session != null && _sessionListener != null) {
      _session!.removeListener(_sessionListener!);
    }

    _session = session;
    _sessionListener = _syncWithSession;
    session.addListener(_sessionListener!);
    await _syncWithSession();
  }

  Future<void> _syncWithSession() async {
    if (_disposed) {
      return;
    }

    final session = _session;
    if (session == null || session.status != SessionStatus.signedIn) {
      _musicRunning = false;
      _musicElement?.pause();
      _musicElement?.currentTime = 0;
      return;
    }

    _musicElement?.volume = _musicVolume;
    for (final element in _effectElements) {
      element.volume = _effectVolume;
    }

    if (_musicRunning) {
      return;
    }
    await ensureMusicPlaying();
  }

  Future<void> ensureMusicPlaying() async {
    if (_disposed) {
      return;
    }

    final session = _session;
    if (session == null || session.status != SessionStatus.signedIn) {
      return;
    }

    try {
      await _prepareMusic();
      final element = _musicElement ??= HTMLAudioElement();
      element
        ..src = _battleLoopSource!
        ..loop = true
        ..preload = 'auto'
        ..volume = _musicVolume;
      await element.play().toDart;
      _musicRunning = true;
    } catch (_) {
      _musicRunning = false;
    }
  }

  Future<void> playCue(GameAudioCue cue) async {
    if (_disposed) {
      return;
    }

    final session = _session;
    if (session == null || session.status != SessionStatus.signedIn) {
      return;
    }

    await _prepareCues();

    final source = _cueSources[cue];
    if (source == null) {
      return;
    }

    final element = _effectElements[_effectCursor % _effectElements.length];
    _effectCursor = (_effectCursor + 1) % _effectElements.length;

    try {
      element
        ..src = source
        ..loop = false
        ..preload = 'auto'
        ..volume = _effectVolume
        ..currentTime = 0;
      await element.play().toDart;
    } catch (_) {
      // Audio is best-effort. Gameplay continues if the browser blocks playback.
    }
  }

  Future<void> playActionCue(String actionName) async {
    if (actionName == 'fight') {
      await playCue(GameAudioCue.fight);
    } else if (actionName == 'rest') {
      await playCue(GameAudioCue.rest);
    } else if (actionName == 'loot') {
      await playCue(GameAudioCue.loot);
    } else {
      await playCue(GameAudioCue.explore);
    }
  }

  Future<void> playHitCue() => playCue(GameAudioCue.hit);

  Future<void> playMissCue() => playCue(GameAudioCue.miss);

  Future<void> playReloadCue() => playCue(GameAudioCue.reload);

  Future<void> playPauseCue({required bool paused}) =>
      playCue(paused ? GameAudioCue.pause : GameAudioCue.explore);

  Future<void> playRoundEndCue({required bool victory}) =>
      playCue(victory ? GameAudioCue.victory : GameAudioCue.defeat);

  Future<void> dispose() async {
    _disposed = true;
    if (_session != null && _sessionListener != null) {
      _session!.removeListener(_sessionListener!);
    }
    _session = null;
    _sessionListener = null;
    _musicRunning = false;
    _musicElement?.pause();
    for (final element in _effectElements) {
      element.pause();
    }
  }

  Future<void> _prepareMusic() async {
    if (_musicPrepared) {
      return;
    }
    _battleLoopSource = _toDataUri(_buildBattleLoop());
    _musicPrepared = true;
  }

  Future<void> _prepareCues() async {
    if (_cueSources.isNotEmpty) {
      return;
    }

    _cueSources[GameAudioCue.explore] = _toDataUri(
      _buildCue(
        durationSeconds: 0.18,
        sampleBuilder: (t) {
          final sweep = _pitchSweep(t, 0.16, 0.28);
          final body = _triangleWave(sweep, t) * _envelope(t, 0.01, 0.06, 0.12);
          return body * 0.8;
        },
      ),
    );
    _cueSources[GameAudioCue.fight] = _toDataUri(
      _buildCue(
        durationSeconds: 0.22,
        sampleBuilder: (t) {
          final sweep = _pitchSweep(t, 0.55, 0.22);
          final body = _sawWave(sweep, t) * _envelope(t, 0.005, 0.05, 0.16);
          return body * 0.9;
        },
      ),
    );
    _cueSources[GameAudioCue.rest] = _toDataUri(
      _buildCue(
        durationSeconds: 0.34,
        sampleBuilder: (t) {
          final base = _bellTone(t, 392) + (_bellTone(t, 523.25) * 0.6);
          return base * _envelope(t, 0.01, 0.08, 0.18) * 0.6;
        },
      ),
    );
    _cueSources[GameAudioCue.loot] = _toDataUri(
      _buildCue(
        durationSeconds: 0.20,
        sampleBuilder: (t) {
          final ping = _bellTone(t, 659.25) + (_bellTone(t, 987.77) * 0.45);
          return ping * _envelope(t, 0.002, 0.03, 0.14) * 0.8;
        },
      ),
    );
    _cueSources[GameAudioCue.fire] = _toDataUri(
      _buildCue(
        durationSeconds: 0.14,
        sampleBuilder: (t) {
          final sweep = _pitchSweep(t, 0.22, 0.1);
          final noise = _noise(t) * 0.18;
          return (_squareWave(sweep, t) * 0.72 + noise) * _envelope(t, 0.002, 0.03, 0.08);
        },
      ),
    );
    _cueSources[GameAudioCue.hit] = _toDataUri(
      _buildCue(
        durationSeconds: 0.18,
        sampleBuilder: (t) {
          final thump = _sineWave(96, t) * _envelope(t, 0.002, 0.02, 0.16);
          final crack = _noise(t) * _envelope(t, 0.0, 0.008, 0.05) * 0.55;
          return thump * 0.85 + crack;
        },
      ),
    );
    _cueSources[GameAudioCue.miss] = _toDataUri(
      _buildCue(
        durationSeconds: 0.08,
        sampleBuilder: (t) {
          final blip = _pitchSweep(t, 0.24, 0.12);
          return _triangleWave(blip, t) * _envelope(t, 0.001, 0.015, 0.04) * 0.72;
        },
      ),
    );
    _cueSources[GameAudioCue.reload] = _toDataUri(
      _buildCue(
        durationSeconds: 0.28,
        sampleBuilder: (t) {
          final sweep = 0.18 + (t * 0.9);
          final base = _sineWave(220 + (220 * sweep), t) + (_sineWave(330 + (330 * sweep), t) * 0.45);
          return base * _envelope(t, 0.005, 0.06, 0.16) * 0.72;
        },
      ),
    );
    _cueSources[GameAudioCue.pause] = _toDataUri(
      _buildCue(
        durationSeconds: 0.12,
        sampleBuilder: (t) => _bellTone(t, 220) * _envelope(t, 0.002, 0.02, 0.06) * 0.6,
      ),
    );
    _cueSources[GameAudioCue.victory] = _toDataUri(
      _buildCue(
        durationSeconds: 0.26,
        sampleBuilder: (t) {
          final first = _bellTone(t, 523.25);
          final second = _bellTone(t, 659.25);
          final third = _bellTone(t, 783.99);
          return (first * 0.55 + second * 0.72 + third * 0.9) *
              _envelope(t, 0.002, 0.04, 0.18) *
              0.6;
        },
      ),
    );
    _cueSources[GameAudioCue.defeat] = _toDataUri(
      _buildCue(
        durationSeconds: 0.30,
        sampleBuilder: (t) {
          final low = _sineWave(174.61, t);
          final fall = _pitchSweep(t, 0.26, 0.08);
          return (low * 0.6 + _triangleWave(fall, t) * 0.7) *
              _envelope(t, 0.005, 0.08, 0.18) *
              0.6;
        },
      ),
    );
  }

  Uint8List _buildBattleLoop() {
    const stepDuration = 0.5;
    const steps = 16;
    final duration = stepDuration * steps;
    final chordPattern = <_Chord>[
      _Chord(root: 110.0, third: 130.81, fifth: 164.81),
      _Chord(root: 87.31, third: 110.0, fifth: 146.83),
      _Chord(root: 130.81, third: 164.81, fifth: 196.0),
      _Chord(root: 98.0, third: 123.47, fifth: 146.83),
    ];
    final bassPattern = <double>[55.0, 65.41, 73.42, 82.41, 55.0, 65.41, 98.0, 82.41];

    return _buildWav(durationSeconds: duration, sampleBuilder: (t) {
      final stepIndex = (t / stepDuration).floor() % steps;
      final beatInStep = (t % stepDuration) / stepDuration;
      final barIndex = (stepIndex ~/ 4) % chordPattern.length;
      final chord = chordPattern[barIndex];
      final bassNote = bassPattern[stepIndex % bassPattern.length];

      final kick = _percussionPulse(t, stepDuration, 0.012, 1.0, 78);
      final snare = _percussionPulse(t - (stepDuration / 2), stepDuration, 0.010, 0.7, 160);
      final hat = _percussionPulse(t, stepDuration / 2, 0.006, 0.22, 6200, highPass: true);

      final bass = _sineWave(bassNote, t) * _envelope(beatInStep, 0.01, 0.06, 0.18) * 0.9;
      final rootPulse = _triangleWave(chord.root * 2, t) * 0.22;
      final arpeggio =
          ((_squareWave(chord.root * 2, t) * 0.5) +
                  (_squareWave(chord.third * 2, t + 0.015) * 0.35) +
                  (_squareWave(chord.fifth * 2, t + 0.03) * 0.28)) *
              _envelope(beatInStep, 0.002, 0.08, 0.26) *
              0.72;
      final lead = _bellTone(t, [329.63, 392.0, 440.0, 493.88][barIndex]) *
          _envelope(beatInStep, 0.008, 0.05, 0.22) *
          0.32;

      final pad = _sineWave(chord.root / 2, t) * 0.12 + _sineWave(chord.third / 2, t) * 0.08;
      final mix = (bass * 0.7 + rootPulse + arpeggio + lead + pad + kick + snare + hat) * 0.55;
      return _softClip(mix);
    });
  }

  Uint8List _buildCue({
    required double durationSeconds,
    required double Function(double t) sampleBuilder,
  }) {
    return _buildWav(durationSeconds: durationSeconds, sampleBuilder: sampleBuilder);
  }

  Uint8List _buildWav({
    required double durationSeconds,
    required double Function(double t) sampleBuilder,
  }) {
    final sampleCount = max(1, (durationSeconds * _sampleRate).round());
    final pcm = Uint8List(44 + (sampleCount * 2));
    final bytes = ByteData.sublistView(pcm);

    void writeAscii(int offset, String text) {
      for (var i = 0; i < text.length; i++) {
        bytes.setUint8(offset + i, text.codeUnitAt(i));
      }
    }

    writeAscii(0, 'RIFF');
    bytes.setUint32(4, 36 + (sampleCount * 2), Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little);
    bytes.setUint16(22, 1, Endian.little);
    bytes.setUint32(24, _sampleRate, Endian.little);
    bytes.setUint32(28, _sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    writeAscii(36, 'data');
    bytes.setUint32(40, sampleCount * 2, Endian.little);

    for (var i = 0; i < sampleCount; i++) {
      final t = i / _sampleRate;
      final value = (sampleBuilder(t).clamp(-1.0, 1.0) * 32767).round();
      bytes.setInt16(44 + (i * 2), value, Endian.little);
    }

    return pcm;
  }

  double _pitchSweep(double t, double start, double end) {
    final eased = (1 - exp(-t * 10)).clamp(0.0, 1.0);
    return start + ((end - start) * eased);
  }

  double _sineWave(double frequency, double t) => sin(2 * pi * frequency * t);

  double _squareWave(double frequency, double t) => _sineWave(frequency, t) >= 0 ? 1.0 : -1.0;

  double _triangleWave(double frequency, double t) {
    final phase = (frequency * t) % 1.0;
    return 4 * (phase < 0.5 ? phase : 1 - phase) - 1;
  }

  double _sawWave(double frequency, double t) {
    final phase = (frequency * t) % 1.0;
    return (phase * 2) - 1;
  }

  double _bellTone(double t, double frequency) {
    final overtone = _sineWave(frequency, t) * 0.65;
    final shimmer = _sineWave(frequency * 2, t) * 0.3;
    final body = _sineWave(frequency * 1.5, t) * 0.18;
    return overtone + shimmer + body;
  }

  double _noise(double t) {
    final raw = sin((t * 124.7) + 0.37) * 43758.5453;
    final fract = raw - raw.floorToDouble();
    return (fract * 2) - 1;
  }

  double _envelope(double t, double attack, double decay, double sustain) {
    if (t <= attack) {
      return (t / max(0.0001, attack)).clamp(0.0, 1.0);
    }
    if (t <= attack + decay) {
      final progress = (t - attack) / max(0.0001, decay);
      return 1 - (progress * (1 - sustain));
    }
    return sustain * exp(-(t - attack - decay) * 5);
  }

  double _percussionPulse(
    double t,
    double interval,
    double attack,
    double gain,
    double frequency, {
    bool highPass = false,
  }) {
    if (t < 0) {
      return 0;
    }
    final position = t % interval;
    final envelope = _envelope(position, attack, 0.04, 0.15);
    final tone = highPass ? _noise(t) * 0.8 + _sineWave(frequency, t) * 0.2 : _sineWave(frequency, t);
    return tone * envelope * gain;
  }

  double _softClip(double sample) => (sample * 1.6).clamp(-1.0, 1.0);

  String _toDataUri(Uint8List bytes) => 'data:audio/wav;base64,${base64Encode(bytes)}';
}

class _Chord {
  const _Chord({
    required this.root,
    required this.third,
    required this.fifth,
  });

  final double root;
  final double third;
  final double fifth;
}
