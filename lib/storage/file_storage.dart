import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:isar_community/isar.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'entities/attachment_entity.dart';

/// Per-kind file storage rooted at `{appDocDir}/<kind>/`.
///
/// Files are content-addressed by SHA-256 with the original extension preserved.
/// This naturally de-duplicates identical attachments across messages.
class AttachmentStore {
  static const _audioDir = 'audio';
  static const _imageDir = 'images';
  static const _filesDir = 'files';

  /// Returns the absolute on-disk path. Creates the parent directory if missing.
  static Future<String> writeBytes({
    required Uint8List bytes,
    required String kind, // 'image' | 'audio' | 'file'
    required String extension, // '.png', '.wav', etc. — leading dot
  }) async {
    final root = await _rootFor(kind);
    final hash = sha256.convert(bytes).toString();
    final path = p.join(root.path, '$hash$extension');
    final file = File(path);
    // Dedup hit — but treat a zero-length file as missing: it's a truncated
    // write from a previous kill, and skipping here would make the corruption
    // permanent.
    if (await file.exists() && (await file.length()) > 0) {
      return path;
    }
    // Write to a temp sibling then rename into place so a kill mid-write can
    // never leave a partial file at the content-addressed path.
    final tmp = File('$path.tmp-$pid-${DateTime.now().microsecondsSinceEpoch}');
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(path);
    } catch (_) {
      // Rename failed (e.g. lost a race with a concurrent writer of the same
      // content — their copy is byte-identical). Drop our temp file; only
      // rethrow if the destination genuinely doesn't exist.
      try {
        await tmp.delete();
      } catch (_) {}
      if (!await file.exists()) rethrow;
    }
    return path;
  }

  /// Compute the sha256 of a file already on disk (used during legacy migration
  /// when an existing audio file is being adopted).
  static Future<String> sha256OfFile(String path) async {
    final file = File(path);
    final input = file.openRead();
    final digest = await sha256.bind(input).first;
    return digest.toString();
  }

  /// Hex-encoded SHA-256 of in-memory bytes.
  static String sha256OfBytes(Uint8List bytes) {
    return sha256.convert(bytes).toString();
  }

  /// Decode a base64 string and persist it. Returns the on-disk path + sha256.
  static Future<({String path, String sha256, int sizeBytes})> writeBase64({
    required String base64Data,
    required String kind,
    required String extension,
  }) async {
    final bytes = base64Decode(base64Data);
    final hash = sha256OfBytes(bytes);
    final path = await writeBytes(bytes: bytes, kind: kind, extension: extension);
    return (path: path, sha256: hash, sizeBytes: bytes.length);
  }

  static Future<bool> deleteByPath(String path) async {
    final f = File(path);
    if (!await f.exists()) return false;
    await f.delete();
    return true;
  }

  /// Conservative GC for attachment files orphaned by deleted chats (chat
  /// deletion removes the DB rows but historically never the files).
  ///
  /// Sweeps the images dir and deletes files that (a) are not referenced by
  /// any [AttachmentEntity] row and (b) are older than [minAge] — the age
  /// guard avoids racing an in-flight save whose file lands on disk before
  /// its row commits. Stored paths can be stale absolute paths from a
  /// previous iOS container, so referenced-ness is keyed on the
  /// content-addressed basename (see [resolveExisting]).
  static Future<({int deleted, int failed})> gcOrphans({
    Duration minAge = const Duration(hours: 24),
  }) async {
    if (!AppDatabase.isOpen) return (deleted: 0, failed: 0);
    final referenced = (await AppDatabase.instance.attachments
            .where()
            .filePathProperty()
            .findAll())
        .map(p.basename)
        .toSet();

    final root = await _rootFor('image');
    final cutoff = DateTime.now().subtract(minAge);
    var deleted = 0;
    var failed = 0;
    await for (final entry in root.list(followLinks: false)) {
      if (entry is! File) continue;
      if (referenced.contains(p.basename(entry.path))) continue;
      try {
        final stat = await entry.stat();
        if (stat.modified.isAfter(cutoff)) continue;
        await entry.delete();
        deleted++;
      } catch (_) {
        failed++;
      }
    }
    return (deleted: deleted, failed: failed);
  }

  /// Resolve a stored attachment path to an existing file. iOS relocates the
  /// app container (new UUID in the path) on EVERY app update, so absolute
  /// paths persisted in the DB go stale each build — re-root by basename
  /// under the current documents dir. Content-addressed filenames (sha256 +
  /// extension) make the basename a stable key. Returns null when the file
  /// is genuinely gone.
  static Future<File?> resolveExisting(String kind, String storedPath) async {
    var f = File(storedPath);
    if (await f.exists()) return f;
    final root = await _rootFor(kind);
    f = File(p.join(root.path, p.basename(storedPath)));
    return await f.exists() ? f : null;
  }

  static Future<Directory> _rootFor(String kind) async {
    final docs = await getApplicationDocumentsDirectory();
    final folderName = switch (kind) {
      'image' => _imageDir,
      'audio' => _audioDir,
      _ => _filesDir,
    };
    final dir = Directory(p.join(docs.path, folderName));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
