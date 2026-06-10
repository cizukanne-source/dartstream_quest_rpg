import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dartstream_quest_rpg/main.dart';

void main() {
  testWidgets('builds the app shell', (tester) async {
    await tester.pumpWidget(const DartStreamQuestApp());

    expect(find.text('DARTSTREAM QUEST RPG'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(4));
    expect(find.text('Create account'), findsNWidgets(2));
  });
}
