import 'package:flutter/material.dart';
import 'package:lemonade_mobile/constants/colors.dart';
import 'package:lemonade_mobile/models/transcription.dart';

class TranscriptionListItem extends StatelessWidget {
  final Transcription transcription;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const TranscriptionListItem({
    super.key,
    required this.transcription,
    this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRealtime = transcription.mode == TranscriptionMode.realtime;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: Icon(
          isRealtime ? Icons.stream : Icons.mic,
          color: isRealtime ? AppColors.streamingGreen : AppColors.capabilityAudio,
        ),
        title: Text(
          transcription.displayTitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Row(
          children: [
            Text(
              _formatDate(transcription.createdAt),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            if (transcription.modelId != null) ...[
              const Text(' \u2022 ', style: TextStyle(fontSize: 12)),
              Flexible(
                child: Text(
                  transcription.modelId!,
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            if (transcription.audioFilePath != null) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.play_circle_outline,
                size: 14,
                color: AppColors.capabilityAudio,
              ),
            ],
          ],
        ),
        trailing: onDelete != null
            ? IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: onDelete,
              )
            : null,
        onTap: onTap,
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';

    return '${date.month}/${date.day}/${date.year}';
  }
}
