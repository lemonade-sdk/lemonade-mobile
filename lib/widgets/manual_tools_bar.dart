import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/types/tool_call.dart';
import '../models/chat_message.dart';
import '../omni/tool_executor.dart';
import '../providers/chat_history_provider.dart';
import '../providers/omni_router_provider.dart';

/// Manual fallback toolbar shown above the chat input when OmniRouter mode is
/// off. Lets the user explicitly invoke each multimodal capability without the
/// LLM deciding when to use it. Buttons are auto-disabled when their
/// corresponding model isn't loaded.
class ManualToolsBar extends ConsumerWidget {
  const ManualToolsBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final caps = ref.watch(omniCapabilitiesProvider);
    final exec = ref.watch(omniToolExecutorProvider);
    final scheme = Theme.of(context).colorScheme;

    final hasImageGen = caps?.has('generate_image') ?? false;
    final hasImageEdit = caps?.has('edit_image') ?? false;
    final hasTts = caps?.has('text_to_speech') ?? false;
    final hasAsr = caps?.has('transcribe_audio') ?? false;
    final hasVision = caps?.has('analyze_image') ?? false;

    final disabled = exec == null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _PillButton(
              icon: Icons.brush,
              label: 'Generate image',
              enabled: !disabled && hasImageGen,
              onTap: () => _runGenerateImage(context, ref),
            ),
            _PillButton(
              icon: Icons.auto_fix_high,
              label: 'Edit image',
              enabled: !disabled && hasImageEdit,
              onTap: () => _runEditImage(context, ref),
            ),
            _PillButton(
              icon: Icons.volume_up,
              label: 'Read aloud',
              enabled: !disabled && hasTts,
              onTap: () => _runTts(context, ref),
            ),
            _PillButton(
              icon: Icons.mic,
              label: 'Voice → text',
              enabled: !disabled && hasAsr,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text(
                    'Voice → text uses the dedicated transcription screen. '
                    'Open the menu and pick "Transcription".',
                  ),
                ));
              },
            ),
            _PillButton(
              icon: Icons.image_search,
              label: 'Analyze image',
              enabled: !disabled && hasVision,
              onTap: () => _runVision(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _runGenerateImage(BuildContext context, WidgetRef ref) async {
    final params = await _showImagePromptDialog(context, title: 'Generate image');
    if (params == null) return;
    await _executeAndAppend(
      context,
      ref,
      toolName: 'generate_image',
      args: {'prompt': params.prompt, 'size': params.size},
      includeUserNote: 'Generate: ${params.prompt}',
    );
  }

  Future<void> _runEditImage(BuildContext context, WidgetRef ref) async {
    final params = await _showImagePromptDialog(context, title: 'Edit image');
    if (params == null) return;
    await _executeAndAppend(
      context,
      ref,
      toolName: 'edit_image',
      args: {'prompt': params.prompt, 'size': params.size},
      includeUserNote: 'Edit: ${params.prompt}',
    );
  }

  Future<void> _runTts(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(chatHistoryProvider.notifier);
    final active = notifier.getActiveChat();
    final lastAssistant = active?.messages.reversed
        .firstWhere(
          (m) => m.isAssistant && m.textContent.isNotEmpty,
          orElse: () => ChatMessage.text(role: MessageRole.assistant, text: ''),
        );
    final text = await _showTextDialog(
      context,
      title: 'Read aloud',
      initial: lastAssistant?.textContent ?? '',
      placeholder: 'Text to speak…',
    );
    if (text == null || text.isEmpty) return;
    await _executeAndAppend(
      context,
      ref,
      toolName: 'text_to_speech',
      args: {'input': text, 'voice': 'af_heart'},
      includeUserNote: 'Speak: $text',
    );
  }

  Future<void> _runVision(BuildContext context, WidgetRef ref) async {
    final notifier = ref.read(chatHistoryProvider.notifier);
    final active = notifier.getActiveChat();
    final hasImage = (active?.messages.any((m) => m.hasImages)) ?? false;
    if (!hasImage) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Attach an image in the chat first, then tap Analyze image.'),
      ));
      return;
    }
    final question = await _showTextDialog(
      context,
      title: 'Analyze image',
      initial: '',
      placeholder: "What would you like to know? (or 'describe')",
    );
    if (question == null) return;
    await _executeAndAppend(
      context,
      ref,
      toolName: 'analyze_image',
      args: {'image_url': '', 'question': question.isEmpty ? 'describe' : question},
      includeUserNote: 'Analyze image: ${question.isEmpty ? "describe" : question}',
    );
  }

  /// Shared executor: runs the tool via the OmniToolExecutor (bypassing the
  /// agent loop) and appends a synthetic assistant message with the result.
  Future<void> _executeAndAppend(
    BuildContext context,
    WidgetRef ref, {
    required String toolName,
    required Map<String, dynamic> args,
    required String includeUserNote,
  }) async {
    final exec = ref.read(omniToolExecutorProvider);
    if (exec == null) return;
    final notifier = ref.read(chatHistoryProvider.notifier);
    final history = notifier.getActiveChat()?.messages ?? const <ChatMessage>[];

    // Build user-side context from the existing chat (last image / audio).
    final ctx = _buildContextFromHistory(history);

    final call = ToolCall(
      id: 'manual_${DateTime.now().microsecondsSinceEpoch}',
      name: toolName,
      argumentsJson: _encode(args),
    );

    // Persist a "manual call" user note so the chat reads sensibly.
    final userMsg = ChatMessage.text(role: MessageRole.user, text: includeUserNote);
    var nextMessages = [...history, userMsg];
    await notifier.updateActiveChat(nextMessages);

    // Show a thinking placeholder.
    final thinking = ChatMessage.text(role: MessageRole.assistant, text: 'Working…');
    nextMessages = [...nextMessages, thinking];
    await notifier.updateActiveChat(nextMessages);

    final result = await exec.execute(call, ctx);

    final finalContents = <MessageContent>[];
    switch (result) {
      case TextResult():
        finalContents.add(MessageContent(
            type: MessageContentType.text, value: result.text));
      case ImageResult():
        final dataUrl = 'data:${result.mime};base64,${result.base64Data}';
        finalContents.add(MessageContent(
            type: MessageContentType.image, value: dataUrl));
      case AudioResult():
        final dataUrl = 'data:${result.mime};base64,${result.base64Data}';
        finalContents.add(MessageContent(
            type: MessageContentType.audio, value: dataUrl));
      case ErrorResult():
        finalContents.add(MessageContent(
            type: MessageContentType.text, value: 'Error: ${result.message}'));
      case EndCallResult():
        // Manual tool bar isn't part of a voice call; nothing to do.
        break;
    }

    final finalMsg = ChatMessage(
      role: MessageRole.assistant,
      content: finalContents,
    );
    final updated = [
      ...nextMessages.sublist(0, nextMessages.length - 1),
      finalMsg,
    ];
    await notifier.updateActiveChat(updated);
  }

  ToolExecutionContext _buildContextFromHistory(List<ChatMessage> history) {
    final images = <({String dataUrl, String mime, String base64})>[];
    final priorArtifacts = <Artifact>[];
    for (final m in history) {
      for (final c in m.content) {
        if (c.type == MessageContentType.image && c.value.startsWith('data:image/')) {
          final mime = c.value.substring(5, c.value.indexOf(';'));
          final commaIdx = c.value.indexOf(',');
          final b64 = c.value.substring(commaIdx + 1);
          if (m.isUser) {
            images.add((dataUrl: c.value, mime: mime, base64: b64));
          } else {
            priorArtifacts.add(Artifact(
              kind: ArtifactKind.image,
              mime: mime,
              base64Data: b64,
            ));
          }
        }
      }
    }
    return ToolExecutionContext(
      extractedAudio: const [],
      extractedImages: images,
      sourceArtifacts: priorArtifacts,
      turnArtifacts: <Artifact>[],
    );
  }

  String _encode(Map<String, dynamic> args) {
    return args.entries
        .map((e) => '"${e.key}":${e.value is String ? '"${e.value}"' : e.value}')
        .toList()
        .join(',')
        .let((s) => '{$s}');
  }
}

