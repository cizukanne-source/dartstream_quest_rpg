import 'package:flutter/material.dart';

import '../state/session.dart';

class ExperienceScreen extends StatelessWidget {
  const ExperienceScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Experience')),
      body: Center(
        child: Text(
          'Experience mirror for ${session.displayName ?? 'Player'}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
