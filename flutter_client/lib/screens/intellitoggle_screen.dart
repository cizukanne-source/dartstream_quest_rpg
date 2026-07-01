import 'package:flutter/material.dart';
import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

import '../intellitoggle/flag_aware.dart';
import '../intellitoggle/intellitoggle.dart';
import '../state/session.dart';

/// Live demo of IntelliToggle exercised through the OpenFeature client surface.
class IntelliToggleScreen extends StatefulWidget {
  const IntelliToggleScreen({super.key, required this.session});
  final Session session;

  @override
  State<IntelliToggleScreen> createState() => _IntelliToggleScreenState();
}

enum _FlagType { boolean, string, integer, double_, object }

class _AttrRow {
  _AttrRow(String key, String value)
      : keyCtl = TextEditingController(text: key),
        valueCtl = TextEditingController(text: value);
  final TextEditingController keyCtl;
  final TextEditingController valueCtl;
  void dispose() {
    keyCtl.dispose();
    valueCtl.dispose();
  }
}

class _IntelliToggleScreenState extends State<IntelliToggleScreen> {
  bool _registering = true;
  Object? _registerError;

  final _keyController = TextEditingController(text: 'new-dashboard');
  _FlagType _type = _FlagType.boolean;
  bool _evaluating = false;
  String? _result;
  bool _resultIsError = false;

  final List<_AttrRow> _targetingRows = [];
  int _widgetRev = 0;

