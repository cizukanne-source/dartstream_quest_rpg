import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Hosts and Firebase config for the live DartStream sample environment.
///
/// The sample uses the same auth pattern as the reference apps:
/// - Firebase Identity Toolkit for the user-facing sign-up / sign-in step
/// - DartStream backend bootstrap for tenant-aware session setup
///
/// Pass the Firebase web API key at build time:
///   flutter run -d chrome --web-port=3000 \
///     --dart-define=FIREBASE_API_KEY=YOUR_FIREBASE_WEB_KEY
class AppConfig {
  static String get firebaseApiKey {
    try {
      final fromEnvFile = dotenv.env['FIREBASE_API_KEY'] ?? '';
      if (fromEnvFile.isNotEmpty) {
        return fromEnvFile;
      }
    } catch (_) {
      // Widget tests and cold starts can reach here before dotenv loads.
    }
    return const String.fromEnvironment('FIREBASE_API_KEY');
  }

  static bool get hasFirebaseApiKey => firebaseApiKey.isNotEmpty;

  static const authHost = 'https://dev-apiauth.dartstream.io';
  static const platformHost = 'https://dev-apiplatform.dartstream.io';
  static const experienceHost = 'https://dev-apiexperience.dartstream.io';
  static const reactiveHost = 'https://dev-apireactive.dartstream.io';
  static const persistenceHost = 'https://dev-apipersistence.dartstream.io';
}
