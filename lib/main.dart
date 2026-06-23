import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
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
      title: 'DartStream Quest RPG',
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: _session.themeMode,
      home: _session.status == SessionStatus.signedIn
          ? HomeScreen(session: _session)
          : LoginScreen(session: _session),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0D1726) : const Color(0xFFF6F8FC);
    final scaffold = isDark ? const Color(0xFF07111C) : const Color(0xFFF2F5FA);
    final textBase = isDark ? Typography.whiteMountainView : Typography.blackMountainView;
    return ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: isDark ? const Color(0xFF7DF9C5) : const Color(0xFF1F5BD8),
        brightness: brightness,
      ).copyWith(
        primary: isDark ? const Color(0xFF7DF9C5) : const Color(0xFF1F5BD8),
        secondary: isDark ? const Color(0xFFFFC857) : const Color(0xFF8A5A00),
        surface: surface,
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: scaffold,
      textTheme: textBase.apply(
        bodyColor: isDark ? const Color(0xFFEAF2FF) : const Color(0xFF1F2937),
        displayColor: isDark ? const Color(0xFFEAF2FF) : const Color(0xFF111827),
      ),
    );
  }
}
