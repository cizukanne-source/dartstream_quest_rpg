import 'dart:convert';
import 'dart:io';

class _Env {
  _Env._(this.values);

  factory _Env.load() {
    final values = <String, String>{};
    final envFile = File('.env');
    if (envFile.existsSync()) {
      for (final rawLine in envFile.readAsLinesSync()) {
        final line = rawLine.trim();
        if (line.isEmpty || line.startsWith('#')) continue;
        final separator = line.indexOf('=');
        if (separator <= 0) continue;
        final key = line.substring(0, separator).trim();
        var value = line.substring(separator + 1).trim();
        if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
          value = value.substring(1, value.length - 1);
        } else if (value.startsWith("'") && value.endsWith("'") && value.length >= 2) {
          value = value.substring(1, value.length - 1);
        } else {
          final commentIndex = _inlineCommentIndex(value);
          if (commentIndex != -1) {
            value = value.substring(0, commentIndex).trimRight();
          }
        }
        if (key.isNotEmpty) {
          values[key] = value;
        }
      }
    }
    values.addAll(Platform.environment);
    return _Env._(values);
  }

  final Map<String, String> values;

  String require(String key) {
    final value = values[key]?.trim() ?? '';
    if (value.isEmpty) {
      throw StateError('Missing $key. Add it to .env or set it in cmd before running.');
    }
    return value;
  }

  String optional(String key, {String? fallback}) {
    final value = values[key]?.trim();
    if (value == null || value.isEmpty) return fallback ?? '';
    return value;
  }
}

class _TokenResult {
  _TokenResult({
    required this.accessToken,
    required this.tokenType,
    required this.expiresIn,
  });

  final String accessToken;
  final String tokenType;
  final int? expiresIn;

  factory _TokenResult.fromJson(Map<String, dynamic> json) {
    final accessToken = _firstString(json, const [
      'access_token',
      'accessToken',
      'token',
      'jwt',
    ]);
    if (accessToken == null || accessToken.isEmpty) {
      throw FormatException('Token response did not include an access token: $json');
    }
    return _TokenResult(
      accessToken: accessToken,
      tokenType: _firstString(json, const ['token_type', 'tokenType']) ?? 'Bearer',
      expiresIn: _firstInt(json, const ['expires_in', 'expiresIn']),
    );
  }
}

Future<void> main() async {
  final env = _Env.load();
  final clientId = env.require('OAUTH2_CLIENT_ID');
  final clientSecret = env.require('OAUTH2_CLIENT_SECRET');
  final billingBaseUrl = env.optional(
    'API_BILLING',
    fallback: 'https://apibilling.dartstream.io',
  );
  final requestedScope = env.optional('OAUTH2_SCOPE');

  final token = await _mintToken(
    billingBaseUrl: billingBaseUrl,
    clientId: clientId,
    clientSecret: clientSecret,
    scope: requestedScope.isEmpty ? null : requestedScope,
  );

  final claims = _decodeJwtClaims(token.accessToken);

  stdout.writeln('OAuth2 token minted successfully');
  stdout.writeln('  token_type: ${token.tokenType}');
  if (token.expiresIn != null) {
    stdout.writeln('  expires_in: ${token.expiresIn}s');
  }
  stdout.writeln('  tenant: ${_claimAsString(claims, const ['tenant', 'tenant_id', 'tenantId', 'tid']) ?? '(missing)'}');
  stdout.writeln('  scope: ${_claimAsString(claims, const ['scope']) ?? '(missing)'}');
  stdout.writeln('  subject: ${_claimAsString(claims, const ['sub', 'subject']) ?? '(missing)'}');
  stdout.writeln();

  final probes = <_Probe>[
    _Probe(
      label: 'persistence/database/providers',
      uri: Uri.parse(billingBaseUrl).replace(path: '/api/v1/persistence/database/providers'),
    ),
    _Probe(
      label: 'reactive/streaming/channels',
      uri: Uri.parse(billingBaseUrl).replace(
        path: '/api/v1/reactive/streaming/channels',
      ),
    ),
    _Probe(
      label: 'experience/connectors',
      uri: Uri.parse(billingBaseUrl).replace(path: '/api/v1/experience/connectors'),
    ),
    _Probe(
      label: 'platform/projects',
      uri: Uri.parse(billingBaseUrl).replace(path: '/api/v1/platform/projects'),
    ),
  ];

  final results = <_ProbeResult>[];
  for (final probe in probes) {
    results.add(await _probeEndpoint(probe, token.accessToken));
  }

  stdout.writeln('Endpoint checks');
  for (final result in results) {
    stdout.writeln(
      '${result.pass ? 'PASS' : 'FAIL'}  '
      '${result.label.padRight(30)}  '
      '${result.summary}',
    );
  }
}

