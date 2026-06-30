import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/model_defaults.dart';
import '../../providers/chat_history_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/models_provider.dart';
import '../../providers/nav_provider.dart';
import '../../screens/talk_screen.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/model_picker_sheet.dart';
import '../../widgets/nexus/nexus_composer.dart';
import '../../widgets/nexus/nexus_message_bubble.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Chat tab. Wraps the existing chat engine (chatProvider + ChatInput +
/// MessageBubble) in the redesign's sub-header + composer chrome. All send /
/// stream / omni-tool logic is reused unchanged.
class ChatTab extends ConsumerStatefulWidget {
  const ChatTab({super.key});

  @override
  ConsumerState<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<ChatTab> {
  final ScrollController _scroll = ScrollController();

  static const _suggestions = [
    'Summarize my day',
    'Draft a follow-up email',
    'Generate an image of…',
    'Explain this code',
  ];

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Open the searchable model picker and remember the choice for this chat.
  Future<void> _pickModel() async {
    final current = ref.read(selectedModelProvider);
    final picked = await ModelPickerSheet.show(context, current: current);
    if (picked == null || picked == current) return;
    await ref.read(selectedModelProvider.notifier).selectModel(picked);
    // Persist the model per-conversation so switching chats restores it.
    final active = ref.read(activeChatProvider);
    if (active != null) {
      final base = active.modelOverrides ?? const ModelDefaults();
      await ref
          .read(chatHistoryProvider.notifier)
          .updateChatOverrides(active.id, base.copyWith(llmModel: picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final messages = ref.watch(chatProvider);
    final model = ref.watch(selectedModelProvider) ?? 'No model';

    // Restore each conversation's own model when switching chats.
    ref.listen(activeChatProvider, (_, next) {
      final ov = next?.modelOverrides?.llmModel;
      if (ov != null && ov.isNotEmpty && ov != ref.read(selectedModelProvider)) {
        ref.read(selectedModelProvider.notifier).selectModel(ov);
      }
    });

    return Container(
      color: t.bg,
      child: Column(
        children: [
          _subHeader(context, model),
          Expanded(
            child: messages.isEmpty
                ? _empty(context)
                : NotificationListener<ScrollNotification>(
                    onNotification: (_) {
                      FocusManager.instance.primaryFocus?.unfocus();
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.only(top: 8, bottom: 12),
                      itemCount: messages.length,
                      itemBuilder: (_, i) =>
                          NexusMessageBubble(message: messages[i]),
                    ),
                  ),
          ),
          NexusComposer(scrollController: _scroll),
        ],
      ),
    );
  }

  Widget _subHeader(BuildContext context, String model) {
    final t = context.nexus;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(
        children: [
          NexusIconButton(
            icon: Icons.menu,
            onTap: () => ref.read(overlayProvider.notifier).openConversations(),
          ),
          Expanded(
            child: GestureDetector(
              onTap: _pickModel,
              behavior: HitTestBehavior.opaque,
              child: Column(
                children: [
                  Text('Chat',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: t.text)),
                  const SizedBox(height: 2),
                  // Tappable model/collection chip — opens the searchable picker.
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: t.line),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: nexusMono(fontSize: 9.5, color: t.muted)),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.expand_more, size: 13, color: t.faint),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          NexusIconButton(
            icon: Icons.call_outlined,
            iconColor: t.accent,
            // Reuses the existing fully-wired duplex voice session screen.
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TalkScreen())),
          ),
          const SizedBox(width: 8),
          NexusIconButton(
            icon: Icons.add,
            iconColor: t.accent,
            onTap: () => ref.read(chatProvider.notifier).clearChat(),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final t = context.nexus;
    return Column(
      children: [
        Expanded(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LemonLogo(size: 44),
                  const SizedBox(height: 16),
                  Text('Message Lemonade',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: t.text)),
                  const SizedBox(height: 6),
                  Text('Ask anything, generate images, or use / for commands.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
                ],
              ),
            ),
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final s in _suggestions)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref
                        .read(chatProvider.notifier)
                        .sendMessage(s, scrollController: _scroll),
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
                      decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: t.line2),
                      ),
                      child: Text(s,
                          style: TextStyle(fontSize: 12.5, color: t.muted)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}
