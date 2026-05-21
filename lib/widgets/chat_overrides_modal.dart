import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/chat_history.dart';
import '../models/model_defaults.dart';
import '../providers/chat_history_provider.dart';
import '../providers/models_provider.dart';

/// Per-chat model override editor. Replaces the old "copy / paste settings via
/// clipboard" hack with a real modal dialog: pick LLM / ASR / TTS / image-gen
/// models for *this* chat, leaving the global defaults alone.
class ChatOverridesModal extends ConsumerStatefulWidget {
  final ChatHistory chat;
  const ChatOverridesModal({super.key, required this.chat});

  @override
  ConsumerState<ChatOverridesModal> createState() => _ChatOverridesModalState();

  static Future<void> show(BuildContext context, ChatHistory chat) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChatOverridesModal(chat: chat),
    );
  }
}

class _ChatOverridesModalState extends ConsumerState<ChatOverridesModal> {
  String? _llm;
  String? _asr;
  String? _tts;
  String? _imageGen;

  @override
  void initState() {
    super.initState();
    final o = widget.chat.modelOverrides;
    _llm = o?.llmModel;
    _asr = o?.audioToTextModel;
    _tts = o?.textToAudioModel;
    _imageGen = o?.imageGenerationModel;
  }

  Future<void> _save() async {
    final overrides = ModelDefaults(
      llmModel: _llm,
      audioToTextModel: _asr,
      textToAudioModel: _tts,
      imageGenerationModel: _imageGen,
    );
    final empty = overrides.isEmpty;
    await ref
        .read(chatHistoryProvider.notifier)
        .updateChatOverrides(widget.chat.id, empty ? null : overrides);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final allModels = ref.watch(modelsProvider);

    return AlertDialog(
      title: Text('Overrides for "${widget.chat.displayTitle}"'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Each row falls back to the global default when "Auto" is selected.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            _ModelDropdown(
              label: 'LLM (chat)',
              models: allModels,
              filter: (m) => !m.supportsTts && !m.supportsAudio && !m.supportsImageGeneration,
              value: _llm,
              onChanged: (v) => setState(() => _llm = v),
            ),
            const SizedBox(height: 8),
            _ModelDropdown(
              label: 'Speech → text',
              models: allModels,
              filter: (m) => m.supportsAudio,
              value: _asr,
              onChanged: (v) => setState(() => _asr = v),
            ),
            const SizedBox(height: 8),
            _ModelDropdown(
              label: 'Text → speech',
              models: allModels,
              filter: (m) => m.supportsTts,
              value: _tts,
              onChanged: (v) => setState(() => _tts = v),
            ),
            const SizedBox(height: 8),
            _ModelDropdown(
              label: 'Image generation',
              models: allModels,
              filter: (m) => m.supportsImageGeneration,
              value: _imageGen,
              onChanged: (v) => setState(() => _imageGen = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _llm = null;
              _asr = null;
              _tts = null;
              _imageGen = null;
            });
          },
          child: const Text('Reset all'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _ModelDropdown extends StatelessWidget {
  final String label;
  final List<ModelInfo> models;
  final bool Function(ModelInfo) filter;
  final String? value;
  final void Function(String?) onChanged;

  const _ModelDropdown({
    required this.label,
    required this.models,
    required this.filter,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final candidates = models.where(filter).toList(growable: false);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: scheme.outline.withValues(alpha: 0.3)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              isExpanded: true,
              value: candidates.any((m) => m.id == value) ? value : null,
              hint: Text(
                candidates.isEmpty ? 'No matching model loaded' : 'Auto',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Auto (use global default)'),
                ),
                for (final m in candidates)
                  DropdownMenuItem<String?>(
                    value: m.id,
                    child: Text(m.id, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: candidates.isEmpty ? null : onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
