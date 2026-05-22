import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/types/tool_call.dart';
import '../models/chat_message.dart';
import '../models/transcription.dart';
import '../omni/tool_executor.dart';
import '../providers/chat_history_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/model_defaults_provider.dart';
import '../providers/omni_router_provider.dart';
import '../providers/servers_provider.dart';
import '../providers/transcription_provider.dart';
import '../services/audio_recorder_service.dart';
import '../services/audio_transcription_service.dart';

/// Bottom sheet that captures a short voice clip, transcribes it, and offers
/// the user a choice: send as a text message, generate an image from it, or
/// cancel.
///
/// This is the inline voice → text + voice → image entry point. The
/// transcription history screen still owns the long-form recording flow.
class VoiceInputSheet extends ConsumerStatefulWidget {
  final ScrollController? chatScrollController;
  const VoiceInputSheet({super.key, this.chatScrollController});

  @override
  ConsumerState<VoiceInputSheet> createState() => _VoiceInputSheetState();

  static Future<void> show(BuildContext context, {ScrollController? chatScrollController}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => VoiceInputSheet(chatScrollController: chatScrollController),
    );
  }
}

enum _Stage { idle, recording, processing, ready, error }

class _VoiceInputSheetState extends ConsumerState<VoiceInputSheet> {
  final _recorder = AudioRecorderService();
  _Stage _stage = _Stage.idle;
  String? _transcript;
  String? _error;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_stage == _Stage.recording) {
      await _stopAndTranscribe();
    } else if (_stage == _Stage.idle || _stage == _Stage.error) {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final ok = await _recorder.hasPermission();
    if (!ok) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Microphone permission is required.';
      });
      return;
    }
    try {
      final path = await _recorder.startFileRecording();
      // path is held by AudioRecorderService internally; we don't need to retain it
      // ourselves until the stop call returns the persisted path.
      // ignore: unnecessary_statements
      path;
      setState(() {
        _stage = _Stage.recording;
        _transcript = null;
        _error = null;
      });
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Failed to start recording: $e';
      });
    }
  }

  Future<void> _stopAndTranscribe() async {
    setState(() => _stage = _Stage.processing);
    try {
      final tempPath = await _recorder.stopFileRecording();
      if (tempPath == null) {
        setState(() {
          _stage = _Stage.error;
          _error = 'Recording produced no audio.';
        });
        return;
      }
      final persisted = await _recorder.persistRecording(tempPath);

      final server = ref.read(selectedServerProvider);
      if (server == null) {
        setState(() {
          _stage = _Stage.error;
          _error = 'No server selected.';
        });
        return;
      }

      final asrModel = ref.read(effectiveAudioModelProvider);
      final svc = AudioTranscriptionService(server);
      final text = await svc.transcribeFile(persisted, model: asrModel);
      setState(() {
        _stage = _Stage.ready;
        _transcript = text;
      });

      // Persist to transcription history regardless of how the user uses it.
      await ref.read(transcriptionHistoryProvider.notifier).addTranscription(
            text: text,
            modelId: asrModel,
            mode: TranscriptionMode.http,
            serverName: server.name,
            audioFilePath: persisted,
          );
    } catch (e) {
      setState(() {
        _stage = _Stage.error;
        _error = 'Transcription failed: $e';
      });
    }
  }

  Future<void> _sendAsMessage() async {
    final text = _transcript;
    if (text == null || text.isEmpty) return;
    Navigator.of(context).pop();
    await ref.read(chatProvider.notifier).sendMessage(
          text,
          scrollController: widget.chatScrollController,
        );
  }

  Future<void> _sendAsImagePrompt() async {
    final text = _transcript;
    if (text == null || text.isEmpty) return;
    final exec = ref.read(omniToolExecutorProvider);
    final caps = ref.read(omniCapabilitiesProvider);
    if (exec == null || !(caps?.has('generate_image') ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('No image-generation model is loaded.'),
      ));
      return;
    }
    Navigator.of(context).pop();

    // Append a user note + assistant placeholder, run generate_image, fill in.
    final notifier = ref.read(chatHistoryProvider.notifier);
    final history = notifier.getActiveChat()?.messages ?? const <ChatMessage>[];

    final userMsg = ChatMessage.text(
      role: MessageRole.user,
      text: '🎙️→🎨  $text',
    );
    final placeholder = ChatMessage.text(
      role: MessageRole.assistant,
      text: 'Generating image…',
    );
    var working = [...history, userMsg, placeholder];
    await notifier.updateActiveChat(working);

    final call = ToolCall(
      id: 'voice_to_image_${DateTime.now().microsecondsSinceEpoch}',
      name: 'generate_image',
      argumentsJson: '{"prompt":${_jsonString(text)},"size":"512x512"}',
    );
    final ctx = ToolExecutionContext(
      extractedAudio: const [],
      extractedImages: const [],
      sourceArtifacts: const [],
      turnArtifacts: <Artifact>[],
    );
    final result = await exec.execute(call, ctx);
    final finalContents = <MessageContent>[];
    switch (result) {
      case ImageResult():
        finalContents.add(MessageContent(
          type: MessageContentType.image,
          value: 'data:${result.mime};base64,${result.base64Data}',
        ));
      case ErrorResult():
        finalContents.add(MessageContent(
          type: MessageContentType.text,
          value: 'Error: ${result.message}',
        ));
      case TextResult():
        finalContents.add(MessageContent(
          type: MessageContentType.text,
          value: result.text,
        ));
      case AudioResult():
        finalContents.add(MessageContent(
          type: MessageContentType.audio,
          value: 'data:${result.mime};base64,${result.base64Data}',
        ));
      case EndCallResult():
        // end_call is a voice-mode control signal; no chat-side effect here.
        break;
    }
    final finalMsg = ChatMessage(role: MessageRole.assistant, content: finalContents);
    final updated = [...working.sublist(0, working.length - 1), finalMsg];
    await notifier.updateActiveChat(updated);
  }

  String _jsonString(String s) {
    final escaped = s
        .replaceAll('\\', '\\\\')
        .replaceAll('"', '\\"')
        .replaceAll('\n', '\\n')
        .replaceAll('\r', '\\r')
        .replaceAll('\t', '\\t');
    return '"$escaped"';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final caps = ref.watch(omniCapabilitiesProvider);
    final canImage = caps?.has('generate_image') ?? false;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Voice input', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _stage == _Stage.processing ? null : _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: switch (_stage) {
                    _Stage.recording => Colors.redAccent,
                    _Stage.processing => Colors.amber,
                    _Stage.ready => scheme.primary,
                    _Stage.error => Colors.redAccent.withValues(alpha: 0.5),
                    _Stage.idle => scheme.primary,
                  },
                  boxShadow: _stage == _Stage.recording
                      ? [
                          BoxShadow(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  switch (_stage) {
                    _Stage.recording => Icons.stop,
                    _Stage.processing => Icons.hourglass_top,
                    _Stage.ready => Icons.check,
                    _Stage.error => Icons.error_outline,
                    _Stage.idle => Icons.mic,
                  },
                  color: scheme.onPrimary,
                  size: 40,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              switch (_stage) {
                _Stage.recording => 'Tap to stop',
                _Stage.processing => 'Transcribing…',
                _Stage.ready => 'Done',
                _Stage.error => _error ?? 'Error',
                _Stage.idle => 'Tap to start',
              },
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          if (_transcript != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_transcript!),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _stage = _Stage.idle;
                        _transcript = null;
                      });
                    },
                    icon: const Icon(Icons.replay),
                    label: const Text('Re-record'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: canImage ? _sendAsImagePrompt : null,
                    icon: const Icon(Icons.brush),
                    label: const Text('To image'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _sendAsMessage,
                    icon: const Icon(Icons.send),
                    label: const Text('Send'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

