import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/shell_screen.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DartStreamQuestApp());
}

class DartStreamQuestApp extends StatefulWidget {
  const DartStreamQuestApp({super.key});

  @override
  State<DartStreamQuestApp> createState() => _DartStreamQuestAppState();
}

class _DartStreamQuestAppState extends State<DartStreamQuestApp> {
  final Session _session = Session();

  @override
  void initState() {
    super.initState();
    _session.addListener(_onSessionChanged);
  }

  void _onSessionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DartStream Arena',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _session.themeMode,
      home: _session.status == SessionStatus.signedIn
          ? ShellScreen(session: _session)
          : LoginScreen(session: _session),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF121826) : const Color(0xFFF5F7FA);
    final scaffold = isDark ? const Color(0xFF05070B) : const Color(0xFFF0F3F8);
    final textBase = isDark ? Typography.whiteMountainView : Typography.blackMountainView;
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
}
