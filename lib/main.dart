import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'state/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {
    // The app still works with --dart-define if the local .env file is absent.
  }
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
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF7DF9C5),
        brightness: Brightness.dark,
      ).copyWith(
        primary: const Color(0xFF7DF9C5),
        secondary: const Color(0xFFFFC857),
        surface: const Color(0xFF0D1726),
      ),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF07111C),
      textTheme: Typography.whiteMountainView.apply(
        bodyColor: const Color(0xFFEAF2FF),
        displayColor: const Color(0xFFEAF2FF),
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'DartStream Quest RPG',
      theme: theme,
      home: _session.status == SessionStatus.signedIn
          ? HomeScreen(session: _session)
          : LoginScreen(session: _session),
    );
  }
}
