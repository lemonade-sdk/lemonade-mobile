import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Base resolution presets the user can pick for AI-generated images.
/// The actual width/height sent to /v1/images/generations is derived from
/// this base × the aspect ratio the LLM chose for the request. The
/// long edge equals [basePx]; the short edge is derived per aspect.
///
/// Default aspect when the LLM doesn't specify is 4:3, so the labels show
/// what you'll actually see at that ratio (the most common output).
///
///   - 512  — tiny, very fast, low quality
///   - 1024 — standard SD/Flux output, the historical default
///   - 2048 — high quality, ~4× compute
///   - 3072 — overkill for most, may exceed server's max
///   - 4096 — 4K-ish; not all models support this
enum ImageResolutionPreset {
  res512(512, '512 · default 512×384'),
  res1k(1024, '1K · default 1024×768'),
  res2k(2048, '2K · default 2048×1536'),
  res3k(3072, '3K · default 3072×2304'),
  res4k(4096, '4K · default 4096×3072');

  const ImageResolutionPreset(this.basePx, this.label);
  final int basePx;
  final String label;
}

const _prefsKey = 'image_generation_resolution_px';

class ImageResolutionNotifier extends StateNotifier<ImageResolutionPreset> {
  ImageResolutionNotifier() : super(ImageResolutionPreset.res1k) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(_prefsKey);
      if (saved == null) return;
      for (final p in ImageResolutionPreset.values) {
        if (p.basePx == saved) {
          state = p;
          break;
        }
      }
    } catch (_) {
      // Stick with the default if SharedPreferences is unavailable.
    }
  }

  Future<void> set(ImageResolutionPreset preset) async {
    state = preset;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, preset.basePx);
    } catch (_) {
      // Best-effort persistence.
    }
  }
}

final imageResolutionProvider =
    StateNotifierProvider<ImageResolutionNotifier, ImageResolutionPreset>(
  (ref) => ImageResolutionNotifier(),
);
