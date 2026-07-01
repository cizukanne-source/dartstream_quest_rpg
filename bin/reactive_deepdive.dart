// Reactive deep-dive: exercises the full ds-reactive-dataflow surface against
// the live backend and prints PASS / FAIL / SKIP per contract.
//
// Covers events (log + subscriptions), streaming channels, notifications
// (configs + log), and lifecycle hooks. CRUD groups run create -> read ->
// update -> delete so they self-clean.
//
//   set -a && source .env && set +a
//   dart run bin/reactive_deepdive.dart

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
  final host = _get(env, 'API_REACTIVE', 'https://dev-apireactive.dartstream.io');
  final base = '$host/api/v1/reactive';

  print('== DartStream reactive deep-dive ==');
  print('  reactive host : $host');
  print('  user          : $email\n');

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

  // ---- events: log ----
  await _step('POST /reactive/events/log', 'events', () {
    return http.post(Uri.parse('$base/events/log'),
        headers: jh,
        body: jsonEncode({
          'event_type': 'deepdive.event',
          'payload': {'score': 1, 'source': 'reactive-deepdive'},
        }));
  }, allow: const [200, 201]);
  await _step('GET  /reactive/events/log', 'events',
      () => http.get(Uri.parse('$base/events/log'), headers: h));

  // ---- events: subscriptions (CRUD) ----
  String? subId;
  await _step('GET  /reactive/events/subscriptions', 'events-sub',
      () => http.get(Uri.parse('$base/events/subscriptions'), headers: h));
  await _step('POST /reactive/events/subscriptions', 'events-sub', () {
    return http.post(Uri.parse('$base/events/subscriptions'),
        headers: jh,
        body: jsonEncode({
          'event_type': 'deepdive.event',
          'subscription_name': 'deepdive_sub_$_ts',
          'config': {},
        }));
  }, allow: const [200, 201], onBody: (b) => subId = _id(b, ['id']));
  await _step('GET  /reactive/events/subscriptions/active', 'events-sub',
      () => http.get(Uri.parse('$base/events/subscriptions/active'), headers: h));
  if (subId != null) {
    await _step('GET  /reactive/events/subscriptions/<id>', 'events-sub',
        () => http.get(Uri.parse('$base/events/subscriptions/$subId'), headers: h));
    await _step('PUT  /reactive/events/subscriptions/<id>', 'events-sub', () {
      return http.put(Uri.parse('$base/events/subscriptions/$subId'),
          headers: jh, body: jsonEncode({'config': {'updated': true}}));
    }, allow: const [200, 201, 204]);
    await _step('DELETE /reactive/events/subscriptions/<id>', 'events-sub',
        () => http.delete(Uri.parse('$base/events/subscriptions/$subId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('events-sub', 'subscription <id> sub-calls — no id from create');
  }

  // ---- streaming channels (CRUD) ----
  String? chId;
  final chName = 'deepdive_ch_$_ts';
  await _step('GET  /reactive/streaming/channels', 'streaming',
      () => http.get(Uri.parse('$base/streaming/channels'), headers: h));
  await _step('GET  /reactive/streaming/channels/count', 'streaming',
      () => http.get(Uri.parse('$base/streaming/channels/count'), headers: h));
  await _step('POST /reactive/streaming/channels', 'streaming', () {
    return http.post(Uri.parse('$base/streaming/channels'),
        headers: jh, body: jsonEncode({'channel_name': chName}));
  }, allow: const [200, 201], onBody: (b) => chId = _id(b, ['id']));
  await _step('GET  /reactive/streaming/channels/name/<name>', 'streaming',
      () => http.get(Uri.parse('$base/streaming/channels/name/$chName'), headers: h));
  if (chId != null) {
    await _step('GET  /reactive/streaming/channels/<id>', 'streaming',
        () => http.get(Uri.parse('$base/streaming/channels/$chId'), headers: h));
    await _step('PUT  /reactive/streaming/channels/<id>', 'streaming', () {
      return http.put(Uri.parse('$base/streaming/channels/$chId'),
          headers: jh, body: jsonEncode({'channel_name': chName, 'enabled': true}));
    }, allow: const [200, 201, 204]);
    await _step('DELETE /reactive/streaming/channels/<id>', 'streaming',
        () => http.delete(Uri.parse('$base/streaming/channels/$chId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('streaming', 'channel <id> sub-calls — no id from create');
  }

  // ---- notifications (configs CRUD + log) ----
  String? ncId;
  await _step('GET  /reactive/notifications/configs', 'notifications',
      () => http.get(Uri.parse('$base/notifications/configs'), headers: h));
  await _step('POST /reactive/notifications/configs', 'notifications', () {
    return http.post(Uri.parse('$base/notifications/configs'),
        headers: jh,
        body: jsonEncode({
          'name': 'deepdive_notif_$_ts',
          'provider_type': 'webhook',
          'config': {'url': 'https://example.test/hook'},
          'enabled': true,
        }));
  }, allow: const [200, 201], onBody: (b) => ncId = _id(b, ['id']));
  await _step('GET  /reactive/notifications/configs/enabled', 'notifications',
      () => http.get(Uri.parse('$base/notifications/configs/enabled'), headers: h));
  if (ncId != null) {
    await _step('GET  /reactive/notifications/configs/<id>', 'notifications',
        () => http.get(Uri.parse('$base/notifications/configs/$ncId'), headers: h));
    await _step('PUT  /reactive/notifications/configs/<id>', 'notifications', () {
      return http.put(Uri.parse('$base/notifications/configs/$ncId'),
          headers: jh, body: jsonEncode({'enabled': false}));
    }, allow: const [200, 201, 204]);
    await _step('DELETE /reactive/notifications/configs/<id>', 'notifications',
        () => http.delete(Uri.parse('$base/notifications/configs/$ncId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('notifications', 'config <id> sub-calls — no id from create');
  }
  await _step('GET  /reactive/notifications/log', 'notifications',
      () => http.get(Uri.parse('$base/notifications/log'), headers: h));

  // ---- lifecycle hooks (CRUD) ----
  String? hookId;
  await _step('GET  /reactive/lifecycle/', 'lifecycle',
      () => http.get(Uri.parse('$base/lifecycle/'), headers: h));
  await _step('POST /reactive/lifecycle/', 'lifecycle', () {
    return http.post(Uri.parse('$base/lifecycle/'),
        headers: jh,
        body: jsonEncode({
          'hook_name': 'deepdive_hook_$_ts',
          'hook_type': 'custom',
          'config': {},
          'enabled': true,
        }));
  }, allow: const [200, 201], onBody: (b) => hookId = _id(b, ['id']));
  await _step('GET  /reactive/lifecycle/enabled', 'lifecycle',
      () => http.get(Uri.parse('$base/lifecycle/enabled'), headers: h));
  if (hookId != null) {
    await _step('GET  /reactive/lifecycle/<id>', 'lifecycle',
        () => http.get(Uri.parse('$base/lifecycle/$hookId'), headers: h));
    await _step('PUT  /reactive/lifecycle/<id>', 'lifecycle', () {
      return http.put(Uri.parse('$base/lifecycle/$hookId'),
          headers: jh, body: jsonEncode({'enabled': false}));
    }, allow: const [200, 201, 204]);
    await _step('DELETE /reactive/lifecycle/<id>', 'lifecycle',
        () => http.delete(Uri.parse('$base/lifecycle/$hookId'), headers: h),
        allow: const [200, 204]);
  } else {
    _skip('lifecycle', 'hook <id> sub-calls — no id from create');
  }

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
  print('\n== Reactive deep-dive summary ==');
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
