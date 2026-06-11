import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class SignupResult {
  SignupResult({
    required this.userId,
    required this.tenantId,
    required this.raw,
  });

  final String userId;
  final String tenantId;
  final Map<String, dynamic> raw;
}

class DartstreamApiException implements Exception {
  DartstreamApiException(this.statusCode, this.body);

  final int statusCode;
  final String body;

  @override
  String toString() => 'DartstreamApiException($statusCode): $body';
}

class DartstreamApi {
  DartstreamApi({
    required this.idToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String idToken;
  final http.Client _client;

  Map<String, String> _headers({
    String? tenantId,
    bool json = false,
  }) {
    final headers = <String, String>{
      'authorization': 'Bearer $idToken',
      'accept': 'application/json',
    };
    if (tenantId != null && tenantId.isNotEmpty) {
      headers['x-tenant-id'] = tenantId;
    }
    if (json) {
      headers['content-type'] = 'application/json';
    }
    return headers;
  }

  Future<SignupResult> signup({
    String? email,
    String? displayName,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.authHost}/api/v1/auth/signup'),
      headers: _headers(json: true),
      body: jsonEncode({
        'idToken': idToken,
        if (email != null && email.isNotEmpty) 'email': email,
        if (displayName != null && displayName.isNotEmpty)
          'displayName': displayName,
      }),
    );

    if (response.statusCode == 409) {
      final login = await _client.post(
        Uri.parse('${AppConfig.authHost}/api/v1/auth/login'),
        headers: _headers(json: true),
        body: jsonEncode({
          'idToken': idToken,
          if (email != null && email.isNotEmpty) 'email': email,
          if (displayName != null && displayName.isNotEmpty)
            'displayName': displayName,
        }),
      );
      return _parseSignup(login);
    }

    return _parseSignup(response);
  }

  Future<Map<String, dynamic>> me() async {
    final response = await _client.get(
      Uri.parse('${AppConfig.authHost}/api/v1/auth/me'),
      headers: _headers(),
    );
    return _jsonOrThrow(response);
  }

  Future<Map<String, dynamic>> profile({
    required String userId,
    required String tenantId,
    String? projectId,
    String? environmentId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/profiles/me'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}'
        '${_scope(projectId, environmentId)}',
      ),
      headers: _headers(tenantId: tenantId),
    );
    return _jsonOrThrow(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> featureFlags({
    required String tenantId,
  }) async {
    final response = await _client.get(
      Uri.parse('${AppConfig.platformHost}/api/v1/platform/feature-flags'),
      headers: _headers(tenantId: tenantId),
    );
    return _jsonOrThrow(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> inventory({
    required String userId,
    required String tenantId,
    String? projectId,
    String? environmentId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/inventory/items'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}'
        '${_scope(projectId, environmentId)}',
      ),
      headers: _headers(tenantId: tenantId),
    );
    return _jsonOrThrow(response) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>?> loadSnapshot({
    required String userId,
    required String tenantId,
    String slotKey = 'quest',
    String? projectId,
    String? environmentId,
  }) async {
    final response = await _client.get(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/cloud-save/snapshot'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}'
        '&slotKey=${Uri.encodeQueryComponent(slotKey)}'
        '${_scope(projectId, environmentId)}',
      ),
      headers: _headers(tenantId: tenantId),
    );
    if (response.statusCode == 404) {
      return null;
    }
    return _jsonOrThrow(response) as Map<String, dynamic>;
  }

  Future<void> saveSnapshot({
    required String userId,
    required String tenantId,
    required Map<String, dynamic> payload,
    String slotKey = 'quest',
    String? projectId,
    String? environmentId,
  }) async {
    final response = await _client.post(
      Uri.parse(
        '${AppConfig.experienceHost}/api/v1/experience/cloud-save/snapshot'
        '?userId=${Uri.encodeQueryComponent(userId)}'
        '&tenantId=${Uri.encodeQueryComponent(tenantId)}'
        '&slotKey=${Uri.encodeQueryComponent(slotKey)}'
        '${_scope(projectId, environmentId)}',
      ),
      headers: _headers(tenantId: tenantId, json: true),
      body: jsonEncode({'payload': payload}),
    );
    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw DartstreamApiException(response.statusCode, response.body);
    }
  }

  Future<Map<String, dynamic>> logEvent({
    required String tenantId,
    required String eventType,
    required Map<String, dynamic> payload,
  }) async {
    final response = await _client.post(
      Uri.parse('${AppConfig.reactiveHost}/api/v1/reactive/events/log'),
      headers: _headers(tenantId: tenantId, json: true),
      body: jsonEncode({
        'event_type': eventType,
        'payload': payload,
      }),
    );
    return _jsonOrThrow(response);
  }

  Future<List<dynamic>> streamingChannels({
    required String tenantId,
  }) async {
    final response = await _client.get(
      Uri.parse('${AppConfig.reactiveHost}/api/v1/reactive/streaming/channels'),
      headers: _headers(tenantId: tenantId),
    );
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DartstreamApiException(
        response.statusCode,
        _errorMessage(decoded, response.body),
      );
    }
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      final data = decoded['data'];
      if (data is List) return data;
      final channels = decoded['channels'];
      if (channels is List) return channels;
    }
    return const [];
  }

