import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../providers/chat_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../voice_input_sheet.dart';

/// Design-faithful chat composer: attach (+), input pill with inline mic, and a
/// send button. Wires to the existing `chatProvider.sendMessage`. Replaces the
/// legacy ChatInput on the Chat tab.
class NexusComposer extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  const NexusComposer({super.key, this.scrollController});

  @override
  ConsumerState<NexusComposer> createState() => _NexusComposerState();
}

class _NexusComposerState extends ConsumerState<NexusComposer> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  final _picker = ImagePicker();
  final List<String> _attached = [];

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _attach() async {
    try {
      final picked = await _picker.pickImage(source: ImageSource.gallery);
      if (picked != null) setState(() => _attached.add(picked.path));
    } catch (_) {}
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty && _attached.isEmpty) return;
    ref.read(chatProvider.notifier).sendMessage(
          text,
          imagePaths: _attached.isEmpty ? null : List.of(_attached),
          scrollController: widget.scrollController,
        );
    _controller.clear();
    setState(() => _attached.clear());
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Container(
      color: t.bg,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_attached.isNotEmpty)
            SizedBox(
              height: 64,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _attached.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(File(_attached[i]),
                                width: 56, height: 56, fit: BoxFit.cover),
                          ),
                          Positioned(
                            top: -4,
                            right: -4,
                            child: GestureDetector(
                              onTap: () =>
                                  setState(() => _attached.removeAt(i)),
                              child: Container(
                                decoration: BoxDecoration(
                                    color: t.bg2,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: t.line2)),
                                child: Icon(Icons.close,
                                    size: 14, color: t.muted),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _squareButton(
                context,
                icon: Icons.add,
                bg: t.surface,
                border: t.line2,
                iconColor: t.muted,
                onTap: _attach,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: t.line2),
                  ),
                  padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focus,
                          minLines: 1,
                          maxLines: 5,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          style: TextStyle(fontSize: 14.5, color: t.text),
                          decoration: InputDecoration(
                            isCollapsed: true,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 11),
                            hintText: 'Message Lemonade…',
                            hintStyle: TextStyle(color: t.faint, fontSize: 14.5),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => VoiceInputSheet.show(context,
                            chatScrollController: widget.scrollController),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(Icons.mic_none,
                              size: 20, color: t.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _send,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.accent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: t.accent.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: const Icon(Icons.send, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _squareButton(BuildContext context,
      {required IconData icon,
      required Color bg,
      required Color border,
      required Color iconColor,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
    );
  }
}
