import 'package:flutter/material.dart';

import '../state/session.dart';
import 'feature_flags_screen.dart';
import 'intellitoggle_control_screen.dart';
import 'overview_screen.dart';
import 'persistence_screen.dart';
import 'profile_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.session});

  final Session session;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  late final List<_Section> _sections = [
    _Section(
      label: 'Overview',
      icon: Icons.sports_esports_outlined,
      selectedIcon: Icons.sports_esports,
      builder: () => OverviewScreen(session: widget.session),
    ),
    _Section(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      builder: () => ProfileScreen(session: widget.session),
    ),
    _Section(
      label: 'Feature flags',
      icon: Icons.flag_outlined,
      selectedIcon: Icons.flag_rounded,
      builder: () => FeatureFlagsScreen(session: widget.session),
    ),
    _Section(
      label: 'IntelliToggle',
      icon: Icons.toggle_on_outlined,
      selectedIcon: Icons.toggle_on_rounded,
      builder: () => IntelliToggleControlScreen(session: widget.session),
    ),
    _Section(
      label: 'Persistence',
      icon: Icons.storage_outlined,
      selectedIcon: Icons.storage_rounded,
      builder: () => PersistenceScreen(session: widget.session),
    ),
  ];

  void _setIndex(int index) {
    setState(() {
      _index = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final current = _sections[_index];
    final title = 'DartStream · ${current.label}';

    final content = IndexedStack(
      index: _index,
      children: [
        for (final section in _sections) section.builder(),
      ],
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.88),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(title),
        actions: [
          if (widget.session.email != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text(widget.session.email!)),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: widget.session.signOut,
          ),
        ],
      ),
      body: SafeArea(
        child: wide
            ? Row(
                children: [
                  _Sidebar(
                    sections: _sections,
                    index: _index,
                    onChanged: _setIndex,
                  ),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              )
            : Column(
                children: [
                  Expanded(child: content),
                  NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _setIndex,
                    destinations: [
                      for (final section in _sections)
                        NavigationDestination(
                          icon: Icon(section.icon),
                          selectedIcon: Icon(section.selectedIcon),
                          label: section.label,
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.sections,
    required this.index,
    required this.onChanged,
  });

  final List<_Section> sections;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: Theme.of(context).colorScheme.surface.withOpacity(0.92),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: NavigationRail(
        selectedIndex: index,
        onDestinationSelected: onChanged,
        labelType: NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6B4A), Color(0xFFFFA24A)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.gps_fixed_rounded, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Text(
                'Arena',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
        destinations: [
          for (final section in sections)
            NavigationRailDestination(
              icon: Icon(section.icon),
              selectedIcon: Icon(section.selectedIcon),
              label: Text(section.label),
            ),
        ],
      ),
    );
  }
}

class _Section {
  _Section({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.builder,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function() builder;
}
