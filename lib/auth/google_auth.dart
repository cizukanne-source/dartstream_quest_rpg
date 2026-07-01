/// Google federated sign-in entry point.
///
/// Resolves to the Google Identity Services (GIS) implementation on the web
/// build (`dart.library.js_interop`) and to a throwing stub elsewhere, so
/// `flutter test` / `flutter analyze` on the Dart VM never compile
/// `dart:js_interop`. Both variants expose [signInWithGoogleFirebaseIdToken].
library;

export 'google_auth_stub.dart'
    if (dart.library.js_interop) 'google_auth_web.dart';
