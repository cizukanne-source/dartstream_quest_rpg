// OAuth2 deep-dive: exercises the machine-to-machine (server-to-server) path —
// the "pay -> create an Application -> mint credentials -> connect your real
// project" flow that DartStream now ships (GitLab #96). Unlike the other
// deep-dives this uses NO Firebase end-user login: it authenticates purely with
// an OAuth2 client_credentials grant, exchanging a clientId + clientSecret for a
// DartStream-signed Bearer JWT and calling the live services with it.
//
// Create the client in the dashboard (Settings -> Applications -> Create OAuth2
// Client), copy the clientId + clientSecret once, then:
//
//   set -a && source .env && set +a
//   dart run bin/oauth2_deepdive.dart
//
// Required env (put the secret only in your gitignored .env, never commit it):
//   OAUTH2_CLIENT_ID, OAUTH2_CLIENT_SECRET
// Optional env:
//   API_BILLING  (token endpoint host; default https://dev-apibilling.dartstream.io)
//   OAUTH2_SCOPE (space-separated subset of the client's scopes; default = all)
//
// The clientSecret is confidential — for backends / CLIs / CI / server-rendered
// apps only. NEVER embed it in a browser or Flutter bundle; those keep the
// Firebase end-user login path (see the other deep-dives).

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

final List<_Result> _results = [];

void main(List<String> args) async {
  final env = Platform.environment;
  final clientId = env['OAUTH2_CLIENT_ID']?.trim();
  final clientSecret = env['OAUTH2_CLIENT_SECRET']?.trim();

  if (clientId == null || clientId.isEmpty) {
    _fatal('OAUTH2_CLIENT_ID not set (create a client in Settings -> '
        'Applications and export it).');
  }
  if (clientSecret == null || clientSecret.isEmpty) {
    _fatal('OAUTH2_CLIENT_SECRET not set (shown once at creation — re-create '
        'the client if you lost it).');
  }

  final billing =
      _get(env, 'API_BILLING', 'https://dev-apibilling.dartstream.io');
  final platform =
      _get(env, 'API_PLATFORM', 'https://dev-apiplatform.dartstream.io');
  final experience =
      _get(env, 'API_EXPERIENCE', 'https://dev-apiexperience.dartstream.io');
  final reactive =
      _get(env, 'API_REACTIVE', 'https://dev-apireactive.dartstream.io');
  final persistence =
      _get(env, 'API_PERSISTENCE', 'https://dev-apipersistence.dartstream.io');
  final scope = env['OAUTH2_SCOPE']?.trim();
  final tokenUrl = '$billing/api/v1/oauth2/token';

  print('== DartStream OAuth2 (client_credentials) deep-dive ==');
  print('  token endpoint : $tokenUrl');
  print('  client id      : $clientId');
  print('  scope          : ${scope == null || scope.isEmpty ? '(all client scopes)' : scope}');
  print('  auth model     : machine-to-machine, NO Firebase user\n');

  // 1. Exchange client_credentials for a Bearer JWT (RFC 6749 §4.4).
  //    Credentials go over HTTP Basic, exactly as a real backend would send them.
  final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
  String? accessToken;
  await _step('POST /api/v1/oauth2/token (grant_type=client_credentials)',
      'token', () {
    final body = {'grant_type': 'client_credentials'};
    if (scope != null && scope.isNotEmpty) body['scope'] = scope;
    return http.post(
      Uri.parse(tokenUrl),
      headers: {
        'authorization': 'Basic $basic',
        'content-type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
  }, onBody: (b) {
    final m = _tryJson(b);
    accessToken = m?['access_token'] as String?;
    final expiresIn = m?['expires_in'];
    final grantedScope = m?['scope'];
    print('   token_type=${m?['token_type']} expires_in=$expiresIn');
    print('   granted scope: $grantedScope');
    _dumpClaims(accessToken);
  });

  if (accessToken == null) {
    print('\n[FAIL] no access_token — cannot exercise services.');
    _summary();
    exit(1);
  }

  // From here on every call carries ONLY the OAuth2 Bearer token. No Firebase
  // ID token, no X-Tenant-ID header — the tenant rides in the JWT claims.
  final h = {'authorization': 'Bearer $accessToken'};

  // 2. Read against each live service (read scope honoured).
  await _step('GET  $platform/api/v1/platform/feature-flags', 'platform',
      () => http.get(Uri.parse('$platform/api/v1/platform/feature-flags'),
          headers: h));

  await _step('GET  $platform/api/v1/platform/projects', 'platform',
      () => http.get(Uri.parse('$platform/api/v1/platform/projects'),
          headers: h));

  await _step(
      'GET  $experience/api/v1/experience/profiles/capabilities', 'experience',
      () => http.get(
          Uri.parse('$experience/api/v1/experience/profiles/capabilities'),
          headers: h));

  await _step(
      'GET  $reactive/api/v1/reactive/events/subscriptions', 'reactive',
      () => http.get(
          Uri.parse('$reactive/api/v1/reactive/events/subscriptions'),
          headers: h));

  await _step('GET  $persistence/api/v1/persistence/database/', 'persistence',
      () => http.get(Uri.parse('$persistence/api/v1/persistence/database/'),
          headers: h));

  // 3. Negative: a clearly-bogus token must be rejected (no silent fail-open).
  await _step('GET  feature-flags with a garbage Bearer (expect 401/403)',
      'negative',
      () => http.get(Uri.parse('$platform/api/v1/platform/feature-flags'),
          headers: {'authorization': 'Bearer not-a-real-token'}),
      allow: const [401, 403]);

  _summary();
  exit(_results.any((r) => r.pass == false) ? 1 : 0);
}

// Decode (without verifying) the JWT payload so the run shows the tenant +
// scopes the token carries — handy evidence that auth is machine-derived.
void _dumpClaims(String? jwt) {
  if (jwt == null) return;
  final parts = jwt.split('.');
  if (parts.length != 3) return;
  try {
    var p = parts[1].replaceAll('-', '+').replaceAll('_', '/');
    p = p.padRight((p.length + 3) & ~3, '=');
    final claims = jsonDecode(utf8.decode(base64Decode(p))) as Map;
    print('   claims: iss=${claims['iss']} aud=${claims['aud']} '
        'tenant=${claims['tenantId'] ?? claims['tenant_id']} '
        'sub=${claims['sub']}');
    if (claims['scope'] != null || claims['scopes'] != null) {
      print('   claim scopes: ${claims['scope'] ?? claims['scopes']}');
    }
  } catch (_) {}
}

Map<String, dynamic>? _tryJson(String body) {
  try {
    final d = jsonDecode(body);
    return d is Map<String, dynamic> ? d : null;
  } catch (_) {
    return null;
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
  print('\n== OAuth2 deep-dive summary ==');
  final pass = _results.where((r) => r.pass == true).length;
  final fail = _results.where((r) => r.pass == false).length;
  final skip = _results.where((r) => r.pass == null).length;
  for (final r in _results) {
    final tag = r.pass == null ? 'SKIP' : (r.pass! ? 'PASS' : 'FAIL');
    final st = r.status != null ? ' (${r.status})' : '';
    final nt = r.note != null ? '  — ${r.note}' : '';
    print('  [$tag] ${r.group.padRight(12)} ${r.label}$st$nt');
  }
  print('  ---- $pass passed, $fail failed, $skip skipped ----');
}