Future<_TokenResult> _mintToken({
  required String billingBaseUrl,
  required String clientId,
  required String clientSecret,
  String? scope,
}) async {
  final uri = Uri.parse(billingBaseUrl).replace(path: '/api/v1/oauth2/token');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    final basic = base64Encode(utf8.encode('$clientId:$clientSecret'));
    request.headers.set(HttpHeaders.authorizationHeader, 'Basic $basic');
    request.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
    final form = <String, String>{
      'grant_type': 'client_credentials',
      if (scope != null && scope.trim().isNotEmpty) 'scope': scope.trim(),
    };
    request.write(Uri(queryParameters: form).query);

    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Token request failed with ${response.statusCode}: $body',
        uri: uri,
      );
    }
    final json = _decodeJson(body, context: 'OAuth2 token response');
    return _TokenResult.fromJson(json);
  } finally {
    client.close(force: true);
  }
}

Future<_ProbeResult> _probeEndpoint(_Probe probe, String bearerToken) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(probe.uri);
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $bearerToken');
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final pass = response.statusCode >= 200 && response.statusCode < 300;
    final summary = pass
        ? _summarizePayload(body)
        : 'HTTP ${response.statusCode}: ${body.isEmpty ? '(empty body)' : body}';
    return _ProbeResult(label: probe.label, pass: pass, summary: summary);
  } finally {
    client.close(force: true);
  }
}

String _summarizePayload(String body) {
  if (body.trim().isEmpty) return 'empty response';
  try {
    final decoded = jsonDecode(body);
    if (decoded is List) {
      return 'list(${decoded.length})';
    }
    if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      return 'keys=${map.keys.take(5).join(', ')}';
    }
    return decoded.toString();
  } catch (_) {
    return body.length > 120 ? '${body.substring(0, 117)}...' : body;
  }
}

Map<String, dynamic> _decodeJson(String body, {required String context}) {
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw FormatException('$context did not return a JSON object: $body');
  } catch (error) {
    throw FormatException('$context was not valid JSON: $body', error);
  }
}

Map<String, dynamic> _decodeJwtClaims(String token) {
  final parts = token.split('.');
  if (parts.length < 2) {
    throw FormatException('Expected a JWT access token but got: $token');
  }
  final payload = parts[1];
  final normalized = payload.padRight(payload.length + ((4 - payload.length % 4) % 4), '=');
  final decoded = utf8.decode(base64Url.decode(normalized));
  final json = jsonDecode(decoded);
  if (json is Map<String, dynamic>) return json;
  if (json is Map) return Map<String, dynamic>.from(json);
  throw FormatException('JWT payload was not a JSON object: $decoded');
}

String? _claimAsString(Map<String, dynamic> claims, List<String> keys) {
  for (final key in keys) {
    final value = claims[key];
    if (value is String && value.isNotEmpty) return value;
    if (value != null) return value.toString();
  }
  return null;
}

int? _firstInt(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is int) return value;
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
  }
  return null;
}

String? _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is String && value.isNotEmpty) return value;
    if (value != null) return value.toString();
  }
  return null;
}

int _inlineCommentIndex(String value) {
  for (var i = 0; i < value.length; i++) {
    if (value[i] == '#') {
      if (i == 0) return 0;
      if (value[i - 1].trim().isEmpty) {
        return i - 1;
      }
    }
  }
  return -1;
}

class _Probe {
  const _Probe({
    required this.label,
    required this.uri,
  });

  final String label;
  final Uri uri;
}

class _ProbeResult {
  const _ProbeResult({
    required this.label,
    required this.pass,
    required this.summary,
  });

  final String label;
  final bool pass;
  final String summary;
}
