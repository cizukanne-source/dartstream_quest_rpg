import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../api/dartstream.dart';
import '../state/session.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.session});

  final Session session;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _LoadStatus { loading, ready, error }

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  static const _slotKey = 'quest';

  final _rng = Random();
  late final AnimationController _pulseController;

  _LoadStatus _status = _LoadStatus.loading;
  Object? _bootstrapError;
  Timer? _saveDebounce;

  late _GameState _state;

  DartstreamApi get _api => widget.session.api!;
  String get _userId => widget.session.userId!;
  String get _tenantId => widget.session.tenantId!;
  String get _displayName =>
      widget.session.displayName ??
      widget.session.email?.split('@').first ??
      'Player';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat(reverse: true);
    _bootstrap();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _saveDebounce?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _status = _LoadStatus.loading;
      _bootstrapError = null;
    });

    try {
      final results = await Future.wait([
        _api.profile(userId: _userId, tenantId: _tenantId),
        _api.featureFlags(tenantId: _tenantId),
        _api.inventory(userId: _userId, tenantId: _tenantId),
        _api.loadSnapshot(userId: _userId, tenantId: _tenantId, slotKey: _slotKey),
      ]);

      final profile = results[0] as Map<String, dynamic>;
      final flags = results[1] as Map<String, dynamic>;
      final inventory = results[2] as Map<String, dynamic>;
      final snapshot = results[3];

      final profileData = _unwrapMap(profile, const ['profile', 'user', 'data']) ?? profile;
      final flagsList = _unwrapList(flags, const ['flags', 'data']);
      final inventoryItems = _unwrapInventory(inventory);
      final saved = _snapshotPayload(snapshot);

      _state = _GameState.fromLiveData(
        displayName: _displayName,
        profileData: profileData,
        flags: flagsList,
        inventory: inventoryItems,
        saved: saved,
      );

      setState(() {
        _status = _LoadStatus.ready;
      });
    } catch (error) {
      setState(() {
        _status = _LoadStatus.error;
        _bootstrapError = error;
      });
    }
  }

  Future<void> _refresh() => _bootstrap();

  void _queueSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        await _api.saveSnapshot(
          userId: _userId,
          tenantId: _tenantId,
          slotKey: _slotKey,
          payload: _state.toSnapshot(),
        );
      } catch (_) {
        // Keep the game playable if save sync briefly fails.
      }
    });
  }

  Future<void> _doAction(_GameAction action) async {
    setState(() {
      _state = _state.apply(action, _rng);
    });
    _queueSave();
    await _api.logEvent(
      tenantId: _tenantId,
      eventType: 'quest.action.${action.name}',
      payload: _state.toSnapshot(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _explore() => _doAction(_GameAction.explore);
  Future<void> _fight() => _doAction(_GameAction.fight);
  Future<void> _rest() => _doAction(_GameAction.rest);
  Future<void> _loot() => _doAction(_GameAction.loot);

  void _signOut() => widget.session.signOut();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF050B14), Color(0xFF091A2E), Color(0xFF16314A)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _AnimatedBackdrop(pulse: _pulseController)),
            SafeArea(
              child: _status == _LoadStatus.loading
                  ? const Center(child: CircularProgressIndicator())
                  : _status == _LoadStatus.error
                      ? _errorView()
                      : _gameView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: _CardShell(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Game not ready',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'We could not load your session. Tap retry to enter the realm again.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFFB7C6DA),
                      ),
                ),
                const SizedBox(height: 14),
                SelectableText(
                  '$_bootstrapError',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _gameView() {
    final state = _state;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeroPanel(state: state),
                const SizedBox(height: 16),
                _HowToPlayCard(state: state),
                const SizedBox(height: 16),
                _StatusGrid(state: state),
                const SizedBox(height: 16),
                _GoalCard(state: state),
                const SizedBox(height: 16),
                _ActionRow(
                  onExplore: _explore,
                  onFight: state.bossReady ? _fight : null,
                  onRest: _rest,
                  onLoot: _loot,
                  onRefresh: _refresh,
                  onSignOut: _signOut,
                ),
                const SizedBox(height: 16),
                _RecentCard(state: state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum _GameAction { explore, fight, rest, loot }

class _GameState {
  _GameState({
    required this.displayName,
    required this.heroClass,
    required this.level,
    required this.xp,
    required this.gold,
    required this.health,
    required this.maxHealth,
    required this.questProgress,
    required this.bossHealth,
    required this.bossMaxHealth,
    required this.enemyName,
    required this.lastMessage,
    required this.inventorySummary,
    required this.recentEvents,
    required this.flags,
    required this.lastSavedAt,
  });

  final String displayName;
  final String heroClass;
  final int level;
  final int xp;
  final int gold;
  final int health;
  final int maxHealth;
  final int questProgress;
  final int bossHealth;
  final int bossMaxHealth;
  final String enemyName;
  final String lastMessage;
  final List<String> inventorySummary;
  final List<_EventItem> recentEvents;
  final List<dynamic> flags;
  final DateTime? lastSavedAt;

  bool get bossReady => questProgress >= 100;

  String get progressLabel => bossReady ? 'Boss unlocked' : 'Reach 100% to unlock the boss';

  String get nextStep {
    if (bossReady) return 'Fight the boss now.';
    if (questProgress < 50) return 'Tap Explore to make progress.';
    return 'You are close. Keep exploring.';
  }

  String get simpleStatus => 'Level $level • $xp XP • $gold gold';

  factory _GameState.fromLiveData({
    required String displayName,
    required Map<String, dynamic> profileData,
    required List<dynamic> flags,
    required List<dynamic> inventory,
    required Map<String, dynamic> saved,
  }) {
    final snapshot = _flattenSnapshot(saved);
    final savedName =
        _stringFromMap(snapshot, const ['displayName', 'display_name']) ??
            _stringFromMap(profileData, const ['displayName', 'display_name', 'name']) ??
            displayName;
    final heroClass =
        _stringFromMap(snapshot, const ['heroClass', 'hero_class']) ??
            _stringFromMap(profileData, const ['heroClass', 'hero_class', 'class']) ??
            'Ranger';
    final xp = _intFromMap(snapshot, const ['xp', 'experiencePoints', 'score']);
    final questProgress =
        _intFromMap(snapshot, const ['questProgress', 'missionProgress', 'progress']).clamp(0, 100);
    final bossHealth = _defaultIfZero(_intFromMap(snapshot, const ['bossHealth', 'enemyHealth']), 80);
    final inventorySummary = inventory.isEmpty
        ? const ['starter sword', '250 coin']
        : inventory
            .map((item) => _stringFromMap(item, const ['name', 'itemName', 'id']))
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .take(4)
            .toList();

    return _GameState(
      displayName: savedName,
      heroClass: heroClass,
      level: (xp ~/ 100) + 1,
      xp: xp,
      gold: _intFromMap(snapshot, const ['gold', 'coins', 'wallet']),
      health: _defaultIfZero(_intFromMap(snapshot, const ['health', 'hp']), 100),
      maxHealth: _defaultIfZero(_intFromMap(snapshot, const ['maxHealth', 'max_hp']), 100),
      questProgress: questProgress,
      bossHealth: bossHealth,
      bossMaxHealth: _defaultIfZero(_intFromMap(snapshot, const ['bossMaxHealth', 'enemyMaxHealth']), 80),
      enemyName:
          _stringFromMap(snapshot, const ['enemyName', 'enemy_name']) ?? 'Ash Warden',
      lastMessage:
          _stringFromMap(snapshot, const ['lastMessage', 'lastAction', 'message']) ??
              'Ready to play',
      inventorySummary: inventorySummary,
      recentEvents: [
        _EventItem(
          title: 'Game loaded',
          detail: 'Your hero is ready.',
          icon: Icons.play_arrow_rounded,
        ),
        _EventItem(
          title: 'Inventory ready',
          detail: inventorySummary.join(', '),
          icon: Icons.inventory_2_rounded,
        ),
        _EventItem(
          title: 'Goal',
          detail: 'Fill the quest bar, then beat the boss.',
          icon: Icons.flag_rounded,
        ),
      ],
      flags: flags,
      lastSavedAt: _dateFromMap(snapshot, const ['lastSavedAt', 'updatedAt']),
    );
  }

  _GameState copyWith({
    String? displayName,
    String? heroClass,
    int? level,
    int? xp,
    int? gold,
    int? health,
    int? maxHealth,
    int? questProgress,
    int? bossHealth,
    int? bossMaxHealth,
    String? enemyName,
    String? lastMessage,
    List<String>? inventorySummary,
    List<_EventItem>? recentEvents,
    List<dynamic>? flags,
    DateTime? lastSavedAt,
  }) {
    return _GameState(
      displayName: displayName ?? this.displayName,
      heroClass: heroClass ?? this.heroClass,
      level: level ?? this.level,
      xp: xp ?? this.xp,
      gold: gold ?? this.gold,
      health: health ?? this.health,
      maxHealth: maxHealth ?? this.maxHealth,
      questProgress: questProgress ?? this.questProgress,
      bossHealth: bossHealth ?? this.bossHealth,
      bossMaxHealth: bossMaxHealth ?? this.bossMaxHealth,
      enemyName: enemyName ?? this.enemyName,
      lastMessage: lastMessage ?? this.lastMessage,
      inventorySummary: inventorySummary ?? this.inventorySummary,
      recentEvents: recentEvents ?? this.recentEvents,
      flags: flags ?? this.flags,
      lastSavedAt: lastSavedAt ?? this.lastSavedAt,
    );
  }

  _GameState apply(_GameAction action, Random rng) {
    switch (action) {
      case _GameAction.explore:
        final progressGain = 20 + rng.nextInt(16);
        final xpGain = 10 + rng.nextInt(8);
        final goldGain = 5 + rng.nextInt(6);
        final nextProgress = (questProgress + progressGain).clamp(0, 100);
        return _withEvent(
          copyWith(
            xp: xp + xpGain,
            gold: gold + goldGain,
            health: max(0, health - 2),
            questProgress: nextProgress,
            bossHealth: nextProgress >= 100 ? bossMaxHealth : bossHealth,
            lastMessage: nextProgress >= 100
                ? 'Boss unlocked'
                : 'Exploring the realm...',
            lastSavedAt: DateTime.now().toUtc(),
          ),
          'Explored',
          '+$progressGain quest, +$xpGain XP',
          Icons.explore_rounded,
        );
      case _GameAction.fight:
        if (!bossReady) {
          return _withEvent(
            copyWith(
              lastMessage: 'You need 100% quest progress first.',
              lastSavedAt: DateTime.now().toUtc(),
            ),
            'Boss locked',
            'Keep exploring until the bar is full.',
            Icons.lock_rounded,
          );
        }
        final damage = 18 + rng.nextInt(15);
        final nextBoss = max(0, bossHealth - damage);
        final victory = nextBoss == 0;
        return _withEvent(
          copyWith(
            xp: xp + (victory ? 35 : 12),
            gold: gold + (victory ? 25 : 8),
            health: max(0, health - 8),
            bossHealth: nextBoss,
            questProgress: victory ? 0 : questProgress,
            lastMessage: victory ? 'Boss defeated!' : 'You hit the boss.',
            inventorySummary: victory
                ? [...inventorySummary, 'boss loot']
                : inventorySummary,
            lastSavedAt: DateTime.now().toUtc(),
          ),
          victory ? 'Victory' : 'Fight',
          victory ? '+25 gold, boss defeated.' : '-$damage boss HP',
          Icons.flash_on_rounded,
        );
      case _GameAction.rest:
        final healed = 12 + rng.nextInt(10);
        return _withEvent(
          copyWith(
            health: min(maxHealth, health + healed),
            lastMessage: 'You rested and recovered.',
            lastSavedAt: DateTime.now().toUtc(),
          ),
          'Rested',
          '+$healed health',
          Icons.bedtime_rounded,
        );
      case _GameAction.loot:
        final coins = 10 + rng.nextInt(16);
        return _withEvent(
          copyWith(
            gold: gold + coins,
            lastMessage: 'You found treasure.',
            lastSavedAt: DateTime.now().toUtc(),
          ),
          'Looted',
          '+$coins gold',
          Icons.lock_open_rounded,
        );
    }
  }

  _GameState _withEvent(
    _GameState next,
    String title,
    String detail,
    IconData icon,
  ) {
    final items = <_EventItem>[
      _EventItem(title: title, detail: detail, icon: icon),
      ...recentEvents,
    ].take(4).toList();
    return next.copyWith(recentEvents: items);
  }

  Map<String, dynamic> toSnapshot() {
    return {
      'displayName': displayName,
      'heroClass': heroClass,
      'xp': xp,
      'gold': gold,
      'health': health,
      'maxHealth': maxHealth,
      'questProgress': questProgress,
      'bossHealth': bossHealth,
      'bossMaxHealth': bossMaxHealth,
      'enemyName': enemyName,
      'lastMessage': lastMessage,
      'lastSavedAt': (lastSavedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
  }
}

class _EventItem {
  const _EventItem({
    required this.title,
    required this.detail,
    required this.icon,
  });

  final String title;
  final String detail;
  final IconData icon;
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.state});

  final _GameState state;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _LevelOrb(level: state.level),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DARTSTREAM QUEST RPG',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  state.displayName,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        height: 0.95,
                      ),
                ),
                const SizedBox(height: 10),
                Text(
                  'You are a ${state.heroClass}. Your simple goal: fill the quest bar, then beat the boss.',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: const Color(0xFFB7C6DA),
                        height: 1.45,
                      ),
                ),
                const SizedBox(height: 14),
                Text(
                  state.simpleStatus,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HowToPlayCard extends StatelessWidget {
  const _HowToPlayCard({required this.state});

  final _GameState state;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to play',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          _StepTile(
            number: '1',
            title: 'Explore',
            body: 'Tap Explore to fill the quest bar.',
            icon: Icons.explore_rounded,
          ),
          const SizedBox(height: 10),
          _StepTile(
            number: '2',
            title: 'Fight the boss',
            body: state.bossReady
                ? 'The boss is ready. Tap Fight.'
                : 'When the bar reaches 100%, the boss opens.',
            icon: Icons.flash_on_rounded,
          ),
          const SizedBox(height: 10),
          _StepTile(
            number: '3',
            title: 'Rest or loot',
            body: 'Use Rest to heal and Loot to gain gold.',
            icon: Icons.auto_awesome_rounded,
          ),
        ],
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({required this.state});

  final _GameState state;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MiniStat(icon: Icons.bolt_rounded, label: 'Quest', value: '${state.questProgress}%'),
      _MiniStat(icon: Icons.favorite_rounded, label: 'Health', value: '${state.health}/${state.maxHealth}'),
      _MiniStat(icon: Icons.savings_rounded, label: 'Gold', value: '${state.gold}'),
      _MiniStat(icon: Icons.workspace_premium_rounded, label: 'Level', value: '${state.level}'),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: cards,
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.state});

  final _GameState state;

  @override
  Widget build(BuildContext context) {
    final progress = state.questProgress / 100;
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Your goal',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ),
              Text(state.progressLabel),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            state.nextStep,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFB7C6DA),
                ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                return LinearProgressIndicator(
                  value: value,
                  minHeight: 12,
                  backgroundColor: const Color(0xFF102237),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    state.bossReady ? const Color(0xFFFFC857) : const Color(0xFF7DF9C5),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            state.bossReady
                ? 'Boss ready: Tap Fight to finish the run.'
                : 'Keep exploring until the bar reaches 100%.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFFB7C6DA),
                ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.onExplore,
    required this.onFight,
    required this.onRest,
    required this.onLoot,
    required this.onRefresh,
    required this.onSignOut,
  });

  final VoidCallback onExplore;
  final VoidCallback? onFight;
  final VoidCallback onRest;
  final VoidCallback onLoot;
  final VoidCallback onRefresh;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          FilledButton.icon(
            onPressed: onExplore,
            icon: const Icon(Icons.explore_rounded),
            label: const Text('Explore'),
          ),
          FilledButton.tonalIcon(
            onPressed: onFight,
            icon: const Icon(Icons.flash_on_rounded),
            label: const Text('Fight boss'),
          ),
          OutlinedButton.icon(
            onPressed: onRest,
            icon: const Icon(Icons.bedtime_rounded),
            label: const Text('Rest'),
          ),
          OutlinedButton.icon(
            onPressed: onLoot,
            icon: const Icon(Icons.lock_open_rounded),
            label: const Text('Loot'),
          ),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Refresh'),
          ),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}

