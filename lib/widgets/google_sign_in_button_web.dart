import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart';

// ignore: unused_parameter
Widget buildGoogleSignInButton({
  required bool enabled,
  required bool ready,
  required VoidCallback onPressed,
}) {
  if (!ready) {
    return const SizedBox(
      width: double.infinity,
      height: 48,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  if (!enabled) {
    return Opacity(
      opacity: 0.55,
      child: IgnorePointer(child: renderButton()),
    );
  }

  return Center(child: renderButton());
}
