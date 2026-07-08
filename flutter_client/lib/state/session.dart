import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/google_auth.dart';
import '../config.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  static const _storageKey = 'dartstream_quest_rpg.session.v1';

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

  /// Federated sign-in with Google (web only). Obtains a Firebase ID token via
  /// Google Identity Services + Identity Toolkit, then onboards a DartStream
  /// session through the SDK's provider path.
  Future<void> signInWithGoogle() => _authenticateConnection(() async {
        if (AppConfig.firebaseApiKey.isEmpty) {
          throw StateError('Firebase API key is required for Google sign-in.');
        }
        final firebaseIdToken = await signInWithGoogleFirebaseIdToken(
          clientId: AppConfig.googleOAuthClientId,
          firebaseApiKey: AppConfig.firebaseApiKey,
        );
        final client = DartStreamClient(config: AppConfig.dartStreamConfig);
        final session = await client.auth.onboardProviderIdToken(
          provider: DartStreamAuthProvider.google,
          firebaseIdToken: firebaseIdToken,
        );
        return DartStreamConnection(
          client: client.withSession(session),
          session: session,
        );
      });

  DartStreamClient? get client => connection?.client;

  DartStreamSession? get sdkSession => connection?.session;

  bool get doubleXpEnabled => hasFeatureFlag('double_xp');

  bool get hardModeEnabled => hasFeatureFlag('hard_mode');

  bool get lightThemeEnabled => hasFeatureFlag('light_mode');

  bool get darkThemeEnabled => hasFeatureFlag('dark_mode');

  bool get reduceMusicVolumeEnabled => hasFeatureFlag('reduce_music_volume');

  bool get reduceSfxVolumeEnabled => hasFeatureFlag('reduce_sfx_volume');

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

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = prefs.getString(_storageKey);
    if (encoded == null || encoded.isEmpty) {
      return;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        await prefs.remove(_storageKey);
        return;
      }
      _applyPersistedState(Map<String, dynamic>.from(decoded));
    } catch (_) {
      await prefs.remove(_storageKey);
      signOut();
    }
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

      await _applySignedInConnection(
        connection,
        displayName: displayName,
        photoUrl:
            _stringFromMap(connection.session.raw, const ['photoUrl', 'photo_url']),
      );
      if (signUp && displayName != null && displayName.trim().isNotEmpty) {
        await updateDisplayName(displayName.trim());
      }
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

  Future<void> _authenticateConnection(
    Future<DartStreamConnection> Function() connect,
  ) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final connection = await connect();
      await _applySignedInConnection(connection);
    } on DartStreamFirebaseAuthException catch (error) {
      status = SessionStatus.error;
      errorMessage = _friendlyFirebaseAuthError(error.message);
    } on DartStreamApiException catch (error) {
      status = SessionStatus.error;
      errorMessage = _friendlyApiError(error);
    } on StateError catch (error) {
      status = SessionStatus.error;
      errorMessage = _friendlyFirebaseAuthError(error.message);
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

  String _friendlyFirebaseAuthError(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('api key not valid') ||
        lower.contains('api_key_invalid') ||
        lower.contains('invalid api key')) {
      return 'Firebase rejected the web API key. Rebuild the web app with a valid `--dart-define=FIREBASE_API_KEY=...` value on its own line, then redeploy.';
    }
    return message;
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
    _clearPersistedSession();
    notifyListeners();
  }

  Future<void> _applySignedInConnection(
    DartStreamConnection connection, {
    String? emailOverride,
    String? displayName,
    String? photoUrl,
    Uint8List? avatarBytes,
  }) async {
    _closeConnection();
    this.connection = connection;
    email = connection.session.email ?? emailOverride;
    this.displayName = displayName;
    this.photoUrl =
        photoUrl ?? _stringFromMap(connection.session.raw, const ['photoUrl', 'photo_url']);
    this.avatarBytes = avatarBytes;
    userId = connection.session.userId;
    tenantId = connection.session.tenantId;
    bootstrap = connection.session.raw;
    featureFlags = const [];
    status = SessionStatus.signedIn;
    try {
      await save();
    } catch (_) {
      // Persistence is best-effort; login should still succeed if storage is unavailable.
    }
  }

  void _closeConnection() {
    connection?.client.close();
    connection = null;
  }

  void updateFeatureFlags(List<dynamic> flags) {
    featureFlags = List<dynamic>.unmodifiable(flags);
    unawaited(save());
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
    unawaited(save());
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
    unawaited(save());
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
    unawaited(save());
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
    unawaited(save());
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
    unawaited(save());
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

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    if (status != SessionStatus.signedIn || connection == null) {
      await prefs.remove(_storageKey);
      return;
    }

    final snapshot = <String, dynamic>{
      'status': status.name,
      'email': email,
      'displayName': displayName,
      'photoUrl': photoUrl,
      'avatarBytes': avatarBytes == null ? null : base64Encode(avatarBytes!),
      'userId': userId,
      'tenantId': tenantId,
      'errorMessage': errorMessage,
      'featureFlags': featureFlags,
      'bootstrap': bootstrap,
      'session': _sessionToJson(connection!.session),
    };

    await prefs.setString(_storageKey, jsonEncode(snapshot));
  }

  Future<void> _clearPersistedSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  void _applyPersistedState(Map<String, dynamic> snapshot) {
    final sessionJson = snapshot['session'];
    if (sessionJson is! Map) {
      signOut();
      return;
    }

    final restoredSession = _sessionFromJson(Map<String, dynamic>.from(sessionJson));
    final restoredClient = DartStreamClient(
      config: AppConfig.dartStreamConfig,
      session: restoredSession,
    );

    connection = DartStreamConnection(
      client: restoredClient,
      session: restoredSession,
    );
    status = SessionStatus.signedIn;
    email = snapshot['email'] as String? ?? restoredSession.email;
    displayName = snapshot['displayName'] as String?;
    photoUrl = snapshot['photoUrl'] as String?;
    avatarBytes = _bytesFromBase64(snapshot['avatarBytes']);
    userId = snapshot['userId'] as String? ?? restoredSession.userId;
    tenantId = snapshot['tenantId'] as String? ?? restoredSession.tenantId;
    errorMessage = snapshot['errorMessage'] as String?;
    featureFlags = _dynamicList(snapshot['featureFlags']);
    bootstrap = _mapFromDynamic(snapshot['bootstrap']) ?? restoredSession.raw;
  }

  Map<String, dynamic> _sessionToJson(DartStreamSession session) => <String, dynamic>{
    'idToken': session.idToken,
    'userId': session.userId,
    'tenantId': session.tenantId,
    'email': session.email,
    'canonicalTenantId': session.canonicalTenantId,
    'tenantRole': session.tenantRole,
    'raw': session.raw,
  };

  DartStreamSession _sessionFromJson(Map<String, dynamic> json) {
    return DartStreamSession(
      idToken: json['idToken'] as String,
      userId: json['userId'] as String,
      tenantId: json['tenantId'] as String,
      email: json['email'] as String?,
      canonicalTenantId: json['canonicalTenantId'] as String?,
      tenantRole: json['tenantRole'] as String?,
      raw: _mapFromDynamic(json['raw']) ?? const <String, dynamic>{},
    );
  }

  Map<String, dynamic>? _mapFromDynamic(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  List<dynamic> _dynamicList(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return const [];
  }

  Uint8List? _bytesFromBase64(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    try {
      return base64Decode(value);
    } catch (_) {
      return null;
    }
  }
}