class _RecentCard extends StatelessWidget {
  const _RecentCard({required this.state});

  final _GameState state;

  @override
  Widget build(BuildContext context) {
    return _CardShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent results',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          ...state.recentEvents.map(
            (event) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EventRow(event: event),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelOrb extends StatelessWidget {
  const _LevelOrb({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.96, end: 1),
      duration: const Duration(milliseconds: 1200),
      curve: Curves.easeInOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const SweepGradient(
                colors: [Color(0xFF7DF9C5), Color(0xFFFFC857), Color(0xFF41A6FF), Color(0xFF7DF9C5)],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 20,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Container(
              margin: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF08111D),
                border: Border.all(color: const Color(0xFF2C4663)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'LVL',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: const Color(0xFFB7C6DA),
                          letterSpacing: 2,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$level',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w900,
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
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 230,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF08111D),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C4663)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: const Color(0xFFB7C6DA),
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.number,
    required this.title,
    required this.body,
    required this.icon,
  });

  final String number;
  final String title;
  final String body;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08111D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22384F)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              number,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB7C6DA),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});

  final _EventItem event;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF08111D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF22384F)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(event.icon, color: Theme.of(context).colorScheme.secondary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  event.detail,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB7C6DA),
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardShell extends StatelessWidget {
  const _CardShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF0D1726).withValues(alpha: 0.97),
            const Color(0xFF07111C).withValues(alpha: 0.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFF2C4663)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 22,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
      child: child,
    );
  }
}