extension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PillButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: Icon(icon, size: 18,
            color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4)),
        label: Text(label,
            style: TextStyle(
              color: enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.4),
            )),
        onPressed: enabled ? onTap : null,
        backgroundColor: scheme.surfaceContainerHigh,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.2)),
      ),
    );
  }
}

class _ImageDialogResult {
  final String prompt;
  final String size;
  _ImageDialogResult({required this.prompt, required this.size});
}

Future<_ImageDialogResult?> _showImagePromptDialog(
  BuildContext context, {
  required String title,
}) async {
  final controller = TextEditingController();
  String size = '512x512';
  return showDialog<_ImageDialogResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Prompt',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Size:'),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: size,
                  items: const [
                    DropdownMenuItem(value: '256x256', child: Text('256×256')),
                    DropdownMenuItem(value: '512x512', child: Text('512×512')),
                    DropdownMenuItem(value: '1024x1024', child: Text('1024×1024')),
                  ],
                  onChanged: (v) => setState(() => size = v ?? size),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, _ImageDialogResult(prompt: text, size: size));
            },
            child: const Text('Run'),
          ),
        ],
      ),
    ),
  );
}

Future<String?> _showTextDialog(
  BuildContext context, {
  required String title,
  required String initial,
  required String placeholder,
}) async {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 5,
        decoration: InputDecoration(
          hintText: placeholder,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () => Navigator.pop(ctx, controller.text),
          child: const Text('Run'),
        ),
      ],
    ),
  );
}
