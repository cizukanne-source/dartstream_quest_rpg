import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../config.dart';
import '../state/session.dart';
import '../widgets/google_sign_in_button.dart';

enum AuthMode { signUp, signIn }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _displayName = TextEditingController();
  StreamSubscription<GoogleSignInAuthenticationEvent>? _googleAuthSubscription;

  AuthMode _mode = AuthMode.signUp;
  String? _localError;
  String? _googleInitError;
  bool _googleBusy = false;
  bool _googleReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeGoogleSignIn());
  }

  Future<void> _initializeGoogleSignIn() async {
    try {
      await _googleSignIn.initialize(
        clientId: AppConfig.googleClientId.isEmpty ? null : AppConfig.googleClientId,
      );
      _googleAuthSubscription = _googleSignIn.authenticationEvents.listen(
        _handleGoogleAuthenticationEvent,
        onError: _handleGoogleAuthenticationError,
      );
      if (kIsWeb) {
        _googleSignIn.attemptLightweightAuthentication();
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _googleReady = true;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _googleReady = false;
        _googleInitError = _googleErrorMessage(error);
      });
    }
  }

  @override
  void dispose() {
    unawaited(_googleAuthSubscription?.cancel());
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _displayName.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == AuthMode.signUp;

  void _setMode(AuthMode mode) {
    setState(() {
      _mode = mode;
      _localError = null;
    });
  }

  Future<void> _handleGoogleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) async {
    if (!mounted || !kIsWeb) {
      return;
    }

    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(user: final user):
        await _completeGoogleSignIn(user);
      case GoogleSignInAuthenticationEventSignOut():
        break;
    }
  }

  Future<void> _handleGoogleAuthenticationError(Object error) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _googleBusy = false;
      _googleInitError = _googleErrorMessage(error);
    });
  }

  Future<void> _startGoogleSignIn() async {
    if (_googleBusy || widget.session.status == SessionStatus.signingIn) {
      return;
    }
    if (kIsWeb) {
      return;
    }

    setState(() {
      _googleBusy = true;
      _localError = null;
    });

    try {
      final account = await _googleSignIn.authenticate();
      await _completeGoogleSignIn(account);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _googleBusy = false;
        _localError = _googleErrorMessage(error);
      });
    }
  }

  Future<void> _completeGoogleSignIn(GoogleSignInAccount account) async {
    if (!mounted) {
      return;
    }
    setState(() {
      _googleBusy = true;
      _localError = null;
    });

    await widget.session.signInWithGoogleAccount(account);

    if (!mounted) {
      return;
    }
    setState(() {
      _googleBusy = false;
    });
  }

  String _googleErrorMessage(Object error) {
    if (error is GoogleSignInException) {
      return error.description ?? error.toString();
    }
    return error.toString();
  }

  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
    }
    if (_isSignUp && _displayName.text.trim().isEmpty) {
      return 'Display name cannot be empty.';
    }
    if (_isSignUp && _password.text != _confirm.text) {
      return 'Passwords do not match.';
    }
    return null;
  }

  void _submit() {
    final error = _validate();
    if (error != null) {
      setState(() => _localError = error);
      return;
    }
    setState(() => _localError = null);

    final email = _email.text.trim();
    final password = _password.text;
    final displayName = _displayName.text.trim();

    if (_isSignUp) {
      widget.session.signUp(email, password, displayName: displayName);
    } else {
      widget.session.signIn(email, password);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.status == SessionStatus.signingIn || _googleBusy;
    final error = _localError ?? widget.session.errorMessage ?? _googleInitError;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF07111C),
              Color(0xFF0B1930),
              Color(0xFF132743),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: _formPanel(context, busy, error),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _formPanel(
    BuildContext context,
    bool busy,
    String? error,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1726).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2B4563)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _isSignUp ? 'Create account' : 'Sign in',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start the adventure with a real identity, then bring your hero into the world.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFB7C6DA),
                ),
          ),
          const SizedBox(height: 20),
          SegmentedButton<AuthMode>(
            segments: const [
              ButtonSegment(
                value: AuthMode.signUp,
                label: Text('Create Account'),
                icon: Icon(Icons.person_add_alt_1_rounded),
              ),
              ButtonSegment(
                value: AuthMode.signIn,
                label: Text('Sign In'),
                icon: Icon(Icons.login_rounded),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: busy ? null : (value) => _setMode(value.first),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
              labelText: 'Email',
              hintText: 'player@example.com',
              border: OutlineInputBorder(),
            ),
            enabled: !busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            decoration: const InputDecoration(
              labelText: 'Password',
              helperText: 'At least 6 characters',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            enabled: !busy,
          ),
          if (_isSignUp) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              decoration: const InputDecoration(
                labelText: 'Confirm password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              enabled: !busy,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _displayName,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'Nova Runner',
                border: OutlineInputBorder(),
              ),
              enabled: !busy,
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: busy ? null : _submit,
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.rocket_launch_rounded),
              label: Text(
                busy
                    ? 'Please wait...'
                    : _isSignUp
                        ? 'Create account'
                        : 'Sign in',
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.12)),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('or'),
              ),
              Expanded(
                child: Divider(color: Colors.white.withValues(alpha: 0.12)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          googleSignInButton(
            enabled: !busy,
            ready: _googleReady || !kIsWeb,
            onPressed: _startGoogleSignIn,
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: error),
          ],
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF402027),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB84B5C)),
      ),
      padding: const EdgeInsets.all(14),
      child: Text(message),
    );
  }
}
