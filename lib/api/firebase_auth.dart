import 'dart:convert';

import 'package:http/http.dart' as http;

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
  static Future<FirebaseAuthResult> signUp(
    String email,
    String password,
  ) async {
    return _post(
      'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=${AppConfig.firebaseApiKey}',
      email: email,
      password: password,
    );
  }

  static Future<FirebaseAuthResult> signIn(
    String email,
    String password,
  ) async {
    return _post(
      'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=${AppConfig.firebaseApiKey}',
      email: email,
      password: password,
    );
  }

  static Future<FirebaseAuthResult> _post(
    String url, {
    required String email,
    required String password,
  }) async {
    if (!AppConfig.hasFirebaseApiKey) {
      throw FirebaseAuthException(
        'Missing FIREBASE_API_KEY. Pass it with --dart-define=FIREBASE_API_KEY=...',
      );
    }

    final response = await http.post(
      Uri.parse(url),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'returnSecureToken': true,
      }),
    );

    final body = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw FirebaseAuthException(_errorMessage(body, response.body));
    }
    if (body is! Map<String, dynamic>) {
      throw FirebaseAuthException('Firebase returned an unexpected payload.');
    }

    return FirebaseAuthResult(
      idToken: body['idToken'] as String? ?? '',
      refreshToken: body['refreshToken'] as String? ?? '',
      localId: body['localId'] as String? ?? '',
      email: body['email'] as String? ?? email,
      raw: body,
    );
  }
}

dynamic _decodeJson(String body) {
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }
  try {
    return jsonDecode(body);
  } catch (_) {
    return {'raw': body};
  }
}

String _errorMessage(dynamic body, String fallback) {
  if (body is Map<String, dynamic>) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    final message = body['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return fallback.isNotEmpty ? fallback : 'Authentication failed.';
}
