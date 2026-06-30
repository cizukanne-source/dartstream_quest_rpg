import 'dart:typed_data';
import 'dart:convert';

import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? email;
  String? displayName;
  String? photoUrl;
  Uint8List? avatarBytes;
  String? userId;
  String? tenantId;
  String? errorMessage;
  DartStreamConnection? connection;
  List<dynamic> featureFlags = const [];
  Map<String, dynamic>? bootstrap;

  Future<void> signUp(String email, String password, {String? displayName}) =>
      _authenticate(email, password, signUp: true, displayName: displayName);

  Future<void> signIn(String email, String password, {String? displayName}) =>
      _authenticate(email, password, signUp: false, displayName: displayName);

  DartStreamClient? get client => connection?.client;

  DartStreamSession? get sdkSession => connection?.session;

  bool get doubleXpEnabled => hasFeatureFlag('double_xp');

  bool get hardModeEnabled => hasFeatureFlag('hard_mode');

  bool get lightThemeEnabled => hasFeatureFlag('light_mode');

  bool get darkThemeEnabled => hasFeatureFlag('dark_mode');

  ThemeMode get themeMode {
    if (lightThemeEnabled) {
      return ThemeMode.light;
    }
    if (darkThemeEnabled) {
      return ThemeMode.dark;
    }
    return ThemeMode.dark;
  }

  @override
  void dispose() {
    _closeConnection();
    super.dispose();
  }

  Future<void> _authenticate(
    String email,
    String password, {
    required bool signUp,
    String? displayName,
  }) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final config = AppConfig.dartStreamConfig;
      final connection = signUp
          ? await DartStreamClient.signUp(
              config: config,
              email: email,
              password: password,
            )
          : await DartStreamClient.signIn(
              config: config,
              email: email,
              password: password,
            );

      _closeConnection();
      this.connection = connection;
      this.email = connection.session.email;
      this.displayName = displayName;
      photoUrl = _stringFromMap(connection.session.raw, const ['photoUrl', 'photo_url']);
      avatarBytes = null;
      userId = connection.session.userId;
      tenantId = connection.session.tenantId;
      bootstrap = connection.session.raw;
      featureFlags = const [];
      status = SessionStatus.signedIn;
    } on DartStreamFirebaseAuthException catch (error) {
      status = SessionStatus.error;
      errorMessage = error.message;
    } on DartStreamApiException catch (error) {
      status = SessionStatus.error;
      errorMessage = _friendlyApiError(error);
    } on StateError catch (error) {
      status = SessionStatus.error;
      errorMessage = error.message;
    } catch (error) {
      status = SessionStatus.error;
      errorMessage = error.toString();
    }

    notifyListeners();
  }

  String _friendlyApiError(DartStreamApiException error) {
    final raw = error.toString();
    final lower = raw.toLowerCase();
    if (error.statusCode == 401) {
      return 'Your session expired or was rejected. Sign in again to continue.';
    }
    if (lower.contains('invalid issuer') ||
        lower.contains('token-verification-failed') ||
        lower.contains('invalid-token') ||
        lower.contains('invalid token')) {
      return 'Firebase token rejected by DartStream: this app is signed in with a Firebase project that the backend does not trust. '
          'Use the Firebase Web API key for the project configured in DartStream, or update the backend issuer allowlist.';
    }
    return raw;
  }

  void signOut() {
    _closeConnection();
    status = SessionStatus.signedOut;
    email = null;
    displayName = null;
    photoUrl = null;
    avatarBytes = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    connection = null;
    featureFlags = const [];
    bootstrap = null;
    notifyListeners();
  }

  void _closeConnection() {
    connection?.client.close();
    connection = null;
  }

  void updateFeatureFlags(List<dynamic> flags) {
    featureFlags = List<dynamic>.unmodifiable(flags);
    notifyListeners();
  }

  Future<void> refreshProfile() async {
    final currentClient = client;
    final currentSession = sdkSession;
    if (currentClient == null || currentSession == null) {
      return;
    }
    final results = await Future.wait([
      currentClient.auth.getUser(currentSession),
      currentClient.auth.avatarBytes(currentSession),
    ]);
    final profile = results[0] as Map<String, dynamic>;
    displayName = _stringFromMap(profile, const ['displayName', 'display_name', 'name']) ?? displayName;
    photoUrl = _stringFromMap(profile, const ['photoUrl', 'photo_url']);
    avatarBytes = results[1] as Uint8List?;
    bootstrap = profile;
    notifyListeners();
  }

  Future<void> updateDisplayName(String newDisplayName) async {
    final currentClient = client;
    final currentSession = sdkSession;
    if (currentClient == null || currentSession == null) {
      return;
    }
    await currentClient.auth.updateUser(
      currentSession,
      displayName: newDisplayName,
    );
    displayName = newDisplayName;
    notifyListeners();
  }

  Future<void> updatePhotoUrl(String? newPhotoUrl) async {
    final currentClient = client;
    final currentSession = sdkSession;
    if (currentClient == null || currentSession == null) {
      return;
    }
    await currentClient.auth.updateUser(
      currentSession,
      photoUrl: newPhotoUrl == null || newPhotoUrl.isEmpty ? null : newPhotoUrl,
      clearPhotoUrl: newPhotoUrl == null || newPhotoUrl.isEmpty,
    );
    photoUrl = newPhotoUrl == null || newPhotoUrl.isEmpty ? null : newPhotoUrl;
    notifyListeners();
  }

  Future<void> uploadAvatar(Uint8List bytes, {required String contentType}) async {
    final currentClient = client;
    final currentSession = sdkSession;
    if (currentClient == null || currentSession == null) {
      return;
    }
    await currentClient.auth.uploadAvatar(
      currentSession,
      image: base64Encode(bytes),
      contentType: contentType,
    );
    avatarBytes = bytes;
    notifyListeners();
  }

  Future<void> deleteAvatar() async {
    final currentClient = client;
    final currentSession = sdkSession;
    if (currentClient == null || currentSession == null) {
      return;
    }
    await currentClient.auth.deleteAvatar(currentSession);
    avatarBytes = null;
    notifyListeners();
  }

  Future<void> changePassword(String newPassword) async {
    final currentSession = sdkSession;
    final key = AppConfig.firebaseApiKey;
    if (currentSession == null || key.isEmpty) {
      throw StateError('Firebase API key is required to change the password.');
    }
    final response = await http.post(
      Uri.https('identitytoolkit.googleapis.com', '/v1/accounts:update', {'key': key}),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({
        'idToken': currentSession.idToken,
        'password': newPassword,
        'returnSecureToken': true,
      }),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DartStreamFirebaseAuthException(
        'Failed to update password.',
        statusCode: response.statusCode,
        body: response.body,
      );
    }
  }

  bool hasFeatureFlag(String key) {
    for (final flag in featureFlags) {
      if (_flagMatches(flag, key)) {
        if (flag is String) {
          return true;
        }
        return _flagIsEnabled(flag);
      }
    }
    return false;
  }

  bool _flagMatches(dynamic flag, String key) {
    if (flag is String) {
      return flag == key;
    }
    if (flag is! Map) {
      return false;
    }
    final map = flag is Map<String, dynamic>
        ? flag
        : Map<String, dynamic>.from(flag);
    final candidates = [
      map['key'],
      map['flagKey'],
      map['featureKey'],
      map['name'],
      map['id'],
    ];
    return candidates.any((value) => value is String && value == key);
  }

  bool _flagIsEnabled(dynamic flag) {
    if (flag is bool) {
      return flag;
    }
    if (flag is String) {
      final normalized = flag.toLowerCase();
      return normalized == 'true' ||
          normalized == 'enabled' ||
          normalized == 'on';
    }
    if (flag is! Map) {
      return false;
    }
    final map = flag is Map<String, dynamic>
        ? flag
        : Map<String, dynamic>.from(flag);
    final candidates = [
      map['enabled'],
      map['value'],
      map['active'],
      map['isEnabled'],
      map['is_enabled'],
    ];
    for (final value in candidates) {
      if (value is bool) {
        return value;
      }
      if (value is String) {
        final normalized = value.toLowerCase();
        if (normalized == 'true' || normalized == 'enabled' || normalized == 'on') {
          return true;
        }
        if (normalized == 'false' ||
            normalized == 'disabled' ||
            normalized == 'off') {
          return false;
        }
      }
    }
    return false;
  }

  String? _stringFromMap(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }
}
