import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? email;
  String? displayName;
  String? userId;
  String? tenantId;
  String? errorMessage;
  DartStreamConnection? connection;
  Map<String, dynamic>? bootstrap;

  Future<void> signUp(String email, String password, {String? displayName}) =>
      _authenticate(email, password, signUp: true, displayName: displayName);

  Future<void> signIn(String email, String password, {String? displayName}) =>
      _authenticate(email, password, signUp: false, displayName: displayName);

  DartStreamClient? get client => connection?.client;

  DartStreamSession? get sdkSession => connection?.session;

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
      if (!AppConfig.hasFirebaseApiKey) {
        throw StateError(
          'Missing FIREBASE_API_KEY. Pass it with --dart-define=FIREBASE_API_KEY=...',
        );
      }

      final config = DartStreamConfig.dev(
        firebaseApiKey: AppConfig.firebaseApiKey,
      );
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
      userId = connection.session.userId;
      tenantId = connection.session.tenantId;
      bootstrap = connection.session.raw;
      status = SessionStatus.signedIn;
    } on DartStreamFirebaseAuthException catch (error) {
      status = SessionStatus.error;
      errorMessage = error.message;
    } on DartStreamApiException catch (error) {
      status = SessionStatus.error;
      errorMessage = error.toString();
    } on StateError catch (error) {
      status = SessionStatus.error;
      errorMessage = error.message;
    } catch (error) {
      status = SessionStatus.error;
      errorMessage = error.toString();
    }

    notifyListeners();
  }

  void signOut() {
    _closeConnection();
    status = SessionStatus.signedOut;
    email = null;
    displayName = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    connection = null;
    bootstrap = null;
    notifyListeners();
  }

  void _closeConnection() {
    connection?.client.close();
    connection = null;
  }
}
