import 'package:flutter/material.dart';

// ignore: unused_parameter
Widget buildGoogleSignInButton({
  required bool enabled,
  required bool ready,
  required VoidCallback onPressed,
}) {
  return SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: const Icon(Icons.account_circle_rounded),
      label: const Text('Continue with Google'),
    ),
  );
}
