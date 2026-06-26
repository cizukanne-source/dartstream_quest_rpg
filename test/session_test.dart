import 'package:flutter_test/flutter_test.dart';

import 'package:dartstream_quest_rpg/state/session.dart';

void main() {
  test('treats matching string flags as enabled', () {
    final session = Session();

    session.updateFeatureFlags(const ['double_xp']);

    expect(session.hasFeatureFlag('double_xp'), isTrue);
    expect(session.doubleXpEnabled, isTrue);
  });
}
