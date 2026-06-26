import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dartstream_quest_rpg/state/session.dart';

void main() {
  test('treats matching string flags as enabled', () {
    final session = Session();

    session.updateFeatureFlags(const ['double_xp']);

    expect(session.hasFeatureFlag('double_xp'), isTrue);
    expect(session.doubleXpEnabled, isTrue);
  });

  test('maps light mode and hard mode flags to session state', () {
    final session = Session();

    session.updateFeatureFlags(const [
      {'key': 'light_mode', 'enabled': true},
      {'key': 'hard_mode', 'enabled': true},
    ]);

    expect(session.lightThemeEnabled, isTrue);
    expect(session.darkThemeEnabled, isFalse);
    expect(session.themeMode, ThemeMode.light);
    expect(session.hardModeEnabled, isTrue);
  });

  test('defaults to dark theme when no theme flags are set', () {
    final session = Session();

    session.updateFeatureFlags(const []);

    expect(session.lightThemeEnabled, isFalse);
    expect(session.darkThemeEnabled, isFalse);
    expect(session.themeMode, ThemeMode.dark);
  });
}
