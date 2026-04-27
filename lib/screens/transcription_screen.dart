import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/transcription_provider.dart';
import 'package:lemonade_mobile/screens/transcription_detail_screen.dart';
import 'package:lemonade_mobile/widgets/recording_widget.dart';
import 'package:lemonade_mobile/widgets/transcription_list_item.dart';

class TranscriptionScreen extends ConsumerWidget {
  const TranscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(transcriptionHistoryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transcription'),
        actions: [
          if (history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Clear All',
              onPressed: () => _confirmClearAll(context, ref),
            ),
        ],
      ),
      body: Column(
        children: [
          // Recording controls
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: RecordingWidget(),
          ),

          const Divider(),

          // History header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Text(
                  'History',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(width: 8),
                Text(
                  '${history.length} transcriptions',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),

          // History list
          Expanded(
            child: history.isEmpty
                ? const Center(
                    child: Text(
                      'No transcriptions yet.\nRecord audio to get started.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];
                      return TranscriptionListItem(
                        transcription: item,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  TranscriptionDetailScreen(transcription: item),
                            ),
                          );
                        },
                        onDelete: () {
                          ref
                              .read(transcriptionHistoryProvider.notifier)
                              .deleteTranscription(item.id);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear All Transcriptions'),
        content: const Text('This will delete all transcription history. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(transcriptionHistoryProvider.notifier).clearAll();
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('Clear All',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
