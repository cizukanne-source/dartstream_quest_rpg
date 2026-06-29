import 'package:flutter/material.dart';

import '../state/session.dart';
import 'home_screen.dart';
import 'intellitoggle_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.session});
  final Session session;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  int _index = 0;

  late final List<_Feature> _features = [
    _Feature(
      label: 'Overview',
      icon: Icons.sports_esports_outlined,
      selectedIcon: Icons.sports_esports,
      builder: () => HomeScreen(session: widget.session),
    ),
    _Feature(
      label: 'IntelliToggle',
      icon: Icons.toggle_on_outlined,
      selectedIcon: Icons.toggle_on,
      builder: () => IntelliToggleScreen(session: widget.session),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final useBottomBar = !wide && _features.length <= 5;
    final useDrawer = !wide && _features.length > 5;

    final body = IndexedStack(
      index: _index,
      children: [for (final f in _features) f.builder()],
    );

    return Scaffold(
      appBar: AppBar(
        title: Text('DartStream Quest RPG · ${_features[_index].label}'),
        actions: [
          if (session.email != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(child: Text(session.email!)),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: session.signOut,
          ),
        ],
      ),
      drawer: useDrawer
          ? Drawer(
              child: SafeArea(
                child: ListView(
                  children: [
                    for (var i = 0; i < _features.length; i++)
                      ListTile(
                        leading: Icon(i == _index
                            ? _features[i].selectedIcon
                            : _features[i].icon),
                        title: Text(_features[i].label),
                        selected: i == _index,
                        onTap: () {
                          setState(() => _index = i);
                          Navigator.pop(context);
                        },
                      ),
                  ],
                ),
              ),
            )
          : null,
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final f in _features)
                      NavigationRailDestination(
                        icon: Icon(f.icon),
                        selectedIcon: Icon(f.selectedIcon),
                        label: Text(f.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      bottomNavigationBar: useBottomBar
          ? NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: [
                for (final f in _features)
                  NavigationDestination(
                    icon: Icon(f.icon),
                    selectedIcon: Icon(f.selectedIcon),
                    label: f.label,
                  ),
              ],
            )
          : null,
    );
  }
}

class _Feature {
  _Feature({
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
