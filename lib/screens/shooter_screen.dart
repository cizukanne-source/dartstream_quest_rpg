import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/game_audio_service.dart';
import '../state/session.dart';

class ShooterScreen extends StatefulWidget {
  const ShooterScreen({super.key, required this.session});

  final Session session;

  @override
  State<ShooterScreen> createState() => _ShooterScreenState();
}

class _ShooterScreenState extends State<ShooterScreen>
    with SingleTickerProviderStateMixin {
  final Random _rng = Random();
  late final Ticker _ticker;

  Duration _lastElapsed = Duration.zero;
  Size _arenaSize = Size.zero;
  Offset _aimPosition = Offset.zero;

  final List<_Zombie> _zombies = [];
  final List<_Impact> _impacts = [];
  final List<_Pickup> _pickups = [];
  final List<_Corpse> _corpses = [];
  final _ZombieSpatialGrid _zombieGrid = _ZombieSpatialGrid(cellSize: 180);

  double _health = 100;
  double _maxHealth = 100;
  double _bulletDamage = 40;
  double _reloadDuration = 0.9;
  double _aimMoveMultiplier = 1.0;
  double _pickupRadius = 120;
  int _bulletPenetration = 0;
  int _zombiesDefeated = 0;
  int _coins = 0;
  int _xp = 0;
  int _level = 1;
  int _xpToNextLevel = 50;
  int _combo = 0;
  int _ammo = 12;
  int _reserveAmmo = 72;
  int _wave = 1;
  int _highestWave = 1;
  double _survivalClock = 0;
  double _spawnClock = 0;
  double _reloadClock = 0;
  double _bannerClock = 0;
  bool _reloading = false;
  bool _paused = false;
  bool _gameOver = false;
  bool _bossSpawned = false;
  bool _levelUpActive = false;
  List<_UpgradeChoice> _pendingUpgrades = const [];
  String? _banner;

  Offset _defaultAimPosition(Size size) => Offset(size.width / 2, size.height / 2);

  Offset _clampAimPosition(Offset position) {
    if (_arenaSize == Size.zero) {
      return position;
    }
    const padding = 44.0;
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
    _setAimPosition(_currentAimPosition + (delta * _aimMoveMultiplier));
  }

  void _moveAimTo(Offset position) {
    _setAimPosition(position);
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    unawaited(GameAudioService.instance.ensureMusicPlaying());
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
      impact.position += impact.velocity * dt;
      impact.rotation += impact.rotationSpeed * dt;
      return impact.life <= 0;
    });
    if (_impacts.length > 160) {
      _impacts.removeRange(0, _impacts.length - 160);
    }

    final player = _currentAimPosition;
    _pickups.removeWhere((pickup) {
      pickup.life -= dt;
      if (pickup.life <= 0) {
        return true;
      }
      final collected = (pickup.position - player).distance <= _pickupRadius + pickup.radius;
      if (collected) {
        _health = min(_maxHealth, _health + pickup.healAmount);
        _flashBanner('+${pickup.healAmount.toInt()} HP');
        unawaited(GameAudioService.instance.playHitCue());
      }
      return collected;
    });

    _corpses.removeWhere((corpse) {
      corpse.life -= dt;
      corpse.wobble += dt * corpse.wobbleSpeed;
      final visibleBounds = Rect.fromLTWH(-220, -220, _arenaSize.width + 440, _arenaSize.height + 440);
      return corpse.life <= 0 || !visibleBounds.contains(corpse.position);
    });
    if (_corpses.length > 80) {
      _corpses.removeRange(0, _corpses.length - 80);
    }

    if (_reloading) {
      _reloadClock -= dt;
      if (_reloadClock <= 0) {
        _finishReload();
      }
    }

    if (_paused || _gameOver) {
      return;
    }

    _survivalClock += dt;
    final nextWave = max(1, 1 + (_survivalClock ~/ 20));
    if (nextWave != _wave) {
      _wave = nextWave;
      _highestWave = max(_highestWave, _wave);
      _flashBanner('Wave $_wave');
      unawaited(GameAudioService.instance.playCue(GameAudioCue.fire));
    } else {
      _wave = nextWave;
      _highestWave = max(_highestWave, _wave);
    }

    if (_survivalClock >= 90 && !_bossSpawned) {
      _spawnBossZombie();
      _bossSpawned = true;
      _flashBanner('Boss zombie!');
    }

    _spawnClock += dt;
    final spawnInterval = _balancedSpawnInterval();
    final spawnBurst = 1 + min(3, (_wave - 1) ~/ 3);
    while (_spawnClock >= spawnInterval) {
      _spawnClock -= spawnInterval;
      for (var i = 0; i < spawnBurst; i++) {
        _spawnZombie();
      }
    }

    final nextZombies = <_Zombie>[];

    for (final zombie in _zombies) {
      final toPlayer = player - zombie.position;
      final distance = toPlayer.distance;
      final attackRadius = zombie.radius * 1.15;
      if (zombie.kind == _ZombieKind.boss) {
        zombie.specialClock += dt;
        if (zombie.isCharging) {
          zombie.chargeClock -= dt;
          final chargeStep = zombie.speed * 3.4 * dt;
          zombie.position += Offset(
            zombie.chargeDirection.dx * chargeStep,
            zombie.chargeDirection.dy * chargeStep,
          );
          if (zombie.chargeClock <= 0) {
            zombie.isCharging = false;
            zombie.specialClock = 0;
          }
        } else {
          final shouldCharge = zombie.specialClock >= 3.5 && distance < 520 && distance > 120;
          if (shouldCharge && distance > 0) {
            zombie.isCharging = true;
            zombie.chargeClock = 0.8;
            zombie.chargeDirection = Offset(toPlayer.dx / distance, toPlayer.dy / distance);
            _flashBanner('Boss charge');
          } else if (distance > 0 && distance > attackRadius) {
            final step = zombie.speed * dt;
            final direction = Offset(toPlayer.dx / distance, toPlayer.dy / distance);
            zombie.position += Offset(direction.dx * step, direction.dy * step);
          }
        }
      } else if (distance > 0 && distance > attackRadius) {
        final step = zombie.speed * dt;
        final direction = Offset(toPlayer.dx / distance, toPlayer.dy / distance);
        zombie.position += Offset(direction.dx * step, direction.dy * step);
      }

      zombie.wobble += dt * zombie.wobbleSpeed;

      final attackMultiplier = zombie.kind == _ZombieKind.boss && zombie.isCharging ? 2.2 : 1.0;
      if (distance <= attackRadius) {
        _health = max(0, _health - (zombie.damagePerSecond * attackMultiplier * dt));
      }

      nextZombies.add(zombie);
    }

    _zombies
      ..clear()
      ..addAll(nextZombies.where((zombie) => zombie.health > 0));
    _rebuildZombieGrid();

    if (_health <= 0) {
      _health = 0;
      _gameOver = true;
      _paused = true;
      _flashBanner('Overrun');
      unawaited(GameAudioService.instance.playRoundEndCue(victory: false));
    }
  }

  void _spawnZombie() {
    if (_arenaSize == Size.zero) {
      return;
    }

    final player = _currentAimPosition;
    final edge = _weightedSpawnEdge(player);
    const margin = 26.0;
    final spawnPoint = switch (edge) {
      0 => Offset(_rng.nextDouble() * _arenaSize.width, -margin),
      1 => Offset(_arenaSize.width + margin, _rng.nextDouble() * _arenaSize.height),
      2 => Offset(_rng.nextDouble() * _arenaSize.width, _arenaSize.height + margin),
      _ => Offset(-margin, _rng.nextDouble() * _arenaSize.height),
    };
    final adjustedSpawnPoint = _pushSpawnAwayFromPlayer(spawnPoint, player);

    final roll = _rng.nextDouble();
    final kind = roll < 0.55
        ? _ZombieKind.normal
        : roll < 0.77
            ? _ZombieKind.fast
            : _ZombieKind.heavy;

    final config = _zombieConfig(kind, _wave);
    _zombies.add(
      _Zombie(
        id: DateTime.now().microsecondsSinceEpoch + _zombies.length,
        position: adjustedSpawnPoint,
        kind: kind,
        speed: config.speed + _rng.nextDouble() * config.speedVariance,
        health: config.health,
        maxHealth: config.health,
        damagePerSecond: config.damagePerSecond,
        radius: config.radius,
        scoreValue: config.scoreValue,
        coinValue: config.coinValue,
        xpValue: config.xpValue,
        wobbleSpeed: config.wobbleSpeed + _rng.nextDouble() * 0.8,
        tintSeed: _rng.nextDouble(),
      ),
    );
  }

  void _spawnBossZombie() {
    if (_arenaSize == Size.zero) {
      return;
    }

    final player = _currentAimPosition;
    final spawnPoint = Offset(
      _arenaSize.width / 2 + (_rng.nextBool() ? -1 : 1) * (_arenaSize.width * 0.42),
      _rng.nextBool() ? -34 : _arenaSize.height + 34,
    );
    final adjustedSpawnPoint = _pushSpawnAwayFromPlayer(spawnPoint, player, minDistance: 280);
    final config = _zombieConfig(_ZombieKind.boss, _wave);
    _zombies.add(
      _Zombie(
        id: DateTime.now().microsecondsSinceEpoch + _zombies.length,
        position: adjustedSpawnPoint,
        kind: _ZombieKind.boss,
        speed: config.speed + _wave * 0.8,
        health: config.health + ((_wave - 1) * 14),
        maxHealth: config.health + ((_wave - 1) * 14),
        damagePerSecond: config.damagePerSecond + ((_wave - 1) * 0.3),
        radius: config.radius,
        scoreValue: config.scoreValue + ((_wave - 1) * 20),
        coinValue: config.coinValue + ((_wave - 1) * 4),
        xpValue: config.xpValue + ((_wave - 1) * 5),
        wobbleSpeed: config.wobbleSpeed,
        tintSeed: _rng.nextDouble(),
      ),
    );
  }

  void _flashBanner(String text) {
    _banner = text;
    _bannerClock = 1.4;
  }

  double _balancedSpawnInterval() {
    final wavePressure = max(0, _wave - 1) * 0.06;
    final densityPressure = max(0, _zombies.length - 70) * 0.0045;
    return max(0.26, 1.08 - wavePressure + densityPressure);
  }

  int _weightedSpawnEdge(Offset player) {
    final left = player.dx;
    final right = _arenaSize.width - player.dx;
    final top = player.dy;
    final bottom = _arenaSize.height - player.dy;
    final weights = [bottom, left, top, right]
        .map((value) => max(40.0, value + 40.0))
        .toList();
    final total = weights.fold<double>(0, (sum, value) => sum + value);
    final pick = _rng.nextDouble() * total;
    var cursor = 0.0;
    for (var i = 0; i < weights.length; i++) {
      cursor += weights[i];
      if (pick <= cursor) {
        return i;
      }
    }
    return _rng.nextInt(4);
  }

  Offset _pushSpawnAwayFromPlayer(Offset spawnPoint, Offset player, {double minDistance = 220}) {
    var point = spawnPoint;
    var attempts = 0;
    while ((point - player).distance < minDistance && attempts < 4) {
      final delta = point - player;
      final length = delta.distance;
      if (length <= 0) {
        break;
      }
      final scale = minDistance / length;
      point = player + delta * scale;
      attempts += 1;
    }
    return point;
  }

  void _beginReload() {
    if (_reloading || _reserveAmmo <= 0) {
      return;
    }
    _reloading = true;
    _reloadClock = _reloadDuration;
    _flashBanner('Reloading');
    unawaited(GameAudioService.instance.playReloadCue());
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
      _maxHealth = 100;
      _bulletDamage = 40;
      _reloadDuration = 0.9;
      _aimMoveMultiplier = 1.0;
      _pickupRadius = 120;
      _bulletPenetration = 0;
      _zombiesDefeated = 0;
      _coins = 0;
      _xp = 0;
      _level = 1;
      _xpToNextLevel = 50;
      _combo = 0;
      _ammo = 12;
      _reserveAmmo = 72;
      _wave = 1;
      _highestWave = 1;
      _spawnClock = 0;
      _reloadClock = 0;
      _bannerClock = 0;
      _reloading = false;
      _paused = false;
      _gameOver = false;
      _banner = null;
      _zombies.clear();
      _impacts.clear();
      _corpses.clear();
      _pickups.clear();
    _zombieGrid.clear();
      _aimPosition = Offset.zero;
      _lastElapsed = Duration.zero;
      _survivalClock = 0;
      _bossSpawned = false;
      _levelUpActive = false;
      _pendingUpgrades = const [];
    });
  }

  void _togglePause() {
    if (_gameOver || _levelUpActive) {
      return;
    }
    setState(() {
      _paused = !_paused;
      _flashBanner(_paused ? 'Paused' : 'Engaged');
    });
    unawaited(GameAudioService.instance.playPauseCue(paused: _paused));
  }

  void _fireAt(Offset position) {
    if (_gameOver) {
      _restartMission();
      return;
    }
    if (_paused || _levelUpActive) {
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
    unawaited(GameAudioService.instance.playCue(GameAudioCue.fire));

    final hits = <_Zombie>[];
    for (final zombie in _zombieGrid.queryPoint(position, 220)) {
      final rendered = _projectZombie(zombie, _arenaSize);
      if (rendered.rect.contains(position)) {
        hits.add(zombie);
      }
    }

    if (hits.isNotEmpty) {
      hits.sort((a, b) => (a.position - position).distance.compareTo((b.position - position).distance));
      final processed = hits.take(1 + _bulletPenetration).toList(growable: false);
      for (final zombie in processed) {
        zombie.health -= _bulletDamage;
        _impacts.add(_Impact(position: zombie.position, life: 0.24, blood: true));
        if (zombie.health <= 0) {
          _registerZombieKill(zombie, zombie.position);
        }
      }
      _flashBanner(processed.length > 1 ? 'Pierce!' : 'Hit');
      unawaited(GameAudioService.instance.playHitCue());
    } else {
      _combo = 0;
      _impacts.add(_Impact(position: position, life: 0.16, miss: true));
      _flashBanner('Miss');
      unawaited(GameAudioService.instance.playMissCue());
    }

    if (_ammo == 0) {
      _beginReload();
    }

    _rebuildZombieGrid();
  }

  void _registerZombieKill(_Zombie zombie, Offset position) {
    _zombies.removeWhere((candidate) => candidate.id == zombie.id);
    _zombiesDefeated += 1;
    _coins += zombie.coinValue;
    _xp += zombie.xpValue;
    _combo += 1;
    _spawnZombieDeathEffects(zombie, position);
    _flashBanner('+${zombie.coinValue} coins');
    unawaited(GameAudioService.instance.playHitCue());

    if (_rng.nextDouble() < 0.22) {
      _spawnHealthPickup(position);
    }

    _checkLevelUp();
  }

  void _spawnZombieDeathEffects(_Zombie zombie, Offset position) {
    _corpses.add(_Corpse(
      id: DateTime.now().microsecondsSinceEpoch + _corpses.length,
      position: position,
      kind: zombie.kind,
      radius: zombie.radius,
      life: zombie.kind == _ZombieKind.boss ? 1.3 : 0.9,
      wobbleSpeed: 2.0 + _rng.nextDouble() * 1.5,
    ));

    final burstCount = zombie.kind == _ZombieKind.boss ? 10 : zombie.kind == _ZombieKind.heavy ? 7 : 5;
    _spawnBloodBurst(position, burstCount, zombie.kind == _ZombieKind.boss ? 1.35 : 1.0);
  }

  void _spawnBloodBurst(Offset origin, int count, double intensity) {
    for (var i = 0; i < count; i++) {
      final angle = _rng.nextDouble() * pi * 2;
      final speed = (50 + _rng.nextDouble() * 130) * intensity;
      _impacts.add(
        _Impact(
          position: origin,
          life: 0.24 + _rng.nextDouble() * 0.22,
          blood: true,
          intensity: 0.85 + _rng.nextDouble() * 0.85,
          velocity: Offset(cos(angle), sin(angle)) * speed,
          rotation: _rng.nextDouble() * pi,
          rotationSpeed: (_rng.nextDouble() - 0.5) * 10,
        ),
      );
    }
  }

  void _rebuildZombieGrid() {
    _zombieGrid.rebuild(_zombies);
  }

  void _spawnHealthPickup(Offset position) {
    final offset = Offset(
      (_rng.nextDouble() - 0.5) * 28,
      (_rng.nextDouble() - 0.5) * 28,
    );
    _pickups.add(
      _Pickup(
        id: DateTime.now().microsecondsSinceEpoch + _pickups.length,
        position: position + offset,
        life: 12,
        healAmount: 16 + _rng.nextInt(12),
        radius: 14,
      ),
    );
  }

  void _checkLevelUp() {
    if (_levelUpActive || _gameOver || _xp < _xpToNextLevel) {
      return;
    }

    final choices = _generateUpgradeChoices();
    if (choices.isEmpty) {
      return;
    }

    setState(() {
      _levelUpActive = true;
      _paused = true;
      _pendingUpgrades = choices;
    });
    _flashBanner('Level up!');
  }

  List<_UpgradeChoice> _generateUpgradeChoices() {
    final pool = <_UpgradeChoice>[
      const _UpgradeChoice(
        type: _UpgradeType.bulletDamage,
        title: 'Bullet Damage',
        description: 'Increase bullet damage by 12.',
      ),
      const _UpgradeChoice(
        type: _UpgradeType.fireRate,
        title: 'Faster Fire Rate',
        description: 'Reduce reload delay and improve fire rhythm.',
      ),
      const _UpgradeChoice(
        type: _UpgradeType.movementSpeed,
        title: 'Movement Speed',
        description: 'Increase aim movement speed by 12%.',
      ),
      const _UpgradeChoice(
        type: _UpgradeType.health,
        title: 'Increased Health',
        description: 'Restore and increase max health by 20.',
      ),
      const _UpgradeChoice(
        type: _UpgradeType.penetration,
        title: 'Bullet Penetration',
        description: 'Bullets pass through one extra zombie.',
      ),
      const _UpgradeChoice(
        type: _UpgradeType.pickupRadius,
        title: 'Pickup Radius',
        description: 'Widen pickup radius for drops and rewards.',
      ),
    ]..shuffle(_rng);

    return pool.take(3).toList(growable: false);
  }

  void _applyUpgrade(_UpgradeType type) {
    if (!_levelUpActive) {
      return;
    }

    setState(() {
      switch (type) {
        case _UpgradeType.bulletDamage:
          _bulletDamage += 12;
          break;
        case _UpgradeType.fireRate:
          _reloadDuration = max(0.45, _reloadDuration - 0.08);
          break;
        case _UpgradeType.movementSpeed:
          _aimMoveMultiplier = min(2.0, _aimMoveMultiplier + 0.12);
          break;
        case _UpgradeType.health:
          _maxHealth += 20;
          _health = min(_maxHealth, _health + 20);
          break;
        case _UpgradeType.penetration:
          _bulletPenetration += 1;
          break;
        case _UpgradeType.pickupRadius:
          _pickupRadius += 18;
          break;
      }

      _level += 1;
      _xp -= _xpToNextLevel;
      _xpToNextLevel = max(60, (_xpToNextLevel * 1.28).round());
      _levelUpActive = false;
      _pendingUpgrades = const [];
      _paused = false;
    });

    unawaited(GameAudioService.instance.playCue(GameAudioCue.fire));
    _checkLevelUp();
  }

  void _fireAtAim() {
    _fireAt(_currentAimPosition);
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    final theme = Theme.of(context);
    final subtitleColor = theme.colorScheme.onSurface.withValues(alpha: 0.72);

    return LayoutBuilder(
      builder: (context, constraints) {
        final safeSize = Size(
          max(1, constraints.maxWidth),
          max(1, constraints.maxHeight),
        );
        _arenaSize = safeSize;

        final zombies = _zombies
            .map((zombie) => _projectZombie(zombie, safeSize))
            .toList(growable: false);

        final arena = _buildArena(context, safeSize, zombies);
        final sidePanel = _buildSidePanel(context, subtitleColor);

        return Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF05070B),
                Color(0xFF09130D),
                Color(0xFF101A13),
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
                  _buildMissionHeader(context),
                  const SizedBox(height: 12),
                  Expanded(
                    child: wide
                        ? Row(
                            children: [
                              Expanded(flex: 8, child: arena),
                              const SizedBox(width: 16),
                              Expanded(flex: 3, child: sidePanel),
                            ],
                          )
                        : Column(
                            children: [
                              Expanded(flex: 8, child: arena),
                              const SizedBox(height: 12),
                              Expanded(flex: 3, child: sidePanel),
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

  Widget _buildMissionHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0B1220).withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _StatCard(
                    label: 'Kills',
                    value: '$_zombiesDefeated',
                    icon: Icons.warning_amber_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Coins',
                    value: '$_coins',
                    icon: Icons.monetization_on_outlined,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Combo',
                    value: 'x$_combo',
                    icon: Icons.bolt_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Status',
                    value: _gameOver
                        ? 'Overrun'
                        : _paused
                            ? 'Paused'
                            : 'Alive',
                    icon: _gameOver
                        ? Icons.warning_amber_rounded
                        : _paused
                            ? Icons.pause_circle_rounded
                            : Icons.track_changes_rounded,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _StatCard(
                    label: 'Timer',
                    value: _formatDuration(_survivalClock),
                    icon: Icons.timer_outlined,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _HudChip(
            label: 'Wave $_wave',
            value: _gameOver
                ? 'Down'
                : _levelUpActive
                    ? 'Upgrade'
                    : (_paused ? 'Hold' : 'Live'),
            accent: _gameOver ? const Color(0xFFFB7185) : const Color(0xFF9AE6B4),
          ),
        ],
      ),
    );
  }

  Widget _buildArena(
    BuildContext context,
    Size size,
    List<_RenderedZombie> zombies,
  ) {
    final theme = Theme.of(context);
    final aimPosition = _currentAimPosition;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
            ...zombies.map(
              (rendered) => Positioned(
                left: rendered.rect.left,
                top: rendered.rect.top,
                width: rendered.rect.width,
                height: rendered.rect.height,
                child: _ZombieSprite(
                  zombie: rendered.zombie,
                  progress: rendered.progress,
                ),
              ),
            ),
            ..._corpses.map(
              (corpse) => Positioned(
                left: corpse.position.dx - corpse.radius * 1.1,
                top: corpse.position.dy - corpse.radius * 0.7,
                width: corpse.radius * 2.2,
                height: corpse.radius * 1.5,
                child: _CorpseSprite(corpse: corpse),
              ),
            ),
            ..._pickups.map(
              (pickup) => Positioned(
                left: pickup.position.dx - pickup.radius,
                top: pickup.position.dy - pickup.radius,
                width: pickup.radius * 2,
                height: pickup.radius * 2,
                child: _PickupSprite(pickup: pickup),
              ),
            ),
            ..._impacts.map(
              (impact) => Positioned(
                left: impact.position.dx - impact.size / 2,
                top: impact.position.dy - impact.size / 2,
                child: Opacity(
                  opacity: impact.life.clamp(0.0, 1.0),
                  child: Transform.rotate(
                    angle: impact.rotation,
                    child: Transform.translate(
                      offset: impact.velocity * impact.life * 0.008,
                      child: Transform.scale(
                        scale: impact.blood ? impact.intensity : 1.0,
                        child: Icon(
                          impact.miss ? Icons.close_rounded : Icons.brightness_1_rounded,
                          color: impact.miss
                              ? const Color(0xFFFB7185)
                              : const Color(0xFFB91C1C),
                          size: impact.miss ? 28 : impact.size,
                        ),
                      ),
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
                color: Color(0xFF9AE6B4),
              ),
            ),
            if (_gameOver)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.58),
                  child: Center(
                    child: Container(
                      width: 320,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      padding: const EdgeInsets.all(22),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xFFFB7185),
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Overrun',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'The horde broke through. Restart to try another survival run.',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _GameOverStatGrid(
                            survivalTime: _formatDuration(_survivalClock),
                            zombiesDefeated: _zombiesDefeated,
                            highestWave: _highestWave,
                            coinsEarned: _coins,
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: _restartMission,
                            icon: const Icon(Icons.restart_alt_rounded),
                            label: const Text('Restart run'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (_levelUpActive)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.68),
                  child: Center(
                    child: Container(
                      width: 420,
                      margin: const EdgeInsets.all(20),
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1220),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black54,
                            blurRadius: 28,
                            offset: Offset(0, 14),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.auto_awesome_rounded,
                                color: Color(0xFF9AE6B4),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Level $_level reached',
                                  style: theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose one upgrade. The horde pauses while you improve your survival kit.',
                            style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white70),
                          ),
                          const SizedBox(height: 16),
                          for (final upgrade in _pendingUpgrades)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _UpgradeTile(
                                upgrade: upgrade,
                                onSelected: () => _applyUpgrade(upgrade.type),
                              ),
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
          color: const Color(0xFF0B1220).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
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
        color: const Color(0xFF0B1220).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Survival brief',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Hold the center, drag to reposition the survivor, and thin out the horde before it reaches you.',
              style: theme.textTheme.bodyMedium?.copyWith(color: subtitleColor),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: const Color(0xFF07111C).withValues(alpha: 0.7),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                    value: _health / _maxHealth,
                    color: const Color(0xFF34D399),
                    rightText: '${_health.toInt()} / ${_maxHealth.toInt()}',
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
                    color: const Color(0xFF9AE6B4),
                    rightText: '$_reserveAmmo',
                  ),
                  const SizedBox(height: 10),
                  _ProgressLine(
                    label: 'XP',
                    value: _xp / _xpToNextLevel,
                    color: const Color(0xFFFBBF24),
                    rightText: '$_xp / $_xpToNextLevel',
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Level $_level',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Pickup radius: ${_pickupRadius.toInt()} px',
                    style: theme.textTheme.bodySmall?.copyWith(color: subtitleColor),
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
                color: const Color(0xFF07111C).withValues(alpha: 0.7),
                border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
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
                    title: 'Keep moving',
                    body: 'Zombies now spawn around the edges and home in on your position.',
                  ),
                  const SizedBox(height: 10),
                  const _NoteTile(
                    icon: Icons.touch_app_rounded,
                    title: 'Drag to reposition',
                    body: 'Use the same controls to move the survivor around the arena.',
                  ),
                  const SizedBox(height: 10),
                  const _NoteTile(
                    icon: Icons.flash_on_rounded,
                    title: 'Shoot on sight',
                    body: 'Tapping a zombie will strike it directly and keep the horde in check.',
                  ),
                  const SizedBox(height: 10),
                  const _NoteTile(
                    icon: Icons.workspace_premium_rounded,
                    title: 'Level up',
                    body: 'XP from kills fills your bar and pauses the game for upgrades.',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _RenderedZombie _projectZombie(_Zombie zombie, Size size) {
    final healthPct = zombie.maxHealth <= 0 ? 0.0 : (zombie.health / zombie.maxHealth).clamp(0.0, 1.0);
    final kindScale = switch (zombie.kind) {
      _ZombieKind.normal => 1.0,
      _ZombieKind.fast => 0.92,
      _ZombieKind.heavy => 1.18,
      _ZombieKind.boss => 1.7,
    };
    final baseSize = ui.lerpDouble(34, 52, healthPct)! * kindScale;
    final rect = Rect.fromCenter(
      center: zombie.position,
      width: baseSize + zombie.radius,
      height: baseSize + zombie.radius,
    );
    return _RenderedZombie(
      zombie: zombie,
      rect: rect,
      progress: healthPct,
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
          Color(0xFF07110B),
          Color(0xFF06110A),
          Color(0xFF040705),
        ],
      ).createShader(rect);
    canvas.drawRect(rect, basePaint);

    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFF9AE6B4).withValues(alpha: 0.14),
          const Color(0xFF0B1220).withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width / 2, size.height / 2),
          radius: size.shortestSide * 0.75,
        ),
      );
    canvas.drawRect(rect, glowPaint);

    final floorPaint = Paint()
      ..color = const Color(0xFF9AE6B4).withValues(alpha: 0.08)
      ..strokeWidth = 1.1;

    for (var i = -6; i <= 6; i++) {
      final t = (i + 6) / 12;
      final topX = size.width / 2 + (i * size.width * 0.07);
      final bottomX = size.width / 2 + (i * size.width * 0.23);
      canvas.drawLine(
        Offset(topX, size.height * 0.18),
        Offset(bottomX, size.height),
        floorPaint,
      );
      if (i.abs() != 6) {
        final pulse = 0.05 + sin(time * 1.7 + i) * 0.02;
        final linePaint = Paint()
          ..color = const Color(0xFFFB7185).withValues(alpha: pulse)
          ..strokeWidth = 1.1;
        canvas.drawLine(
          Offset(size.width * 0.12 * t, size.height * 0.22),
          Offset(size.width * (0.88 - t * 0.76), size.height * 0.22),
          linePaint,
        );
      }
    }

    for (var row = 0; row < 8; row++) {
      final t = row / 7;
      final y = ui.lerpDouble(size.height * 0.22, size.height, t)!;
      final width = ui.lerpDouble(size.width * 0.12, size.width, t)!;
      final alpha = (0.05 + (1 - t) * 0.03) + sin(time * 2 + row) * 0.01;
      final rowPaint = Paint()
        ..color = const Color(0xFF9AE6B4).withValues(alpha: alpha.clamp(0.0, 0.09))
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
          const Color(0xFF34D399).withValues(alpha: health / 350),
          const Color(0xFF34D399).withValues(alpha: 0.0),
        ],
      ).createShader(
        Rect.fromCircle(
          center: Offset(size.width * 0.82, size.height * 0.18),
          radius: size.shortestSide * 0.36,
        ),
      );
    canvas.drawRect(rect, healthGlow);

    final bloodStreakPaint = Paint()
      ..color = const Color(0xFFB91C1C).withValues(alpha: 0.05)
      ..strokeWidth = 2.3;
    for (var i = 0; i < 5; i++) {
      final offset = (time * 90 + i * 120) % (size.height + 120);
      canvas.drawLine(
        Offset(size.width * 0.12 + i * 18, offset - 80),
        Offset(size.width * 0.88 - i * 18, offset),
        bloodStreakPaint,
      );
    }

    final hudPaint = Paint()
      ..color = const Color(0xFFFB7185).withValues(alpha: 0.08 + (wave - 1) * 0.01)
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

class _ZombieSprite extends StatelessWidget {
  const _ZombieSprite({
    required this.zombie,
    required this.progress,
  });

  final _Zombie zombie;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final bodyColor = switch (zombie.kind) {
      _ZombieKind.normal => Color.lerp(
          const Color(0xFF274735),
          const Color(0xFF6B7F1A),
          1 - progress,
        )!,
      _ZombieKind.fast => Color.lerp(
          const Color(0xFF4C6B1F),
          const Color(0xFFF59E0B),
          1 - progress,
        )!,
      _ZombieKind.heavy => Color.lerp(
          const Color(0xFF5B3B26),
          const Color(0xFF8B1E1E),
          1 - progress,
        )!,
      _ZombieKind.boss => Color.lerp(
          const Color(0xFF5B1020),
          const Color(0xFFB91C1C),
          1 - progress,
        )!,
    };
    final glowColor = switch (zombie.kind) {
      _ZombieKind.normal => const Color(0xFF9AE6B4),
      _ZombieKind.fast => const Color(0xFFFBBF24),
      _ZombieKind.heavy => const Color(0xFFFB7185),
      _ZombieKind.boss => const Color(0xFFEF4444),
    };

    final bob = sin(zombie.wobble) * 0.04;
    final angle = sin(zombie.wobble * 0.9) * 0.08;
    final eyeIntensity = progress < 0.45 ? 1.0 : 0.55;
    final isBoss = zombie.kind == _ZombieKind.boss;
    final bossPulse = isBoss ? (0.5 + sin(zombie.wobble * 2.1) * 0.5) : 0.0;
    final icon = switch (zombie.kind) {
      _ZombieKind.normal => Icons.person_rounded,
      _ZombieKind.fast => Icons.directions_run_rounded,
      _ZombieKind.heavy => Icons.shield_rounded,
      _ZombieKind.boss => Icons.person_search_rounded,
    };

    return Transform.rotate(
      angle: angle,
      child: Transform.translate(
        offset: Offset(0, bob * 12),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.white.withValues(alpha: isBoss ? 0.98 : 0.92),
                bodyColor.withValues(alpha: isBoss ? 1.0 : 0.96),
                const Color(0xFF08110B),
              ],
              stops: const [0.0, 0.48, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withValues(alpha: isBoss ? 0.45 : 0.28),
                blurRadius: isBoss ? 28 : 18,
                spreadRadius: isBoss ? 4 : 2,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (isBoss)
                Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.18 + bossPulse * 0.18),
                      width: 2,
                    ),
                  ),
                ),
              Container(
                margin: EdgeInsets.all(isBoss ? 6 : 8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: isBoss ? 0.42 : 0.28),
                    width: 2,
                  ),
                ),
              ),
              Icon(
                icon,
                color: Colors.white.withValues(alpha: 0.92),
                size: isBoss ? 38 : 28,
              ),
              Positioned(
                top: isBoss ? 9 : 12,
                left: isBoss ? 18 : 13,
                child: Container(
                  width: isBoss ? 8 : 5,
                  height: isBoss ? 8 : 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: eyeIntensity),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              if (isBoss)
                Positioned(
                  bottom: 6,
                  child: Container(
                    width: 20,
                    height: 5,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.55 + bossPulse * 0.25),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              Positioned(
                bottom: isBoss ? 12 : 11,
                child: Container(
                  width: isBoss ? 16 : 12,
                  height: isBoss ? 5 : 4,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.52),
                    borderRadius: BorderRadius.circular(999),
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

class _CorpseSprite extends StatelessWidget {
  const _CorpseSprite({required this.corpse});

  final _Corpse corpse;

  @override
  Widget build(BuildContext context) {
    final lifePct = (corpse.life / corpse.maxLife).clamp(0.0, 1.0);
    final flatten = ui.lerpDouble(1.0, 0.65, 1 - lifePct)!;
    final fade = lifePct;
    final color = switch (corpse.kind) {
      _ZombieKind.normal => const Color(0xFF335C3F),
      _ZombieKind.fast => const Color(0xFF556B2F),
      _ZombieKind.heavy => const Color(0xFF5A2C24),
      _ZombieKind.boss => const Color(0xFF7F1D1D),
    };

    return Opacity(
      opacity: fade,
      child: Transform.rotate(
        angle: sin(corpse.wobble) * 0.18,
        child: Transform.scale(
          scale: flatten,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  color.withValues(alpha: 0.9),
                  const Color(0xFF120A0A).withValues(alpha: 0.95),
                ],
                stops: const [0.0, 1.0],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFB91C1C).withValues(alpha: 0.18 * fade),
                  blurRadius: 14,
                  spreadRadius: 1,
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
                    border: Border.all(color: Colors.black.withValues(alpha: 0.35), width: 2),
                  ),
                ),
                Icon(
                  corpse.kind == _ZombieKind.boss
                      ? Icons.warning_rounded
                      : Icons.circle_rounded,
                  color: Colors.black.withValues(alpha: 0.5),
                  size: corpse.kind == _ZombieKind.boss ? 26 : 20,
                ),
              ],
            ),
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
      ..color = color.withValues(alpha: 0.95)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()..color = color.withValues(alpha: 0.95);
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
            backgroundColor: Colors.white.withValues(alpha: 0.08),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label,
            style: TextStyle(
              color: accent.withValues(alpha: 0.9),
              fontSize: 10,
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
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withValues(alpha: 0.76),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF9AE6B4), size: 16),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
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
        Icon(icon, color: const Color(0xFF9AE6B4), size: 18),
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

class _PickupSprite extends StatelessWidget {
  const _PickupSprite({required this.pickup});

  final _Pickup pickup;

  @override
  Widget build(BuildContext context) {
    final pulse = 0.9 + sin(pickup.life * 3.2) * 0.06;
    return Center(
      child: Transform.scale(
        scale: pulse,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFE8FFF4).withValues(alpha: 0.95),
                const Color(0xFF34D399).withValues(alpha: 0.9),
                const Color(0xFF064E3B),
              ],
              stops: const [0.0, 0.4, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF34D399).withValues(alpha: 0.36),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.favorite_rounded,
              size: pickup.radius,
              color: const Color(0xFF063B28),
            ),
          ),
        ),
      ),
    );
  }
}