  String _scope(String? projectId, String? environmentId) {
    final buffer = StringBuffer();
    if (projectId != null && projectId.isNotEmpty) {
      buffer.write('&projectId=${Uri.encodeQueryComponent(projectId)}');
    }
    if (environmentId != null && environmentId.isNotEmpty) {
      buffer.write('&environmentId=${Uri.encodeQueryComponent(environmentId)}');
    }
    return buffer.toString();
  }

  SignupResult _parseSignup(http.Response response) {
    final decoded = _jsonOrThrow(response);
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw DartstreamApiException(response.statusCode, response.body);
    }

    final map = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    final user = _extractUserRecord(map);
    final userId = _pickString(user, const ['id', 'user_id', 'uid', 'localId']);
    final tenantId = _pickString(
      user,
      const ['tenant_id', 'tenantId', 'active_tenant_id', 'canonical_tenant_id'],
    ) ??
        _pickString(
          map,
          const ['active_tenant_id', 'tenant_id', 'tenantId', 'canonical_tenant_id'],
        );
    final fallbackTenant = _pickString(
      map,
      const ['tenant_id', 'tenantId', 'active_tenant_id', 'canonical_tenant_id'],
    );
    if (userId == null || (tenantId ?? fallbackTenant) == null) {
      throw DartstreamApiException(
        response.statusCode,
        'Could not extract userId/tenantId from: ${response.body}',
      );
    }
    return SignupResult(
      userId: userId,
      tenantId: tenantId ?? fallbackTenant!,
      raw: map,
    );
  }

  dynamic _jsonOrThrow(http.Response response) {
    final decoded = _decode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw DartstreamApiException(
        response.statusCode,
        _errorMessage(decoded, response.body),
      );
    }
    return decoded;
  }
}

dynamic _decode(String body) {
  if (body.trim().isEmpty) {
    return <String, dynamic>{};
  }
  try {
    return jsonDecode(body);
  } catch (_) {
    return {'raw': body};
  }
}

String _errorMessage(dynamic decoded, String fallback) {
  if (decoded is Map<String, dynamic>) {
    final error = decoded['error'];
    if (error is Map<String, dynamic>) {
      final message = error['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
      final details = error['details'];
      if (details is String && details.isNotEmpty) {
        return details;
      }
    }
    final message = decoded['message'];
    if (message is String && message.isNotEmpty) {
      return message;
    }
  }
  return fallback.isNotEmpty ? fallback : 'Request failed.';
}

Map<String, dynamic>? _findMap(
  Map<String, dynamic> map,
  List<String> keys,
) {
  for (final key in keys) {
    final value = map[key];
    if (value is Map<String, dynamic>) {
      return value;
    }
  }
  return null;
}

Map<String, dynamic> _extractUserRecord(Map<String, dynamic> map) {
  final directUser = _findMap(map, const ['user', 'account']);
  if (directUser != null) {
    return directUser;
  }

  final data = map['data'];
  if (data is Map<String, dynamic>) {
    final nestedUser = _findMap(data, const ['user', 'account']);
    if (nestedUser != null) {
      return nestedUser;
    }
    return data;
  }

  return map;
}

String? _pickString(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
  }
  return null;
}
