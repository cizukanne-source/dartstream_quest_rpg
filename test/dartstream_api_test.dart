import 'dart:convert';

import 'package:dartstream_quest_rpg/api/dartstream.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('saveSnapshot wraps payload in the payload envelope', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('', 204);
    });

    final api = DartstreamApi(idToken: 'token-123', client: client);
    await api.saveSnapshot(
      userId: 'user-1',
      tenantId: 'tenant-1',
      payload: const {'xp': 120, 'gold': 45},
    );

    expect(capturedRequest.headers['authorization'], 'Bearer token-123');
    expect(capturedRequest.headers['x-tenant-id'], 'tenant-1');
    expect(
      jsonDecode(capturedRequest.body),
      <String, dynamic>{
        'payload': <String, dynamic>{
          'xp': 120,
          'gold': 45,
        },
      },
    );
  });

  test('logEvent sends event_type in snake case', () async {
    late http.Request capturedRequest;
    final client = MockClient((request) async {
      capturedRequest = request;
      return http.Response('{"ok":true}', 200);
    });

    final api = DartstreamApi(idToken: 'token-123', client: client);
    await api.logEvent(
      tenantId: 'tenant-1',
      eventType: 'quest.action.explore',
      payload: const {'xp': 12},
    );

    expect(capturedRequest.headers['authorization'], 'Bearer token-123');
    expect(capturedRequest.headers['x-tenant-id'], 'tenant-1');
    expect(
      jsonDecode(capturedRequest.body),
      <String, dynamic>{
        'event_type': 'quest.action.explore',
        'payload': <String, dynamic>{'xp': 12},
      },
    );
  });

  test('loadSnapshot returns null for a missing snapshot', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/experience/cloud-save/snapshot');
      return http.Response('', 404);
    });

    final api = DartstreamApi(idToken: 'token-123', client: client);
    final snapshot = await api.loadSnapshot(
      userId: 'user-1',
      tenantId: 'tenant-1',
    );

    expect(snapshot, isNull);
  });
}
