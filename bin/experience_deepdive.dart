// Experience deep-dive: exercises the full ds-experience-orchestration surface
// against the live backend and prints PASS / FAIL / SKIP per contract.
//
// Companion to auth_deepdive.dart / platform_deepdive.dart. Covers profiles,
// cloud-save, inventory, sessions, and connectors — including the per-module
// /capabilities endpoints the smoke CLI doesn't touch.
//
//   set -a && source .env && set +a
//   dart run bin/experience_deepdive.dart

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

  if (apiKey == null || apiKey.isEmpty) _fatal('FIREBASE_API_KEY not set.');
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    _fatal('TEST_EMAIL / TEST_PASSWORD not set.');
  }

  final authHost = _get(env, 'API_AUTH', 'https://dev-apiauth.dartstream.io');
  final host =
      _get(env, 'API_EXPERIENCE', 'https://dev-apiexperience.dartstream.io');
  final base = '$host/api/v1/experience';

  print('== DartStream experience deep-dive ==');
  print('  experience host : $host');
  print('  user            : $email\n');

  final idToken = await _firebaseAuth(apiKey!, email!, password!);
  if (idToken == null) {
    _summary();
    exit(1);
  }

  String? userId;
  String? tenantId;
  await _step('POST $authHost/api/v1/auth/signup (bootstrap)', 'bootstrap', () {
    return http.post(Uri.parse('$authHost/api/v1/auth/signup'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'idToken': idToken}));
  }, allow: const [200, 201, 409], onBody: (b) {
    final ids = _extractIds(b);
    userId = ids.$1;
    tenantId = ids.$2;
    print('   userId=$userId tenantId=$tenantId');
  });
  if (userId == null || tenantId == null) {
    _record('bootstrap', 'user/tenant context', false, note: 'no ids');
    _summary();
    exit(1);
  }

  final h = {
    'authorization': 'Bearer $idToken',
    'x-tenant-id': tenantId!,
    'x-user-id': userId!,
  };
  final jh = {...h, 'content-type': 'application/json'};
  final q = 'userId=${Uri.encodeQueryComponent(userId!)}'
      '&tenantId=${Uri.encodeQueryComponent(tenantId!)}';

  // ---- profiles ----
  await _step('GET  /experience/profiles/capabilities', 'profiles',
      () => http.get(Uri.parse('$base/profiles/capabilities?$q'), headers: h));
  await _step('GET  /experience/profiles/me', 'profiles',
      () => http.get(Uri.parse('$base/profiles/me?$q'), headers: h));

  // ---- cloud-save ----
  await _step('GET  /experience/cloud-save/capabilities', 'cloud-save',
      () => http.get(Uri.parse('$base/cloud-save/capabilities?$q'), headers: h));
  await _step('POST /experience/cloud-save/snapshot', 'cloud-save', () {
    return http.post(
      Uri.parse('$base/cloud-save/snapshot?$q&slotKey=deepdive'),
      headers: jh,
      body: jsonEncode({
        'payload': {
          'score': 7,
          'savedAt': DateTime.now().toUtc().toIso8601String(),
        },
      }),
    );
  }, allow: const [200, 201]);
  await _step('GET  /experience/cloud-save/snapshot', 'cloud-save',
      () => http.get(
          Uri.parse('$base/cloud-save/snapshot?$q&slotKey=deepdive'),
          headers: h));

  // ---- cloud-save: project/environment scoping (the SaaS gaming-sample delta) ----
  // The experience modules now key storage by tenant/project/environment (the
  // Unity/Flame samples pass projectId + environmentId). Prove the contract
  // independently: a snapshot saved under one scope must read back within that
  // scope (and survive a fresh read) but must NOT leak into a different
  // environment or the legacy unscoped (default-app/development) slot.
  await _scopingChecks(base, h, jh, q);

  // ---- inventory ----
  await _step('GET  /experience/inventory/capabilities', 'inventory',
      () => http.get(Uri.parse('$base/inventory/capabilities?$q'), headers: h));
  await _step('GET  /experience/inventory/items', 'inventory',
      () => http.get(Uri.parse('$base/inventory/items?$q'), headers: h));

  // ---- sessions ----
  await _step('GET  /experience/sessions/capabilities', 'sessions',
      () => http.get(Uri.parse('$base/sessions/capabilities?$q'), headers: h));
  await _step('GET  /experience/sessions/active', 'sessions',
      () => http.get(Uri.parse('$base/sessions/active?$q'), headers: h));

  // ---- connectors ----
  await _step('GET  /experience/connectors/', 'connectors',
      () => http.get(Uri.parse('$base/connectors/?$q'), headers: h));

  _summary();
  exit(_results.any((r) => r.pass == false) ? 1 : 0);
}

