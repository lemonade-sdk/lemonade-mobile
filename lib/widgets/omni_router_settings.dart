import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../omni/omni_workflow.dart';
import '../providers/model_defaults_provider.dart';
import '../providers/model_downloads_provider.dart';
import '../providers/models_provider.dart';
import '../providers/omni_router_provider.dart';

/// Settings panel for OmniRouter mode. The user picks one of three workflows
/// at the top — Custom, Lite, Ultra — and the body shows that workflow's
/// four model slots: text generation (LLM), image generation, text-to-speech,
/// and transcription. Lite and Ultra mirror the server-side downloadable
/// Collections and are read-only; Custom lets the user pick any installed
/// model per slot, and the picks survive across workflow switches.
///
/// Each template slot also exposes the same install controls the admin
/// Models tab uses — Installed pill, Download button, progress bar — so the
/// user can pull missing components without leaving the OmniRouter screen.
///
/// When the toggle is off, the chat falls back to plain streaming and the
/// chat input shows the manual fallback toolbar (see ChatInput).
class OmniRouterSettings extends ConsumerWidget {
  const OmniRouterSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(omniRouterEnabledProvider);
    final caps = ref.watch(omniCapabilitiesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.hub, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Lemonade Omni',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Switch(
              value: enabled,
              onChanged: (v) => ref
                  .read(omniRouterEnabledProvider.notifier)
                  .setEnabled(v),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          enabled
              ? 'On — the LLM drives multimodal tools automatically (image gen, TTS, ASR, vision).'
              : 'Off — plain text chat. Use the toolbar buttons in the chat input for image gen, TTS, etc.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (enabled) ...[
          const SizedBox(height: 20),
          Text('Workflow', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          const _WorkflowPicker(),
          const SizedBox(height: 16),
          if (caps != null && !caps.llmSupportsToolCalling)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _Note(
                'The selected LLM does not advertise the "tool-calling" label. '
                'Lemonade Omni will refuse multi-tool calls. Pick a tool-calling LLM, or turn Lemonade Omni off.',
                tone: _NoteTone.warn,
              ),
            ),
          const _WorkflowSlots(),
        ],
      ],
    );
  }
}

class _WorkflowPicker extends ConsumerWidget {
  const _WorkflowPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Pull whatever Omni Collections (recipe == 'collection.omni') are actually
    // installed on this server, by ID. Previously this picker hard-coded
    // "Lite" and "Ultra" with fixed model names — but servers freely name
    // their Omni Collections (e.g. "LMX-Omni-…"), so the static list was
    // useless for anything but the canonical server build.
    final installed = ref.watch(modelsProvider);
    final collections =
        installed.where((m) => m.isCollection).toList(growable: false);
    final selectedId = ref.watch(selectedModelProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // "Custom" — no Collection, free per-tool model picks via globalModelDefaults.
        _CustomWorkflowTile(
          selected: selectedId == null ||
              !collections.any((c) => c.id == selectedId),
          onTap: () {
            // Clearing the selection drops us out of any Collection-driven
            // workflow. The user can then pick any chat-shaped LLM from
            // the chat header model picker.
            ref.read(selectedModelProvider.notifier).clearSelection();
          },
        ),
        const SizedBox(height: 6),
        if (collections.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'No Omni Collections installed on this server. Install one '
              'from the Admin Console → Models tab (look for any model whose '
              'recipe is "collection.omni"), or stay on Custom and pick '
              'per-tool models below.',
              style: theme.textTheme.bodySmall,
            ),
          )
        else
          for (final c in collections)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _CollectionWorkflowTile(
                collection: c,
                selected: selectedId == c.id,
                onTap: () => ref
                    .read(selectedModelProvider.notifier)
                    .selectModel(c.id),
              ),
            ),
      ],
    );
  }
}

/// "Custom" workflow row — uses the per-tool dropdowns instead of an Omni
/// Collection. Picking it clears any selected Collection so the chat falls
/// back to the user's manually configured slots.
class _CustomWorkflowTile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  const _CustomWorkflowTile({required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _WorkflowTile(
      icon: Icons.tune,
      title: 'Custom',
      subtitle:
          'Pick your own LLM + image / TTS / ASR models from the dropdowns below.',
      selected: selected,
      onTap: onTap,
      theme: theme,
    );
  }
}

