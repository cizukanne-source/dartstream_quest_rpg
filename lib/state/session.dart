import 'package:flutter/foundation.dart';

import '../api/dartstream.dart';
import '../api/firebase_auth.dart';

enum SessionStatus { signedOut, signingIn, signedIn, error }

class Session extends ChangeNotifier {
  SessionStatus status = SessionStatus.signedOut;
  String? email;
  String? displayName;
  String? userId;
  String? tenantId;
  String? errorMessage;
  DartstreamApi? api;
  Map<String, dynamic>? bootstrap;

  Future<void> signUp(String email, String password, {String? displayName}) =>
      _authenticate(
        () => FirebaseAuthRest.signUp(email, password),
        displayName: displayName,
      );

  Future<void> signIn(String email, String password, {String? displayName}) =>
      _authenticate(
        () => FirebaseAuthRest.signIn(email, password),
        displayName: displayName,
      );

  Future<void> _authenticate(
    Future<FirebaseAuthResult> Function() firebaseAuth, {
    String? displayName,
  }) async {
    status = SessionStatus.signingIn;
    errorMessage = null;
    notifyListeners();

    try {
      final auth = await firebaseAuth();
      final api = DartstreamApi(idToken: auth.idToken);
      final ids = await api.signup(
        email: auth.email,
        displayName: displayName,
      );

      this.api = api;
      email = auth.email;
      this.displayName = displayName;
      userId = ids.userId;
      tenantId = ids.tenantId;
      bootstrap = ids.raw;
      status = SessionStatus.signedIn;
    } on FirebaseAuthException catch (error) {
      status = SessionStatus.error;
      errorMessage = error.message;
    } on DartstreamApiException catch (error) {
      status = SessionStatus.error;
      errorMessage = error.toString();
    } catch (error) {
      status = SessionStatus.error;
      errorMessage = error.toString();
    }

    notifyListeners();
  }

  void signOut() {
    status = SessionStatus.signedOut;
    email = null;
    displayName = null;
    userId = null;
    tenantId = null;
    errorMessage = null;
    api = null;
    bootstrap = null;
    notifyListeners();
  }
}
