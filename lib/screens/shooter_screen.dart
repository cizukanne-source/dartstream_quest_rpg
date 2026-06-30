import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../state/session.dart';

class ShooterScreen extends StatefulWidget {
  const ShooterScreen({super.key, required this.session});

  final Session session;

  @override
  State<ShooterScreen> createState() => _ShooterScreenState();
}

class _ShooterScreenState extends State<ShooterScreen>
    with TickerProviderStateMixin {
  final Random _rng = Random();
  late final Ticker _ticker;

  Duration _lastElapsed = Duration.zero;
  Size _arenaSize = Size.zero;
  Offset _aimPosition = Offset.zero;

  final List<_Target> _targets = [];
  final List<_Impact> _impacts = [];

  double _health = 100;
  int _score = 0;
  int _combo = 0;
  int _ammo = 12;
  int _reserveAmmo = 72;
  int _wave = 1;
  double _spawnClock = 0;
  double _reloadClock = 0;
  double _bannerClock = 0;
  bool _reloading = false;
  bool _paused = false;
  bool _gameOver = false;
  String? _banner;

  Session get _session => widget.session;
  String get _playerName =>
      _session.displayName ??
      _session.email?.split('@').first ??
      'Operator';

  Offset _defaultAimPosition(Size size) => Offset(size.width / 2, size.height / 2);

  Offset _clampAimPosition(Offset position) {
    if (_arenaSize == Size.zero) {
      return position;
    }
    const padding = 46.0;
    return Offset(
      position.dx.clamp(padding, _arenaSize.width - padding),
      position.dy.clamp(padding, _arenaSize.height - padding),
    );
  }

  Offset get _currentAimPosition {
    if (_arenaSize == Size.zero) {
      return _aimPosition;
    }
    if (_aimPosition == Offset.zero) {
      return _defaultAimPosition(_arenaSize);
    }
    return _clampAimPosition(_aimPosition);
  }

  void _setAimPosition(Offset position, {bool repaint = true}) {
    _aimPosition = _clampAimPosition(position);
    if (repaint && mounted) {
      setState(() {});
    }
  }

  void _moveAimBy(Offset delta) {
    _setAimPosition(_currentAimPosition + delta);
  }

  void _moveAimTo(Offset position) {
    _setAimPosition(position);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final dt = _lastElapsed == Duration.zero
        ? 0.016
        : (elapsed - _lastElapsed).inMicroseconds / 1000000.0;
    _lastElapsed = elapsed;

    _step(dt.clamp(0.0, 0.05));

    if (mounted) {
      setState(() {});
    }
  }

  void _step(double dt) {
    _bannerClock = max(0, _bannerClock - dt);
    _impacts.removeWhere((impact) {
      impact.life -= dt;
      return impact.life <= 0;
    });

    if (_reloading) {
      _reloadClock -= dt;
      if (_reloadClock <= 0) {
        _finishReload();
      }
    }

    if (_paused || _gameOver) {
      return;
    }

    _spawnClock += dt;
    final spawnInterval = max(0.48, 1.15 - ((_wave - 1) * 0.05));
    while (_spawnClock >= spawnInterval) {
      _spawnClock -= spawnInterval;
      _spawnTarget();
      if (_wave >= 4 && _rng.nextBool()) {
        _spawnTarget();
      }
    }

    final nextTargets = <_Target>[];
    for (final target in _targets) {
      target.depth -= target.speed * dt;
      target.sway += target.drift * dt;
      if (target.depth <= 0.04) {
        _health = max(0, _health - target.damage);
        _combo = 0;
        _flashBanner('Target breached -${target.damage.toInt()} HP');
        continue;
      }
      nextTargets.add(target);
    }
    _targets
      ..clear()
      ..addAll(nextTargets);

    _wave = max(1, 1 + (_score ~/ 220));

    if (_health <= 0) {
      _health = 0;
      _gameOver = true;
      _paused = true;
      _flashBanner('Mission failed');
    }
  }

  void _spawnTarget() {
    final lanes = [-0.85, -0.48, -0.12, 0.22, 0.56, 0.9];
    final lane = lanes[_rng.nextInt(lanes.length)];
    final depth = 1.0 + (_rng.nextDouble() * 0.2);
    final kindRoll = _rng.nextDouble();
    final kind = kindRoll < 0.55
        ? _TargetKind.drone
        : kindRoll < 0.82
            ? _TargetKind.turret
            : _TargetKind.armor;
    final baseSpeed = kind == _TargetKind.armor ? 0.17 : 0.22;
    final waveBoost = min(0.14, (_wave - 1) * 0.015);
    _targets.add(
      _Target(
        id: DateTime.now().microsecondsSinceEpoch + _targets.length,
        lane: lane,
        depth: depth,
        speed: baseSpeed + waveBoost + _rng.nextDouble() * 0.06,
        sway: _rng.nextDouble() * pi * 2,
        drift: 0.8 + _rng.nextDouble() * 1.2,
        damage: kind == _TargetKind.armor ? 20 : 14,
        value: kind == _TargetKind.armor ? 35 : kind == _TargetKind.turret ? 24 : 18,
        kind: kind,
      ),
    );
  }

  void _flashBanner(String text) {
    _banner = text;
    _bannerClock = 1.4;
  }

  void _beginReload() {
    if (_reloading || _reserveAmmo <= 0) {
      return;
    }
    _reloading = true;
    _reloadClock = 0.9;
    _flashBanner('Reloading');
  }

  void _finishReload() {
    final refill = min(12, _reserveAmmo);
    _reserveAmmo -= refill;
    _ammo = refill;
    _reloading = false;
    _reloadClock = 0;
    _flashBanner('Reloaded');
  }

  void _restartMission() {
    setState(() {
      _health = 100;
      _score = 0;
      _combo = 0;
      _ammo = 12;
      _reserveAmmo = 72;
      _wave = 1;
      _spawnClock = 0;
      _reloadClock = 0;
      _bannerClock = 0;
      _reloading = false;
      _paused = false;
      _gameOver = false;
      _banner = null;
      _targets.clear();
      _impacts.clear();
      _aimPosition = Offset.zero;
      _lastElapsed = Duration.zero;
    });
  }

  void _togglePause() {
    if (_gameOver) {
      return;
    }
    setState(() {
      _paused = !_paused;
      _flashBanner(_paused ? 'Paused' : 'Engaged');
    });
  }

  void _fireAt(Offset position) {
    if (_gameOver) {
      _restartMission();
      return;
    }
    if (_paused) {
      return;
    }
    if (_reloading) {
      _flashBanner('Reloading');
      return;
    }
    if (_ammo <= 0) {
      _beginReload();
      return;
    }

    _ammo -= 1;

    _RenderedTarget? bestHit;
    for (final target in _targets) {
      final rendered = _projectTarget(target, _arenaSize);
      if (!rendered.rect.contains(position)) {
        continue;
      }
      if (bestHit == null || rendered.depth < bestHit.depth) {
        bestHit = rendered;
      }
    }

    if (bestHit != null) {
      _targets.removeWhere((target) => target.id == bestHit!.target.id);
      final points = bestHit.target.value + (_combo * 2);
      _score += points;
      _combo += 1;
      _impacts.add(_Impact(position: position, life: 0.22));
      _flashBanner('+$points');
    } else {
      _combo = 0;
      _impacts.add(_Impact(position: position, life: 0.16, miss: true));
      _flashBanner('Miss');
    }

    if (_ammo == 0) {
      _beginReload();
    }
  }

  void _fireAtAim() {
    _fireAt(_currentAimPosition);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final theme = Theme.of(context);
    final subtitleColor = theme.colorScheme.onSurface.withOpacity(0.72);

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeSize = Size(
          max(1, constraints.maxWidth),
          max(1, constraints.maxHeight),
        );
        _arenaSize = safeSize;

        final targets = _targets
            .map((target) => _projectTarget(target, safeSize))
            .toList(growable: false);

        final arena = _buildArena(context, safeSize, targets);
        final sidePanel = _buildSidePanel(context, subtitleColor);

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF05070B),
                Color(0xFF09111A),
                Color(0xFF101A29),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildMissionHeader(context, subtitleColor),
                  const SizedBox(height: 16),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              Expanded(flex: 7, child: arena),
                              const SizedBox(width: 16),
                              Expanded(flex: 4, child: sidePanel),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(flex: 7, child: arena),
                              const SizedBox(height: 16),
                              Expanded(flex: 4, child: sidePanel),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMissionHeader(BuildContext context, Color subtitleColor) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220).withOpacity(0.84),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                colors: [Color(0xFFFFA24A), Color(0xFFE6492D)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF7A3D).withOpacity(0.45),
                  blurRadius: 18,
                ),
              ],
            ),
            child: const Icon(Icons.gps_fixed_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '3D strike arena',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Operator $_playerName, eliminate incoming targets before they breach the line.',
                  style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _HudChip(
            label: 'Wave $_wave',
            value: _gameOver ? 'Down' : (_paused ? 'Hold' : 'Live'),
            accent: _gameOver ? const Color(0xFFFB7185) : const Color(0xFF6EE7F9),
          ),
        ],
      ),
    );
  }

  Widget _buildArena(
    BuildContext context,
    Size size,
    List<_RenderedTarget> targets,
  ) {
    final theme = Theme.of(context);
    final aimPosition = _currentAimPosition;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (details) {
          _moveAimTo(details.localPosition);
          _fireAt(details.localPosition);
        },
        onPanStart: (details) => _moveAimTo(details.localPosition),
        onPanUpdate: (details) => _moveAimBy(details.delta),
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _ArenaBackdropPainter(
                  time: _lastElapsed.inMilliseconds / 1000.0,
                  wave: _wave.toDouble(),
                  health: _health,
                ),
              ),
            ),
            ...targets.map(
              (rendered) => Positioned(
                left: rendered.rect.left,
                top: rendered.rect.top,
                width: rendered.rect.width,
                height: rendered.rect.height,
                child: _TargetSprite(
                  target: rendered.target,
                  progress: rendered.progress,
                ),
              ),
            ),
            ..._impacts.map(
              (impact) => Positioned(
                left: impact.position.dx - 18,
                top: impact.position.dy - 18,
                child: Opacity(
                  opacity: impact.life.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: impact.miss ? 1.35 : 1.0,
                    child: Icon(
                      impact.miss ? Icons.close_rounded : Icons.brightness_1_rounded,
                      color: impact.miss
                          ? const Color(0xFFFB7185)
                          : const Color(0xFFFFD166),
                      size: impact.miss ? 28 : 22,
                    ),
                  ),
                ),
              ),
            ),
            Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: _buildBanner(),
              ),
            ),
            Positioned(
              left: aimPosition.dx - 46,
              top: aimPosition.dy - 46,
              child: const _Crosshair(
                color: Color(0xFF6EE7F9),
              ),
            ),
            if (_gameOver)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(0.58),
                  child: Center(
                    child: Container(
                      width: 320,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.08)),
                      ),
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.local_fire_department_rounded,
                            color: Color(0xFFFF6B4A),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Mission failed',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Reset the arena and take another run.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _restartMission,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Restart mission'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBanner() {
    if (_banner == null || _bannerClock <= 0) {
      return const SizedBox.shrink();
    }
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 120),
      opacity: (_bannerClock / 1.4).clamp(0.0, 1.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0B1220).withOpacity(0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: Text(
          _banner!,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  Widget _buildSidePanel(BuildContext context, Color subtitleColor) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220).withOpacity(0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mission brief',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Track moving targets in a neon strike corridor and keep the line from collapsing.',
              style: theme.textTheme.bodyMedium?.copyWith(color: subtitleColor),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Score',
                    value: '$_score',
                    icon: Icons.emoji_events_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _StatCard(
                    label: 'Combo',
                    value: 'x$_combo',
                    icon: Icons.bolt_rounded,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _StatCard(
              label: 'Status',
              value: _gameOver
                  ? 'Down'
                  : _paused
                      ? 'Paused'
                      : 'Engaged',
              icon: _gameOver
                  ? Icons.warning_amber_rounded
                  : _paused
                      ? Icons.pause_circle_rounded
                      : Icons.track_changes_rounded,
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF07111C).withOpacity(0.7),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Weapon HUD',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _ProgressLine(
                    label: 'Health',
                    value: _health / 100,
                    color: const Color(0xFF34D399),
                    rightText: '${_health.toInt()}%',
                  ),
                  const SizedBox(height: 10),
                  _ProgressLine(
                    label: 'Ammo',
                    value: _ammo / 12,
                    color: const Color(0xFFFFA24A),
                    rightText: '$_ammo / 12',
                  ),
                  const SizedBox(height: 10),
                  _ProgressLine(
                    label: 'Reserve',
                    value: _reserveAmmo / 72,
                    color: const Color(0xFF6EE7F9),
                    rightText: '$_reserveAmmo',
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 360;
                      final pauseButton = _HudButton(
                        icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                        label: _paused ? 'Resume' : 'Pause',
                        onPressed: _togglePause,
                      );
                      final restartButton = _HudButton(
                        icon: Icons.restart_alt_rounded,
                        label: 'Restart',
                        onPressed: _restartMission,
                      );
                      final fireButton = FilledButton.icon(
                        onPressed: _fireAtAim,
                        icon: const Icon(Icons.gps_fixed_rounded),
                        label: const Text('Fire'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                        ),
                      );

                      if (compact) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            pauseButton,
                            const SizedBox(height: 10),
                            restartButton,
                            const SizedBox(height: 10),
                            fireButton,
                          ],
                        );
                      }

                      return Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [pauseButton, restartButton, fireButton],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF07111C).withOpacity(0.7),
                border: Border.all(color: Colors.white.withOpacity(0.06)),
              ),
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tactical notes',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _NoteTile(
                    icon: Icons.adjust_rounded,
                    title: 'Aim center mass',
                    body: 'Targets that reach the front line drain health fast.',
                  ),
                  const SizedBox(height: 10),
                  const _NoteTile(
                    icon: Icons.flash_on_rounded,
                    title: 'Keep combo alive',
                    body: 'Consecutive hits ramp score and keep the arena hot.',
                  ),
                  const SizedBox(height: 10),
                  const _NoteTile(
                    icon: Icons.replay_rounded,
                    title: 'Reload smart',
                    body: 'Use the pause button or reload window to reset your rhythm.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _RenderedTarget _projectTarget(_Target target, Size size) {
    final depthFactor = (1.0 - target.depth).clamp(0.0, 1.0);
    final perspective = Curves.easeOutCubic.transform(depthFactor);
    final width = ui.lerpDouble(size.width * 0.10, size.width * 0.24, perspective)!;
    final height = ui.lerpDouble(size.height * 0.10, size.height * 0.28, perspective)!;
    final centerX = size.width / 2 +
        (target.lane * size.width * 0.24 * (0.25 + perspective)) +
        sin(target.sway) * size.width * 0.04;
    final centerY = size.height * 0.18 + perspective * size.height * 0.62;
    final rect = Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: width * (target.kind == _TargetKind.armor ? 1.15 : 1),
      height: height * (target.kind == _TargetKind.armor ? 1.1 : 1),
    );
    return _RenderedTarget(
      target: target,
      rect: rect,
      depth: target.depth,
      progress: depthFactor,
    );
  }
}

