import 'package:isar_community/isar.dart';

part 'chat_history_entity.g.dart';

@collection
class ChatHistoryEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  String? title;

  /// Null = root / Inbox.
  @Index()
  String? folderUuid;

  late DateTime createdAt;

  @Index()
  late DateTime lastUpdated;

  bool isActive = false;

  /// JSON-encoded ModelDefaults override for this chat (null = use globals).
  String? modelOverridesJson;

  int schemaVersion = 1;
}
