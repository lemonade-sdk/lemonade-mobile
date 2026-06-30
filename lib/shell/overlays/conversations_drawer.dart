import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_history.dart';
import '../../providers/chat_history_provider.dart';
import '../../providers/nav_provider.dart';
import '../../themes/nexus_tokens.dart';

/// Left slide-in conversations list. Wired to [chatHistoryProvider].
class ConversationsDrawer extends ConsumerWidget {
  const ConversationsDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final chats = ref.watch(chatHistoryProvider);
    final active = ref.watch(activeChatProvider);
    final close = ref.read(overlayProvider.notifier).close;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: close,
            child: Container(color: Colors.black.withValues(alpha: 0.6)),
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: _Slide(
            child: Container(
              width: MediaQuery.of(context).size.width * 0.82,
              decoration: BoxDecoration(
                color: t.bg2,
                border: Border(right: BorderSide(color: t.line2)),
              ),
              child: SafeArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                      child: Row(children: [
                        Expanded(
                          child: Text('Conversations',
                              style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                  color: t.text)),
                        ),
                        GestureDetector(
                          onTap: () {
                            ref
                                .read(chatHistoryProvider.notifier)
                                .createNewChat();
                            close();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                                color: t.accent,
                                borderRadius: BorderRadius.circular(11)),
                            child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.add, size: 14, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text('New',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white)),
                                ]),
                          ),
                        ),
                      ]),
                    ),
                    Expanded(
                      child: chats.isEmpty
                          ? Center(
                              child: Text('No conversations yet.',
                                  style:
                                      TextStyle(fontSize: 13, color: t.muted)))
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                              itemCount: chats.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 8),
                              itemBuilder: (_, i) => _tile(
                                  context, ref, chats[i],
                                  isActive: chats[i].id == active?.id,
                                  onTap: () {
                                    ref
                                        .read(chatHistoryProvider.notifier)
                                        .loadChat(chats[i].id);
                                    close();
                                  }),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, ChatHistory c,
      {required bool isActive, required VoidCallback onTap}) {
    final t = context.nexus;
    final snippet =
        c.messages.isNotEmpty ? c.messages.last.textContent : 'Empty chat';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? t.accentSoft : t.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: isActive ? t.accent : t.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(c.title.isEmpty ? 'New chat' : c.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: isActive ? t.accent2 : t.text)),
            const SizedBox(height: 3),
            Text(snippet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: t.muted)),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatefulWidget {
  final Widget child;
  const _Slide({required this.child});
  @override
  State<_Slide> createState() => _SlideState();
}

class _SlideState extends State<_Slide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: Tween(begin: const Offset(-1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic)),
      child: widget.child,
    );
  }
}
