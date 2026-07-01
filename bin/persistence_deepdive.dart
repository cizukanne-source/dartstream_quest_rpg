// Persistence deep-dive: exercises the full ds-persistence surface against the
// live backend and prints PASS / FAIL / SKIP per contract.
//
// Covers database connections, storage configs (+ validate), and logging
// (entries + configs). CRUD groups run create -> read -> update -> delete so
// they self-clean.
//
// Note: storage/config validate endpoints legitimately reject configs that lack
// real cloud credentials, so 400/422 there counts as "endpoint works" — only a
// 500 (or other unexpected status) is a FAIL.
//
//   set -a && source .env && set +a
//   dart run bin/persistence_deepdive.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _firebaseSignIn =
    'https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword';
const _firebaseSignUp =
    'https://identitytoolkit.googleapis.com/v1/accounts:signUp';

final List<_Result> _results = [];
final int _ts = DateTime.now().millisecondsSinceEpoch;

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
      _get(env, 'API_PERSISTENCE', 'https://dev-apipersistence.dartstream.io');
  final base = '$host/api/v1/persistence';

  print('== DartStream persistence deep-dive ==');
  print('  persistence host : $host');
  print('  user             : $email\n');

  final idToken = await _firebaseAuth(apiKey!, email!, password!);
  if (idToken == null) {
    _summary();
    exit(1);
  }

  String? tenantId, userId;
  await _step('POST $authHost/api/v1/auth/signup (bootstrap)', 'bootstrap', () {
    return http.post(Uri.parse('$authHost/api/v1/auth/signup'),
        headers: const {'content-type': 'application/json'},
        body: jsonEncode({'idToken': idToken}));
  }, allow: const [200, 201, 409], onBody: (b) {
    final ids = _extractIds(b);
    userId = ids.$1;
    tenantId = ids.$2;
    print('   tenantId=$tenantId userId=$userId');
  });
  if (tenantId == null) {
    _record('bootstrap', 'tenant context', false, note: 'no tenantId');
    _summary();
    exit(1);
  }

  final h = {
    'authorization': 'Bearer $idToken',
    'x-tenant-id': tenantId!,
    if (userId != null) 'x-user-id': userId!,
  };
  final jh = {...h, 'content-type': 'application/json'};

  // ---- database connections (CRUD) ----
  String? dbId;
  await _step('GET  /persistence/database/', 'database',
      () => http.get(Uri.parse('$base/database/'), headers: h));
  await _step('POST /persistence/database/', 'database', () {
    return http.post(Uri.parse('$base/database/'),
        headers: jh,
        body: jsonEncode({
          'name': 'deepdive_db_$_ts',
          'provider_type': 'postgres',
          'config': {'host': 'localhost', 'database': 'demo'},
        }));
  }, allow: const [200, 201], onBody: (b) => dbId = _id(b, ['id']));
  if (dbId != null) {
    await _step('GET  /persistence/database/<id>', 'database',
        () => http.get(Uri.parse('$base/database/$dbId'), headers: h));
    await _step('PUT  /persistence/database/<id>', 'database', () {
      return http.put(Uri.parse('$base/database/$dbId'),
          headers: jh, body: jsonEncode({'name': 'deepdive_db_${_ts}_upd'}));
    }, allow: const [200, 201, 204]);
    await _step('DELETE /persistence/database/<id>', 'database',
        () => http.delete(Uri.parse('$base/database/$dbId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('database', 'connection <id> sub-calls — no id from create');
  }

  // ---- storage configs (CRUD + validate) ----
  String? stId;
  final storageBody = {
    'bucket_name': 'deepdive-bucket-$_ts',
    'provider_type': 'gcs',
    'config': {
      'project_id': 'deepdive',
      // GCS config requires project_id + credentials (structural check only).
      'service_account_json': '{"type":"service_account","project_id":"deepdive"}',
    },
  };
  await _step('GET  /persistence/storage/configs', 'storage',
      () => http.get(Uri.parse('$base/storage/configs'), headers: h));
  await _step('POST /persistence/storage/configs', 'storage', () {
    return http.post(Uri.parse('$base/storage/configs'),
        headers: jh, body: jsonEncode(storageBody));
  }, allow: const [200, 201], onBody: (b) => stId = _id(b, ['id']));
  // validate (config-shape check; 400/422 is a legit rejection, not a failure)
  await _step('POST /persistence/storage/configs/validate', 'storage', () {
    return http.post(Uri.parse('$base/storage/configs/validate'),
        headers: jh, body: jsonEncode(storageBody));
  }, allow: const [200, 400, 422]);
  if (stId != null) {
    await _step('GET  /persistence/storage/configs/<id>', 'storage',
        () => http.get(Uri.parse('$base/storage/configs/$stId'), headers: h));
    await _step('PUT  /persistence/storage/configs/<id>', 'storage', () {
      // PUT replaces the config, so re-send the full valid GCS config.
      return http.put(Uri.parse('$base/storage/configs/$stId'),
          headers: jh,
          body: jsonEncode({
            ...storageBody,
            'config': {
              'project_id': 'deepdive2',
              'service_account_json':
                  '{"type":"service_account","project_id":"deepdive2"}',
            },
          }));
    }, allow: const [200, 201, 204]);
    await _step('POST /persistence/storage/configs/<id>/validate', 'storage',
        () => http.post(Uri.parse('$base/storage/configs/$stId/validate'),
            headers: jh, body: '{}'),
        allow: const [200, 400, 422]);
    await _step('DELETE /persistence/storage/configs/<id>', 'storage',
        () => http.delete(Uri.parse('$base/storage/configs/$stId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('storage', 'config <id> sub-calls — no id from create');
  }

  // ---- logging (entries + configs) ----
  await _step('POST /persistence/logging/entries', 'logging', () {
    return http.post(Uri.parse('$base/logging/entries'),
        headers: jh,
        body: jsonEncode({
          'level': 'info',
          'message': 'deepdive log entry $_ts',
          'source': 'persistence-deepdive',
          'context': {'run': _ts},
        }));
  }, allow: const [200, 201]);
  await _step('GET  /persistence/logging/entries', 'logging',
      () => http.get(Uri.parse('$base/logging/entries'), headers: h));

  String? logCfgId;
  await _step('GET  /persistence/logging/configs', 'logging',
      () => http.get(Uri.parse('$base/logging/configs'), headers: h));
  await _step('POST /persistence/logging/configs', 'logging', () {
    return http.post(Uri.parse('$base/logging/configs'),
        headers: jh,
        body: jsonEncode({
          'provider_type': 'gcpLogging',
          'config': {},
          'enabled': true,
        }));
  }, allow: const [200, 201], onBody: (b) => logCfgId = _id(b, ['id']));
  if (logCfgId != null) {
    await _step('DELETE /persistence/logging/configs/<id> (disable)', 'logging',
        () => http.delete(Uri.parse('$base/logging/configs/$logCfgId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('logging', 'config <id> disable — no id from create');
  }
  // clean up our log entries (delete-old; tolerate query-less call)
  await _step('DELETE /persistence/logging/entries (delete old)', 'logging',
      () => http.delete(Uri.parse('$base/logging/entries'), headers: h),
      allow: const [200, 204, 400]);

  _summary();
  exit(_results.any((r) => r.pass == false) ? 1 : 0);
}

// ---------------------------------------------------------------------------

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
void _skip(String group, String label) => _record(group, label, null);

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
    print('   ${ok ? '[PASS]' : '[FAIL]'} -> ${resp.statusCode} in ${sw.elapsedMilliseconds}ms');
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

String? _id(String body, List<String> keys) {
  try {
    final d = jsonDecode(body);
    Map? m = d is Map ? d : null;
    if (m != null && m['data'] is Map) m = m['data'] as Map;
    for (final k in keys) {
      final v = m?[k];
      if (v is String && v.isNotEmpty) return v;
    }
  } catch (_) {}
  return null;
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
    if (user is Map) tid = pick(user, ['tenant_id', 'tenantId', 'active_tenant_id']);
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
  final body = jsonEncode({'email': email, 'password': pw, 'returnSecureToken': true});
  final headers = {
    'content-type': 'application/json',
    'referer': Platform.environment['FIREBASE_REFERER'] ?? 'http://localhost:3000',
  };
  final si = await http.post(Uri.parse('$_firebaseSignIn?key=$apiKey'), headers: headers, body: body);
  if (si.statusCode == 200) {
    final t = (jsonDecode(si.body) as Map)['idToken'] as String?;
    if (t != null) {
      print('   [PASS] signIn -> idToken');
      return t;
    }
  }
  final su = await http.post(Uri.parse('$_firebaseSignUp?key=$apiKey'), headers: headers, body: body);
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
  print('\n== Persistence deep-dive summary ==');
  final pass = _results.where((r) => r.pass == true).length;
  final fail = _results.where((r) => r.pass == false).length;
  final skip = _results.where((r) => r.pass == null).length;
  for (final r in _results) {
    final tag = r.pass == null ? 'SKIP' : (r.pass! ? 'PASS' : 'FAIL');
    final st = r.status != null ? ' (${r.status})' : '';
    final nt = r.note != null ? '  — ${r.note}' : '';
    print('  [$tag] ${r.group.padRight(10)} ${r.label}$st$nt');
  }
  print('\n  $pass pass, $fail fail, $skip skip');
}
