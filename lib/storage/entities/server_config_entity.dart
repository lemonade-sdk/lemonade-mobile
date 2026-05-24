import 'package:isar_community/isar.dart';

part 'server_config_entity.g.dart';

@collection
class ServerConfigEntity {
  Id id = Isar.autoIncrement;

  /// Display name. Treated as the user-facing identifier (and the secure-storage
  /// key for any associated API token).
  @Index(unique: true, caseSensitive: true)
  late String name;

  late String baseUrl;

  /// Whether an API key has been stored in secure storage under this server's name.
  /// The actual key is never stored in Isar.
  bool hasApiKey = false;

  late DateTime createdAt;

  int schemaVersion = 1;
}
