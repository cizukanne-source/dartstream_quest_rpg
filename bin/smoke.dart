import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

const _firebaseSignIn =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const _firebaseSignUp =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

int _passes = 0;
int _fails = 0;
int _skips = 0;

void main(List<String> args) async {
  final env = Platform.environment;
  final apiKey = env['FIREBASE_API_KEY'];
  final email = env['TEST_EMAIL'];
  final password = env['TEST_PASSWORD'];

  if (apiKey == null || apiKey.isEmpty) {
    _fatal('FIREBASE_API_KEY not set. See .env.example.');
  }
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    _fatal('TEST_EMAIL / TEST_PASSWORD not set. See .env.example.');
  }

  final hosts = _Hosts.fromEnv(env);

  print('== DartStream E2E smoke ==');
  print('  auth        : ${hosts.auth}');
  print('  platform    : ${hosts.platform}');
  print('  experience  : ${hosts.experience}');
  print('  reactive    : ${hosts.reactive}');
  print('  persistence : ${hosts.persistence}');
  print('  user        : $email');
  print('');

  final idToken = await _firebaseAuth(apiKey!, email!, password!);
  if (idToken == null) {
    _summary();
    exit(1);
  }

  // Step: signup -> captures userId + tenantId for downstream calls.
  String? userId;
  String? tenantId;
  await _step('POST /api/v1/auth/signup', () async {
    return http.post(
      Uri.parse('${hosts.auth}/api/v1/auth/signup'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
  }, allowStatuses: const [200, 201, 409], onBody: (body) {
    final ids = _extractIds(body);
    userId = ids.$1;
    tenantId = ids.$2;
    print('   extracted userId=$userId tenantId=$tenantId');
  });

  if (userId == null || tenantId == null) {
    print('   [FAIL] Could not extract userId/tenantId from signup body; aborting downstream calls.');
    _fails++;
    _summary();
    exit(1);
  }

  final authHeaders = {
    'authorization': 'Bearer $idToken',
    'x-tenant-id': tenantId!,
    'x-user-id': userId!,
  };

  await _step('GET  /api/v1/auth/me', () async {
    return http.get(
      Uri.parse('${hosts.auth}/api/v1/auth/me'),
      headers: authHeaders,
    );
  });

  await _step('GET  /api/v1/platform/feature-flags', () async {
    return http.get(
      Uri.parse('${hosts.platform}/api/v1/platform/feature-flags'),
      headers: authHeaders,
    );
  });

  final expQuery = 'userId=${Uri.encodeQueryComponent(userId!)}'
      '&tenantId=${Uri.encodeQueryComponent(tenantId!)}';

  await _step('GET  /api/v1/experience/profiles/me', () async {
    return http.get(
      Uri.parse('${hosts.experience}/api/v1/experience/profiles/me?$expQuery'),
      headers: authHeaders,
    );
  });

  await _step('POST /api/v1/experience/cloud-save/snapshot', () async {
    return http.post(
      Uri.parse(
        '${hosts.experience}/api/v1/experience/cloud-save/snapshot?$expQuery&slotKey=smoke',
      ),
      headers: {
        ...authHeaders,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'payload': {
          'score': 42,
          'level': 1,
          'items': ['coin', 'coin', 'star'],
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
  }, allowStatuses: const [200, 201]);

  await _step('GET  /api/v1/experience/cloud-save/snapshot', () async {
    return http.get(
      Uri.parse(
        '${hosts.experience}/api/v1/experience/cloud-save/snapshot?$expQuery&slotKey=smoke',
      ),
      headers: authHeaders,
    );
  });

  await _step('GET  /api/v1/experience/inventory/items', () async {
    return http.get(
      Uri.parse(
        '${hosts.experience}/api/v1/experience/inventory/items?$expQuery',
      ),
      headers: authHeaders,
    );
  });

  await _step('POST /api/v1/reactive/events/log', () async {
    return http.post(
      Uri.parse('${hosts.reactive}/api/v1/reactive/events/log'),
      headers: {
        ...authHeaders,
        'content-type': 'application/json',
      },
      body: jsonEncode({
        'event_type': 'smoke.score.milestone',
        'payload': {'score': 42, 'source': 'e2e-smoke'},
      }),
    );
  }, allowStatuses: const [200, 201]);

  await _step('GET  /api/v1/reactive/streaming/channels', () async {
    return http.get(
      Uri.parse('${hosts.reactive}/api/v1/reactive/streaming/channels'),
      headers: authHeaders,
    );
  });

  await _step('GET  /api/v1/persistence/database', () async {
    return http.get(
      Uri.parse('${hosts.persistence}/api/v1/persistence/database/'),
      headers: authHeaders,
    );
  });

  // IntelliToggle — Aortem's feature-flag SaaS, evaluated via the OpenFeature
  // provider. Different auth model from everything above (OAuth2
  // client-credentials, no Firebase user), so it's optional: skipped unless its
  // credentials are supplied. See bin/intellitoggle_deepdive.dart for the full
  // exercise.
  await _intelliToggleStep(env, userId!);

  _summary();
  exit(_fails == 0 ? 0 : 1);
}

/// One representative IntelliToggle contract: register the OpenFeature provider
/// (the OAuth2 client-credentials exchange runs inside it — reaching READY is
/// the proof it worked), then evaluate a single boolean flag against the
/// signed-in identity.
Future<void> _intelliToggleStep(Map<String, String> env, String userId) async {
  print('-- IntelliToggle feature flag (OpenFeature) --');
  final clientId = env['INTELLITOGGLE_CLIENT_ID']?.trim();
  final clientSecret = env['INTELLITOGGLE_CLIENT_SECRET']?.trim();
  final tenantId = env['INTELLITOGGLE_TENANT_ID']?.trim();
  if ((clientId?.isEmpty ?? true) ||
      (clientSecret?.isEmpty ?? true) ||
      (tenantId?.isEmpty ?? true)) {
    _skip('IntelliToggle — set INTELLITOGGLE_CLIENT_ID / _CLIENT_SECRET / '
        '_TENANT_ID to include it');
    return;
  }

  final apiUrl = (env['INTELLITOGGLE_API_URL']?.trim().isNotEmpty ?? false)
      ? env['INTELLITOGGLE_API_URL']!.trim()
      : 'https://api.intellitoggle.com';
  final flagKey = (env['INTELLITOGGLE_BOOL_FLAG']?.trim().isNotEmpty ?? false)
      ? env['INTELLITOGGLE_BOOL_FLAG']!.trim()
      : 'new-dashboard';

  try {
    final provider = IntelliToggleProvider(
      clientId: clientId!,
      clientSecret: clientSecret!,
      tenantId: tenantId!,
      options: IntelliToggleOptions.production(baseUri: Uri.parse(apiUrl)),
    );
    try {
      await OpenFeatureAPI().setProvider(provider);
    } catch (_) {
      // setProvider keeps the provider in ERROR state rather than throwing.
    }
    if (provider.state != ProviderState.READY) {
      _fail('IntelliToggle provider not READY (state=${provider.state.name}) '
          '— check client-credentials / INTELLITOGGLE_API_URL');
      return;
    }
    OpenFeatureAPI()
        .setGlobalContext(OpenFeatureEvaluationContext({'userId': userId}));
    final res = await provider
        .getBooleanFlag(flagKey, false)
        .timeout(const Duration(seconds: 20));
    _pass('IntelliToggle getBooleanFlag("$flagKey") -> value=${res.value} '
        'reason=${res.reason}');
  } on TimeoutException {
    _fail('IntelliToggle -> TIMEOUT after 20s');
  } catch (e) {
    _fail('IntelliToggle -> exception: $e');
  }
}

(String?, String?) _extractIds(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is! Map) return (null, null);
    final user = (decoded['data'] is Map ? decoded['data']['user'] : null) ??
        decoded['user'] ??
        decoded;
    String? pick(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }
    final uid = user is Map
        ? pick(user, ['id', 'user_id', 'userId', 'uid'])
        : null;
    String? tid;
    if (user is Map) {
      tid = pick(user, ['tenant_id', 'tenantId', 'active_tenant_id', 'activeTenantId']);
    }
    tid ??= decoded['active_tenant_id'] as String? ??
        decoded['activeTenantId'] as String? ??
        decoded['tenant_id'] as String? ??
        decoded['tenantId'] as String?;
    return (uid, tid);
  } catch (_) {
    return (null, null);
  }
}

class _Hosts {
  _Hosts({
    required this.auth,
    required this.platform,
    required this.experience,
    required this.reactive,
    required this.persistence,
  });

  final String auth;
  final String platform;
  final String experience;
  final String reactive;
  final String persistence;

  static _Hosts fromEnv(Map<String, String> env) {
    String get(String key, String fallback) =>
        (env[key]?.trim().isNotEmpty ?? false) ? env[key]!.trim() : fallback;
    return _Hosts(
      auth: get('API_AUTH', 'https://dev-apiauth.dartstream.io'),
      platform: get('API_PLATFORM', 'https://dev-apiplatform.dartstream.io'),
      experience:
          get('API_EXPERIENCE', 'https://dev-apiexperience.dartstream.io'),
      reactive: get('API_REACTIVE', 'https://dev-apireactive.dartstream.io'),
      persistence:
          get('API_PERSISTENCE', 'https://dev-apipersistence.dartstream.io'),
    );
  }
}

Future<String?> _firebaseAuth(
  String apiKey,
  String email,
  String password,
) async {
  print('-- Firebase sign-in --');
  final body = jsonEncode({
    'email': email,
    'password': password,
    'returnSecureToken': true,
  });
  final referer =
      Platform.environment['FIREBASE_REFERER'] ?? 'http://localhost:3000';
  final headers = {
    'content-type': 'application/json',
    'referer': referer,
  };

  final signInResp = await http.post(
    Uri.parse('$_firebaseSignIn?key=$apiKey'),
    headers: headers,
    body: body,
  );

  if (signInResp.statusCode == 200) {
    final token = (jsonDecode(signInResp.body) as Map)['idToken'] as String?;
    if (token != null) {
      _pass(
          'Firebase signInWithPassword -> got idToken (${token.length} chars)');
      return token;
    }
  }

  final signInError = _firebaseErrorMessage(signInResp.body);
  print('   signIn failed: HTTP ${signInResp.statusCode} ($signInError) — trying signUp');

  final signUpResp = await http.post(
    Uri.parse('$_firebaseSignUp?key=$apiKey'),
    headers: headers,
    body: body,
  );
  if (signUpResp.statusCode == 200) {
    final token = (jsonDecode(signUpResp.body) as Map)['idToken'] as String?;
    if (token != null) {
      _pass('Firebase signUp -> got idToken (${token.length} chars)');
      return token;
    }
  }

  _fail(
    'Firebase auth failed. signIn=${signInResp.statusCode} ($signInError); '
    'signUp=${signUpResp.statusCode} (${_firebaseErrorMessage(signUpResp.body)})',
  );
  return null;
}

String _firebaseErrorMessage(String body) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map &&
        decoded['error'] is Map &&
        decoded['error']['message'] is String) {
      return decoded['error']['message'] as String;
    }
  } catch (_) {}
  return body.length > 120 ? '${body.substring(0, 120)}...' : body;
}

