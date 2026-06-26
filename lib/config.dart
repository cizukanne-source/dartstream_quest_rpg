import 'package:dartstream_client/dartstream_client.dart';

/// Hosts and Firebase config for the live DartStream sample environment.
///
/// The sample uses the same auth pattern as the reference apps:
/// - Firebase Identity Toolkit for the user-facing sign-up / sign-in step
/// - DartStream backend bootstrap for tenant-aware session setup
///
/// The app ships with the public sample Firebase web key baked in, and a
/// build-time FIREBASE_API_KEY still overrides it when provided.
///
/// The backend hosts can also be overridden at build time with API_AUTH,
/// API_PLATFORM, API_EXPERIENCE, API_REACTIVE, and API_PERSISTENCE.
class AppConfig {
  // This is a public Firebase web API key for the sample project.
  // A build-time FIREBASE_API_KEY still overrides it when provided.
  static const _defaultFirebaseApiKey =
      '';

  static const _defaultAuthHost = 'https://apiauth.dartstream.io';
  static const _defaultPlatformHost = 'https://apiplatform.dartstream.io';
  static const _defaultExperienceHost = 'https://apiexperience.dartstream.io';
  static const _defaultReactiveHost = 'https://apireactive.dartstream.io';
  static const _defaultPersistenceHost =
      'https://apipersistence.dartstream.io';
  static const _defaultBillingHost = 'https://apibilling.dartstream.io';

  static String get firebaseApiKey {
    final buildTimeKey = const String.fromEnvironment('FIREBASE_API_KEY').trim();
    return buildTimeKey.isNotEmpty ? buildTimeKey : _defaultFirebaseApiKey;
  }

  static bool get hasFirebaseApiKey => firebaseApiKey.isNotEmpty;

  static String get authHost {
    final override = const String.fromEnvironment('API_AUTH').trim();
    return override.isNotEmpty ? override : _defaultAuthHost;
  }

  static String get platformHost {
    final override = const String.fromEnvironment('API_PLATFORM').trim();
    return override.isNotEmpty ? override : _defaultPlatformHost;
  }

  static String get experienceHost {
    final override = const String.fromEnvironment('API_EXPERIENCE').trim();
    return override.isNotEmpty ? override : _defaultExperienceHost;
  }

  static String get reactiveHost {
    final override = const String.fromEnvironment('API_REACTIVE').trim();
    return override.isNotEmpty ? override : _defaultReactiveHost;
  }

  static String get persistenceHost {
    final override = const String.fromEnvironment('API_PERSISTENCE').trim();
    return override.isNotEmpty ? override : _defaultPersistenceHost;
  }

  static String get billingHost {
    final override = const String.fromEnvironment('API_BILLING').trim();
    return override.isNotEmpty ? override : _defaultBillingHost;
  }

  static DartStreamConfig get dartStreamConfig => DartStreamConfig(
        authBaseUrl: Uri.parse(authHost),
        platformBaseUrl: Uri.parse(platformHost),
        experienceBaseUrl: Uri.parse(experienceHost),
        reactiveBaseUrl: Uri.parse(reactiveHost),
        persistenceBaseUrl: Uri.parse(persistenceHost),
        billingBaseUrl: Uri.parse(billingHost),
        firebaseApiKey: firebaseApiKey,
      );
}
