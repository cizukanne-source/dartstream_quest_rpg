import 'package:flutter/material.dart';

import '../intellitoggle/intellitoggle.dart';
import '../state/session.dart';

class IntelliToggleControlScreen extends StatefulWidget {
  const IntelliToggleControlScreen({super.key, required this.session});

  final Session session;

  @override
  State<IntelliToggleControlScreen> createState() => _IntelliToggleControlScreenState();
}

class _IntelliToggleControlScreenState extends State<IntelliToggleControlScreen> {
  bool _enabled = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _register();
  }

  Future<void> _register() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_enabled) {
        await IntelliToggle.instance.register(
          targeting: {
            'targetingKey': widget.session.userId ?? widget.session.email ?? 'anonymous',
            'email': widget.session.email ?? '',
            'tenantId': widget.session.tenantId ?? '',
            'displayName': widget.session.displayName ?? '',
          },
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
      _busy = true;
      _error = null;
    });
    try {
      if (value) {
        await IntelliToggle.instance.reconnect(
          targeting: {
            'targetingKey': widget.session.userId ?? widget.session.email ?? 'anonymous',
            'email': widget.session.email ?? '',
            'tenantId': widget.session.tenantId ?? '',
            'displayName': widget.session.displayName ?? '',
          },
        );
      } else {
        IntelliToggle.instance.clearLogs();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'IntelliToggle',
          style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text(
          'Enable or pause the provider that powers live evaluations.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text('Provider state', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                  if (_busy)
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Switch(value: _enabled, onChanged: _toggle),
                ],
              ),
              const SizedBox(height: 8),
              Text(_enabled
                  ? 'IntelliToggle is active and can evaluate live flags.'
                  : 'IntelliToggle is paused. Live evaluations are suspended.'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _Pill(label: IntelliToggle.instance.isConfigured ? 'Credentials ready' : 'Missing defines'),
                  _Pill(label: IntelliToggle.instance.isReady ? 'Registered' : 'Not registered'),
                  _Pill(label: IntelliToggle.instance.environment),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Card(
          child: ValueListenableBuilder<List<String>>(
            valueListenable: IntelliToggle.instance.logs,
            builder: (context, logs, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Recent evaluation logs', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800))),
                      TextButton(
                        onPressed: IntelliToggle.instance.clearLogs,
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (logs.isEmpty)
                    const Text('No IntelliToggle activity yet.')
                  else
                    ...logs.reversed.take(12).map(
                      (line) => Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(line, style: const TextStyle(fontFamily: 'monospace')),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(label));
  }
}