class _ArenaBackdropPainter extends CustomPainter {
  _ArenaBackdropPainter({
    required this.time,
    required this.wave,
    required this.health,
  });

  final double time;
  final double wave;
  final double health;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final basePaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Color(0xFF0A1320),
          Color(0xFF08101A),
          Color(0xFF05070B),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final horizonY = size.height * 0.22;
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFF6B4A).withOpacity(0.22),
          const Color(0xFF0B1220).withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width / 2, horizonY),
          radius: size.shortestSide * 0.72,
        ),
      );
    canvas.drawRect(rect, glowPaint);

    final floorPaint = Paint()
      ..color = const Color(0xFF6EE7F9).withOpacity(0.08)
      ..strokeWidth = 1.1;

    for (var i = -6; i <= 6; i++) {
      final t = (i + 6) / 12;
      final topX = size.width / 2 + (i * size.width * 0.07);
      final bottomX = size.width / 2 + (i * size.width * 0.23);
      canvas.drawLine(
        Offset(topX, horizonY),
        Offset(bottomX, size.height),
        floorPaint,
      );
      if (i.abs() != 6) {
        final pulse = 0.07 + sin(time * 1.7 + i) * 0.03;
        final linePaint = Paint()
          ..color = const Color(0xFFFFA24A).withOpacity(pulse)
          ..strokeWidth = 1.2;
        canvas.drawLine(
          Offset(size.width * 0.12 * t, horizonY + 4),
          Offset(size.width * (0.88 - t * 0.76), horizonY + 4),
          linePaint,
        );
      }
    }

    for (var row = 0; row < 8; row++) {
      final t = row / 7;
      final y = ui.lerpDouble(horizonY + 10, size.height, t)!;
      final width = ui.lerpDouble(size.width * 0.12, size.width, t)!;
      final alpha = (0.05 + (1 - t) * 0.03) + sin(time * 2 + row) * 0.01;
      final rowPaint = Paint()
        ..color = const Color(0xFF6EE7F9).withOpacity(alpha.clamp(0.0, 0.09))
        ..strokeWidth = 1;
      canvas.drawLine(
        Offset((size.width - width) / 2, y),
        Offset((size.width + width) / 2, y),
        rowPaint,
      );
    }

    final healthGlow = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF34D399).withOpacity(health / 350),
          const Color(0xFF34D399).withOpacity(0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.82, size.height * 0.18),
          radius: size.shortestSide * 0.36,
        ),
      );
    canvas.drawRect(rect, healthGlow);

    final streakPaint = Paint()
      ..color = const Color(0xFFFFFFFF).withOpacity(0.05)
      ..strokeWidth = 2.3;
    for (var i = 0; i < 5; i++) {
      final offset = (time * 90 + i * 120) % (size.height + 120);
      canvas.drawLine(
        Offset(size.width * 0.12 + i * 18, offset - 80),
        Offset(size.width * 0.88 - i * 18, offset),
        streakPaint,
      );
    }

    final hudPaint = Paint()
      ..color = const Color(0xFFFB7185).withOpacity(0.08 + (wave - 1) * 0.01)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 12, size.width - 24, size.height - 24),
        const Radius.circular(26),
      ),
      hudPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArenaBackdropPainter oldDelegate) {
    return oldDelegate.time != time ||
        oldDelegate.wave != wave ||
        oldDelegate.health != health;
  }
}

