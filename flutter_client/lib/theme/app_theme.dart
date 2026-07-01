import 'package:flutter/material.dart';

ThemeData buildQuestTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final surface = isDark ? const Color(0xFF121826) : const Color(0xFFF5F7FA);
  final scaffold = isDark ? const Color(0xFF05070B) : const Color(0xFFF0F3F8);
  final textBase =
      isDark ? Typography.whiteMountainView : Typography.blackMountainView;

  return ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: isDark ? const Color(0xFFFF6B4A) : const Color(0xFF0E7490),
      brightness: brightness,
    ).copyWith(
      primary: isDark ? const Color(0xFFFF6B4A) : const Color(0xFF0E7490),
      secondary: isDark ? const Color(0xFF6EE7F9) : const Color(0xFFF97316),
      surface: surface,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: scaffold,
    textTheme: textBase.apply(
      bodyColor: isDark ? const Color(0xFFEAF2FF) : const Color(0xFF102033),
      displayColor: isDark ? const Color(0xFFEAF2FF) : const Color(0xFF0F172A),
    ),
  );
}
