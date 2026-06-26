import 'package:dartstream_client/dartstream_client.dart';

/// Hosts and Firebase config for the DartStream sample environment.
///
/// The app uses Firebase Identity Toolkit for the user-facing sign-up / sign-in
/// step and then bootstraps a DartStream session for tenant-aware access.
///
/// Build-time defines can override the Firebase API key and any service hosts.
class AppConfig {
  static const _defaultFirebaseApiKey = '';

  static const _defaultAuthHost = 'https://dev-apiauth.dartstream.io';
  static const _defaultPlatformHost = 'https://dev-apiplatform.dartstream.io';
  static const _defaultExperienceHost =
      'https://dev-apiexperience.dartstream.io';
  static const _defaultReactiveHost = 'https://dev-apireactive.dartstream.io';
  static const _defaultPersistenceHost =
      'https://dev-apipersistence.dartstream.io';
  static const _defaultBillingHost = 'https://dev-apibilling.dartstream.io';

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

  static DartStreamConfig get dartStreamConfig => DartStreamConfig.dev(
        firebaseApiKey: firebaseApiKey.isEmpty ? null : firebaseApiKey,
      ).copyWith(
        authBaseUrl: Uri.parse(authHost),
        platformBaseUrl: Uri.parse(platformHost),
        experienceBaseUrl: Uri.parse(experienceHost),
        reactiveBaseUrl: Uri.parse(reactiveHost),
        persistenceBaseUrl: Uri.parse(persistenceHost),
        billingBaseUrl: Uri.parse(billingHost),
      );
}