class _TargetSprite extends StatelessWidget {
  const _TargetSprite({
    required this.target,
    required this.progress,
  });

  final _Target target;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final glowColor = switch (target.kind) {
      _TargetKind.drone => const Color(0xFF6EE7F9),
      _TargetKind.turret => const Color(0xFFFFA24A),
      _TargetKind.armor => const Color(0xFFFB7185),
    };

    final scale = ui.lerpDouble(0.72, 1.08, progress)!;
    final opacity = ui.lerpDouble(0.32, 1.0, progress)!.clamp(0.2, 1.0);

    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withOpacity(0.96),
                glowColor.withOpacity(0.96),
                const Color(0xFF111827),
              ],
              stops: const [0.0, 0.38, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(0.35),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withOpacity(0.5), width: 2),
                ),
              ),
              Container(
                width: target.kind == _TargetKind.armor ? 34 : 28,
                height: target.kind == _TargetKind.armor ? 34 : 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF05070B).withOpacity(0.72),
                  border: Border.all(color: Colors.white.withOpacity(0.8), width: 2),
                ),
                child: Icon(
                  switch (target.kind) {
                    _TargetKind.drone => Icons.brightness_1_rounded,
                    _TargetKind.turret => Icons.adjust_rounded,
                    _TargetKind.armor => Icons.shield_rounded,
                  },
                  color: Colors.white,
                  size: target.kind == _TargetKind.armor ? 16 : 14,
                ),
              ),
              if (target.kind != _TargetKind.drone)
                Positioned(
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: CustomPaint(
        painter: _CrosshairPainter(color: color),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final strokePaint = Paint()
      ..color = color.withOpacity(0.95)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()..color = color.withOpacity(0.95);
    canvas.drawCircle(center, 16, strokePaint);
    canvas.drawCircle(center, 4, fillPaint);
    canvas.drawLine(center.translate(-30, 0), center.translate(-12, 0), strokePaint);
    canvas.drawLine(center.translate(12, 0), center.translate(30, 0), strokePaint);
    canvas.drawLine(center.translate(0, -30), center.translate(0, -12), strokePaint);
    canvas.drawLine(center.translate(0, 12), center.translate(0, 30), strokePaint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _ProgressLine extends StatelessWidget {
  const _ProgressLine({
    required this.label,
    required this.value,
    required this.color,
    required this.rightText,
  });

  final String label;
  final double value;
  final Color color;
  final String rightText;

  @override
  Widget build(BuildContext context) {
    final pct = value.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(
              rightText,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: pct,
            backgroundColor: Colors.white.withOpacity(0.08),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _HudChip extends StatelessWidget {
  const _HudChip({
    required this.label,
    required this.value,
    required this.accent,
  });

  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent.withOpacity(0.9),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withOpacity(0.76),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF6EE7F9), size: 18),
          const SizedBox(height: 10),
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _NoteTile extends StatelessWidget {
  const _NoteTile({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFFFA24A), size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Target {
  _Target({
    required this.id,
    required this.lane,
    required this.depth,
    required this.speed,
    required this.sway,
    required this.drift,
    required this.damage,
    required this.value,
    required this.kind,
  });

  final int id;
  final double lane;
  double depth;
  final double speed;
  double sway;
  final double drift;
  final int damage;
  final int value;
  final _TargetKind kind;
}

class _RenderedTarget {
  _RenderedTarget({
    required this.target,
    required this.rect,
    required this.depth,
    required this.progress,
  });

  final _Target target;
  final Rect rect;
  final double depth;
  final double progress;
}

class _Impact {
  _Impact({
    required this.position,
    required this.life,
    this.miss = false,
  });

  final Offset position;
  double life;
  final bool miss;
}

enum _TargetKind { drone, turret, armor }
