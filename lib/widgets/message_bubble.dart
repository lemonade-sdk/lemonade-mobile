import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:lemonade_mobile/models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.content));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Message copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _copyMessage(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: isUser ? const Radius.circular(20) : const Radius.circular(6),
              bottomRight: isUser ? const Radius.circular(6) : const Radius.circular(20),
            ),
            boxShadow: [
              BoxShadow(
                color: theme.shadowColor.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MarkdownBody(
                data: message.content,
                styleSheet: MarkdownStyleSheet(
                  p: TextStyle(
                    color: isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontSize: 16,
                    height: 1.4,
                  ),
                  code: TextStyle(
                    color: isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                    fontFamily: 'monospace',
                    fontSize: 14,
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                builders: {
                  'code': CodeBlockBuilder(
                    isUser: isUser,
                    isDark: isDark,
                    onCopyCode: (code) => _copyCode(context, code),
                  ),
                },
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.copy,
                    size: 12,
                    color: (isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface).withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Long press to copy',
                    style: TextStyle(
                      fontSize: 10,
                      color: (isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface).withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Code copied to clipboard'),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ),
    );
  }

class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isUser;
  final bool isDark;
  final Function(String) onCopyCode;

  CodeBlockBuilder({
    required this.isUser,
    required this.isDark,
    required this.onCopyCode,
  });

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final language = element.attributes['language'] ?? '';
    final code = element.textContent.trim();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF8F8F8),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? const Color(0xFF404040) : const Color(0xFFE0E0E0),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (language.isNotEmpty)
                Text(
                  language,
                  style: TextStyle(
                    color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF666666),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              IconButton(
                onPressed: () => onCopyCode(code),
                icon: Icon(
                  Icons.copy,
                  size: 14,
                  color: isDark ? const Color(0xFFCCCCCC) : const Color(0xFF666666),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
                tooltip: 'Copy code',
              ),
            ],
          ),
          if (language.isNotEmpty) const SizedBox(height: 4),
          GestureDetector(
            onLongPress: () => onCopyCode(code),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: HighlightView(
                code,
                language: language.isNotEmpty ? language.toLowerCase() : 'plaintext',
                theme: isDark
                    ? {
                        'root': TextStyle(color: const Color(0xFFE6E6E6), backgroundColor: Colors.transparent),
                        'keyword': TextStyle(color: const Color(0xFF569CD6), fontWeight: FontWeight.bold),
                        'string': TextStyle(color: const Color(0xFFCE9178)),
                        'comment': TextStyle(color: const Color(0xFF6A9955)),
                        'number': TextStyle(color: const Color(0xFFB5CEA8)),
                        'function': TextStyle(color: const Color(0xFFDCBDFB)),
                        'type': TextStyle(color: const Color(0xFF4EC9B0)),
                      }
                    : {
                        'root': TextStyle(color: const Color(0xFF1E1E1E), backgroundColor: Colors.transparent),
                        'keyword': TextStyle(color: const Color(0xFF0000FF), fontWeight: FontWeight.bold),
                        'string': TextStyle(color: const Color(0xFF008000)),
                        'comment': TextStyle(color: const Color(0xFF008000)),
                        'number': TextStyle(color: const Color(0xFF0000FF)),
                        'function': TextStyle(color: const Color(0xFF795E26)),
                        'type': TextStyle(color: const Color(0xFF267F99)),
                      },
                padding: const EdgeInsets.all(4),
                textStyle: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
