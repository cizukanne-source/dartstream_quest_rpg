// Firebase auth deep-dive: exercises EVERY ds-auth endpoint against the live
// backend and prints PASS / FAIL / SKIP per contract, then a summary table.
//
// This is the "go deep on auth" companion to smoke.dart. smoke.dart proves the
// happy path across all five services; this file fans out across the full
// ds-auth surface (auth + users + providers) so we can see exactly which auth
// features actually work and ticket the ones that don't.
//
//   set -a && source .env && set +a
//   dart run bin/auth_deepdive.dart
//
// Destructive ops (DELETE user, revoke-all sessions) are SKIPPED unless you set
//   DEEPDIVE_DESTRUCTIVE=1
// so the shared test account is not bricked by a normal run.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _firebaseSignIn =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const _firebaseSignUp =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

final List<_Result> _results = [];

void main(List<String> args) async {
  final env = Platform.environment;
  final apiKey = env['FIREBASE_API_KEY'];
  final email = env['TEST_EMAIL'];
  final password = env['TEST_PASSWORD'];
  final destructive = env['DEEPDIVE_DESTRUCTIVE'] == '1';

  if (apiKey == null || apiKey.isEmpty) _fatal('FIREBASE_API_KEY not set.');
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    _fatal('TEST_EMAIL / TEST_PASSWORD not set.');
  }

  final authHost =
      _get(env, 'API_AUTH', 'https://dev-apiauth.dartstream.io');

  print('== DartStream auth deep-dive ==');
  print('  auth host  : $authHost');
  print('  user       : $email');
  print('  destructive : $destructive');
  print('');

  final idToken = await _firebaseAuth(apiKey!, email!, password!);
  if (idToken == null) {
    _summary();
    exit(1);
  }

  // ---- Bootstrap: signup gives us the DartStream userId + tenantId ----
  String? userId;
  String? tenantId;
  await _step('POST /api/v1/auth/signup', 'auth', () {
    return http.post(
      Uri.parse('$authHost/api/v1/auth/signup'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
  }, allow: const [200, 201, 409], onBody: (b) {
    final ids = _extractIds(b);
    userId = ids.$1;
    tenantId = ids.$2;
    print('   userId=$userId tenantId=$tenantId');
  });

  if (userId == null || tenantId == null) {
    _record('bootstrap', 'extract userId/tenantId', false,
        note: 'signup body had no usable ids; aborting authed calls');
    _summary();
    exit(1);
  }

  final authHeaders = {
    'authorization': 'Bearer $idToken',
    'x-tenant-id': tenantId!,
    'x-user-id': userId!,
  };
  final jsonHeaders = {...authHeaders, 'content-type': 'application/json'};

  // ---- auth module ----
  await _step('POST /api/v1/auth/login (idempotent)', 'auth', () {
    return http.post(
      Uri.parse('$authHost/api/v1/auth/login'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'idToken': idToken}),
    );
  }, allow: const [200, 201]);

  await _step('GET  /api/v1/auth/me', 'auth', () {
    return http.get(Uri.parse('$authHost/api/v1/auth/me'), headers: authHeaders);
  });

  await _step('GET  /api/v1/auth/user-status', 'auth', () {
    return http.get(Uri.parse('$authHost/api/v1/auth/user-status'),
        headers: authHeaders);
  });

  await _step('GET  /api/v1/providers', 'providers', () {
    return http.get(Uri.parse('$authHost/api/v1/providers'),
        headers: authHeaders);
  });

  // ---- federated sign-in plumbing (verifies the same Firebase token) ----
  for (final p in const ['google', 'github', 'microsoft']) {
    await _step('POST /api/v1/auth/signin/$p', 'auth-federated', () {
      return http.post(
        Uri.parse('$authHost/api/v1/auth/signin/$p'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'providerName': p}),
      );
    }, allow: const [200, 201], note: 'plumbing only — token is a Firebase '
        'password token, not a real $p federated token');
  }

  // ---- users module ----
  await _step('GET  /api/v1/users/', 'users', () {
    return http.get(Uri.parse('$authHost/api/v1/users/'), headers: authHeaders);
  });

  await _step('GET  /api/v1/users/<id>', 'users', () {
    return http.get(Uri.parse('$authHost/api/v1/users/$userId'),
        headers: authHeaders);
  });

  await _step('PUT  /api/v1/users/<id>', 'users', () {
    return http.put(
      Uri.parse('$authHost/api/v1/users/$userId'),
      headers: jsonHeaders,
      body: jsonEncode({'displayName': 'Deep Dive ${DateTime.now().toUtc()}'}),
    );
  });

  // sessions
  String? sessionId;
  await _step('GET  /api/v1/users/<id>/sessions', 'users-sessions', () {
    return http.get(Uri.parse('$authHost/api/v1/users/$userId/sessions'),
        headers: authHeaders);
  }, onBody: (b) => sessionId = _firstSessionId(b));

  // avatar lifecycle
  await _step('POST /api/v1/users/<id>/avatar', 'users-avatar', () {
    return http.post(
      Uri.parse('$authHost/api/v1/users/$userId/avatar'),
      headers: jsonHeaders,
      body: jsonEncode({
        'image': 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB'
            'CAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        'contentType': 'image/png',
      }),
    );
  }, allow: const [200, 201]);

  await _step('GET  /api/v1/users/<id>/avatar', 'users-avatar', () {
    return http.get(Uri.parse('$authHost/api/v1/users/$userId/avatar'),
        headers: authHeaders);
  });

  await _step('DELETE /api/v1/users/<id>/avatar', 'users-avatar', () {
    return http.delete(Uri.parse('$authHost/api/v1/users/$userId/avatar'),
        headers: authHeaders);
  }, allow: const [200, 204]);

  // reversible status transitions: suspend -> activate, deactivate -> activate
  await _step('POST /api/v1/users/<id>/suspend', 'users-status', () {
    return http.post(Uri.parse('$authHost/api/v1/users/$userId/suspend'),
        headers: jsonHeaders, body: jsonEncode({'reason': 'deep-dive test'}));
  }, allow: const [200, 201]);

  await _step('POST /api/v1/users/<id>/activate', 'users-status', () {
    return http.post(Uri.parse('$authHost/api/v1/users/$userId/activate'),
        headers: jsonHeaders, body: '{}');
  }, allow: const [200, 201]);

  await _step('PATCH /api/v1/users/<id>/deactivate', 'users-status', () {
    return http.patch(Uri.parse('$authHost/api/v1/users/$userId/deactivate'),
        headers: jsonHeaders, body: '{}');
  }, allow: const [200, 201, 204]);

  // re-activate so the account is left usable
  await _step('POST /api/v1/users/<id>/activate (restore)', 'users-status', () {
    return http.post(Uri.parse('$authHost/api/v1/users/$userId/activate'),
        headers: jsonHeaders, body: '{}');
  }, allow: const [200, 201]);

  // logout (needs a sessionId)
  if (sessionId != null) {
    await _step('POST /api/v1/auth/logout', 'auth', () {
      return http.post(Uri.parse('$authHost/api/v1/auth/logout'),
          headers: jsonHeaders, body: jsonEncode({'sessionId': sessionId}));
    });
  } else {
    _record('auth', 'POST /api/v1/auth/logout', null,
        note: 'SKIP — no sessionId returned by /sessions to log out');
  }

  // ---- destructive (guarded) ----
  if (destructive) {
    await _step('DELETE /api/v1/users/<id>/sessions (revoke all)',
        'users-sessions', () {
      return http.delete(Uri.parse('$authHost/api/v1/users/$userId/sessions'),
          headers: authHeaders);
    }, allow: const [200, 204]);

    await _step('DELETE /api/v1/users/<id> (delete user)', 'users', () {
      return http.delete(Uri.parse('$authHost/api/v1/users/$userId'),
          headers: authHeaders);
    }, allow: const [200, 204]);
  } else {
    _record('users', 'DELETE /api/v1/users/<id>/sessions', null,
        note: 'SKIP — set DEEPDIVE_DESTRUCTIVE=1 to run');
    _record('users', 'DELETE /api/v1/users/<id>', null,
        note: 'SKIP — set DEEPDIVE_DESTRUCTIVE=1 to run');
  }

  _summary();
  exit(_results.any((r) => r.pass == false) ? 1 : 0);
}

