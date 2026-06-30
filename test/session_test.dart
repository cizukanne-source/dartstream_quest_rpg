import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dartstream_quest_rpg/config.dart';
import 'package:dartstream_quest_rpg/state/session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

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

  test('restores a saved signed-in session from shared preferences', () async {
    SharedPreferences.setMockInitialValues({});

    final session = Session();
    session.connection = DartStreamConnection(
      client: DartStreamClient(
        config: AppConfig.dartStreamConfig,
        session: const DartStreamSession(
          idToken: 'firebase-id-token',
          userId: 'user-123',
          tenantId: 'tenant-456',
          email: 'hero@example.com',
          raw: <String, dynamic>{
            'displayName': 'Hero',
          },
        ),
      ),
      session: const DartStreamSession(
        idToken: 'firebase-id-token',
        userId: 'user-123',
        tenantId: 'tenant-456',
        email: 'hero@example.com',
        raw: <String, dynamic>{
          'displayName': 'Hero',
        },
      ),
    );
    session.status = SessionStatus.signedIn;
    session.email = 'hero@example.com';
    session.displayName = 'Hero';
    session.userId = 'user-123';
    session.tenantId = 'tenant-456';
    session.bootstrap = const {'displayName': 'Hero'};
    session.updateFeatureFlags(const ['double_xp']);

    await session.save();

    final restored = Session();
    await restored.restore();

    expect(restored.status, SessionStatus.signedIn);
    expect(restored.email, 'hero@example.com');
    expect(restored.displayName, 'Hero');
    expect(restored.userId, 'user-123');
    expect(restored.tenantId, 'tenant-456');
    expect(restored.hasFeatureFlag('double_xp'), isTrue);
    expect(restored.sdkSession?.idToken, 'firebase-id-token');
    expect(restored.bootstrap, isNotNull);
  });
}
