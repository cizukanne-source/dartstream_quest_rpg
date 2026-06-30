import 'package:flutter/material.dart';

import '../state/session.dart';
import 'shooter_screen.dart';

class ShellScreen extends StatelessWidget {
  const ShellScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    final session = this.session;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text('DartStream Arena'),
        actions: [
          if (session.email != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: Text(
                  session.email!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout_rounded),
            onPressed: session.signOut,
          ),
        ],
      ),
      body: ShooterScreen(session: session),
    );
  }
}
