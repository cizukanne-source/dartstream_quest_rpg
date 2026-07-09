import 'dart:async';

import 'package:flutter/material.dart';
import 'package:openfeature_provider_intellitoggle/openfeature_provider_intellitoggle.dart';

import 'intellitoggle.dart';

class ItFlagAware extends StatefulWidget {
  const ItFlagAware({
    super.key,
    required this.flagKey,
    required this.onChild,
    this.offChild,
    this.defaultValue = false,
  });

  final String flagKey;
  final Widget onChild;
  final Widget? offChild;
  final bool defaultValue;

  @override
  State<ItFlagAware> createState() => _ItFlagAwareState();
}

class _ItFlagAwareState extends State<ItFlagAware> {
  bool? _value;
  StreamSubscription<IntelliToggleEvent>? _eventsSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _subscribeToLiveUpdates();
    _evaluate();
  }

  @override
  void didUpdateWidget(ItFlagAware oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flagKey != widget.flagKey) _evaluate();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _subscribeToLiveUpdates() {
    _eventsSub = IntelliToggle.instance.events.listen((event) {
      if (!mounted) return;
      if (event.type == IntelliToggleEventType.configurationChanged ||
          event.type == IntelliToggleEventType.ready) {
        _evaluate();
      }
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _evaluate();
    });
  }

  Future<void> _evaluate() async {
    try {
      final res = await IntelliToggle.instance.getBoolean(
        widget.flagKey,
        defaultValue: widget.defaultValue,
      );
      if (mounted) setState(() => _value = res.value);
    } catch (_) {
      if (mounted) setState(() => _value = widget.defaultValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_value == null) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return _value! ? widget.onChild : (widget.offChild ?? const SizedBox.shrink());
  }
}

class ItExperiment extends StatefulWidget {
  const ItExperiment({
    super.key,
    required this.flagKey,
    required this.variants,
    required this.defaultVariant,
  });

  final String flagKey;
  final Map<String, Widget> variants;
  final String defaultVariant;

  @override
  State<ItExperiment> createState() => _ItExperimentState();
}

class _ItExperimentState extends State<ItExperiment> {
  String? _variant;
  StreamSubscription<IntelliToggleEvent>? _eventsSub;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _subscribeToLiveUpdates();
    _evaluate();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _subscribeToLiveUpdates() {
    _eventsSub = IntelliToggle.instance.events.listen((event) {
      if (!mounted) return;
      if (event.type == IntelliToggleEventType.configurationChanged ||
          event.type == IntelliToggleEventType.ready) {
        _evaluate();
      }
    });
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _evaluate();
    });
  }

  Future<void> _evaluate() async {
    try {
      final res = await IntelliToggle.instance.getString(
        widget.flagKey,
        defaultValue: widget.defaultVariant,
      );
      final v = widget.variants.containsKey(res.value)
          ? res.value
          : widget.defaultVariant;
      if (mounted) setState(() => _variant = v);
    } catch (_) {
      if (mounted) setState(() => _variant = widget.defaultVariant);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_variant == null) {
      return const SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return widget.variants[_variant] ??
        widget.variants[widget.defaultVariant] ??
        const SizedBox.shrink();
  }
}
