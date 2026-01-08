import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:lemonade_mobile/models/chat_message.dart';
import 'package:lemonade_mobile/constants/messages.dart';
import 'package:lemonade_mobile/constants/colors.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return _MessageBubbleContent(message: message);
  }
}

class _MessageBubbleContent extends StatelessWidget {
  final ChatMessage message;

  const _MessageBubbleContent({
    required this.message,
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
                _buildImage(context, message.imageContent!),
                if (hasText) const SizedBox(height: 8),
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