class _GameOverStatGrid extends StatelessWidget {
  const _GameOverStatGrid({
    required this.survivalTime,
    required this.zombiesDefeated,
    required this.highestWave,
    required this.coinsEarned,
  });

  final String survivalTime;
  final int zombiesDefeated;
  final int highestWave;
  final int coinsEarned;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.8,
      children: [
        _EndStatTile(label: 'Survival time', value: survivalTime),
        _EndStatTile(label: 'Zombies defeated', value: '$zombiesDefeated'),
        _EndStatTile(label: 'Highest wave', value: '$highestWave'),
        _EndStatTile(label: 'Coins earned', value: '$coinsEarned'),
      ],
    );
  }
}

class _EndStatTile extends StatelessWidget {
  const _EndStatTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF07111C).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _Pickup {
  _Pickup({
    required this.id,
    required this.position,
    required this.life,
    required this.healAmount,
    required this.radius,
  });

  final int id;
  final Offset position;
  double life;
  final int healAmount;
  final double radius;
}

class _Corpse {
  _Corpse({
    required this.id,
    required this.position,
    required this.kind,
    required this.radius,
    required this.life,
    required this.wobbleSpeed,
  });

  final int id;
  final Offset position;
  final _ZombieKind kind;
  final double radius;
  final double maxLife = 1.3;
  double life;
  final double wobbleSpeed;
  double wobble = 0;
}

