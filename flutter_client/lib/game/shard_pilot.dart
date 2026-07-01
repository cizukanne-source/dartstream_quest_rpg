import 'package:flutter/material.dart';

import '../screens/shooter_screen.dart';
import '../state/session.dart';

class ShardPilot extends StatelessWidget {
  const ShardPilot({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ShooterScreen(session: session);
  }
}
