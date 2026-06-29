import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dartstream_quest_rpg/services/intellitoggle_service.dart';

void main() {
  test('fetches a bearer token and evaluates the configured flag', () async {
    late Uri tokenUri;
    late Uri evaluateUri;
    late Map<String, String> evaluateHeaders;
    late Map<String, dynamic> evaluateBody;
    var tokenRequests = 0;

    final service = IntelliToggleService(
      config: const IntelliToggleConfig(
        apiUrl: 'https://dev-api.intellitoggle.com',
        tokenUrl: 'https://dev-api.intellitoggle.com/api/v1/oauth/token',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        tenantId: 'tenant-123',
        projectId: 'proj-456',
        environment: 'production',
        flagKey: 'double_xp',
        scope: 'flags:read flags:evaluate projects:read',
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/oauth/token')) {
          tokenRequests += 1;
          tokenUri = request.url;
          final form = Uri.splitQueryString(request.body);
          expect(form['grant_type'], 'client_credentials');
          expect(form['client_id'], 'client-id');
          expect(form['client_secret'], 'client-secret');
          return http.Response(
            jsonEncode({
              'access_token': 'access-123',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }

        evaluateUri = request.url;
        evaluateHeaders = request.headers;
        evaluateBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'enabled': true,
            'variant': 'beta',
            'value': true,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final evaluation = await service.evaluateFlag(
      targetingKey: 'integration-smoke-test',
      attributes: const {'service': 'dartstream-quest-rpg'},
    );

    expect(tokenRequests, 1);
    expect(tokenUri.path, '/api/v1/oauth/token');
    expect(evaluateUri.path, '/api/v1/flags/double_xp/evaluate');
    expect(evaluateHeaders['authorization'], 'Bearer access-123');
    expect(evaluateHeaders['x-tenant-id'], 'tenant-123');
    expect(evaluateHeaders['x-environment'], 'production');
    expect(evaluateHeaders['x-project-id'], 'proj-456');
    expect(evaluateBody['targetingKey'], 'integration-smoke-test');
    expect(evaluateBody['attributes'], isA<Map<String, dynamic>>());
    expect(evaluation.enabled, isTrue);
    expect(evaluation.raw['variant'], 'beta');
    expect(evaluation.targetingKey, 'integration-smoke-test');
  });

  test('treats string-style enabled values as true', () async {
    final service = IntelliToggleService(
      config: const IntelliToggleConfig(
        apiUrl: 'https://dev-api.intellitoggle.com',
        tokenUrl: 'https://dev-api.intellitoggle.com/api/v1/oauth/token',
        clientId: 'client-id',
        clientSecret: 'client-secret',
        tenantId: 'tenant-123',
        projectId: '',
        environment: 'production',
        flagKey: 'double_xp',
        scope: 'flags:read flags:evaluate',
      ),
      httpClient: MockClient((request) async {
        if (request.url.path.endsWith('/oauth/token')) {
          return http.Response(
            jsonEncode({
              'access_token': 'access-123',
              'expires_in': 3600,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({
            'value': 'enabled',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final evaluation = await service.evaluateFlag(
      targetingKey: 'integration-smoke-test',
    );

    expect(evaluation.enabled, isTrue);
  });
}
