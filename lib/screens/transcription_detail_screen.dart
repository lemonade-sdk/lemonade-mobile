import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/transcription.dart';
import 'package:lemonade_mobile/widgets/audio_waveform_bar.dart';

class TranscriptionDetailScreen extends ConsumerStatefulWidget {
  final Transcription transcription;

  const TranscriptionDetailScreen({
    super.key,
    required this.transcription,
  });

  @override
  ConsumerState<TranscriptionDetailScreen> createState() =>
      _TranscriptionDetailScreenState();
}

class _TranscriptionDetailScreenState
    extends ConsumerState<TranscriptionDetailScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final transcription = widget.transcription;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcription'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copy to clipboard',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: transcription.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Transcription copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Metadata
            _buildMetadataRow(
              context,
              'Mode',
              transcription.mode == TranscriptionMode.realtime ? 'Live Stream' : 'Record & Send',
            ),
            if (transcription.modelId != null)
              _buildMetadataRow(context, 'Model', transcription.modelId!),
            if (transcription.serverName != null)
              _buildMetadataRow(context, 'Server', transcription.serverName!),
            _buildMetadataRow(
              context,
              'Date',
              _formatDateTime(transcription.createdAt),
            ),
            if (transcription.audioDuration != null)
              _buildMetadataRow(
                context,
                'Duration',
                _formatDuration(transcription.audioDuration!),
              ),

            // Audio playback
            if (transcription.audioFilePath != null) ...[
              const SizedBox(height: 12),
              FutureBuilder<bool>(
                future: File(transcription.audioFilePath!).exists(),
                builder: (context, snapshot) {
                  if (snapshot.data == true) {
                    return AudioWaveformBar(
                      filePath: transcription.audioFilePath!,
                      duration: transcription.audioDuration ?? Duration.zero,
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),

            // Transcription text
            SelectableText(
              transcription.text.isEmpty ? '(empty transcription)' : transcription.text,
              style: TextStyle(
                fontSize: 16,
                height: 1.6,
                color: transcription.text.isEmpty
                    ? theme.colorScheme.onSurface.withValues(alpha: 0.4)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime date) {
    return '${date.month}/${date.day}/${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
