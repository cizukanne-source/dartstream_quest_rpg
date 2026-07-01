import 'package:flutter/material.dart';

/// Reusable list + create + delete card for a backend resource.
///
/// The screen using this widget decides which persistence endpoints to call;
/// this widget only handles loading, form state, and surfacing backend errors
/// in SnackBars.
class ResourceCrudSection extends StatefulWidget {
  const ResourceCrudSection({
    super.key,
    required this.title,
    required this.inputLabel,
    required this.fetch,
    required this.onCreate,
    required this.onDelete,
    required this.titleOf,
  });

  final String title;
  final String inputLabel;
  final Future<List<dynamic>> Function() fetch;
  final Future<void> Function(String input) onCreate;
  final Future<void> Function(Map<String, dynamic> item) onDelete;
  final String Function(Map item) titleOf;

  @override
  State<ResourceCrudSection> createState() => _ResourceCrudSectionState();
}

class _ResourceCrudSectionState extends State<ResourceCrudSection> {
  bool _loading = true;
  bool _busy = false;
  List<dynamic> _items = const [];
  final _input = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final items = await widget.fetch();
      if (mounted) {
        setState(() {
          _items = items;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _snack('${widget.title}: load failed - $e', error: true);
    }
  }

  Future<void> _create() async {
    final value = _input.text.trim();
    if (value.isEmpty) return;
    setState(() => _busy = true);
    try {
      await widget.onCreate(value);
      _input.clear();
      _snack('${widget.title}: created "$value".');
      await _load();
    } catch (e) {
      _snack('${widget.title}: create failed - $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    setState(() => _busy = true);
    try {
      await widget.onDelete(item);
      _snack('${widget.title}: deleted.');
      await _load();
    } catch (e) {
      _snack('${widget.title}: delete failed - $e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.title} (${_items.length})',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: widget.inputLabel,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onSubmitted: (_) => _create(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _busy ? null : _create,
                  child: const Text('Add'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_items.isEmpty)
              const Text('(none)')
            else
              for (final item in _items)
                if (item is Map<String, dynamic>)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(widget.titleOf(item)),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _busy ? null : () => _delete(item),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
