import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

enum MessageRole { user, assistant }

enum MessageContentType { text, image, audio }

/// Prefix for on-disk attachment references loaded without base64 into RAM.
/// Format: `lemonade-file:<mime>|<absolute-path>`
const String kFileRefPrefix = 'lemonade-file:';

class MessageContent {
  final MessageContentType type;

  /// Text body, `data:` URL, raw path, or [kFileRefPrefix] file-backed ref.
  final String value;
  Uint8List? _cachedImageBytes;

  MessageContent({
    required this.type,
    required this.value,
  });

  /// Encode a disk-backed attachment for cold-start loads (no base64 in RAM).
  static String fileRef({required String mime, required String path}) =>
      '$kFileRefPrefix$mime|$path';

  /// Parse a [fileRef] value; null if not a file reference.
  static ({String mime, String path})? parseFileRef(String value) {
    if (!value.startsWith(kFileRefPrefix)) return null;
    final rest = value.substring(kFileRefPrefix.length);
    final bar = rest.indexOf('|');
    if (bar <= 0) return null;
    return (mime: rest.substring(0, bar), path: rest.substring(bar + 1));
  }

  bool get isFileRef => value.startsWith(kFileRefPrefix);

  /// Absolute path if this is a file ref, else null.
  String? get fileRefPath => parseFileRef(value)?.path;

  /// MIME if this is a file ref or data URL image/audio.
  String? get mimeType {
    final ref = parseFileRef(value);
    if (ref != null) return ref.mime;
    if (value.startsWith('data:')) {
      final semi = value.indexOf(';');
      if (semi > 5) return value.substring(5, semi);
    }
    return null;
  }

  /// Resolve to a `data:` URL for the wire / model (loads disk once).
  Future<String> resolveDataUrl() async {
    if (value.startsWith('data:')) return value;
    final ref = parseFileRef(value);
    if (ref != null) {
      final bytes = await File(ref.path).readAsBytes();
      return 'data:${ref.mime};base64,${base64Encode(bytes)}';
    }
    // Bare path fallback
    if (!value.startsWith('http') && await File(value).exists()) {
      final bytes = await File(value).readAsBytes();
      final mime = type == MessageContentType.audio ? 'audio/wav' : 'image/jpeg';
      return 'data:$mime;base64,${base64Encode(bytes)}';
    }
    return value;
  }

  /// Get cached image bytes; decode data URL or read file ref on demand.
  Uint8List? getCachedImageBytes() {
    if (_cachedImageBytes != null) return _cachedImageBytes;
    if (type != MessageContentType.image) return null;

    if (value.startsWith('data:image/')) {
      try {
        final parts = value.split(',');
        if (parts.length >= 2) {
          _cachedImageBytes = base64Decode(parts[1]);
          return _cachedImageBytes;
        }
      } catch (_) {
        return null;
      }
    }

    final ref = parseFileRef(value);
    final path = ref?.path ??
        ((!value.startsWith('data:') && !value.startsWith('http'))
            ? value
            : null);
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) {
          _cachedImageBytes = f.readAsBytesSync();
          return _cachedImageBytes;
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'value': value,
      };

  factory MessageContent.fromJson(Map<String, dynamic> json) {
    return MessageContent(
      type: MessageContentType.values.firstWhere(
        (e) => e.name == json['type'],
      ),
      value: json['value'],
    );
  }
}

class ChatMessage {
  /// Stable id for differential persistence (Isar message uuid).
  final String id;
  final MessageRole role;
  final List<MessageContent> content;
  final DateTime timestamp;

  static const _uuid = Uuid();

  ChatMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? timestamp,
  })  : id = id ?? _uuid.v4(),
        timestamp = timestamp ?? DateTime.now();

  ChatMessage.text({
    String? id,
    required this.role,
    required String text,
    DateTime? timestamp,
  })  : id = id ?? _uuid.v4(),
        content = [MessageContent(type: MessageContentType.text, value: text)],
        timestamp = timestamp ?? DateTime.now();

  ChatMessage.image({
    String? id,
    required this.role,
    required String imageBase64,
    DateTime? timestamp,
  })  : id = id ?? _uuid.v4(),
        content = [
          MessageContent(type: MessageContentType.image, value: imageBase64)
        ],
        timestamp = timestamp ?? DateTime.now();

  /// Copy with the same [id] (used when streaming updates assistant text).
  ChatMessage copyWith({
    MessageRole? role,
    List<MessageContent>? content,
    DateTime? timestamp,
  }) =>
      ChatMessage(
        id: id,
        role: role ?? this.role,
        content: content ?? this.content,
        timestamp: timestamp ?? this.timestamp,
      );

  String get textContent {
    return content
        .where((c) => c.type == MessageContentType.text)
        .map((c) => c.value)
        .join(' ');
  }

  String? get imageContent {
    return content
        .where((c) => c.type == MessageContentType.image)
        .map((c) => c.value)
        .firstOrNull;
  }

  bool get hasImages => content.any((c) => c.type == MessageContentType.image);

  bool get hasAudio => content.any((c) => c.type == MessageContentType.audio);

  Iterable<String> get audioContent => content
      .where((c) => c.type == MessageContentType.audio)
      .map((c) => c.value);

  /// Fingerprint for differential save: id + role + text + media values.
  String get persistFingerprint {
    final buf = StringBuffer('$id|${role.name}|');
    for (final c in content) {
      buf.write('${c.type.name}:${c.value.length}:');
      // Full value for text (short); for media use prefix or path only.
      if (c.type == MessageContentType.text) {
        buf.write(c.value);
      } else {
        buf.write(c.value.length > 80 ? c.value.substring(0, 80) : c.value);
        if (c.value.startsWith('data:') && c.value.length > 100) {
          // data URLs change identity when rebuilt; include length + tail hash-ish
          buf.write(':${c.value.length}:${c.value.hashCode}');
        }
      }
      buf.write(';');
    }
    return buf.toString();
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'role': role.name,
      'content': content.map((c) => c.toJson()).toList(),
      'timestamp': timestamp.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    if (json['content'] is String) {
      return ChatMessage(
        id: json['id'] as String?,
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
        ),
        content: [
          MessageContent(
              type: MessageContentType.text, value: json['content'] as String)
        ],
        timestamp: DateTime.parse(json['timestamp'] as String),
      );
    }

    return ChatMessage(
      id: json['id'] as String?,
      role: MessageRole.values.firstWhere(
        (e) => e.name == json['role'],
      ),
      content: (json['content'] as List<dynamic>)
          .map((c) => MessageContent.fromJson(c as Map<String, dynamic>))
          .toList(),
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }

  bool get isUser => role == MessageRole.user;
  bool get isAssistant => role == MessageRole.assistant;
}
