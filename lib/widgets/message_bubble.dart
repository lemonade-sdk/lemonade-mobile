import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:lemonade_mobile/models/chat_message.dart';
import 'package:lemonade_mobile/constants/messages.dart';
import 'package:lemonade_mobile/constants/colors.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/screens/image_viewer_screen.dart';
import 'package:lemonade_mobile/widgets/inline_audio_player.dart';

class MessageBubble extends ConsumerWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _MessageBubbleContent(message: message, ref: ref);
  }
}

class _MessageBubbleContent extends StatelessWidget {
  final ChatMessage message;
  final WidgetRef ref;

  const _MessageBubbleContent({
    required this.message,
    required this.ref,
  });

  void _copyMessage(BuildContext context) {
    Clipboard.setData(ClipboardData(text: message.textContent));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppMessages.messageCopied),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .primary,
      ),
    );
  }

  Widget _buildImage(BuildContext context, String imageData) {
    //print('MessageBubble: Displaying image, data length: ${imageData.length}, starts with: ${imageData.substring(0, math.min(50, imageData.length))}');

    // 1. Handle Network URLs
    if (imageData.startsWith('http')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          imageData,
          fit: BoxFit.cover,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return Container(
              height: 200,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const CircularProgressIndicator(),
            );
          },
          errorBuilder: (context, error, stackTrace) =>
              _buildImageError(context, "Failed to load network image"),
        ),
      );
    }

    // 2. Handle Data URLs (most common case now) - use cached bytes from message content
    if (imageData.startsWith('data:image/')) {
      // Get cached bytes from the message content (stable caching at message level)
      final imageContent = message.content.firstWhere(
        (c) => c.type == MessageContentType.image && c.value == imageData,
        orElse: () => MessageContent(type: MessageContentType.image, value: imageData),
      );

      final cachedBytes = imageContent.getCachedImageBytes();

      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            cachedBytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildImageError(context, "Failed to display image"),
          ),
        );
      } else {
        return _buildImageError(context, "No image data");
      }
    }

    // 3. Handle legacy Base64 or File Path formats
    final cleanData = imageData.trim();

    // Check if it's a file path (contains path separators and looks like a path)
    bool isFilePath = (cleanData.contains('/') || cleanData.contains('\\')) &&
                     (cleanData.contains('.') || cleanData.length < 1000);

    if (isFilePath) {
      // Load from file path
      return _buildLocalImage(context, cleanData);
    } else {
      // Try as legacy Base64 - get from message content cache
      final imageContent = message.content.firstWhere(
        (c) => c.type == MessageContentType.image && c.value == imageData,
        orElse: () => MessageContent(type: MessageContentType.image, value: imageData),
      );

      final cachedBytes = imageContent.getCachedImageBytes();

      if (cachedBytes != null && cachedBytes.isNotEmpty) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            cachedBytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) =>
                _buildImageError(context, "Failed to display image"),
          ),
        );
      } else {
        return _buildImageError(context, "No image data");
      }
    }
  }

  Widget _buildLocalImage(BuildContext context, String path) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildImageError(context, "File not found"),
      ),
    );
  }

  Widget _buildImageError(BuildContext context, String errorMessage) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .colorScheme
            .errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.broken_image, size: 48),
          const SizedBox(height: 8),
          Text(
            errorMessage,
            style: TextStyle(
              color: Theme
                  .of(context)
                  .colorScheme
                  .onErrorContainer,
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTextContent(BuildContext context, bool isUser, bool isDark) {
    if (message.textContent.isEmpty) return const SizedBox.shrink();

    return MarkdownBody(
      data: message.textContent,
      styleSheet: MarkdownStyleSheet(
        p: TextStyle(
          color: isUser
              ? Theme
              .of(context)
              .colorScheme
              .onPrimary
              : Theme
              .of(context)
              .colorScheme
              .onSurface,
          fontSize: 16,
          height: 1.4,
        ),
        code: TextStyle(
          color: isUser
              ? (isDark ? AppColors.inlineCodeKeywordDark : AppColors.inlineCodeKeywordLight)
              : (isDark ? AppColors.inlineCodeStringDark : AppColors.inlineCodeStringLight),
          fontFamily: 'monospace',
          fontSize: 14,
          backgroundColor: isUser
              ? (isDark ? AppColors.inlineCodeBackgroundDark : AppColors.inlineCodeBackgroundLight)
              : (isDark ? AppColors.inlineCodeBackgroundDark : AppColors.inlineCodeBackgroundLight),
        ),
        codeblockDecoration: BoxDecoration(
          color: isDark ? AppColors.codeBlockBackgroundDark : AppColors.codeBlockBackgroundLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isDark ? AppColors.codeBlockBorderDark : AppColors.codeBlockBorderLight,
            width: 0.5,
          ),
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppColors.blockquoteBackground,
          border: Border(
            left: BorderSide(
              color: isDark ? AppColors.blockquoteBorderDark : AppColors.blockquoteBorderLight,
              width: 4,
            ),
          ),
        ),
        tableBorder: TableBorder.all(
          color: isDark ? AppColors.tableBorderDark : AppColors.tableBorderLight,
          width: 1,
        ),
        tableHead: TextStyle(
          color: isUser
              ? Theme
              .of(context)
              .colorScheme
              .onPrimary
              : Theme
              .of(context)
              .colorScheme
              .onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
      builders: {
        'code': CodeBlockBuilder(
          isUser: isUser,
          isDark: isDark,
          onCopyCode: (code) => _copyCode(context, code),
        ),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasText = message.textContent.isNotEmpty;
    final hasImage = message.hasImages;
    final audios = message.audioContent.toList();

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () => _copyMessage(context),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          constraints: BoxConstraints(
            maxWidth: MediaQuery
                .of(context)
                .size
                .width * 0.75,
          ),
          decoration: BoxDecoration(
            color: isUser
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: isUser ? const Radius.circular(20) : const Radius
                  .circular(6),
              bottomRight: isUser ? const Radius.circular(6) : const Radius
                  .circular(20),
            ),
              boxShadow: [
                BoxShadow(
                  color: theme.shadowColor.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasImage) ...[
                GestureDetector(
                  onTap: () => _openImageViewer(context, message.imageContent!),
                  child: _buildImage(context, message.imageContent!),
                ),
                if (hasText || audios.isNotEmpty) const SizedBox(height: 8),
              ],
              for (final src in audios) ...[
                InlineAudioPlayer(
                  source: src,
                  color: isUser
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.primary,
                ),
                const SizedBox(height: 8),
              ],
              if (hasText) _buildTextContent(context, isUser, isDark),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.copy,
                    size: 12,
                    color: (isUser
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface).withOpacity(0.5),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    AppMessages.copyHint,
                    style: TextStyle(
                      fontSize: 10,
                      color: (isUser
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.onSurface).withOpacity(0.5),
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

  void _copyCode(BuildContext context, String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppMessages.codeCopied),
        duration: const Duration(seconds: 2),
        backgroundColor: Theme
            .of(context)
            .colorScheme
            .primary,
      ),
    );
  }

  /// Push the fullscreen image viewer for [imageValue] (a data URL, file
  /// path, or network URL — only data URLs and the in-memory cached bytes
  /// support Share / Download in the viewer; the others are show-only).
  void _openImageViewer(BuildContext context, String imageValue) {
    // Pull the bytes from the MessageContent's cache so we don't
    // re-decode base64 each tap. Only data URLs are supported here for
    // the action buttons; network URLs and file paths fall back to a
    // simple Image.network/file in the viewer (caller can extend).
    final imageContent = message.content.firstWhere(
      (c) => c.type == MessageContentType.image && c.value == imageValue,
      orElse: () =>
          MessageContent(type: MessageContentType.image, value: imageValue),
    );
    final bytes = imageContent.getCachedImageBytes();
    if (bytes == null || bytes.isEmpty) {
      // Not bytes-backed (file path / URL). Skip the viewer for now —
      // we'd need a separate code path to load from those sources.
      return;
    }
    // Sniff the mime out of the data URL prefix if present.
    String mime = 'image/png';
    if (imageValue.startsWith('data:')) {
      final semi = imageValue.indexOf(';');
      if (semi > 5) mime = imageValue.substring(5, semi);
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ImageViewerScreen(
        bytes: bytes,
        mime: mime,
        onDelete: () => _deleteImage(imageValue),
      ),
    ));
  }

  /// Remove the image MessageContent identified by [imageValue] from this
  /// message and persist the updated chat. Other parts of the message
  /// (text, audio attachments) stay untouched. If the message ends up
  /// empty (e.g. it was image-only), it is removed from the chat entirely.
  Future<void> _deleteImage(String imageValue) async {
    final history =
        ref.read(chatHistoryProvider.notifier).getActiveChat()?.messages ??
            const <ChatMessage>[];
    final idx = history.indexOf(message);
    if (idx < 0) return; // Message no longer in active chat — nothing to do.
    final updatedContent = message.content
        .where((c) =>
            !(c.type == MessageContentType.image && c.value == imageValue))
        .toList(growable: false);
    final next = List<ChatMessage>.of(history);
    if (updatedContent.isEmpty) {
      next.removeAt(idx);
    } else {
      next[idx] = ChatMessage(
        role: message.role,
        content: updatedContent,
        timestamp: message.timestamp,
      );
    }
    await ref.read(chatHistoryProvider.notifier).updateActiveChat(next);
  }
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
        color: isDark ? AppColors.codeBlockBackgroundDark : AppColors.codeBlockBackgroundLight,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isDark ? AppColors.codeBlockBorderDark : AppColors.codeBlockBorderLight,
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
                    color: isDark ? AppColors.codeBlockTextDark : AppColors.codeBlockTextLight,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              IconButton(
                onPressed: () => onCopyCode(code),
                icon: Icon(
                  Icons.copy,
                  size: 14,
                  color: isDark ? AppColors.codeBlockTextDark : AppColors.codeBlockTextLight,
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
                theme: isDark ? AppColors.getSyntaxThemeDark() : AppColors.getSyntaxThemeLight(),
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
