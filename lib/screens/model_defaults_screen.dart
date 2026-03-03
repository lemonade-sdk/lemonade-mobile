import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/model_defaults_provider.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';

class ModelDefaultsScreen extends ConsumerWidget {
  const ModelDefaultsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final defaults = ref.watch(globalModelDefaultsProvider);
    final models = ref.watch(modelsProvider);

    final allModels = models.map((m) => m.id).toList();
    final audioModels = models.where((m) => m.supportsAudio).map((m) => m.id).toList();
    final ttsModels = models.where((m) => m.supportsTts).map((m) => m.id).toList();
    final imageGenModels = models.where((m) => m.supportsImageGeneration).map((m) => m.id).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Model Defaults'),
        actions: [
          TextButton(
            onPressed: () {
              ref.read(globalModelDefaultsProvider.notifier).resetAll();
            },
            child: const Text('Reset All'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Set default models for each type. These apply globally unless overridden per-chat.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          _ModelDefaultDropdown(
            label: 'LLM (Chat)',
            icon: Icons.chat,
            currentValue: defaults.llmModel,
            options: allModels,
            onChanged: (value) {
              ref.read(globalModelDefaultsProvider.notifier).setLlmModel(value);
            },
            onReset: () {
              ref.read(globalModelDefaultsProvider.notifier).setLlmModel(null);
            },
          ),
          const SizedBox(height: 16),
          _ModelDefaultDropdown(
            label: 'Audio-to-Text (Transcription)',
            icon: Icons.mic,
            currentValue: defaults.audioToTextModel,
            options: audioModels.isNotEmpty ? audioModels : allModels,
            emptyHint: audioModels.isEmpty ? 'No audio models detected — showing all' : null,
            onChanged: (value) {
              ref.read(globalModelDefaultsProvider.notifier).setAudioToTextModel(value);
            },
            onReset: () {
              ref.read(globalModelDefaultsProvider.notifier).setAudioToTextModel(null);
            },
          ),
          const SizedBox(height: 16),
          _ModelDefaultDropdown(
            label: 'Text-to-Audio (TTS)',
            icon: Icons.volume_up,
            currentValue: defaults.textToAudioModel,
            options: ttsModels.isNotEmpty ? ttsModels : allModels,
            emptyHint: ttsModels.isEmpty ? 'No TTS models detected — showing all' : null,
            onChanged: (value) {
              ref.read(globalModelDefaultsProvider.notifier).setTextToAudioModel(value);
            },
            onReset: () {
              ref.read(globalModelDefaultsProvider.notifier).setTextToAudioModel(null);
            },
          ),
          const SizedBox(height: 16),
          _ModelDefaultDropdown(
            label: 'Image Generation',
            icon: Icons.image,
            currentValue: defaults.imageGenerationModel,
            options: imageGenModels.isNotEmpty ? imageGenModels : allModels,
            emptyHint: imageGenModels.isEmpty ? 'No image gen models detected — showing all' : null,
            onChanged: (value) {
              ref.read(globalModelDefaultsProvider.notifier).setImageGenerationModel(value);
            },
            onReset: () {
              ref.read(globalModelDefaultsProvider.notifier).setImageGenerationModel(null);
            },
          ),
        ],
      ),
    );
  }
}

class _ModelDefaultDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String? currentValue;
  final List<String> options;
  final String? emptyHint;
  final ValueChanged<String?> onChanged;
  final VoidCallback onReset;

  const _ModelDefaultDropdown({
    required this.label,
    required this.icon,
    required this.currentValue,
    required this.options,
    this.emptyHint,
    required this.onChanged,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                if (currentValue != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Reset to Auto',
                    onPressed: onReset,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
            if (emptyHint != null) ...[
              const SizedBox(height: 4),
              Text(emptyHint!, style: TextStyle(fontSize: 12, color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: currentValue != null && options.contains(currentValue) ? currentValue : null,
              decoration: const InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              hint: const Text('Auto (first available)'),
              isExpanded: true,
              items: options.map((modelId) {
                return DropdownMenuItem(
                  value: modelId,
                  child: Text(modelId, overflow: TextOverflow.ellipsis),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
