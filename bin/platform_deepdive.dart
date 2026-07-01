// Platform deep-dive: exercises the full ds-platform-services surface against
// the live backend and prints PASS / FAIL / SKIP per contract.
//
// Companion to auth_deepdive.dart. Covers feature-flags, projects (+
// environments, integrations, orchestration), api-keys, settings, team, and the
// middleware/discovery sub-services. CRUD paths are run as create -> read ->
// update -> delete so they self-clean and don't litter the live tenant.
//
//   set -a && source .env && set +a
//   dart run bin/platform_deepdive.dart
//
// Outward-facing ops (sending a team invitation email, changing a real member's
// role) are SKIPPED unless DEEPDIVE_DESTRUCTIVE=1.

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
  final destructive = env['DEEPDIVE_DESTRUCTIVE'] == '1';

  if (apiKey == null || apiKey.isEmpty) _fatal('FIREBASE_API_KEY not set.');
  if (email == null || email.isEmpty || password == null || password.isEmpty) {
    _fatal('TEST_EMAIL / TEST_PASSWORD not set.');
  }

  final authHost = _get(env, 'API_AUTH', 'https://dev-apiauth.dartstream.io');
  final host =
      _get(env, 'API_PLATFORM', 'https://dev-apiplatform.dartstream.io');
  final base = '$host/api/v1/platform';

  print('== DartStream platform deep-dive ==');
  print('  platform host : $host');
  print('  user          : $email');
  print('  destructive   : $destructive\n');

  final idToken = await _firebaseAuth(apiKey!, email!, password!);
  if (idToken == null) {
    _summary();
    exit(1);
  }

  // Bootstrap tenant via ds-auth signup.
  String? tenantId;
  String? userId;
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

  final h = {'authorization': 'Bearer $idToken', 'x-tenant-id': tenantId!};
  final jh = {...h, 'content-type': 'application/json'};

  // ---- feature flags (lifecycle) ----
  await _step('GET  /platform/feature-flags', 'feature-flags',
      () => http.get(Uri.parse('$base/feature-flags'), headers: h));

  String? flagId;
  await _step('POST /platform/feature-flags', 'feature-flags', () {
    return http.post(Uri.parse('$base/feature-flags'),
        headers: jh,
        body: jsonEncode({
          'key': 'deepdive_$_ts',
          'name': 'Deep Dive $_ts',
          'description': 'created by platform_deepdive',
        }));
  }, allow: const [200, 201], onBody: (b) => flagId = _id(b, ['id', 'flagId']));

  if (flagId != null) {
    await _step('GET  /platform/feature-flags/<id>', 'feature-flags',
        () => http.get(Uri.parse('$base/feature-flags/$flagId'), headers: h));
    await _step('PATCH /platform/feature-flags/<id>', 'feature-flags', () {
      return http.patch(Uri.parse('$base/feature-flags/$flagId'),
          headers: jh, body: jsonEncode({'description': 'updated'}));
    });
    await _step('DELETE /platform/feature-flags/<id>', 'feature-flags',
        () => http.delete(Uri.parse('$base/feature-flags/$flagId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('feature-flags', 'flag <id> sub-calls — create returned no id');
  }

  // ---- projects (lifecycle) ----
  await _step('GET  /platform/projects', 'projects',
      () => http.get(Uri.parse('$base/projects'), headers: h));

  String? projectId;
  await _step('POST /platform/projects', 'projects', () {
    return http.post(Uri.parse('$base/projects'),
        headers: jh,
        body: jsonEncode({'name': 'DeepDive $_ts', 'description': 'temp'}));
  }, allow: const [200, 201], onBody: (b) => projectId = _id(b, ['id', 'projectId']));

  if (projectId != null) {
    await _step('GET  /platform/projects/<id>', 'projects',
        () => http.get(Uri.parse('$base/projects/$projectId'), headers: h));
    await _step('PATCH /platform/projects/<id>', 'projects', () {
      return http.patch(Uri.parse('$base/projects/$projectId'),
          headers: jh, body: jsonEncode({'description': 'updated'}));
    });
    await _step('GET  /platform/projects/<id>/environments', 'projects-env',
        () => http.get(Uri.parse('$base/projects/$projectId/environments'),
            headers: h));
    await _step('POST /platform/projects/<id>/environments', 'projects-env', () {
      return http.post(Uri.parse('$base/projects/$projectId/environments'),
          headers: jh,
          body: jsonEncode({'name': 'Staging', 'key': 'staging_$_ts'}));
    }, allow: const [200, 201]);
    await _step('GET  /platform/projects/<id>/integrations', 'projects-int',
        () => http.get(Uri.parse('$base/projects/$projectId/integrations'),
            headers: h));
    await _step('PUT  /platform/projects/<id>/integrations', 'projects-int', () {
      return http.put(Uri.parse('$base/projects/$projectId/integrations'),
          headers: jh,
          body: jsonEncode(
              {'provider': 'firebase', 'enabled': true, 'config': {}}));
    });
    await _step(
        'GET  /platform/projects/<id>/orchestration/profile-provider',
        'projects-orch',
        () => http.get(
            Uri.parse(
                '$base/projects/$projectId/orchestration/profile-provider'),
            headers: h));
    await _step(
        'GET  /platform/projects/<id>/orchestration/providers/<domain>',
        'projects-orch',
        () => http.get(
            Uri.parse(
                '$base/projects/$projectId/orchestration/providers/profiles'),
            headers: h));
    await _step('DELETE /platform/projects/<id> (archive)', 'projects',
        () => http.delete(Uri.parse('$base/projects/$projectId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('projects', 'project <id> sub-calls — create returned no id');
  }

  // ---- api keys (lifecycle) ----
  await _step('GET  /platform/api-keys', 'api-keys',
      () => http.get(Uri.parse('$base/api-keys'), headers: h));
  String? keyId;
  await _step('POST /platform/api-keys', 'api-keys', () {
    return http.post(Uri.parse('$base/api-keys'),
        headers: jh,
        body: jsonEncode({
          'name': 'DeepDive Key $_ts',
          'scopes': ['read'],
          'environment': 'development',
        }));
  }, allow: const [200, 201], onBody: (b) => keyId = _id(b, ['id', 'keyId', 'clientId']));
  if (keyId != null) {
    await _step('DELETE /platform/api-keys/<id>', 'api-keys',
        () => http.delete(Uri.parse('$base/api-keys/$keyId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('api-keys', 'key <id> delete — create returned no id');
  }

  // ---- settings ----
  await _step('GET  /platform/settings/profile', 'settings',
      () => http.get(Uri.parse('$base/settings/profile'), headers: h));
  await _step('PATCH /platform/settings/profile', 'settings', () {
    return http.patch(Uri.parse('$base/settings/profile'),
        headers: jh, body: jsonEncode({'displayName': 'DeepDive Tenant'}));
  });
  await _step('GET  /platform/settings/notifications', 'settings',
      () => http.get(Uri.parse('$base/settings/notifications'), headers: h));
  await _step('PATCH /platform/settings/notifications', 'settings', () {
    return http.patch(Uri.parse('$base/settings/notifications'),
        headers: jh, body: jsonEncode({'emailNotifications': true}));
  });

  // ---- team ----
  await _step('GET  /platform/team/members', 'team',
      () => http.get(Uri.parse('$base/team/members'), headers: h));
  await _step('GET  /platform/team/invitations', 'team',
      () => http.get(Uri.parse('$base/team/invitations'), headers: h));
  if (destructive) {
    await _step('POST /platform/team/invitations (sends email)', 'team', () {
      return http.post(Uri.parse('$base/team/invitations'),
          headers: {...jh, 'origin': 'http://localhost:3000'},
          body: jsonEncode(
              {'email': 'deepdive+$_ts@dartstream.test', 'role': 'member'}));
    }, allow: const [200, 201]);
  } else {
    _skip('team', 'POST /team/invitations — sends real email; '
        'set DEEPDIVE_DESTRUCTIVE=1');
    _skip('team', 'PATCH /team/members/<id>/role — mutates a real member; '
        'set DEEPDIVE_DESTRUCTIVE=1');
  }

  // ---- middleware sub-service (lifecycle) ----
  await _miniCrud('middleware', '$base/middleware', h, jh,
      createBody: {'name': 'DeepDive MW $_ts', 'middleware_type': 'custom'});

  // ---- discovery/extensions sub-service (lifecycle) ----
  await _miniCrud('discovery', '$base/discovery', h, jh,
      createBody: {'name': 'DeepDive Ext $_ts', 'extension_type': 'thirdParty'});

  _summary();
  exit(_results.any((r) => r.pass == false) ? 1 : 0);
}

/// list -> create -> get -> update -> delete against a CRUD sub-service.
Future<void> _miniCrud(
  String group,
  String url,
  Map<String, String> h,
  Map<String, String> jh, {
  required Map<String, dynamic> createBody,
}) async {
  await _step('GET  ${_short(url)}/', group,
      () => http.get(Uri.parse('$url/'), headers: h));
  String? id;
  await _step('POST ${_short(url)}/', group, () {
    return http.post(Uri.parse('$url/'), headers: jh, body: jsonEncode(createBody));
  }, allow: const [200, 201], onBody: (b) => id = _id(b, ['id']));
  if (id == null) {
    _skip(group, '<id> sub-calls — create returned no id');
    return;
  }
  await _step('GET  ${_short(url)}/<id>', group,
      () => http.get(Uri.parse('$url/$id'), headers: h));
  await _step('PUT  ${_short(url)}/<id>', group, () {
    return http.put(Uri.parse('$url/$id'),
        headers: jh, body: jsonEncode({...createBody, 'enabled': true}));
  }, allow: const [200, 201, 204]);
  await _step('DELETE ${_short(url)}/<id>', group,
      () => http.delete(Uri.parse('$url/$id'), headers: h),
      allow: const [200, 204]);
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

String _short(String url) => url.replaceFirst(RegExp(r'^https?://[^/]+'), '');

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
  print('\n== Platform deep-dive summary ==');
  final pass = _results.where((r) => r.pass == true).length;
  final fail = _results.where((r) => r.pass == false).length;
  final skip = _results.where((r) => r.pass == null).length;
  for (final r in _results) {
    final tag = r.pass == null ? 'SKIP' : (r.pass! ? 'PASS' : 'FAIL');
    final st = r.status != null ? ' (${r.status})' : '';
    final nt = r.note != null ? '  — ${r.note}' : '';
    print('  [$tag] ${r.group.padRight(14)} ${r.label}$st$nt');
  }
  print('\n  $pass pass, $fail fail, $skip skip');
}