class _AnimatedBackdrop extends StatelessWidget {
  const _AnimatedBackdrop({required this.pulse});

  final Animation<double> pulse;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulse,
      builder: (context, child) {
        final value = pulse.value;
        return Stack(
          children: [
            Positioned(
              left: -70 + (value * 24),
              top: -50,
              child: _Glow(size: 240, color: const Color(0xFF7DF9C5).withValues(alpha: 0.18)),
            ),
            Positioned(
              right: -80,
              top: 90 + (value * 28),
              child: _Glow(size: 210, color: const Color(0xFFFFC857).withValues(alpha: 0.14)),
            ),
            Positioned(
              left: 120,
              bottom: -90 + (value * 24),
              child: _Glow(size: 260, color: const Color(0xFF41A6FF).withValues(alpha: 0.12)),
            ),
          ],
        );
      },
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color, color.withValues(alpha: 0.04), Colors.transparent],
          stops: const [0, 0.45, 1],
        ),
      ),
    );
  }
}

Map<String, dynamic>? _unwrapMap(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map<String, dynamic>) return value;
  }
  return null;
}

List<dynamic> _unwrapList(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) return value;
  }
  return const [];
}

List<dynamic> _unwrapInventory(Map<String, dynamic> inventory) {
  final nested = _unwrapMap(inventory, const ['inventory', 'data']);
  if (nested != null) {
    final items = nested['items'];
    if (items is List) return items;
  }
  final items = inventory['items'];
  if (items is List) return items;
  return const [];
}

