import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/constants/colors.dart';
import 'package:lemonade_mobile/models/transcription.dart';
import 'package:lemonade_mobile/providers/transcription_provider.dart';
import 'package:lemonade_mobile/widgets/live_audio_visualizer.dart';
import 'package:lemonade_mobile/widgets/audio_waveform_bar.dart';

class RecordingWidget extends ConsumerStatefulWidget {
  const RecordingWidget({super.key});

  @override
  ConsumerState<RecordingWidget> createState() => _RecordingWidgetState();
}

class _RecordingWidgetState extends ConsumerState<RecordingWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isLivePreviewExpanded = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordingState = ref.watch(recordingStateProvider);
    final mode = ref.watch(transcriptionModeProvider);
    final liveText = ref.watch(liveTranscriptionTextProvider);
    final error = ref.watch(transcriptionErrorProvider);
    final lastRecording = ref.watch(lastRecordingInfoProvider);

    // Control pulse animation
    if (recordingState == RecordingState.recording) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
      }
    } else {
      _pulseController.stop();
      _pulseController.reset();
    }

    return Column(
      children: [
        // Mode toggle
        _buildModeToggle(mode),
        const SizedBox(height: 24),

        // Status text
        _buildStatusText(recordingState, mode),
        const SizedBox(height: 16),

        // Live audio visualizer during recording
        if (recordingState == RecordingState.recording) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LiveAudioVisualizer(
              color: mode == TranscriptionMode.http
                  ? AppColors.recordingRed
                  : AppColors.streamingGreen,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Post-recording waveform bar (HTTP mode, idle, recording just completed)
        if (recordingState == RecordingState.idle && lastRecording != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: AudioWaveformBar(
              filePath: lastRecording.filePath,
              amplitudes: lastRecording.amplitudes,
              duration: lastRecording.duration,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Mic button
        _buildMicButton(recordingState, mode),
        const SizedBox(height: 8),

        // Live transcription preview (realtime mode, collapsible, below mic)
        if (mode == TranscriptionMode.realtime &&
            (recordingState == RecordingState.recording || liveText.isNotEmpty)) ...[
          const SizedBox(height: 8),
          _buildCollapsibleLivePreview(liveText, recordingState == RecordingState.recording),
        ],

        // Error display
        if (error != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildModeToggle(TranscriptionMode mode) {
    return SegmentedButton<TranscriptionMode>(
      segments: const [
        ButtonSegment(
          value: TranscriptionMode.http,
          label: Text('Record'),
          icon: Icon(Icons.fiber_manual_record, size: 16),
        ),
        ButtonSegment(
          value: TranscriptionMode.realtime,
          label: Text('Live Stream'),
          icon: Icon(Icons.stream, size: 16),
        ),
      ],
      selected: {mode},
      onSelectionChanged: (selected) {
        ref.read(transcriptionModeProvider.notifier).state = selected.first;
      },
    );
  }

  Widget _buildStatusText(
    RecordingState recordingState,
    TranscriptionMode mode,
  ) {
    String text;
    Color color;

    switch (recordingState) {
      case RecordingState.idle:
        text = mode == TranscriptionMode.http
            ? 'Tap to record'
            : 'Tap to start live stream';
        color = Colors.grey;
        break;
      case RecordingState.recording:
        text = mode == TranscriptionMode.http
            ? 'Recording... Tap to stop'
            : 'Streaming... Tap to stop';
        color = AppColors.recordingRed;
        break;
      case RecordingState.processing:
        if (mode == TranscriptionMode.realtime) {
          text = 'Saving transcription...';
        } else {
          text = 'Processing transcription...';
        }
        color = Colors.amber;
        break;
    }

    return Text(
      text,
      style: TextStyle(fontSize: 14, color: color, fontWeight: FontWeight.w500),
    );
  }

  Widget _buildCollapsibleLivePreview(String text, bool isActive) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.streamingGreen.withValues(alpha: isActive ? 0.5 : 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Collapsible header
          InkWell(
            onTap: () => setState(() => _isLivePreviewExpanded = !_isLivePreviewExpanded),
            borderRadius: _isLivePreviewExpanded
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _isLivePreviewExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: AppColors.streamingGreen,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Live Transcription',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.streamingGreen,
                    ),
                  ),
                  const Spacer(),
                  if (isActive)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.streamingGreen,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Expandable body
          if (_isLivePreviewExpanded) ...[
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              width: double.infinity,
              child: SingleChildScrollView(
                reverse: true,
                child: Text(
                  text.isNotEmpty ? text : 'Listening...',
                  style: TextStyle(
                    fontSize: 14,
                    color: text.isNotEmpty
                        ? null
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontStyle: text.isEmpty ? FontStyle.italic : null,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMicButton(RecordingState recordingState, TranscriptionMode mode) {
    final isRecording = recordingState == RecordingState.recording;
    final isProcessing = recordingState == RecordingState.processing;

    return GestureDetector(
      onTap: isProcessing ? null : () => _handleMicTap(recordingState, mode),
      child: AnimatedBuilder(
        animation: _pulseAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: isRecording ? _pulseAnimation.value : 1.0,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isRecording
                    ? AppColors.recordingRed
                    : isProcessing
                        ? Colors.amber
                        : Theme.of(context).colorScheme.primary,
                boxShadow: isRecording
                    ? [
                        BoxShadow(
                          color: AppColors.recordingRed.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                isRecording
                    ? Icons.stop
                    : isProcessing
                        ? Icons.hourglass_top
                        : Icons.mic,
                size: 36,
                color: Colors.white,
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleMicTap(RecordingState recordingState, TranscriptionMode mode) async {
    final controller = ref.read(transcriptionControllerProvider);

    // Check permissions first
    final hasPermission = await controller.checkPermission();
    if (!hasPermission) {
      ref.read(transcriptionErrorProvider.notifier).state =
          'Microphone permission is required for transcription';
      return;
    }

    if (recordingState == RecordingState.recording) {
      // Stop
      if (mode == TranscriptionMode.http) {
        await controller.stopHttpRecordingAndTranscribe();
      } else {
        await controller.stopRealtimeStream();
      }
    } else if (recordingState == RecordingState.idle) {
      // Start
      if (mode == TranscriptionMode.http) {
        await controller.startHttpRecording();
      } else {
        await controller.startRealtimeStream();
      }
    }
  }
}