  final _trackNameController = TextEditingController(text: 'demo_event');
  final _trackValueController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final s = widget.session;
    _targetingRows.add(_AttrRow(
        'targetingKey', s.userId ?? s.email ?? 'anonymous'));
    if (s.email != null) _targetingRows.add(_AttrRow('email', s.email!));
    if (s.tenantId != null) _targetingRows.add(_AttrRow('tenantId', s.tenantId!));
    _targetingRows.add(_AttrRow('plan', 'premium'));
    _register();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _trackNameController.dispose();
    _trackValueController.dispose();
    for (final r in _targetingRows) {
      r.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _targetingMap() {
    final map = <String, dynamic>{};
    for (final r in _targetingRows) {
      final k = r.keyCtl.text.trim();
      final v = r.valueCtl.text.trim();
      if (k.isNotEmpty) map[k] = v;
    }
    return map;
  }

  Future<void> _register() async {
    if (!IntelliToggle.instance.isConfigured) {
      setState(() => _registering = false);
      return;
    }
    setState(() {
      _registering = true;
      _registerError = null;
    });
    try {
      await IntelliToggle.instance.register(targeting: _targetingMap());
      if (mounted) setState(() => _registering = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _registerError = e;
          _registering = false;
        });
      }
    }
  }

  Future<void> _reconnect() async {
    setState(() {
      _registering = true;
      _registerError = null;
    });
    try {
      await IntelliToggle.instance.reconnect(targeting: _targetingMap());
    } catch (e) {
      _registerError = e;
    }
    if (mounted) setState(() => _registering = false);
  }

  void _applyTargeting() {
    IntelliToggle.instance.applyTargeting(_targetingMap());
    setState(() => _widgetRev++);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Targeting context applied - re-evaluating')),
    );
  }

  Future<void> _evaluate() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) return;
    setState(() {
      _evaluating = true;
      _result = null;
      _resultIsError = false;
    });
    try {
      final FlagEvaluationDetails details;
      switch (_type) {
        case _FlagType.boolean:
          details = await IntelliToggle.instance.evalBoolean(key);
        case _FlagType.string:
          details = await IntelliToggle.instance.evalString(key);
        case _FlagType.integer:
          details = await IntelliToggle.instance.evalInteger(key);
        case _FlagType.double_:
          details = await IntelliToggle.instance.evalDouble(key);
        case _FlagType.object:
          details = await IntelliToggle.instance.evalObject(key);
      }
      final isErr = details.errorCode != null;
      if (mounted) {
        setState(() {
          _result = _format(details);
          _resultIsError = isErr;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _result = '${_classify(e)}\n$e';
          _resultIsError = true;
        });
      }
    } finally {
      if (mounted) setState(() => _evaluating = false);
    }
  }

  Future<void> _track() async {
    final name = _trackNameController.text.trim();
    if (name.isEmpty) return;
    final raw = _trackValueController.text.trim();
    final value = raw.isEmpty ? null : num.tryParse(raw);
    try {
      await IntelliToggle.instance.track(name, value: value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tracked "$name" via OpenFeature tracking API')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Track failed: $e')));
      }
    }
  }

  String _classify(Object e) {
    if (e is AuthenticationException) return '[auth] OAuth/client-credentials rejected';
    if (e is FlagNotFoundException) return '[not-found] flag does not exist in the tenant';
    if (e is TypeMismatchException) return '[type-mismatch] flag is a different type';
    if (e is ApiException) return '[api] IntelliToggle API error';
    return '[error]';
  }

  String _format(FlagEvaluationDetails res) {
    final lines = <String>[
      'value: ${res.value}',
      if (res.reason != null) 'reason: ${res.reason}',
      if (res.variant != null) 'variant: ${res.variant}',
      if (res.errorCode != null) 'errorCode: ${res.errorCode}',
      if (res.errorMessage != null) 'errorMessage: ${res.errorMessage}',
      'at: ${res.timestamp.toIso8601String()}',
    ];
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    if (!IntelliToggle.instance.isConfigured) return _notConfigured();
    if (_registering) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_registerError != null) return _registerErrorView();
    return _ready();
  }

  Widget _notConfigured() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.toggle_off_outlined, size: 48),
              const SizedBox(height: 12),
              Text('IntelliToggle is not configured',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              const Text(
                'Supply OAuth2 client-credentials at build time to evaluate '
                'flags from IntelliToggle:\n\n'
                '--dart-define=INTELLITOGGLE_CLIENT_ID=...\n'
                '--dart-define=INTELLITOGGLE_CLIENT_SECRET=...\n'
                '--dart-define=INTELLITOGGLE_TENANT_ID=...',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );

  Widget _registerErrorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Could not register the IntelliToggle provider:\n'
                  '$_registerError',
                  textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _register, child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _ready() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _statusCard(IntelliToggle.instance.provider),
        const SizedBox(height: 16),
        _targetingCard(),
        const SizedBox(height: 16),
        _evaluatorCard(),
        const SizedBox(height: 16),
        _trackCard(),
        const SizedBox(height: 16),
        _telemetryCard(),
        const SizedBox(height: 16),
        _widgetDemoCard(),
      ],
    );
  }

  Widget _statusCard(FeatureProvider provider) {
    final it = IntelliToggle.instance;
    final ready = provider.state == ProviderState.READY;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 96, child: Text(k, style: Theme.of(context).textTheme.bodySmall)),
              Expanded(
                  child: Text(v,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            ],
          ),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Provider: ${provider.metadata.name}',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                if (!ready)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: _reconnect,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Reconnect'),
                    ),
                  ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(provider.state.name),
                  backgroundColor: ready
                      ? Colors.green.withValues(alpha: 0.18)
                      : Theme.of(context).colorScheme.errorContainer,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
                ready
                    ? 'OAuth2 client-credentials via OpenFeature.'
                    : 'Provider not ready - the init handshake failed (it fails closed and does not auto-retry). Tap Reconnect.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            row('environment', it.environment),
            row('endpoint', it.baseUri?.toString() ?? '—'),
            row('timeout', '${it.timeout?.inSeconds ?? '—'}s'),
            row('cache TTL', '${it.cacheTtl?.inSeconds ?? '—'}s'),
            row('streaming', '${it.streaming}'),
            row('polling', '${it.polling}'),
          ],
        ),
      ),
    );
  }

  Widget _targetingCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Targeting context',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Attributes flags are scored against (seeded from your signed-in DartStream identity). Edit or add attributes, then apply.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (int i = 0; i < _targetingRows.length; i++) _attrRow(i),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () => setState(
                      () => _targetingRows.add(_AttrRow('', ''))),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add attribute'),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _applyTargeting,
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Apply targeting'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _attrRow(int i) {
    final row = _targetingRows[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: row.keyCtl,
              decoration: const InputDecoration(
                  labelText: 'key', isDense: true, border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: TextField(
              controller: row.valueCtl,
              decoration: const InputDecoration(
                  labelText: 'value', isDense: true, border: OutlineInputBorder()),
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, size: 18),
            onPressed: () => setState(() {
              _targetingRows.removeAt(i).dispose();
            }),
          ),
        ],
      ),
    );
  }

  Widget _evaluatorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Evaluate a flag',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Runs through the OpenFeature client, so the hooks below fire.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _keyController,
                    decoration: const InputDecoration(
                      labelText: 'Flag key',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _evaluate(),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<_FlagType>(
                  value: _type,
                  onChanged: (t) => setState(() => _type = t!),
                  items: const [
                    DropdownMenuItem(
                        value: _FlagType.boolean, child: Text('boolean')),
                    DropdownMenuItem(
                        value: _FlagType.string, child: Text('string')),
                    DropdownMenuItem(
                        value: _FlagType.integer, child: Text('integer')),
                    DropdownMenuItem(
                        value: _FlagType.double_, child: Text('double')),
                    DropdownMenuItem(
                        value: _FlagType.object, child: Text('object')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _evaluating ? null : _evaluate,
                icon: _evaluating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.play_arrow),
                label: Text(_evaluating ? 'Evaluating...' : 'Evaluate'),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _resultIsError
                      ? Theme.of(context).colorScheme.errorContainer
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_result!,
                    style: const TextStyle(fontFamily: 'monospace')),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _trackCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Track an event',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'OpenFeature tracking API (spec section 6) -> IntelliToggle analytics. Scored against the current targeting context.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _trackNameController,
                    decoration: const InputDecoration(
                        labelText: 'Event name',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _trackValueController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'value (opt)',
                        isDense: true,
                        border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _track,
                  icon: const Icon(Icons.bar_chart, size: 18),
                  label: const Text('Track'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _telemetryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Telemetry - hooks',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => IntelliToggle.instance.clearLogs(),
                  icon: const Icon(Icons.clear_all, size: 18),
                  label: const Text('Clear'),
                ),
              ],
            ),
            Text(
              'Live OpenFeature hook lifecycle (before / after / finally / error) from ConsoleLoggingHook + IntelliToggleTelemetryHook (OTel spans).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<List<String>>(
              valueListenable: IntelliToggle.instance.logs,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return Text('No evaluations yet - run one above.',
                      style: Theme.of(context).textTheme.bodySmall);
                }
                final recent = logs.reversed.take(20).toList();
                return Container(
                  width: double.infinity,
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      recent.join('\n'),
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _widgetDemoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Flag-aware widgets',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'These widgets render straight from the live flag value (keys: "new-dashboard", "hero-variant"). Re-evaluated on apply.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            ItFlagAware(
              key: ValueKey('flagaware-$_widgetRev'),
              flagKey: 'new-dashboard',
              onChild: const ListTile(
                leading: Icon(Icons.dashboard, color: Colors.green),
                title: Text('New dashboard is ON'),
              ),
              offChild: const ListTile(
                leading: Icon(Icons.dashboard_outlined),
                title: Text('New dashboard is OFF (default)'),
              ),
            ),
            const Divider(),
            ItExperiment(
              key: ValueKey('experiment-$_widgetRev'),
              flagKey: 'hero-variant',
              defaultVariant: 'control',
              variants: const {
                'control': ListTile(
                  leading: Icon(Icons.science_outlined),
                  title: Text('Hero: control'),
                ),
                'treatment': ListTile(
                  leading: Icon(Icons.science, color: Colors.blue),
                  title: Text('Hero: treatment'),
                ),
              },
            ),
          ],
        ),
      ),
    );
  }
}