class _Zombie {
  _Zombie({
    required this.id,
    required this.position,
    required this.kind,
    required this.speed,
    required this.health,
    required this.maxHealth,
    required this.damagePerSecond,
    required this.radius,
    required this.scoreValue,
    required this.coinValue,
    required this.xpValue,
    required this.wobbleSpeed,
    required this.tintSeed,
  });

  final int id;
  Offset position;
  final _ZombieKind kind;
  final double speed;
  double health;
  final double maxHealth;
  final double damagePerSecond;
  final double radius;
  final int scoreValue;
  final int coinValue;
  final int xpValue;
  final double wobbleSpeed;
  final double tintSeed;
  double wobble = 0;
  double specialClock = 0;
  double chargeClock = 0;
  bool isCharging = false;
  Offset chargeDirection = Offset.zero;
}

class _ZombieConfig {
  const _ZombieConfig({
    required this.speed,
    required this.speedVariance,
    required this.health,
    required this.damagePerSecond,
    required this.radius,
    required this.scoreValue,
    required this.coinValue,
    required this.xpValue,
    required this.wobbleSpeed,
  });

  final double speed;
  final double speedVariance;
  final double health;
  final double damagePerSecond;
  final double radius;
  final int scoreValue;
  final int coinValue;
  final int xpValue;
  final double wobbleSpeed;
}

