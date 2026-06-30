import 'package:flutter/material.dart';

import '../config.dart';
import '../state/session.dart';

enum AuthMode { signUp, signIn }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session});

  final Session session;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _displayName = TextEditingController(text: 'Nova Runner');


  AuthMode _mode = AuthMode.signUp;
  String? _localError;

  @override
  void dispose() {
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

  String? _validate() {
    final email = _email.text.trim();
    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      return 'Enter a valid email address.';
    }
    if (_password.text.length < 6) {
      return 'Password must be at least 6 characters.';
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
      widget.session.signIn(email, password, displayName: displayName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = widget.session.status == SessionStatus.signingIn;
    final hasKey = AppConfig.hasFirebaseApiKey;
    final error = _localError ?? widget.session.errorMessage;

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
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 900;
                    final left = _heroPanel(context, hasKey);
                    final right = _formPanel(context, busy, error, hasKey);
                    if (compact) {
                      return Column(
                        children: [
                          left,
                          const SizedBox(height: 20),
                          right,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: left),
                        const SizedBox(width: 20),
                        Expanded(flex: 4, child: right),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _heroPanel(BuildContext context, bool hasKey) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1726).withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFF2B4563)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black54,
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DARTSTREAM ARENA',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.secondary,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            'A cinematic 3D action shooter where your account enters the arena, your progress carries forward, and every tap turns into firepower.',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: 0.95,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            'Sign up or sign in to enter the strike zone, load your operator profile, and continue your run with live save data behind the scenes.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFB7C6DA),
                  height: 1.5,
                ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: const [
              _Pill(label: 'Live auth', icon: Icons.key_rounded),
              _Pill(label: 'Strike loadout', icon: Icons.shield_rounded),
              _Pill(label: 'Cloud save', icon: Icons.cloud_sync_rounded),
              _Pill(label: 'Action campaign', icon: Icons.local_fire_department_rounded),
            ],
          ),
          const SizedBox(height: 20),
          _FeatureCard(
            icon: Icons.play_circle_rounded,
            title: 'Built for action',
            body:
                'Create your operator, drop into the arena, then keep shooting, chaining hits, and climbing the scoreboard.',
          ),
          const SizedBox(height: 12),
          _FeatureCard(
            icon: Icons.rocket_launch_rounded,
            title: 'Starts safely',
            body: hasKey
                ? 'Firebase key loaded and ready.'
                : 'Firebase key is unavailable, so auth will not start until one is supplied.',
          ),
        ],
      ),
    );
  }

  Widget _formPanel(
    BuildContext context,
    bool busy,
    String? error,
    bool hasKey,
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
          if (error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: error),
          ],
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1626),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2C4663)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0A1626),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2C4663)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFFB7C6DA),
                      ),
                ),
              ],
            ),
          ),
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
