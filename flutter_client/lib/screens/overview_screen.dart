import 'package:flutter/material.dart';

import '../state/session.dart';
import 'shooter_screen.dart';

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return ShooterScreen(session: session);
  }
}
