enum TranscriptionMode { http, realtime }

class Transcription {
  final String id;
  final String text;
  final String? modelId;
  final TranscriptionMode mode;
  final DateTime createdAt;
  final String? serverName;
  final String? audioFilePath;
  final Duration? audioDuration;

  Transcription({
    required this.id,
    required this.text,
    this.modelId,
    required this.mode,
    DateTime? createdAt,
    this.serverName,
    this.audioFilePath,
    this.audioDuration,
  }) : createdAt = createdAt ?? DateTime.now();

  String get displayTitle {
    if (text.isEmpty) return 'Empty transcription';
    return text.length > 80 ? '${text.substring(0, 80)}...' : text;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'modelId': modelId,
      'mode': mode == TranscriptionMode.http ? 'http' : 'realtime',
      'createdAt': createdAt.toIso8601String(),
      'serverName': serverName,
      'audioFilePath': audioFilePath,
      'audioDurationMs': audioDuration?.inMilliseconds,
    };
  }

  factory Transcription.fromJson(Map<String, dynamic> json) {
    return Transcription(
      id: json['id'],
      text: json['text'],
      modelId: json['modelId'],
      mode: json['mode'] == 'realtime' ? TranscriptionMode.realtime : TranscriptionMode.http,
      createdAt: DateTime.parse(json['createdAt']),
      serverName: json['serverName'],
      audioFilePath: json['audioFilePath'],
      audioDuration: json['audioDurationMs'] != null
          ? Duration(milliseconds: json['audioDurationMs'])
          : null,
    );
  }

  Transcription copyWith({
    String? id,
    String? text,
    String? modelId,
    TranscriptionMode? mode,
    DateTime? createdAt,
    String? serverName,
    String? audioFilePath,
    Duration? audioDuration,
  }) {
    return Transcription(
      id: id ?? this.id,
      text: text ?? this.text,
      modelId: modelId ?? this.modelId,
      mode: mode ?? this.mode,
      createdAt: createdAt ?? this.createdAt,
      serverName: serverName ?? this.serverName,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      audioDuration: audioDuration ?? this.audioDuration,
    );
  }
}
