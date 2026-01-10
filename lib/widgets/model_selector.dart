import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';
import 'package:lemonade_mobile/utils/model_utils.dart';

class ModelSelector extends ConsumerWidget {
  final bool compact; // For different display modes

  const ModelSelector({
    super.key,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedModel = ref.watch(selectedModelProvider);
    final availableModels = ref.watch(modelsProvider);

    if (compact) {
      // Compact version for app bar
      return Container(
        margin: const EdgeInsets.only(right: 8),
        child: PopupMenuButton<String>(
          onSelected: (modelId) {
            ref.read(selectedModelProvider.notifier).selectModel(modelId);
          },
          itemBuilder: (context) => availableModels.map((model) => PopupMenuItem(
            value: model.id,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(model.id, style: const TextStyle(fontWeight: FontWeight.w500)),
                      Builder(
                        builder: (context) {
                          final capabilities = model.capabilities;
                          final List<String> capabilityNames = [];

                          if (capabilities.contains(ModelCapabilities.vision)) {
                            capabilityNames.add('Vision');
                          }
                          if (capabilities.contains(ModelCapabilities.imageGeneration)) {
                            capabilityNames.add('Image Gen');
                          }
                          if (capabilities.contains(ModelCapabilities.thinking)) {
                            capabilityNames.add('Thinking');
                          }
                          if (capabilities.contains(ModelCapabilities.textOnly) && capabilities.length == 1) {
                            capabilityNames.add('Text Only');
                          }

                          final text = capabilityNames.isEmpty ? 'Text Only' : capabilityNames.join(' + ');
                          return Text(
                            text,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                ModelUtils.buildCapabilityIcon(model.capabilities),
              ],
            ),
          )).toList(),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(
                  selectedModel ?? 'Select Model',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.arrow_drop_down,
                  size: 18,
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // Full version for drawer
      return ExpansionTile(
        title: const Text('Model'),
        subtitle: Text(selectedModel ?? 'Select a model'),
        onExpansionChanged: (expanded) {
          if (expanded && availableModels.isEmpty) {
            // Fetch models when expanding if we don't have them yet
            ref.read(modelsProvider.notifier).fetchModels();
          }
        },
        children: [
          if (availableModels.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Loading models...'),
            )
          else
            ...availableModels.map((modelInfo) => ListTile(
                  title: Row(
                    children: [
                      Expanded(child: Text(modelInfo.id)),
                      ModelUtils.buildCapabilityIcon(modelInfo.capabilities),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ModelUtils.buildCapabilityText(modelInfo.capabilities),
                      const SizedBox(height: 4),
                      ModelUtils.buildLabelTags(modelInfo.labels),
                    ],
                  ),
                  selected: modelInfo.id == selectedModel,
                  onTap: () {
                    ref.read(selectedModelProvider.notifier).selectModel(modelInfo.id);
                    if (!compact) {
                      Navigator.pop(context); // Close drawer when selecting model
                    }
                  },
                )),
        ],
      );
    }
  }
}
