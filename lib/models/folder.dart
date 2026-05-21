/// Domain model for a conversation folder. Mirrors `FolderEntity` in Isar.
class Folder {
  final String id;
  final String name;
  final String? parentFolderId;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Folder({
    required this.id,
    required this.name,
    this.parentFolderId,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  Folder copyWith({
    String? name,
    String? parentFolderId,
    int? sortOrder,
    DateTime? updatedAt,
    bool clearParent = false,
  }) {
    return Folder(
      id: id,
      name: name ?? this.name,
      parentFolderId: clearParent ? null : (parentFolderId ?? this.parentFolderId),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
