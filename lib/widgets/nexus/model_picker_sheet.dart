import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/app_mode_provider.dart';
import '../../providers/models_provider.dart';
import '../../providers/servers_provider.dart';
import '../../themes/nexus_tokens.dart';
import 'nexus_ui.dart';

/// Searchable model / collection picker. Returns the chosen model id (or null
/// if dismissed). Used to set a conversation's model from the chat sub-header.
class ModelPickerSheet extends ConsumerStatefulWidget {
  final String? current;
  const ModelPickerSheet({super.key, this.current});

  static Future<String?> show(BuildContext context, {String? current}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ModelPickerSheet(current: current),
    );
  }

  @override
  ConsumerState<ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends ConsumerState<ModelPickerSheet> {
  final _query = TextEditingController();
  String _q = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Re-fetch from the server every time the picker opens — models
    // added/removed server-side otherwise only appeared after an app restart.
    Future.microtask(_refresh);
  }

  Future<void> _refresh() async {
    if (mounted) setState(() => _loading = true);
    try {
      await ref.read(modelsProvider.notifier).fetchModels();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    // Subscription is locked to the curated NXS* collections (the provider
    // already filters); explain that so the internal-looking names don't read
    // as someone else's data — a tester asked "are these your conversations?".
    final subscription =
        ref.watch(appModeProvider) == AppMode.subscription;
    // Subscription users pick from the curated NXS collections only — the
    // catalog also holds their raw component models (needed internally for
    // wire-model substitution and tool routing), which aren't chooseable.
    final models = subscription
        ? ref.watch(modelsProvider).where(isNxsCollection).toList()
        : ref.watch(modelsProvider);
    final filtered = _q.isEmpty
        ? models
        : models
            .where((m) => m.id.toLowerCase().contains(_q.toLowerCase()))
            .toList();
    final collections = filtered.where((m) => m.isCollection).toList();
    final plain = filtered.where((m) => !m.isCollection).toList();

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.78),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Conversation model',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
              const SizedBox(height: 4),
              Text(
                  subscription
                      ? 'AI collections included with your subscription — '
                        'pick one for this chat.'
                      : 'Pick the model / collection for this chat.',
                  style: TextStyle(fontSize: 12.5, color: t.muted)),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                autofocus: true,
                onChanged: (v) => setState(() => _q = v),
                style: TextStyle(fontSize: 14, color: t.text),
                decoration: InputDecoration(
                  hintText: 'Search models…',
                  prefixIcon: Icon(Icons.search, size: 18, color: t.faint),
                ),
              ),
              const SizedBox(height: 12),
              if (models.isEmpty)
                _emptyState(context)
              else if (filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('No models match “$_q”.',
                          style: TextStyle(color: t.muted))),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (plain.isNotEmpty) ...[
                        _sectionLabel(context, 'Models'),
                        for (final m in plain) _tile(context, m),
                      ],
                      if (collections.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _sectionLabel(
                            context,
                            subscription
                                ? 'Included with your plan'
                                : 'Collections'),
                        for (final m in collections) _tile(context, m),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Empty catalog: say WHY (no server, still loading, or the fetch error)
  /// and offer a retry, instead of a bare "No models on this server."
  Widget _emptyState(BuildContext context) {
    final t = context.nexus;
    final server = ref.watch(selectedServerProvider);
    final error = ref.watch(modelsFetchErrorProvider);
    final String message;
    if (server == null) {
      message = 'No server selected. Add or pick one under '
          'Settings → Manage servers.';
    } else if (_loading) {
      message = 'Loading models from “${server.name}”…';
    } else if (error != null) {
      message = error;
    } else {
      message = 'No models on “${server.name}”.';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (server != null && _loading)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Text(message,
              textAlign: TextAlign.center,
              style: TextStyle(color: error != null && !_loading
                  ? t.danger
                  : t.muted)),
          if (server != null && !_loading) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Retry'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, top: 4),
      child: Text(text.toUpperCase(),
          style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: t.faint)),
    );
  }

  Widget _tile(BuildContext context, ModelInfo m) {
    final t = context.nexus;
    final selected = m.id == widget.current;
    return InkWell(
      onTap: () => Navigator.of(context).pop(m.id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? t.accentSoft : t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? t.accent : t.line),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: nexusMono(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text)),
                const SizedBox(height: 2),
                Text(_caps(m),
                    style: TextStyle(fontSize: 10.5, color: t.muted)),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_circle, color: t.accent, size: 18),
        ]),
      ),
    );
  }

  String _caps(ModelInfo m) {
    final caps = <String>[];
    if (m.isCollection) caps.add('collection');
    if (m.supportsVision) caps.add('vision');
    if (m.supportsImageGeneration) caps.add('image-gen');
    if (m.supportsTts) caps.add('tts');
    if (m.supportsAudio) caps.add('audio');
    if (m.supportsThinking) caps.add('thinking');
    if (caps.isEmpty) caps.add('text');
    return caps.join(' · ');
  }
}