// ---------------------------------------------------------------------------

class _Result {
  _Result(this.group, this.label, this.pass, {this.status, this.note});
  final String group;
  final String label;
  final bool? pass; // null = skipped
  final int? status;
  final String? note;
}

void _record(String group, String label, bool? pass,
    {int? status, String? note}) {
  _results.add(_Result(group, label, pass, status: status, note: note));
}

Future<void> _step(
  String label,
  String group,
  Future<http.Response> Function() send, {
  List<int> allow = const [200, 201, 204],
  void Function(String body)? onBody,
  String? note,
}) async {
  print('-- $label --');
  if (note != null) print('   ($note)');
  try {
    final sw = Stopwatch()..start();
    final resp = await send().timeout(const Duration(seconds: 25));
    sw.stop();
    final ok = allow.contains(resp.statusCode);
    final excerpt = _excerpt(resp.body);
    print('   ${ok ? '[PASS]' : '[FAIL]'} $label -> ${resp.statusCode} '
        'in ${sw.elapsedMilliseconds}ms');
    if (excerpt.isNotEmpty) print('   body: $excerpt');
    _record(group, label, ok, status: resp.statusCode, note: note);
    if (ok) onBody?.call(resp.body);
  } on TimeoutException {
    print('   [FAIL] $label -> TIMEOUT');
    _record(group, label, false, note: 'timeout');
  } catch (e) {
    print('   [FAIL] $label -> $e');
    _record(group, label, false, note: '$e');
  }
}

