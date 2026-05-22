import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Compact in-bubble player for an audio attachment. Accepts either a `data:`
/// URL (typical for TTS-just-generated audio) or a file path. The first time
/// the user taps play, the bytes are decoded and cached on disk.
class InlineAudioPlayer extends StatefulWidget {
  final String source;
  final Color? color;

  const InlineAudioPlayer({super.key, required this.source, this.color});

  @override
  State<InlineAudioPlayer> createState() => _InlineAudioPlayerState();
}

class _InlineAudioPlayerState extends State<InlineAudioPlayer> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  bool _loading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _player.playerStateStream.listen((s) {
      if (!mounted) return;
      setState(() => _playing = s.playing);
    });
    _player.durationStream.listen((d) {
      if (!mounted || d == null) return;
      setState(() => _duration = d);
    });
    _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _ensureLoaded() async {
    if (_ready || _loading) return;
    setState(() => _loading = true);
    try {
      String path;
      if (widget.source.startsWith('data:')) {
        final commaIdx = widget.source.indexOf(',');
        if (commaIdx <= 0) return;
        final mime = widget.source.substring(5, widget.source.indexOf(';'));
        final bytes = base64Decode(widget.source.substring(commaIdx + 1));
        path = await _writeToCache(bytes, mime);
      } else {
        path = widget.source;
        if (!await File(path).exists()) return;
      }
      await _player.setFilePath(path);
      if (mounted) setState(() => _ready = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggle() async {
    await _ensureLoaded();
    if (!_ready) return;
    if (_playing) {
      await _player.pause();
    } else {
      if (_position >= _duration && _duration > Duration.zero) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
  }

  Future<String> _writeToCache(Uint8List bytes, String mime) async {
    final dir = await getTemporaryDirectory();
    // macOS app sandbox: getTemporaryDirectory() returns Library/Caches/,
    // which the OS doesn't always pre-create. Make sure it exists before
    // writing — without this, the very first inline-audio tap crashes with
    // PathNotFoundException.
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final ext = '.${mime.split('/').last}';
    final path = p.join(
      dir.path,
      'audio_${DateTime.now().microsecondsSinceEpoch}$ext',
    );
    final file = File(path);
    await file.writeAsBytes(bytes, flush: true);
    return path;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? Theme.of(context).colorScheme.primary;
    final progress = _duration.inMilliseconds == 0
        ? 0.0
        : _position.inMilliseconds / _duration.inMilliseconds;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: _loading ? null : _toggle,
            color: color,
            iconSize: 28,
            icon: _loading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : Icon(_playing ? Icons.pause_circle : Icons.play_circle),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _ready ? 'Audio' : (_loading ? 'Loading…' : 'Tap to play'),
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  color: color,
                  backgroundColor: color.withValues(alpha: 0.2),
                ),
                const SizedBox(height: 2),
                Text(
                  '${_fmt(_position)} / ${_fmt(_duration)}',
                  style: TextStyle(
                    color: color.withValues(alpha: 0.7),
                    fontSize: 11,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final mm = d.inMinutes.toString().padLeft(1, '0');
    final ss = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }
}
