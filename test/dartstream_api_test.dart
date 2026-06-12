import 'dart:convert';

import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

DartStreamClient _client(MockClient mockClient) {
  return DartStreamClient(
    config: DartStreamConfig.local(firebaseApiKey: 'test-key'),
    httpClient: mockClient,
  );
}

DartStreamSession _session() {
  return const DartStreamSession(
    idToken: 'firebase-id-token',
    userId: 'user-123',
    tenantId: 'tenant-456',
    raw: <String, dynamic>{},
  );
}

void main() {
  test('saveCloudSave wraps payload in the expected envelope', () async {
    late Uri requestUri;
    late Map<String, String> requestHeaders;
    late Map<String, dynamic> requestBody;

    final client = _client(
      MockClient((request) async {
        requestUri = request.url;
        requestHeaders = request.headers;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      }),
    );

    await client.experience.saveCloudSave(
      _session(),
      slotKey: 'quest',
      payload: const {'xp': 42, 'gold': 7},
    );

    expect(requestUri.path, '/api/v1/experience/cloud-save/snapshot');
    expect(requestUri.queryParameters['slotKey'], 'quest');
    expect(requestUri.queryParameters['projectId'], 'default-app');
    expect(requestUri.queryParameters['environmentId'], 'development');
    expect(requestHeaders['authorization'], 'Bearer firebase-id-token');
    expect(requestHeaders['x-tenant-id'], 'tenant-456');
    expect(requestBody, {
      'payload': {'xp': 42, 'gold': 7},
    });
  });

  test('trackEvent uses snake_case event_type', () async {
    late Uri requestUri;
    late Map<String, dynamic> requestBody;

    final client = _client(
      MockClient((request) async {
        requestUri = request.url;
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      }),
    );

    await client.reactive.trackEvent(
      _session(),
      eventType: 'quest.action.explore',
      payload: const {'step': 'explore'},
    );

    expect(requestUri.path, '/api/v1/reactive/events/log');
    expect(requestBody, {
      'event_type': 'quest.action.explore',
      'payload': {'step': 'explore'},
    });
  });

  test('loadCloudSave returns null for missing snapshots', () async {
    final client = _client(
      MockClient((request) async {
        expect(request.url.path, '/api/v1/experience/cloud-save/snapshot');
        return http.Response('', 404);
      }),
    );

    final snapshot = await client.experience.loadCloudSave(
      _session(),
      slotKey: 'quest',
    );

    expect(snapshot, isNull);
  });
}