/// One row per installed Omni Collection. Shows the collection's ID and its
/// component count; tapping selects it as the active chat model.
class _CollectionWorkflowTile extends StatelessWidget {
  final ModelInfo collection;
  final bool selected;
  final VoidCallback onTap;
  const _CollectionWorkflowTile({
    required this.collection,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = collection.compositeModels.length;
    return _WorkflowTile(
      icon: Icons.auto_awesome,
      title: collection.id,
      subtitle: n == 0
          ? 'Omni Collection (components unknown).'
          : 'Omni Collection · $n component model${n == 1 ? "" : "s"}',
      selected: selected,
      onTap: onTap,
      theme: theme,
    );
  }
}

class _WorkflowTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final ThemeData theme;
  const _WorkflowTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.5)
              : scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.6)
                : scheme.outline.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_circle, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _WorkflowSlots extends ConsumerWidget {
  const _WorkflowSlots();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workflow = ref.watch(activeOmniWorkflowProvider);
    final installed = ref.watch(modelsProvider);
    final defaults = ref.watch(globalModelDefaultsProvider);

    if (workflow.isTemplate) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TemplateSummary(workflow: workflow),
          const SizedBox(height: 12),
          _TemplateSlot(
            label: 'Text generation',
            modelId: workflow.llmModel,
            isInstalled: _idInstalled(installed, workflow.llmModel),
          ),
          const SizedBox(height: 8),
          _TemplateSlot(
            label: 'Image generation',
            modelId: workflow.imageGenModel,
            isInstalled: _idInstalled(installed, workflow.imageGenModel),
          ),
          const SizedBox(height: 8),
          _TemplateSlot(
            label: 'Text-to-speech',
            modelId: workflow.ttsModel,
            isInstalled: _idInstalled(installed, workflow.ttsModel),
          ),
          const SizedBox(height: 8),
          _TemplateSlot(
            label: 'Transcription',
            modelId: workflow.asrModel,
            isInstalled: _idInstalled(installed, workflow.asrModel),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pick the model for each capability. Empty = let Lemonade Omni pick the first installed match.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        // Custom LLM dropdown reads/writes selectedModelProvider — same one
        // the chat header is bound to — so changing it here also flips the
        // model the chat actually sends to.
        _CustomLlmSlot(),
        const SizedBox(height: 8),
        _CustomSlot(
          label: 'Image generation',
          requiredLabels: const ['image'],
          currentValue: defaults.imageGenerationModel,
          onChanged: (v) => ref
              .read(globalModelDefaultsProvider.notifier)
              .setImageGenerationModel(v),
        ),
        const SizedBox(height: 8),
        _CustomSlot(
          label: 'Text-to-speech',
          requiredLabels: const ['tts', 'speech'],
          currentValue: defaults.textToAudioModel,
          onChanged: (v) => ref
              .read(globalModelDefaultsProvider.notifier)
              .setTextToAudioModel(v),
        ),
        const SizedBox(height: 8),
        _CustomSlot(
          label: 'Transcription',
          requiredLabels: const ['audio', 'transcription'],
          currentValue: defaults.audioToTextModel,
          onChanged: (v) => ref
              .read(globalModelDefaultsProvider.notifier)
              .setAudioToTextModel(v),
        ),
      ],
    );
  }

  bool _idInstalled(List<ModelInfo> installed, String? id) {
    if (id == null) return false;
    return installed.any((m) => m.id == id);
  }
}

class _TemplateSummary extends StatelessWidget {
  final OmniWorkflow workflow;
  const _TemplateSummary({required this.workflow});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = workflow.kind == OmniWorkflowKind.lite
        ? 'Mirrors the server\'s "Lite Collection" — small, fast models.'
        : 'Mirrors the server\'s "Ultra Collection" — top-tier capability, large download.';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Read-only display of a template-recommended model, plus the same
/// Installed pill / Download button / progress bar that the admin Models
/// tab shows. Lets the user pull missing components without bouncing over
/// to the admin console.
///
/// Download progress comes from `modelDownloadsProvider`, which lives above
/// the navigator — so the bar keeps moving even if the user leaves and
/// comes back to this screen mid-pull.
class _TemplateSlot extends ConsumerWidget {
  final String label;
  final String? modelId;
  final bool isInstalled;

