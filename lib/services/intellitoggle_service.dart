import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';

class IntelliToggleConfig {
  const IntelliToggleConfig({
    required this.apiUrl,
    required this.tokenUrl,
    required this.clientId,
    required this.clientSecret,
    required this.tenantId,
    required this.projectId,
    required this.environment,
    required this.flagKey,
    required this.scope,
  });

  final String apiUrl;
  final String tokenUrl;
  final String clientId;
  final String clientSecret;
  final String tenantId;
  final String projectId;
  final String environment;
  final String flagKey;
  final String scope;

  factory IntelliToggleConfig.fromAppConfig() {
    return IntelliToggleConfig(
      apiUrl: AppConfig.intellitoggleApiUrl,
      tokenUrl: AppConfig.intellitoggleTokenUrl,
      clientId: AppConfig.intellitoggleClientId,
      clientSecret: AppConfig.intellitoggleClientSecret,
      tenantId: AppConfig.intellitoggleTenantId,
      projectId: AppConfig.intellitoggleProjectId,
      environment: AppConfig.intellitoggleEnvironment,
      flagKey: AppConfig.intellitoggleFlagKey,
      scope: AppConfig.intellitoggleScope,
    );
  }

  bool get isConfigured =>
      clientId.isNotEmpty &&
      clientSecret.isNotEmpty &&
      tenantId.isNotEmpty &&
      flagKey.isNotEmpty;
}

class IntelliToggleEvaluation {
  const IntelliToggleEvaluation({
    required this.enabled,
    required this.raw,
    required this.targetingKey,
  });

  final bool enabled;
  final Map<String, dynamic> raw;
  final String targetingKey;
}

class IntelliToggleService {
  IntelliToggleService({
    http.Client? httpClient,
    IntelliToggleConfig? config,
  })  : _client = httpClient ?? http.Client(),
        config = config ?? IntelliToggleConfig.fromAppConfig();

  final http.Client _client;
  final IntelliToggleConfig config;

  String? _cachedAccessToken;
  DateTime? _cachedAccessTokenExpiry;

  bool get hasCredentials => config.isConfigured;

  void dispose() {
    _client.close();
  }

  Future<IntelliToggleEvaluation> evaluateFlag({
    required String targetingKey,
    Map<String, dynamic> attributes = const {},
  }) async {
    final token = await _getAccessToken();
    final uri = _apiUri('/api/v1/flags/${Uri.encodeComponent(config.flagKey)}/evaluate');
    final response = await _client.post(
      uri,
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
        'X-Tenant-ID': config.tenantId,
        'X-Environment': config.environment,
        if (config.projectId.isNotEmpty) 'X-Project-ID': config.projectId,
      },
      body: jsonEncode({
        'targetingKey': targetingKey,
        'attributes': {
          'service': 'dartstream-quest-rpg',
          'environment': config.environment,
          ...attributes,
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'IntelliToggle evaluation failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = _decodeJson(response.body);
    final enabled = _extractEnabled(decoded);
    final raw = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
    return IntelliToggleEvaluation(
      enabled: enabled,
      raw: raw,
      targetingKey: targetingKey,
    );
  }

  Future<String> _getAccessToken() async {
    final cached = _cachedAccessToken;
    final expiry = _cachedAccessTokenExpiry;
    if (cached != null &&
        expiry != null &&
        DateTime.now().toUtc().isBefore(expiry.subtract(const Duration(seconds: 20)))) {
      return cached;
    }

    final response = await _client.post(
      Uri.parse(config.tokenUrl),
      headers: const {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: _encodeForm({
        'grant_type': 'client_credentials',
        'client_id': config.clientId,
        'client_secret': config.clientSecret,
        'scope': config.scope,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'IntelliToggle token request failed (${response.statusCode}): ${response.body}',
      );
    }

    final decoded = _decodeJson(response.body);
    final data = decoded is Map<String, dynamic>
        ? decoded
        : Map<String, dynamic>.from(decoded as Map);
    final accessToken = data['access_token'];
    if (accessToken is! String || accessToken.isEmpty) {
      throw StateError('IntelliToggle token response did not include access_token.');
    }

    final expiresIn = _intFromValue(data['expires_in']) ?? 3600;
    _cachedAccessToken = accessToken;
    _cachedAccessTokenExpiry = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
    return accessToken;
  }

  Uri _apiUri(String path) {
    final base = Uri.parse(config.apiUrl);
    return base.replace(path: path);
  }

  dynamic _decodeJson(String body) {
    if (body.trim().isEmpty) {
      return const <String, dynamic>{};
    }
    return jsonDecode(body);
  }

  bool _extractEnabled(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is String) {
      final normalized = value.toLowerCase();
      return normalized == 'true' ||
          normalized == 'enabled' ||
          normalized == 'on';
    }
    if (value is! Map) {
      return false;
    }
    final map = value is Map<String, dynamic>
        ? value
        : Map<String, dynamic>.from(value);
    final candidates = [
      map['enabled'],
      map['value'],
      map['active'],
      map['result'],
      map['status'],
    ];
    for (final candidate in candidates) {
      if (candidate is bool) {
        return candidate;
      }
      if (candidate is String) {
        final normalized = candidate.toLowerCase();
        if (normalized == 'true' ||
            normalized == 'enabled' ||
            normalized == 'on') {
          return true;
        }
        if (normalized == 'false' ||
            normalized == 'disabled' ||
            normalized == 'off') {
          return false;
        }
      }
    }
    return false;
  }

  int? _intFromValue(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is num) {
      return value.toInt();
    }
    return null;
  }

  String _encodeForm(Map<String, String> fields) {
    return fields.entries
        .map(
          (entry) =>
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}',
        )
        .join('&');
  }
}
