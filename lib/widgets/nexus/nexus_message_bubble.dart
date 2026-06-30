import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/chat_message.dart';
import '../../providers/nav_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../inline_audio_player.dart';
import 'nexus_ui.dart';

/// Design-faithful chat bubble for the Nexus redesign. Renders text (markdown
/// for assistant), image cards (tap → lightbox), and inline audio, in the
/// design's bubble shapes/colors. Replaces the legacy MessageBubble.
class NexusMessageBubble extends ConsumerWidget {
  final ChatMessage message;
  const NexusMessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final isUser = message.isUser;
    final hasText = message.textContent.isNotEmpty;
    final hasImage = message.hasImages;
    final audios = message.audioContent.toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (hasImage)
            _imageCard(context, ref, message.imageContent!),
          if (hasImage && (hasText || audios.isNotEmpty))
            const SizedBox(height: 8),
          for (final src in audios) ...[
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.84),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.line),
                ),
                child: InlineAudioPlayer(source: src, color: t.accent2),
              ),
            ),
            const SizedBox(height: 6),
          ],
          if (hasText) _textBubble(context, isUser),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(_meta(),
                style: nexusMono(fontSize: 10, color: t.faint)),
          ),
        ],
      ),
    );
  }

  String _meta() {
    final d = message.timestamp;
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${message.isUser ? 'You' : 'Lemonade'} · $hh:$mm';
  }

  Widget _textBubble(BuildContext context, bool isUser) {
    final t = context.nexus;
    return GestureDetector(
      onLongPress: () => _copy(context),
      child: ConstrainedBox(
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: isUser ? t.accent : t.surface,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 5),
              bottomRight: Radius.circular(isUser ? 5 : 16),
            ),
            border: isUser ? null : Border.all(color: t.line),
          ),
          child: isUser
              ? Text(message.textContent,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 14.5, height: 1.5))
              : MarkdownBody(
                  data: message.textContent,
                  styleSheet: MarkdownStyleSheet(
                    p: TextStyle(color: t.text, fontSize: 14.5, height: 1.5),
                    a: TextStyle(color: t.accent2),
                    code: nexusMono(
                        fontSize: 13, color: t.accent2),
                    codeblockPadding: const EdgeInsets.all(12),
                    codeblockDecoration: BoxDecoration(
                      color: t.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.line2),
                    ),
                    blockquoteDecoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(8),
                      border: Border(
                          left: BorderSide(color: t.accent2, width: 3)),
                    ),
                    h1: TextStyle(
                        color: t.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w700),
                    h2: TextStyle(
                        color: t.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700),
                    h3: TextStyle(
                        color: t.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    listBullet:
                        TextStyle(color: t.text, fontSize: 14.5, height: 1.5),
                    tableBorder: TableBorder.all(color: t.line2),
                    tableHead:
                        TextStyle(color: t.text, fontWeight: FontWeight.w700),
                    tableBody: TextStyle(color: t.muted),
                  ),
                  onTapLink: (_, href, __) {},
                ),
        ),
      ),
    );
  }

  Widget _imageCard(BuildContext context, WidgetRef ref, String imageData) {
    final t = context.nexus;
    Widget img;
    final content = message.content.firstWhere(
      (c) => c.type == MessageContentType.image && c.value == imageData,
      orElse: () =>
          MessageContent(type: MessageContentType.image, value: imageData),
    );
    final bytes = content.getCachedImageBytes();

    if (bytes != null && bytes.isNotEmpty) {
      img = Image.memory(bytes, fit: BoxFit.cover);
    } else if (imageData.startsWith('http')) {
      img = Image.network(imageData, fit: BoxFit.cover);
    } else if (!imageData.startsWith('data:')) {
      img = Image.file(File(imageData), fit: BoxFit.cover);
    } else {
      img = Container(
        color: t.surface2,
        child: Icon(Icons.broken_image, color: t.faint, size: 36),
      );
    }

    return GestureDetector(
      onTap: () {
        if (bytes != null && bytes.isNotEmpty) {
          ref.read(overlayProvider.notifier).openLightbox(
              bytes: bytes, caption: message.textContent);
        }
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 240, maxHeight: 240),
          decoration: BoxDecoration(border: Border.all(color: t.line2)),
          child: img,
        ),
      ),
    );
  }

  void _copy(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.textContent));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied'), duration: Duration(seconds: 1)),
    );
  }
}
