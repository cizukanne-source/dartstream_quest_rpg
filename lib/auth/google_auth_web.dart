// JS interop bindings use the upstream Google Identity Services key names
// (client_id, access_token, error_callback), which aren't lowerCamelCase.
// ignore_for_file: non_constant_identifier_names

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:http/http.dart' as http;

/// Signs in with Google on the web and returns a Firebase ID token.
///
/// Flow:
///   1. Google Identity Services opens the account chooser popup and returns a
///      Google OAuth access token.
///   2. Firebase Identity Toolkit `accounts:signInWithIdp` exchanges that for
///      a Firebase ID token carrying the Google identity.
///
/// The caller hands the returned token to
/// `client.auth.onboardProviderIdToken(provider: DartStreamAuthProvider.google, ...)`.
Future<String> signInWithGoogleFirebaseIdToken({
  required String clientId,
  required String firebaseApiKey,
}) async {
  final accessToken = await _requestGoogleAccessToken(clientId);

  final uri = Uri.https(
    'identitytoolkit.googleapis.com',
    '/v1/accounts:signInWithIdp',
    {'key': firebaseApiKey},
  );
  final response = await http.post(
    uri,
    headers: const {'content-type': 'application/json'},
    body: jsonEncode({
      'postBody': 'access_token=$accessToken&providerId=google.com',
      // On Flutter web `Uri.base` is the page URL; its origin is the authorized
      // request origin Identity Toolkit expects for the IdP exchange.
      'requestUri': Uri.base.origin,
      'returnIdpCredential': true,
      'returnSecureToken': true,
    }),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Google federation failed (${response.statusCode}): ${response.body}',
    );
  }
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final idToken = json['idToken'] as String?;
  if (idToken == null || idToken.isEmpty) {
    throw StateError('signInWithIdp returned no Firebase ID token.');
  }
  return idToken;
}

/// Opens the GIS popup and resolves with a Google OAuth access token.
Future<String> _requestGoogleAccessToken(String clientId) {
  if (!globalContext.has('google')) {
    throw StateError(
      'Google Identity Services did not load. Check the '
      'https://accounts.google.com/gsi/client <script> in web/index.html.',
    );
  }

  final completer = Completer<String>();
  final tokenClient = _initTokenClient(
    _TokenClientConfig(
      client_id: clientId,
      scope: 'openid email profile',
      callback: (_GoogleTokenResponse response) {
        final error = response.error;
        if (error != null && error.isNotEmpty) {
          completer.completeError(StateError('Google sign-in error: $error'));
          return;
        }
        final token = response.access_token;
        if (token == null || token.isEmpty) {
          completer.completeError(
            StateError('Google sign-in returned no access token.'),
          );
          return;
        }
        completer.complete(token);
      }.toJS,
      error_callback: (JSObject _) {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Google sign-in was cancelled.'));
        }
      }.toJS,
    ),
  );
  tokenClient.requestAccessToken();
  return completer.future;
}

@JS('google.accounts.oauth2.initTokenClient')
external _TokenClient _initTokenClient(_TokenClientConfig config);

extension type _TokenClient(JSObject _) implements JSObject {
  external void requestAccessToken();
}

extension type _TokenClientConfig._(JSObject _) implements JSObject {
  external factory _TokenClientConfig({
    required String client_id,
    required String scope,
    required JSFunction callback,
    JSFunction? error_callback,
  });
}

extension type _GoogleTokenResponse(JSObject _) implements JSObject {
  external String? get access_token;
  external String? get error;
}
