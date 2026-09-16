import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/thinking_level.dart';
import '../providers/model_thinking_provider.dart';
import '../providers/models_provider.dart';

/// Per-model reasoning controls. Thinking is intentionally Off unless the
/// user opts a particular model into one of its supported effort levels.
class ModelThinkingScreen extends ConsumerWidget {
  const ModelThinkingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final levels = ref.watch(modelThinkingLevelsProvider);
    final models =
        ref
            .watch(modelsProvider)
            .where((m) => m.supportsThinking && !m.isCollection)
            .toList()
          ..sort((a, b) => a.id.toLowerCase().compareTo(b.id.toLowerCase()));

    return Scaffold(
      appBar: AppBar(title: const Text('Thinking levels')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          Text(
            'Thinking is off by default. Enable it only for models where you '
            'want deeper reasoning; higher levels can take longer and use more tokens.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (models.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No reasoning-capable models were found on the active server.',
                ),
              ),
            )
          else
            for (final model in models)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.psychology_outlined, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                model.id,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<ThinkingLevel>(
                          initialValue: levels[model.id] ?? ThinkingLevel.off,
                          decoration: const InputDecoration(
                            labelText: 'Reasoning effort',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          items: [
                            for (final level in ThinkingLevel.values)
                              DropdownMenuItem(
                                value: level,
                                child: Text(level.label),
                              ),
                          ],
                          onChanged: (level) {
                            if (level == null) return;
                            ref
                                .read(modelThinkingLevelsProvider.notifier)
                                .setLevel(model.id, level);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
