// IntelliToggle deep-dive: exercises Aortem's feature-flag SaaS the way the
// Flutter client does — through the standard OpenFeature provider. Unlike the
// other deep-dives there is NO Firebase end-user login and NO hand-written HTTP:
// the published `openfeature_provider_intellitoggle` provider performs the
// OAuth2 client_credentials handshake (clientId + clientSecret + tenantId)
// internally, and we evaluate flags via the OpenFeature API.
//
// Create an OAuth client in the IntelliToggle dashboard, copy the clientId +
// clientSecret once, then:
//
//   set -a && source .env && set +a
//   dart run bin/intellitoggle_deepdive.dart
//
// Required env (put the secret only in your gitignored .env, never commit it):
//   INTELLITOGGLE_CLIENT_ID, INTELLITOGGLE_CLIENT_SECRET, INTELLITOGGLE_TENANT_ID
// Optional env:
//   INTELLITOGGLE_API_URL   (default https://api.intellitoggle.com)
//   INTELLITOGGLE_BOOL_FLAG / _STRING_FLAG / _INT_FLAG / _OBJECT_FLAG
//   INTELLITOGGLE_TARGET_USER (targeting key; default deepdive-cli)
//
// The clientSecret is confidential — for backends / CLIs / CI only. The Flutter
// client only carries it for a demo/sandbox tenant; production keeps
// client-credentials server-side.

import 'dart:async';
import 'dart:io';

import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

final List<_Result> _results = [];

void main(List<String> args) async {
  final env = Platform.environment;
  final clientId = env['INTELLITOGGLE_CLIENT_ID']?.trim();
  final clientSecret = env['INTELLITOGGLE_CLIENT_SECRET']?.trim();
  final tenantId = env['INTELLITOGGLE_TENANT_ID']?.trim();

  if (clientId == null || clientId.isEmpty) {
    _fatal('INTELLITOGGLE_CLIENT_ID not set (create an OAuth client in the '
        'IntelliToggle dashboard and export it).');
  }
  if (clientSecret == null || clientSecret.isEmpty) {
    _fatal('INTELLITOGGLE_CLIENT_SECRET not set (shown once at creation — '
        're-create the client if you lost it).');
  }
  if (tenantId == null || tenantId.isEmpty) {
    _fatal('INTELLITOGGLE_TENANT_ID not set.');
  }

  final apiUrl =
      _get(env, 'INTELLITOGGLE_API_URL', 'https://api.intellitoggle.com');
  final boolFlag = _get(env, 'INTELLITOGGLE_BOOL_FLAG', 'new-dashboard');
  final stringFlag = _get(env, 'INTELLITOGGLE_STRING_FLAG', 'hero-variant');
  final intFlag = _get(env, 'INTELLITOGGLE_INT_FLAG', 'max-items');
  final objectFlag = _get(env, 'INTELLITOGGLE_OBJECT_FLAG', 'theme-config');
  final targetUser = _get(env, 'INTELLITOGGLE_TARGET_USER', 'deepdive-cli');

  print('== IntelliToggle (OpenFeature) deep-dive ==');
  print('  api endpoint : $apiUrl');
  print('  client id    : $clientId');
  print('  tenant id    : $tenantId');
  print('  auth model   : OAuth2 client_credentials, NO Firebase user');
  print('  targeting    : userId=$targetUser\n');

  // 1. Register the provider. setProvider() runs initialize(), which exchanges
  //    client_credentials for a token and tests the connection — so reaching
  //    ProviderState.READY is the proof that OAuth succeeded. A bad secret /
  //    unreachable host lands in ERROR (fail-closed), never silently READY.
  final provider = IntelliToggleProvider(
    clientId: clientId,
    clientSecret: clientSecret,
    tenantId: tenantId,
    options: IntelliToggleOptions.production(baseUri: Uri.parse(apiUrl)),
  );

  await _check(
    'register provider (OAuth client_credentials -> READY)',
    'auth',
    () async {
      try {
        await OpenFeatureAPI().setProvider(provider);
      } catch (_) {
        // setProvider keeps the provider in ERROR state rather than throwing;
        // the state check below is the real assertion.
      }
      print('   provider=${provider.metadata.name} state=${provider.state.name}');
      return provider.state == ProviderState.READY;
    },
  );

  if (provider.state != ProviderState.READY) {
    print('\n[FAIL] provider not READY — cannot evaluate flags. Check the '
        'client_credentials and INTELLITOGGLE_API_URL.');
    _summary();
    exit(1);
  }

  // Score every flag against the signed-in identity (global targeting context).
  OpenFeatureAPI()
      .setGlobalContext(OpenFeatureEvaluationContext({'userId': targetUser}));

  // 2. Evaluate each flag type. A returned result (even a fail-safe default for
  //    an unknown flag) means the evaluation path works; only a thrown error
  //    fails. We print value + reason + variant + errorCode either way.
  await _check('getBooleanFlag("$boolFlag")', 'evaluate', () async {
    final r = await provider.getBooleanFlag(boolFlag, false);
    _dump(r);
    return true;
  });

  await _check('getStringFlag("$stringFlag")', 'evaluate', () async {
    final r = await provider.getStringFlag(stringFlag, 'control');
    _dump(r);
    return true;
  });

  await _check('getIntegerFlag("$intFlag")', 'evaluate', () async {
    final r = await provider.getIntegerFlag(intFlag, 0);
    _dump(r);
    return true;
  });

  await _check('getObjectFlag("$objectFlag")', 'evaluate', () async {
    final r = await provider.getObjectFlag(objectFlag, const {});
    _dump(r);
    return true;
  });

  // 3. Negative: a provider built with a deliberately wrong secret must NOT
  //    reach READY — proves auth fails closed (no fail-open).
  await _check('register with a bad secret (expect NOT ready)', 'negative',
      () async {
    final bad = IntelliToggleProvider(
      clientId: clientId,
      clientSecret: '$clientSecret-deepdive-invalid',
      tenantId: tenantId,
      options: IntelliToggleOptions.production(baseUri: Uri.parse(apiUrl)),
    );
    try {
      await OpenFeatureAPI().setProvider(bad);
    } catch (_) {/* expected */}
    print('   bad-secret provider state=${bad.state.name}');
    return bad.state != ProviderState.READY;
  });

  _summary();
  exit(_results.any((r) => r.pass == false) ? 1 : 0);
}

