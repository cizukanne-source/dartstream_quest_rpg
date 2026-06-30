import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/material.dart';

import '../state/session.dart';

class FeatureFlagsScreen extends StatefulWidget {
  const FeatureFlagsScreen({super.key, required this.session});

  final Session session;

  @override
  State<FeatureFlagsScreen> createState() => _FeatureFlagsScreenState();
}

class _FeatureFlagsScreenState extends State<FeatureFlagsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  List<dynamic> _flags = const [];

  DartStreamClient get _client => widget.session.client!;
  DartStreamSession get _sdkSession => widget.session.sdkSession!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Map<String, dynamic>? _mapFlag(dynamic flag) {
    if (flag is Map<String, dynamic>) return flag;
    if (flag is Map) return Map<String, dynamic>.from(flag);
    return null;
  }

  String _flagKey(dynamic flag) {
    final map = _mapFlag(flag);
    if (map == null) return flag.toString();
    for (final key in ['key', 'flagKey', 'featureKey', 'id', 'name']) {
      final value = map[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return 'unknown';
  }

  bool _flagEnabled(dynamic flag) {
    if (flag is bool) return flag;
    final map = _mapFlag(flag);
    if (map == null) return false;
    for (final key in ['enabled', 'value', 'active', 'isEnabled', 'is_enabled']) {
      final value = map[key];
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.toLowerCase();
        if (normalized == 'true' || normalized == 'enabled' || normalized == 'on') {
          return true;
        }
        if (normalized == 'false' || normalized == 'disabled' || normalized == 'off') {
          return false;
        }
      }
    }
    return false;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final flags = await _client.platform.featureFlags(_sdkSession);
      widget.session.updateFeatureFlags(flags);
      if (!mounted) return;
      setState(() {
        _flags = flags;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  Future<void> _toggleFlag(dynamic flag, bool enabled) async {
    final key = _flagKey(flag);
    final map = _mapFlag(flag) ?? <String, dynamic>{'key': key};
    setState(() => _saving = true);
    try {
      await _client.platform.updateFeatureFlag(
        _sdkSession,
        key,
        updates: {
          ...map,
          'enabled': enabled,
          'value': enabled,
        },
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteFlag(dynamic flag) async {
    final key = _flagKey(flag);
    setState(() => _saving = true);
    try {
      await _client.platform.deleteFeatureFlag(_sdkSession, key);
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addFlag() async {
    final result = await showDialog<_NewFlag>(
      context: context,
      builder: (context) => const _NewFlagDialog(),
    );
    if (result == null) return;
    setState(() => _saving = true);
    try {
      await _client.platform.createFeatureFlag(
        _sdkSession,
        flag: result.toPayload(),
      );
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quickFlags = [
      'double_xp',
      'hard_mode',
      'light_mode',
      'dark_mode',
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Feature flags',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            FilledButton.icon(
              onPressed: _saving ? null : _addFlag,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add flag'),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Manage the live tenant flags that drive the arena.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          _Banner(message: _error!, isError: true),
        ],
        const SizedBox(height: 16),
        if (_loading)
          const LinearProgressIndicator(minHeight: 6)
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: quickFlags
                .map((key) => _Chip(label: key, icon: Icons.flag_rounded))
                .toList(),
          ),
          const SizedBox(height: 16),
          ..._flags.map((flag) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FlagCard(
                  flag: flag,
                  enabled: _flagEnabled(flag),
                  onToggle: (value) => _toggleFlag(flag, value),
                  onDelete: () => _deleteFlag(flag),
                ),
              )),
          if (_flags.isEmpty)
            const _Banner(message: 'No flags returned by the tenant yet.', isError: false),
        ],
      ],
    );
  }
}

class _FlagCard extends StatelessWidget {
  const _FlagCard({
    required this.flag,
    required this.enabled,
    required this.onToggle,
    required this.onDelete,
  });

  final dynamic flag;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  Map<String, dynamic> get _map {
    if (flag is Map<String, dynamic>) return flag as Map<String, dynamic>;
    if (flag is Map) return Map<String, dynamic>.from(flag as Map);
    return <String, dynamic>{'key': flag.toString()};
  }

  @override
  Widget build(BuildContext context) {
    final key = (_map['key'] ?? _map['flagKey'] ?? _map['featureKey'] ?? _map['name'] ?? _map['id'] ?? 'flag').toString();
    final description = (_map['description'] ?? _map['details'] ?? '').toString();
    final type = (_map['type'] ?? _map['kind'] ?? 'boolean').toString();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(key, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    _Pill(text: type),
                  ],
                ),
                const SizedBox(height: 6),
                Text(description.isEmpty ? 'No description set.' : description),
                const SizedBox(height: 8),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: enabled,
                  onChanged: onToggle,
                  title: const Text('Enabled'),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

class _NewFlagDialog extends StatefulWidget {
  const _NewFlagDialog();

  @override
  State<_NewFlagDialog> createState() => _NewFlagDialogState();
}

class _NewFlagDialogState extends State<_NewFlagDialog> {
  final _key = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _value = TextEditingController(text: 'true');
  bool _enabled = true;
  String _type = 'boolean';

  @override
  void dispose() {
    _key.dispose();
    _name.dispose();
    _description.dispose();
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add feature flag'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _key,
                decoration: const InputDecoration(labelText: 'Flag key', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                items: const [
                  DropdownMenuItem(value: 'boolean', child: Text('Boolean')),
                  DropdownMenuItem(value: 'string', child: Text('String')),
                  DropdownMenuItem(value: 'integer', child: Text('Integer')),
                  DropdownMenuItem(value: 'double', child: Text('Double')),
                  DropdownMenuItem(value: 'object', child: Text('Object')),
                ],
                onChanged: (value) => setState(() => _type = value ?? 'boolean'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _value,
                decoration: const InputDecoration(labelText: 'Default value', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                title: const Text('Enabled'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            final key = _key.text.trim();
            if (key.isEmpty) return;
            Navigator.pop(
              context,
              _NewFlag(
                key: key,
                name: _name.text.trim(),
                description: _description.text.trim(),
                type: _type,
                enabled: _enabled,
                value: _value.text.trim(),
              ),
            );
          },
          child: const Text('Create'),
        ),
      ],
    );
  }
}

class _NewFlag {
  _NewFlag({
    required this.key,
    required this.name,
    required this.description,
    required this.type,
    required this.enabled,
    required this.value,
  });

  final String key;
  final String name;
  final String description;
  final String type;
  final bool enabled;
  final String value;

  Map<String, dynamic> toPayload() => {
        'key': key,
        if (name.isNotEmpty) 'name': name,
        if (description.isNotEmpty) 'description': description,
        'type': type,
        'enabled': enabled,
        'value': value,
      };
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(text));
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError ? const Color(0xFF4C1D1D) : const Color(0xFF0F5132),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(message),
    );
  }
}
