import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dartstream_quest_rpg/verification/oauth2_verifier.dart';

String _jwt({
  required Map<String, dynamic> header,
  required Map<String, dynamic> claims,
}) {
  final encodedHeader = base64UrlEncode(utf8.encode(jsonEncode(header))).replaceAll('=', '');
  final encodedClaims = base64UrlEncode(utf8.encode(jsonEncode(claims))).replaceAll('=', '');
  return '$encodedHeader.$encodedClaims.signature';
}

void main() {
  test('accepts a live-style RS256 JWT that is not expired', () {
    final now = DateTime.utc(2026, 6, 26, 12);
    final token = _jwt(
      header: const {'alg': 'RS256', 'typ': 'JWT'},
      claims: {
        'iss': 'https://issuer.example.test',
        'sub': 'user-123',
        'exp': now.add(const Duration(minutes: 30)).millisecondsSinceEpoch ~/ 1000,
        'nbf': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
      },
    );

    final verification = inspectJwtAccessToken(
      token,
      now: now,
      expectedIssuer: 'https://issuer.example.test',
    );

    expect(verification.passed, isTrue);
    expect(verification.issuer, 'https://issuer.example.test');
    expect(verification.subject, 'user-123');
  });

  test('rejects an expired or non-RS256 token', () {
    final now = DateTime.utc(2026, 6, 26, 12);
    final token = _jwt(
      header: const {'alg': 'HS256', 'typ': 'JWT'},
      claims: {
        'iss': 'https://issuer.example.test',
        'exp': now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch ~/ 1000,
      },
    );

    final verification = inspectJwtAccessToken(
      token,
      now: now,
      expectedIssuer: 'https://issuer.example.test',
    );

    expect(verification.passed, isFalse);
    expect(
      verification.issues,
      containsAll(<Matcher>[
        contains('expected RS256'),
        contains('already expired'),
      ]),
    );
  });
}
