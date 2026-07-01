import 'package:flutter/material.dart';

import 'google_sign_in_button_stub.dart'
    if (dart.library.html) 'google_sign_in_button_web.dart';

Widget googleSignInButton({
  required bool enabled,
  required bool ready,
  required VoidCallback onPressed,
}) {
  return buildGoogleSignInButton(
    enabled: enabled,
    ready: ready,
    onPressed: onPressed,
  );
}
