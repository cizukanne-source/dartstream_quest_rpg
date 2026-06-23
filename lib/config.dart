/// Hosts and Firebase config for the live DartStream sample environment.
///
/// The sample uses the same auth pattern as the reference apps:
/// - Firebase Identity Toolkit for the user-facing sign-up / sign-in step
/// - DartStream backend bootstrap for tenant-aware session setup
///
/// The app ships with the public sample Firebase web key baked in, and a
/// build-time FIREBASE_API_KEY still overrides it when provided.
class AppConfig {
  // This is a public Firebase web API key for the sample project.
  // A build-time FIREBASE_API_KEY still overrides it when provided.
  static const _defaultFirebaseApiKey =
      '';

  static String get firebaseApiKey {
    final buildTimeKey = const String.fromEnvironment('FIREBASE_API_KEY').trim();
    return buildTimeKey.isNotEmpty ? buildTimeKey : _defaultFirebaseApiKey;
  }

  static bool get hasFirebaseApiKey => firebaseApiKey.isNotEmpty;

  static const authHost = 'https://dev-apiauth.dartstream.io';
  static const platformHost = 'https://dev-apiplatform.dartstream.io';
  static const experienceHost = 'https://dev-apiexperience.dartstream.io';
  static const reactiveHost = 'https://dev-apireactive.dartstream.io';
  static const persistenceHost = 'https://dev-apipersistence.dartstream.io';
}
