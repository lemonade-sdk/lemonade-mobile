import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';

import '../../providers/nav_provider.dart';
import '../../themes/nexus_tokens.dart';

/// Full-screen image viewer with pinch-zoom and save-to-gallery.
class ImageLightboxOverlay extends ConsumerWidget {
  final Uint8List? bytes;
  final String? label;
  final String? caption;
  const ImageLightboxOverlay({super.key, this.bytes, this.label, this.caption});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final close = ref.read(overlayProvider.notifier).close;

    return Material(
      color: Colors.black.withValues(alpha: 0.94),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            children: [
              Row(children: [
                GestureDetector(
                  onTap: close,
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: t.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.line2)),
                    child: Icon(Icons.close, color: t.text, size: 18),
                  ),
                ),
                const Spacer(),
                if (bytes != null)
                  GestureDetector(
                    onTap: () => _save(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                          color: t.accent,
                          borderRadius: BorderRadius.circular(12)),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.download, color: Colors.white, size: 15),
                        SizedBox(width: 6),
                        Text('Save',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: Colors.white)),
                      ]),
                    ),
                  ),
              ]),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: bytes != null
                      ? InteractiveViewer(
                          minScale: 0.8,
                          maxScale: 4,
                          child: Image.memory(bytes!, fit: BoxFit.contain),
                        )
                      : Container(
                          decoration: BoxDecoration(
                              color: t.surface,
                              borderRadius: BorderRadius.circular(18)),
                          child: Icon(Icons.image_outlined,
                              color: t.faint, size: 64),
                        ),
                ),
              ),
              if (caption != null && caption!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(caption!,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, height: 1.5, color: t.text)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save(BuildContext context) async {
    if (bytes == null) return;
    try {
      await Gal.putImageBytes(bytes!);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Saved to gallery')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }
}