Future<void> _step(
  String label,
  Future<http.Response> Function() send, {
  List<int> allowStatuses = const [200, 201, 204],
  void Function(String body)? onBody,
}) async {
  print('-- $label --');
  try {
    final stopwatch = Stopwatch()..start();
    final resp = await send().timeout(const Duration(seconds: 20));
    stopwatch.stop();
    final excerpt = _excerpt(resp.body);
    if (allowStatuses.contains(resp.statusCode)) {
      _pass(
          '$label -> ${resp.statusCode} in ${stopwatch.elapsedMilliseconds}ms');
      if (excerpt.isNotEmpty) print('   body: $excerpt');
      onBody?.call(resp.body);
    } else {
      _fail('$label -> ${resp.statusCode}');
      if (excerpt.isNotEmpty) print('   body: $excerpt');
    }
  } on TimeoutException {
    _fail('$label -> TIMEOUT after 20s');
  } catch (e) {
    _fail('$label -> exception: $e');
  }
}

String _excerpt(String body) {
  final trimmed = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (trimmed.isEmpty) return '';
  return trimmed.length > 280 ? '${trimmed.substring(0, 280)}...' : trimmed;
}

void _pass(String msg) {
  _passes++;
  print('   [PASS] $msg');
}

void _fail(String msg) {
  _fails++;
  print('   [FAIL] $msg');
}

void _skip(String msg) {
  _skips++;
  print('   [SKIP] $msg');
}

void _fatal(String msg) {
  stderr.writeln('FATAL: $msg');
  exit(2);
}

void _summary() {
  print('');
  print('== Summary: $_passes pass, $_fails fail, $_skips skip ==');
}