_ZombieConfig _zombieConfig(_ZombieKind kind, int wave) {
  final waveBoost = max(0, wave - 1).toDouble();
  return switch (kind) {
    _ZombieKind.normal => _ZombieConfig(
        speed: 36,
        speedVariance: 10,
        health: 28 + (waveBoost * 1.4),
        damagePerSecond: 12 + (waveBoost * 0.6),
        radius: 18,
        scoreValue: 20,
        coinValue: 5,
        xpValue: 10,
        wobbleSpeed: 2.0,
      ),
    _ZombieKind.fast => _ZombieConfig(
        speed: 58,
        speedVariance: 14,
        health: 20 + (waveBoost * 0.95),
        damagePerSecond: 10 + (waveBoost * 0.5),
        radius: 16,
        scoreValue: 24,
        coinValue: 7,
        xpValue: 12,
        wobbleSpeed: 2.8,
      ),
    _ZombieKind.heavy => _ZombieConfig(
        speed: 26,
        speedVariance: 8,
        health: 60 + (waveBoost * 3.2),
        damagePerSecond: 16 + (waveBoost * 0.7),
        radius: 22,
        scoreValue: 40,
        coinValue: 10,
        xpValue: 18,
        wobbleSpeed: 1.5,
      ),
    _ZombieKind.boss => _ZombieConfig(
        speed: 22,
        speedVariance: 0,
        health: 260 + (waveBoost * 18),
        damagePerSecond: 24 + (waveBoost * 0.9),
        radius: 34,
        scoreValue: 250,
        coinValue: 80,
        xpValue: 150,
        wobbleSpeed: 1.1,
      ),
  };
}