// ---------------------------------------------------------------------------

/// Exercises project/environment scoping on cloud-save. Saves a uniquely-tagged
/// snapshot under one scope, then asserts isolation across environment + the
/// legacy unscoped default, plus durability on a fresh re-read.
Future<void> _scopingChecks(
  String base,
  Map<String, String> h,
  Map<String, String> jh,
  String q,
) async {
  const group = 'scoping';
  const slot = 'scope-probe';
  final nonce = 'dd-${DateTime.now().microsecondsSinceEpoch}';

  String url(String? projectId, String? environmentId) {
    final b = StringBuffer('$base/cloud-save/snapshot?$q&slotKey=$slot');
    if (projectId != null) {
      b.write('&projectId=${Uri.encodeQueryComponent(projectId)}');
    }
    if (environmentId != null) {
      b.write('&environmentId=${Uri.encodeQueryComponent(environmentId)}');
    }
    return b.toString();
  }

  // Save the marker under scope A = (default-app / production).
  await _step('POST cloud-save snapshot @ default-app/production', group, () {
    return http.post(Uri.parse(url('default-app', 'production')),
        headers: jh, body: jsonEncode({'payload': {'marker': nonce}}));
  }, allow: const [200, 201]);

  // (1) same scope -> marker present.
  await _assertBody(
    'GET cloud-save @ default-app/production (same scope -> present)',
    group,
    () => http.get(Uri.parse(url('default-app', 'production')), headers: h),
    (status, body) => status == 200 && _payloadMarker(body) == nonce,
    expect: 'marker=$nonce',
  );

  // (2) different environment -> isolated (absent, or 404).
  await _assertBody(
    'GET cloud-save @ default-app/development (other env -> isolated)',
    group,
    () => http.get(Uri.parse(url('default-app', 'development')), headers: h),
    (status, body) => status == 404 || _payloadMarker(body) != nonce,
    expect: 'marker!=$nonce',
  );

  // (3) legacy unscoped read (defaults to default-app/development) -> isolated.
  await _assertBody(
    'GET cloud-save @ unscoped (legacy default -> isolated)',
    group,
    () => http.get(Uri.parse(url(null, null)), headers: h),
    (status, body) => status == 404 || _payloadMarker(body) != nonce,
    expect: 'marker!=$nonce',
  );

  // (4) durability: a fresh read under scope A still returns the marker.
  await _assertBody(
    'GET cloud-save @ default-app/production (re-read -> durable)',
    group,
    () => http.get(Uri.parse(url('default-app', 'production')), headers: h),
    (status, body) => status == 200 && _payloadMarker(body) == nonce,
    expect: 'marker=$nonce (durable)',
  );
}

/// Pulls `payload.marker` out of a cloud-save body, tolerating the
/// `{snapshot:{payload:{...}}}` envelope. Returns null when absent.
String? _payloadMarker(String body) {
  try {
    final d = jsonDecode(body);
    if (d is! Map) return null;
    final snap = d['snapshot'];
    final payload = (snap is Map ? snap['payload'] : null) ?? d['payload'];
    if (payload is Map && payload['marker'] is String) {
      return payload['marker'] as String;
    }
    return null;
  } catch (_) {
    return null;
  }
}

