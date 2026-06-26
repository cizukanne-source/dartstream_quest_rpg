import 'dart:convert';

class OAuth2TokenVerification {
  const OAuth2TokenVerification({
    required this.header,
    required this.claims,
    required this.issues,
    required this.now,
  });

  final Map<String, dynamic> header;
  final Map<String, dynamic> claims;
  final List<String> issues;
  final DateTime now;

  bool get passed => issues.isEmpty;

  String? get algorithm => _stringClaim(header, const ['alg']);

  String? get issuer => _stringClaim(claims, const ['iss']);

  String? get subject => _stringClaim(claims, const ['sub', 'subject']);

  DateTime? get expiresAt => _dateTimeClaim(claims, const ['exp']);

  DateTime? get issuedAt => _dateTimeClaim(claims, const ['iat']);

  DateTime? get notBefore => _dateTimeClaim(claims, const ['nbf']);

  String summary() {
    final parts = <String>[
      'alg=${algorithm ?? "(missing)"}',
      'iss=${issuer ?? "(missing)"}',
      'sub=${subject ?? "(missing)"}',
      'exp=${expiresAt?.toIso8601String() ?? "(missing)"}',
    ];
    return parts.join(', ');
  }
}

OAuth2TokenVerification inspectJwtAccessToken(
  String token, {
  DateTime? now,
  String? expectedIssuer,
}) {
  final currentTime = now ?? DateTime.now().toUtc();
  final header = decodeJwtHeader(token);
  final claims = decodeJwtClaims(token);
  final issues = <String>[];

  final algorithm = _stringClaim(header, const ['alg']);
  if (algorithm == null || algorithm.isEmpty) {
    issues.add('JWT header is missing alg');
  } else if (algorithm != 'RS256') {
    issues.add('JWT header alg is $algorithm, expected RS256');
  }

  final issuer = _stringClaim(claims, const ['iss']);
  if (issuer == null || issuer.isEmpty) {
    issues.add('JWT claims are missing iss');
  } else if (expectedIssuer != null && expectedIssuer.isNotEmpty && issuer != expectedIssuer) {
    issues.add('JWT issuer is $issuer, expected $expectedIssuer');
  }

  final expiresAt = _dateTimeClaim(claims, const ['exp']);
  if (expiresAt == null) {
    issues.add('JWT claims are missing exp');
  } else if (!expiresAt.isAfter(currentTime)) {
    issues.add('JWT access token is already expired at ${expiresAt.toIso8601String()}');
  }

  final notBefore = _dateTimeClaim(claims, const ['nbf']);
  if (notBefore != null && notBefore.isAfter(currentTime)) {
    issues.add('JWT access token is not valid before ${notBefore.toIso8601String()}');
  }

  return OAuth2TokenVerification(
    header: header,
    claims: claims,
    issues: issues,
    now: currentTime,
  );
}

Map<String, dynamic> decodeJwtHeader(String token) {
  return _decodeJwtPart(token, partIndex: 0, context: 'JWT header');
}

Map<String, dynamic> decodeJwtClaims(String token) {
  return _decodeJwtPart(token, partIndex: 1, context: 'JWT payload');
}

Map<String, dynamic> _decodeJwtPart(
  String token, {
  required int partIndex,
  required String context,
}) {
  final parts = token.split('.');
  if (parts.length < 2) {
    throw FormatException('Expected a JWT but got: $token');
  }
  final part = parts[partIndex];
  final normalized = part.padRight(part.length + ((4 - part.length % 4) % 4), '=');
  final decoded = utf8.decode(base64Url.decode(normalized));
  final json = jsonDecode(decoded);
  if (json is Map<String, dynamic>) return json;
  if (json is Map) return Map<String, dynamic>.from(json);
  throw FormatException('$context was not a JSON object: $decoded');
}

String? _stringClaim(Map<String, dynamic> claims, List<String> keys) {
  for (final key in keys) {
    final value = claims[key];
    if (value is String && value.isNotEmpty) return value;
    if (value != null) return value.toString();
  }
  return null;
}

DateTime? _dateTimeClaim(Map<String, dynamic> claims, List<String> keys) {
  for (final key in keys) {
    final value = claims[key];
    if (value is String) {
      return DateTime.tryParse(value);
    }
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
  }
  return null;
}