String _formatDuration(double seconds) {
  final total = seconds.floor();
  final minutes = total ~/ 60;
  final remainingSeconds = total % 60;
  return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
}

class _UpgradeChoice {
  const _UpgradeChoice({
    required this.type,
    required this.title,
    required this.description,
  });

  final _UpgradeType type;
  final String title;
  final String description;
}

class _UpgradeTile extends StatelessWidget {
  const _UpgradeTile({
    required this.upgrade,
    required this.onSelected,
  });

  final _UpgradeChoice upgrade;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF07111C).withValues(alpha: 0.76),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        ),
        child: Row(
          children: [
            const Icon(Icons.add_circle_outline_rounded, color: Color(0xFF9AE6B4)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    upgrade.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    upgrade.description,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _UpgradeType { bulletDamage, fireRate, movementSpeed, health, penetration, pickupRadius }

enum _ZombieKind { normal, fast, heavy, boss }

class _RenderedZombie {
  _RenderedZombie({
    required this.zombie,
    required this.rect,
    required this.progress,
  });

  final _Zombie zombie;
  final Rect rect;
  final double progress;
}

class _Impact {
  _Impact({
    required this.position,
    required this.life,
    this.miss = false,
    this.blood = false,
    this.intensity = 1.0,
    this.velocity = Offset.zero,
    this.rotation = 0,
    this.rotationSpeed = 0,
  });

  Offset position;
  double life;
  final bool miss;
  final bool blood;
  final double intensity;
  final Offset velocity;
  double rotation;
  final double rotationSpeed;

  double get size => blood ? 22 * intensity : 18;
}

class _ZombieSpatialGrid {
  _ZombieSpatialGrid({required this.cellSize});

  final double cellSize;
  final Map<int, List<_Zombie>> _cells = <int, List<_Zombie>>{};

  void clear() => _cells.clear();

  void rebuild(List<_Zombie> zombies) {
    _cells.clear();
    for (final zombie in zombies) {
      final key = _cellKeyFor(zombie.position);
      final bucket = _cells.putIfAbsent(key, () => <_Zombie>[]);
      bucket.add(zombie);
    }
  }

  List<_Zombie> queryPoint(Offset point, double radius) {
    final minX = ((point.dx - radius) / cellSize).floor();
    final maxX = ((point.dx + radius) / cellSize).floor();
    final minY = ((point.dy - radius) / cellSize).floor();
    final maxY = ((point.dy + radius) / cellSize).floor();
    final results = <_Zombie>[];
    for (var x = minX; x <= maxX; x++) {
      for (var y = minY; y <= maxY; y++) {
        final bucket = _cells[_cellKey(x, y)];
        if (bucket != null) {
          results.addAll(bucket);
        }
      }
    }
    return results;
  }

  int _cellKeyFor(Offset position) {
    return _cellKey((position.dx / cellSize).floor(), (position.dy / cellSize).floor());
  }

  int _cellKey(int x, int y) => (x << 16) ^ (y & 0xFFFF);
}