/// Like [_step] but asserts on the response body via [check] (status, body),
/// for contract checks that depend on content rather than status alone.
Future<void> _assertBody(
  String label,
  String group,
  Future<http.Response> Function() send,
  bool Function(int status, String body) check, {
  String? expect,
}) async {
  print('-- $label --');
  try {
    final resp = await send().timeout(const Duration(seconds: 25));
    final ok = check(resp.statusCode, resp.body);
    print('   ${ok ? '[PASS]' : '[FAIL]'} -> ${resp.statusCode}'
        '${expect != null ? '  (expected $expect)' : ''}');
    final ex = _excerpt(resp.body);
    if (ex.isNotEmpty) print('   body: $ex');
    _record(group, label, ok, status: resp.statusCode);
  } on TimeoutException {
    print('   [FAIL] TIMEOUT');
    _record(group, label, false, note: 'timeout');
  } catch (e) {
    print('   [FAIL] $e');
    _record(group, label, false, note: '$e');
  }
}

class _Result {
  _Result(this.group, this.label, this.pass, {this.status, this.note});
  final String group;
  final String label;
  final bool? pass;
  final int? status;
  final String? note;
}

void _record(String group, String label, bool? pass, {int? status, String? note}) =>
    _results.add(_Result(group, label, pass, status: status, note: note));

Future<void> _step(
  String label,
  String group,
  Future<http.Response> Function() send, {
  List<int> allow = const [200, 201, 204],
  void Function(String body)? onBody,
}) async {
  print('-- $label --');
  try {
    final sw = Stopwatch()..start();
    final resp = await send().timeout(const Duration(seconds: 25));
    sw.stop();
    final ok = allow.contains(resp.statusCode);
    final ex = _excerpt(resp.body);
    print('   ${ok ? '[PASS]' : '[FAIL]'} -> ${resp.statusCode} '
        'in ${sw.elapsedMilliseconds}ms');
    if (ex.isNotEmpty) print('   body: $ex');
    _record(group, label, ok, status: resp.statusCode);
    if (ok) onBody?.call(resp.body);
  } on TimeoutException {
    print('   [FAIL] TIMEOUT');
    _record(group, label, false, note: 'timeout');
  } catch (e) {
    print('   [FAIL] $e');
    _record(group, label, false, note: '$e');
  }
}

(String?, String?) _extractIds(String body) {
  try {
    final d = jsonDecode(body);
    if (d is! Map) return (null, null);
    final user = (d['data'] is Map ? d['data']['user'] : null) ?? d['user'] ?? d;
    String? pick(Map m, List<String> ks) {
      for (final k in ks) {
        final v = m[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final uid = user is Map ? pick(user, ['id', 'user_id', 'userId', 'uid']) : null;
    String? tid;
    if (user is Map) {
      tid = pick(user, ['tenant_id', 'tenantId', 'active_tenant_id']);
    }
    tid ??= d['active_tenant_id'] as String? ??
        d['tenant_id'] as String? ??
        d['tenantId'] as String?;
    return (uid, tid);
  } catch (_) {
    return (null, null);
  }
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
      print('   [PASS] signIn -> idToken');
      return t;
    }
  }
  final su = await http.post(Uri.parse('$_firebaseSignUp?key=$apiKey'),
      headers: headers, body: body);
  if (su.statusCode == 200) {
    final t = (jsonDecode(su.body) as Map)['idToken'] as String?;
    if (t != null) {
      print('   [PASS] signUp -> idToken');
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
  print('\n== Experience deep-dive summary ==');
  final pass = _results.where((r) => r.pass == true).length;
  final fail = _results.where((r) => r.pass == false).length;
  final skip = _results.where((r) => r.pass == null).length;
  for (final r in _results) {
    final tag = r.pass == null ? 'SKIP' : (r.pass! ? 'PASS' : 'FAIL');
    final st = r.status != null ? ' (${r.status})' : '';
    final nt = r.note != null ? '  — ${r.note}' : '';
    print('  [$tag] ${r.group.padRight(12)} ${r.label}$st$nt');
  }
  print('\n  $pass pass, $fail fail, $skip skip');
}
