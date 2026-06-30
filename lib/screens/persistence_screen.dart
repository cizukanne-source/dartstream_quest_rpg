import 'package:dartstream_client/dartstream_client.dart';
import 'package:flutter/material.dart';

import '../state/session.dart';

class PersistenceScreen extends StatefulWidget {
  const PersistenceScreen({super.key, required this.session});

  final Session session;

  @override
  State<PersistenceScreen> createState() => _PersistenceScreenState();
}

class _PersistenceScreenState extends State<PersistenceScreen> {
  bool _loading = true;
  String? _error;
  List<dynamic> _databaseProviders = const [];
  List<dynamic> _storageProviders = const [];
  List<dynamic> _loggingProviders = const [];
  final List<String> _selected = [];

  DartStreamClient get _client => widget.session.client!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _client.persistence.databaseProviders(),
        _client.persistence.storageProviders(),
        _client.persistence.loggingProviders(),
      ]);
      if (!mounted) return;
      setState(() {
        _databaseProviders = results[0] as List<dynamic>;
        _storageProviders = results[1] as List<dynamic>;
        _loggingProviders = results[2] as List<dynamic>;
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

  String _label(dynamic item) {
    if (item is String) return item;
    if (item is Map) {
      final map = Map<String, dynamic>.from(item);
      for (final key in ['name', 'key', 'providerKey', 'id', 'title']) {
        final value = map[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
      return map.toString();
    }
    return item.toString();
  }

  void _addProvider(String label) {
    if (_selected.contains(label)) return;
    setState(() => _selected.add(label));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added $label to the workspace')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sections = [
      ('Database providers', _databaseProviders, Icons.storage_rounded),
      ('Storage providers', _storageProviders, Icons.cloud_queue_rounded),
      ('Logging providers', _loggingProviders, Icons.receipt_long_rounded),
    ];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Persistence',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Browse DartStream persistence providers and add the ones you want to your workspace.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        if (_error != null) ...[
          _Banner(message: _error!, isError: true),
          const SizedBox(height: 16),
        ],
        if (_selected.isNotEmpty) ...[
          Text('Selected providers', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _selected.map((item) => Chip(label: Text(item))).toList(),
          ),
          const SizedBox(height: 16),
        ],
        if (_loading)
          const LinearProgressIndicator(minHeight: 6)
        else
          ...sections.map(
            (section) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _ProviderCard(
                title: section.$1,
                icon: section.$3,
                items: section.$2,
                labelOf: _label,
                onAdd: _addProvider,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.title,
    required this.icon,
    required this.items,
    required this.labelOf,
    required this.onAdd,
  });

  final String title;
  final IconData icon;
  final List<dynamic> items;
  final String Function(dynamic) labelOf;
  final ValueChanged<String> onAdd;

  @override
  Widget build(BuildContext context) {
    final labels = items.map(labelOf).where((label) => label.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (labels.isEmpty)
            const Text('No providers returned.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: labels
                  .map(
                    (label) => InputChip(
                      label: Text(label),
                      onPressed: () => onAdd(label),
                      avatar: const Icon(Icons.add_rounded, size: 16),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
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
