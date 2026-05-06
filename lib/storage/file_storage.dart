import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
    if (!await file.exists()) {
      await file.writeAsBytes(bytes, flush: true);
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