Map<String, dynamic> _snapshotPayload(dynamic snapshot) {
  if (snapshot == null) return {};
  if (snapshot is! Map) return {};
  final map = snapshot is Map<String, dynamic>
      ? snapshot
      : Map<String, dynamic>.from(snapshot);
  final nested = _unwrapMap(map, const ['snapshot', 'data']);
  if (nested != null) {
    final payload = nested['payload'];
    if (payload is Map<String, dynamic>) return payload;
    return nested;
  }
  final payload = map['payload'];
  if (payload is Map<String, dynamic>) return payload;
  return map;
}

Map<String, dynamic> _flattenSnapshot(Map<String, dynamic> snapshot) {
  return _unwrapMap(snapshot, const ['snapshot', 'data']) ?? snapshot;
}

String? _stringFromMap(Map? map, List<String> keys) {
  if (map == null) return null;
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.isNotEmpty) return value;
  }
  return null;
}

int _intFromMap(Map? map, List<String> keys) {
  if (map == null) return 0;
  for (final key in keys) {
    final value = map[key];
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return 0;
}

DateTime? _dateFromMap(Map? map, List<String> keys) {
  if (map == null) return null;
  for (final key in keys) {
    final value = map[key];
    if (value is String) return DateTime.tryParse(value);
  }
  return null;
}

int _defaultIfZero(int value, int fallback) => value == 0 ? fallback : value;
