import 'package:isar_community/isar.dart';

part 'transcription_entity.g.dart';

@collection
class TranscriptionEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late String text;
  String? modelId;

  /// 'http' | 'realtime'
  late String mode;

  String? serverName;

  /// Path to the WAV/M4A file on disk.
  String? audioFilePath;
  int? audioDurationMs;

  @Index()
  late DateTime createdAt;

  int schemaVersion = 1;
}