(String?, String?) _extractIds(String body) {
  try {
    final d = jsonDecode(body);
    if (d is! Map) return (null, null);
    final user =
        (d['data'] is Map ? d['data']['user'] : null) ?? d['user'] ?? d;
    String? pick(Map m, List<String> keys) {
      for (final k in keys) {
        final v = m[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final uid =
        user is Map ? pick(user, ['id', 'user_id', 'userId', 'uid']) : null;
    String? tid;
    if (user is Map) {
      tid = pick(user,
          ['tenant_id', 'tenantId', 'active_tenant_id', 'activeTenantId']);
    }
    tid ??= d['active_tenant_id'] as String? ??
        d['tenant_id'] as String? ??
        d['tenantId'] as String?;
    return (uid, tid);
  } catch (_) {
    return (null, null);
  }
}

String? _firstSessionId(String body) {
  try {
    final d = jsonDecode(body);
    final list = d is List
        ? d
        : (d is Map
            ? (d['sessions'] ?? d['data'] ?? d['items'])
            : null);
    if (list is List && list.isNotEmpty && list.first is Map) {
      final m = list.first as Map;
      for (final k in ['id', 'sessionId', 'session_id']) {
        if (m[k] is String) return m[k] as String;
      }
    }
  } catch (_) {}
  return null;
}

Future<String?> _firebaseAuth(String apiKey, String email, String pw) async {
  print('-- Firebase sign-in --');
  final body =
      jsonEncode({'email': email, 'password': pw, 'returnSecureToken': true});
  final headers = {
    'content-type': 'application/json',
    'referer':
        Platform.environment['FIREBASE_REFERER'] ?? 'http://localhost:3000',
  };
  final si = await http.post(Uri.parse('$_firebaseSignIn?key=$apiKey'),
      headers: headers, body: body);
  if (si.statusCode == 200) {
    final t = (jsonDecode(si.body) as Map)['idToken'] as String?;
    if (t != null) {
      print('   [PASS] signIn -> idToken (${t.length} chars)');
      return t;
    }
  }
  print('   signIn ${si.statusCode}; trying signUp');
  final su = await http.post(Uri.parse('$_firebaseSignUp?key=$apiKey'),
      headers: headers, body: body);
  if (su.statusCode == 200) {
    final t = (jsonDecode(su.body) as Map)['idToken'] as String?;
    if (t != null) {
      print('   [PASS] signUp -> idToken (${t.length} chars)');
      return t;
    }
  }
  print('   [FAIL] Firebase auth: signIn=${si.statusCode} signUp=${su.statusCode}');
  return null;
}

String _get(Map<String, String> env, String k, String fallback) =>
    (env[k]?.trim().isNotEmpty ?? false) ? env[k]!.trim() : fallback;

String _excerpt(String body) {
  final t = body.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t.isEmpty) return '';
  return t.length > 240 ? '${t.substring(0, 240)}...' : t;
}

void _fatal(String msg) {
  stderr.writeln('FATAL: $msg');
  exit(2);
}

void _summary() {
  print('\n== Auth deep-dive summary ==');
  final pass = _results.where((r) => r.pass == true).length;
  final fail = _results.where((r) => r.pass == false).length;
  final skip = _results.where((r) => r.pass == null).length;
  for (final r in _results) {
    final tag = r.pass == null ? 'SKIP' : (r.pass! ? 'PASS' : 'FAIL');
    final st = r.status != null ? ' (${r.status})' : '';
    final nt = r.note != null ? '  — ${r.note}' : '';
    print('  [$tag] ${r.group.padRight(16)} ${r.label}$st$nt');
  }
  print('\n  $pass pass, $fail fail, $skip skip');
}
