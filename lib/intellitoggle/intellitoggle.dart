import 'package:flutter/foundation.dart';
import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

import '../config.dart';

/// Thin app-level wrapper around the IntelliToggle OpenFeature provider.
///
/// IntelliToggle is Aortem's feature-flag SaaS. Unlike DartStream's own
/// `platform.featureFlags` (tenant-facing CRUD), here we exercise the full
/// OpenFeature client surface against the live provider:
///
///  * register the [IntelliToggleProvider] (OAuth2 client-credentials, handled
///    internally - the app never mints a token by hand),
///  * evaluate every flag type through an [OpenFeature] client so the hook
///    pipeline runs,
///  * drive targeting by editing the global evaluation context,
///  * record analytics with the OpenFeature tracking API.
///
/// Registration is global (OpenFeature keeps a single active provider), so this
/// is a process-wide singleton that registers lazily.
class IntelliToggle {
  IntelliToggle._();
  static final IntelliToggle instance = IntelliToggle._();

  bool _registered = false;
  FeatureClient? _client;
  IntelliToggleOptions? _options;
  Map<String, dynamic> _targeting = const {};

  /// Live, capped feed of OpenFeature hook lifecycle lines.
  final ValueNotifier<List<String>> logs = ValueNotifier<List<String>>(const []);

  /// Whether the OAuth client-credentials were injected at build time.
  bool get isConfigured => AppConfig.hasIntelliToggle;

  /// Whether the provider has been registered with OpenFeature.
  bool get isReady => _registered;

  /// The active OpenFeature provider - only valid once [register] has run.
  FeatureProvider get provider => OpenFeatureAPI().provider;

  // ---- provider configuration (surfaced in the UI) ------------------------
  IntelliToggleOptions? get options => _options;
  Uri? get baseUri => _options?.baseUri;
  Duration? get timeout => _options?.timeout;
  Duration? get cacheTtl => _options?.cacheTtl;
  bool get streaming => _options?.enableStreaming ?? false;
  bool get polling => _options?.enablePolling ?? false;

  /// The host the provider was pointed at.
  String get environment =>
      (_options?.baseUri.host ?? '').startsWith('dev-') ? 'development' : 'production';

  /// The active targeting / evaluation context.
  Map<String, dynamic> get targeting => Map.unmodifiable(_targeting);

  /// Register the IntelliToggle provider with OpenFeature (idempotent), wire up
  /// the hook pipeline, and seed the targeting context.
  Future<void> register({Map<String, dynamic>? targeting}) async {
    if (!isConfigured) {
      throw StateError(
        'IntelliToggle client-credentials are missing - supply '
        'INTELLITOGGLE_CLIENT_ID / _CLIENT_SECRET / _TENANT_ID via --dart-define.',
      );
    }
    if (!_registered) {
      _options = IntelliToggleOptions.production(
        baseUri: Uri.parse(AppConfig.intelliToggleApiUrl),
      );
      final provider = IntelliToggleProvider(
        clientId: AppConfig.intelliToggleClientId,
        clientSecret: AppConfig.intelliToggleClientSecret,
        tenantId: AppConfig.intelliToggleTenantId,
        options: _options!,
      );
      await OpenFeatureAPI().setProvider(provider);
      _registered = true;
    }
    applyTargeting(targeting ?? _targeting);
  }

  /// Re-initialize the provider after a transient init failure.
  Future<void> reconnect({Map<String, dynamic>? targeting}) async {
    _registered = false;
    await register(targeting: targeting ?? _targeting);
  }

  /// Replace the global targeting context and rebuild the hooked client.
  void applyTargeting(Map<String, dynamic> targeting) {
    final m = Map<String, dynamic>.from(targeting);
    if (!m.containsKey('targetingKey') && !m.containsKey('key')) {
      final tk = m['userId'] ?? m['email'] ?? m['tenantId'];
      if (tk != null) m['targetingKey'] = '$tk';
    }
    _targeting = m;
    OpenFeatureAPI().setGlobalContext(OpenFeatureEvaluationContext(_targeting));
    _rebuildClient();
  }

  void _rebuildClient() {
    final client = OpenFeatureAPI().getClient('intellitoggle');
    client.addHook(ConsoleLoggingHook(
      printContext: true,
      domain: 'intellitoggle',
      logger: _appendLog,
    ));
    client.addHook(IntelliToggleTelemetryHook());
    _client = client;
  }

  void _appendLog(String message) {
    final next = List<String>.from(logs.value)..add(message);
    if (next.length > 100) next.removeRange(0, next.length - 100);
    logs.value = next;
  }

  void clearLogs() => logs.value = const [];

  EvaluationContext get _evalContext =>
      EvaluationContext(attributes: _targeting.map((k, v) => MapEntry(k, '$v')));

  Future<FlagEvaluationDetails<bool>> evalBoolean(String key, {bool def = false}) =>
      _client!.getBooleanDetails(key, defaultValue: def, context: _evalContext);

  Future<FlagEvaluationDetails<String>> evalString(String key, {String def = ''}) =>
      _client!.getStringDetails(key, defaultValue: def, context: _evalContext);

  Future<FlagEvaluationDetails<int>> evalInteger(String key, {int def = 0}) =>
      _client!.getIntegerDetails(key, defaultValue: def, context: _evalContext);

  Future<FlagEvaluationDetails<double>> evalDouble(String key, {double def = 0}) =>
      _client!.getDoubleDetails(key, defaultValue: def, context: _evalContext);

  Future<FlagEvaluationDetails<Map<String, dynamic>>> evalObject(
    String key, {
    Map<String, dynamic> def = const {},
  }) =>
      _client!.getObjectDetails(key, defaultValue: def, context: _evalContext);

  Future<void> track(
    String eventName, {
    num? value,
    Map<String, dynamic> attributes = const {},
  }) =>
      provider.track(
        eventName,
        evaluationContext: _targeting,
        trackingDetails:
            TrackingEventDetails(value: value?.toDouble(), attributes: attributes),
      );

  Future<FlagEvaluationResult<bool>> getBoolean(
    String flagKey, {
    bool defaultValue = false,
    Map<String, dynamic>? context,
  }) =>
      provider.getBooleanFlag(flagKey, defaultValue, context: context);

  Future<FlagEvaluationResult<String>> getString(
    String flagKey, {
    String defaultValue = '',
    Map<String, dynamic>? context,
  }) =>
      provider.getStringFlag(flagKey, defaultValue, context: context);
}