  const _TemplateSlot({
    required this.label,
    required this.modelId,
    required this.isInstalled,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(modelDownloadsProvider);
    final id = modelId;
    final entry = id == null ? null : downloads.active[id];
    final downloading = entry != null;
    final progress = entry?.progress;

    ref.listen<ModelDownloadsState>(modelDownloadsProvider, (prev, next) {
      if (id == null) return;
      final wasActive = prev?.active.containsKey(id) ?? false;
      final nowActive = next.active.containsKey(id);
      if (!wasActive || nowActive) return;
      final fin = next.finished[id];
      if (fin?.error != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: ${fin!.error}')),
        );
      }
      ref.read(modelsProvider.notifier).fetchModels();
    });

    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: 2),
                    Text(
                      id ?? '—',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _trailing(
                context: context,
                ref: ref,
                downloading: downloading,
              ),
            ],
          ),
          if (downloading)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(child: LinearProgressIndicator(value: progress)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      progress == null
                          ? '…'
                          : '${(progress * 100).toStringAsFixed(0)}%',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _trailing({
    required BuildContext context,
    required WidgetRef ref,
    required bool downloading,
  }) {
    if (downloading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    if (modelId == null) {
      return const _StatusPill(text: 'No model', color: Colors.grey);
    }
    if (isInstalled) {
      return const _StatusPill(text: 'Installed', color: Colors.green);
    }
    return TextButton.icon(
      onPressed: () => ref
          .read(modelDownloadsProvider.notifier)
          .start(modelId!),
      icon: const Icon(Icons.download, size: 18),
      label: const Text('Download'),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Custom-workflow LLM picker. Bound to selectedModelProvider so it's the
/// same model the chat header uses — there's only ever one chat LLM.
class _CustomLlmSlot extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allModels = ref.watch(modelsProvider);
    final selected = ref.watch(selectedModelProvider);

    // Show models that look chat-shaped: not pure image / TTS / ASR.
    final candidates = allModels
        .where((m) =>
            !m.supportsTts &&
            !m.supportsAudio &&
            !m.supportsImageGeneration)
        .toList(growable: false);

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Text generation',
            style: Theme.of(context).textTheme.bodyMedium),
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
              value: candidates.any((m) => m.id == selected) ? selected : null,
              hint: Text(
                candidates.isEmpty
                    ? 'No chat models installed'
                    : 'Pick a chat model',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              items: [
                for (final m in candidates)
                  DropdownMenuItem<String?>(
                    value: m.id,
                    child: Text(m.id, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: candidates.isEmpty
                  ? null
                  : (v) {
                      if (v != null) {
                        ref.read(selectedModelProvider.notifier).selectModel(v);
                      }
                    },
            ),
          ),
        ),
      ],
    );
  }
}

class _CustomSlot extends ConsumerWidget {
  final String label;
  final List<String> requiredLabels;
  final String? currentValue;
  final void Function(String?) onChanged;

  const _CustomSlot({
    required this.label,
    required this.requiredLabels,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allModels = ref.watch(modelsProvider);
    final wanted = requiredLabels.toSet();
    final candidates = allModels
        .where((m) => m.labels.any(wanted.contains))
        .toList(growable: false);

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
              value: candidates.any((m) => m.id == currentValue)
                  ? currentValue
                  : null,
              hint: Text(
                candidates.isEmpty
                    ? 'No matching model installed'
                    : 'Auto (first matching)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Auto'),
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

enum _NoteTone { info, warn }

class _Note extends StatelessWidget {
  final String text;
  final _NoteTone tone;
  const _Note(this.text, {this.tone = _NoteTone.info});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = tone == _NoteTone.warn
        ? scheme.errorContainer
        : scheme.surfaceContainer;
    final fg = tone == _NoteTone.warn
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            tone == _NoteTone.warn ? Icons.warning_amber : Icons.info_outline,
            color: fg,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
