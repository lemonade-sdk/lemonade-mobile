import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Fullscreen image viewer.
///
/// Tap the image in a chat bubble → this screen opens with the image
/// centered, pinch-to-zoom enabled, an X to close in the top-right, and
/// three action buttons (Share, Download, Delete) along the bottom.
///
/// The viewer accepts either raw decoded bytes (the common case — the
/// chat bubble already keeps the bytes cached) or a data: URL it can
/// decode itself. Deletion is delegated to the caller via [onDelete]
/// because the chat-history mutation logic lives there.
class ImageViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final String mime;

  /// Called when the user taps Delete. If non-null, a confirm dialog is
  /// shown first; on confirm we pop the viewer then invoke this.
  final Future<void> Function()? onDelete;

  const ImageViewerScreen({
    super.key,
    required this.bytes,
    this.mime = 'image/png',
    this.onDelete,
  });

  /// Convenience constructor that decodes a `data:image/...;base64,...`
  /// URL. Throws if the URL isn't a data URL — callers should branch on
  /// the value's prefix beforehand.
  factory ImageViewerScreen.fromDataUrl(
    String dataUrl, {
    Future<void> Function()? onDelete,
  }) {
    if (!dataUrl.startsWith('data:')) {
      throw ArgumentError('Not a data URL: ${dataUrl.substring(0, 32)}…');
    }
    final semi = dataUrl.indexOf(';');
    final comma = dataUrl.indexOf(',');
    final mime = semi > 5 ? dataUrl.substring(5, semi) : 'image/png';
    final bytes = base64Decode(dataUrl.substring(comma + 1));
    return ImageViewerScreen(bytes: bytes, mime: mime, onDelete: onDelete);
  }

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _busy = false;

  String get _extension {
    final slash = widget.mime.indexOf('/');
    return slash > 0 ? widget.mime.substring(slash + 1) : 'png';
  }

  Future<String> _writeToTemp() async {
    final dir = await getTemporaryDirectory();
    if (!await dir.exists()) await dir.create(recursive: true);
    final path = p.join(
      dir.path,
      'lemonade_${DateTime.now().microsecondsSinceEpoch}.$_extension',
    );
    final file = File(path);
    await file.writeAsBytes(widget.bytes, flush: true);
    return path;
  }

  Future<void> _onShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _writeToTemp();
      await Share.shareXFiles(
        [XFile(path, mimeType: widget.mime)],
        subject: 'Image from Lemonade',
      );
    } catch (e) {
      _showError('Share failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDownload() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Gal handles permission prompts itself on iOS/Android the first
      // time it's called. On macOS it writes through the system Photos
      // library if available.
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          _showError('Photo library access denied.');
          return;
        }
      }
      // putImageBytes wants a file path on some platforms and bytes on
      // others; the unified API takes bytes directly in recent gal.
      await Gal.putImageBytes(widget.bytes, name: 'lemonade-${DateTime.now().millisecondsSinceEpoch}');
      _showSuccess('Saved to Photos.');
    } on GalException catch (e) {
      _showError('Save failed: ${e.type.message}');
    } catch (e) {
      _showError('Save failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onDelete() async {
    if (_busy || widget.onDelete == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete image?'),
        content: const Text(
          'This removes the image from this chat. Other parts of the message '
          '(text, audio) will stay.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await widget.onDelete!();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showError('Delete failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      // Keep the close button on top so the user always has an out, and
      // a translucent bottom bar with the actions so the image isn't
      // obscured while panning.
      body: SafeArea(
        child: Stack(
          children: [
            // The image itself — pinch to zoom, drag to pan within zoom.
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1.0,
                maxScale: 6.0,
                child: Center(
                  child: Image.memory(
                    widget.bytes,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // Close (X) — top right.
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black.withValues(alpha: 0.45),
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            // Action bar — bottom.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.0),
                      Colors.black.withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: Icons.ios_share,
                      label: 'Share',
                      onPressed: _busy ? null : _onShare,
                    ),
                    _ActionButton(
                      icon: Icons.download,
                      label: 'Download',
                      onPressed: _busy ? null : _onDownload,
                    ),
                    _ActionButton(
                      icon: Icons.delete_outline,
                      label: 'Delete',
                      tint: scheme.error,
                      onPressed: widget.onDelete == null || _busy
                          ? null
                          : _onDelete,
                    ),
                  ],
                ),
              ),
            ),

            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Color? tint;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final color = onPressed == null ? Colors.white38 : (tint ?? Colors.white);
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12)),
        ],
      ),
    );
  }
}
