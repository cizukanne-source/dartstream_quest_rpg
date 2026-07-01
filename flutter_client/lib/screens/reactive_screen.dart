import 'package:flutter/material.dart';

import '../state/session.dart';

class ReactiveScreen extends StatelessWidget {
  const ReactiveScreen({super.key, required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reactive')),
      body: Center(
        child: Text(
          'Reactive mirror for ${session.displayName ?? 'Player'}',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
