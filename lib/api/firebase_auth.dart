import 'package:dartstream_client/dartstream_client.dart';

import '../config.dart';

class FirebaseAuthResult {
  FirebaseAuthResult({
    required this.idToken,
    required this.refreshToken,
    required this.localId,
    required this.email,
    required this.raw,
  });

  final String idToken;
  final String refreshToken;
  final String localId;
  final String email;
  final Map<String, dynamic> raw;
}

class FirebaseAuthException implements Exception {
  FirebaseAuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FirebaseAuthRest {
  static DartStreamClient? _client;

  static DartStreamClient get _dartStreamClient {
    if (!AppConfig.hasFirebaseApiKey) {
      throw FirebaseAuthException(
        'Missing FIREBASE_API_KEY. Pass it with --dart-define=FIREBASE_API_KEY=...',
      );
    }

    return _client ??= DartStreamClient(
      config: DartStreamConfig.dev(firebaseApiKey: AppConfig.firebaseApiKey),
    );
  }

  static Future<FirebaseAuthResult> signUp(
    String email,
    String password,
  ) async {
    return _authenticate(email, password);
  }

  static Future<FirebaseAuthResult> signIn(
    String email,
    String password,
  ) async {
    final firebaseSession = await _dartStreamClient.signInWithEmailPassword(
      email: email,
      password: password,
    );
    final session = await _dartStreamClient.onboardFirebaseSession(
      firebaseSession,
    );

    return _wrapSession(
      firebaseSession: firebaseSession,
      onboardedSession: session,
      fallbackEmail: email,
    );
  }

  static Future<FirebaseAuthResult> _authenticate(
    String email,
    String password,
  ) async {
    final firebaseSession = await _dartStreamClient.createEmailPasswordSession(
      email: email,
      password: password,
    );
    final session = await _dartStreamClient.onboardFirebaseSession(
      firebaseSession,
    );

    return _wrapSession(
      firebaseSession: firebaseSession,
      onboardedSession: session,
      fallbackEmail: email,
    );
  }
}

FirebaseAuthResult _wrapSession({
  required dynamic firebaseSession,
  required dynamic onboardedSession,
  required String fallbackEmail,
}) {
  final idToken = _stringValue(firebaseSession, const [
    'idToken',
    'id_token',
    'token',
  ]);
  final refreshToken = _stringValue(firebaseSession, const [
    'refreshToken',
    'refresh_token',
  ]);
  final localId = _stringValue(firebaseSession, const [
    'localId',
    'local_id',
    'userId',
    'uid',
  ]);
  final sessionEmail = _stringValue(firebaseSession, const [
    'email',
    'userEmail',
  ]);

  if (idToken == null || idToken.isEmpty) {
    throw FirebaseAuthException(
      'DartStream Client did not return a Firebase idToken.',
    );
  }

  return FirebaseAuthResult(
    idToken: idToken,
    refreshToken: refreshToken ?? '',
    localId: localId ?? '',
    email: sessionEmail ?? fallbackEmail,
    raw: <String, dynamic>{
      'firebaseSession': _toJsonLike(firebaseSession),
      'onboardedSession': _toJsonLike(onboardedSession),
    },
  );
}

String? _stringValue(dynamic value, List<String> keys) {
  for (final key in keys) {
    try {
      final result = switch (key) {
        'idToken' => value.idToken,
        'id_token' => value.idToken,
        'token' => value.token,
        'refreshToken' => value.refreshToken,
        'refresh_token' => value.refreshToken,
        'localId' => value.localId,
        'local_id' => value.localId,
        'userId' => value.userId,
        'uid' => value.uid,
        'email' => value.email,
        'userEmail' => value.userEmail,
        _ => null,
      };
      if (result is String && result.isNotEmpty) {
        return result;
      }
    } catch (_) {
      // Try the next shape.
    }
  }
  return null;
}

Map<String, dynamic> _toJsonLike(dynamic value) {
  try {
    final json = value.toJson();
    if (json is Map<String, dynamic>) {
      return json;
    }
    if (json is Map) {
      return Map<String, dynamic>.from(json);
    }
  } catch (_) {
    // Fall through to a string snapshot.
  }
  return <String, dynamic>{'value': value.toString()};
}
