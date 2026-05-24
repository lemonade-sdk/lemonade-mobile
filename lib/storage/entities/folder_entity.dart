import 'package:isar_community/isar.dart';

part 'folder_entity.g.dart';

@collection
class FolderEntity {
  Id id = Isar.autoIncrement;

  @Index(unique: true)
  late String uuid;

  late String name;

  /// Null = root-level folder (e.g. "Inbox").
  String? parentFolderUuid;

  /// Manual ordering within a parent. Lower = earlier.
  int sortOrder = 0;

  late DateTime createdAt;
  late DateTime updatedAt;

  /// Per-row schema stamp; bump when shape changes to allow targeted migrations.
  int schemaVersion = 1;
}
