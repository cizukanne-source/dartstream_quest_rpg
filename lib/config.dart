import 'package:dartstream_client/dartstream_client.dart';

/// Hosts and Firebase config for the DartStream Quest RPG.
///
/// The app uses Firebase Identity Toolkit for the user-facing sign-up / sign-in
/// step and then bootstraps a DartStream session for tenant-aware access.
///
/// Build-time defines can override the Firebase API key and any service hosts.
class AppConfig {
  static const _defaultFirebaseApiKey = '';
  static const _defaultGoogleOAuthClientId = '';

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

  static String get googleOAuthClientId {
    final buildTimeClientId =
        const String.fromEnvironment('GOOGLE_OAUTH_CLIENT_ID').trim();
    if (buildTimeClientId.isNotEmpty) {
      return buildTimeClientId;
    }
    final legacyBuildTimeClientId =
        const String.fromEnvironment('GOOGLE_CLIENT_ID').trim();
    return legacyBuildTimeClientId.isNotEmpty
        ? legacyBuildTimeClientId
        : _defaultGoogleOAuthClientId;
  }

  static bool get hasGoogleSignIn => googleOAuthClientId.isNotEmpty;

  /// Backwards-compatible alias for older call sites.
  static String get googleClientId => googleOAuthClientId;

  /// Backwards-compatible alias for older call sites.
  static bool get hasGoogleClientId => hasGoogleSignIn;

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

  // ---- IntelliToggle (Aortem feature-flag SaaS, via OpenFeature) ----------
  //
  // The IntelliToggle OpenFeature provider authenticates with OAuth2
  // client-credentials. These are injected at build time, never committed:
  //   flutter run -d chrome --web-port=3000 \
  //     --dart-define=FIREBASE_API_KEY=YOUR_KEY \
  //     --dart-define=INTELLITOGGLE_CLIENT_ID=... \
  //     --dart-define=INTELLITOGGLE_CLIENT_SECRET=... \
  //     --dart-define=INTELLITOGGLE_TENANT_ID=...
  // The secret is confidential - supplying it to a web bundle is only safe for
  // a demo/sandbox tenant; production keeps client-credentials server-side.
  static const intelliToggleClientId =
      String.fromEnvironment('INTELLITOGGLE_CLIENT_ID');
  static const intelliToggleClientSecret =
      String.fromEnvironment('INTELLITOGGLE_CLIENT_SECRET');
  static const intelliToggleTenantId =
      String.fromEnvironment('INTELLITOGGLE_TENANT_ID');

  /// Optional API host override; defaults to IntelliToggle production.
  static String get intelliToggleApiUrl {
    final override = const String.fromEnvironment('INTELLITOGGLE_API_URL').trim();
    return override.isNotEmpty
        ? override
        : 'https://api.intellitoggle.com';
  }

  /// Whether the IntelliToggle client-credentials were injected; the dedicated
  /// IntelliToggle screen surfaces this and explains how to supply them.
  static bool get hasIntelliToggle =>
      intelliToggleClientId.isNotEmpty &&
      intelliToggleClientSecret.isNotEmpty &&
      intelliToggleTenantId.isNotEmpty;

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

  /// Backwards-compatible alias for older call sites.
  static DartStreamConfig get dartStream => dartStreamConfig;
}