void _dump(FlagEvaluationResult res) {
  final parts = <String>[
    'value=${res.value}',
    'reason=${res.reason}',
    if (res.variant != null) 'variant=${res.variant}',
    if (res.errorCode != null) 'errorCode=${res.errorCode}',
  ];
  print('   ${parts.join('  ')}');
}

class _Result {
  _Result(this.group, this.label, this.pass, {this.note});
  final String group;
  final String label;
  final bool? pass;
  final String? note;
}

Future<void> _check(
  String label,
  String group,
  Future<bool> Function() run,
) async {
  print('-- $label --');
  try {
    final sw = Stopwatch()..start();
    final ok = await run().timeout(const Duration(seconds: 30));
    sw.stop();
    print('   ${ok ? '[PASS]' : '[FAIL]'} in ${sw.elapsedMilliseconds}ms');
    _results.add(_Result(group, label, ok));
  } on TimeoutException {
    print('   [FAIL] TIMEOUT');
    _results.add(_Result(group, label, false, note: 'timeout'));
  } catch (e) {
    print('   [FAIL] $e');
    _results.add(_Result(group, label, false, note: '$e'));
  }
}

String _get(Map<String, String> env, String k, String fallback) =>
    (env[k]?.trim().isNotEmpty ?? false) ? env[k]!.trim() : fallback;

Never _fatal(String msg) {
  stderr.writeln('FATAL: $msg');
  exit(2);
}

void _summary() {
  print('\n== IntelliToggle deep-dive summary ==');
  final pass = _results.where((r) => r.pass == true).length;
  final fail = _results.where((r) => r.pass == false).length;
  final skip = _results.where((r) => r.pass == null).length;
  for (final r in _results) {
    final tag = r.pass == null ? 'SKIP' : (r.pass! ? 'PASS' : 'FAIL');
    final nt = r.note != null ? '  — ${r.note}' : '';
    print('  [$tag] ${r.group.padRight(10)} ${r.label}$nt');
  }
  print('  ---- $pass passed, $fail failed, $skip skipped ----');
}
