import 'dart:convert';
import 'dart:typed_data';

import '../api/lemonade_client.dart';
import '../api/types/audio_request.dart';
import '../api/types/chat_message.dart';
import '../api/types/chat_request.dart';
import '../api/types/image_request.dart';
import '../api/types/tool_call.dart';

/// In-conversation context for tool execution. The agent loop populates this
/// before invoking executors so tools have access to the binary blobs that the
/// LLM was shown only as placeholder text.
class ToolExecutionContext {
  /// User-attached audio data (base64) extracted from message history.
  /// Indices align with `[User provided audio file #N]` placeholders.
  final List<({String data, String mime})> extractedAudio;

  /// User-attached images (data URLs) from message history.
  /// Indices align with `[User provided image #N]` placeholders.
  final List<({String dataUrl, String mime, String base64})> extractedImages;

  /// Artifacts produced earlier in the conversation (prior turns) — used as
  /// `edit_image` source. Not rendered in this turn's output.
  final List<Artifact> sourceArtifacts;

  /// Artifacts generated *this turn* by tool calls. The agent loop appends to
  /// this list so later iterations can reference them.
  final List<Artifact> turnArtifacts;

  ToolExecutionContext({
    required this.extractedAudio,
    required this.extractedImages,
    required this.sourceArtifacts,
    required this.turnArtifacts,
  });
}

/// A piece of binary content produced or consumed by a tool.
class Artifact {
  final ArtifactKind kind;
  final String mime;

  /// Base64-encoded payload. Files-on-disk references are not used here; the
  /// agent loop persists artifacts to disk after this turn.
  final String base64Data;

  const Artifact({required this.kind, required this.mime, required this.base64Data});
}

enum ArtifactKind { image, audio }

/// Per-tool result returned by [OmniToolExecutor.execute]. The agent loop turns
/// this into a tool-role message + (when applicable) a turn artifact.
sealed class ToolExecutionResult {
  const ToolExecutionResult();
}

class TextResult extends ToolExecutionResult {
  final String text;
  const TextResult(this.text);
}

class ImageResult extends ToolExecutionResult {
  final String base64Data;
  final String mime;
  /// 'generate' | 'edit' — used by the agent loop to decide whether this
  /// replaces the prior turn artifact or appends a new one.
  final String mode;
  const ImageResult({
    required this.base64Data,
    required this.mime,
    required this.mode,
  });
}

class AudioResult extends ToolExecutionResult {
  final String base64Data;
  final String mime;
  const AudioResult({required this.base64Data, required this.mime});
}

class ErrorResult extends ToolExecutionResult {
  final String message;
  const ErrorResult(this.message);
}

/// Translates a tool_call into the appropriate Lemonade endpoint call.
class OmniToolExecutor {
  final LemonadeApiClient client;

  /// Maps tool name → model id chosen for that tool.
  final Map<String, String> toolModels;

  OmniToolExecutor({required this.client, required this.toolModels});

  Future<ToolExecutionResult> execute(
    ToolCall call,
    ToolExecutionContext ctx,
  ) async {
    Map<String, dynamic> args;
    try {
      args = jsonDecode(call.argumentsJson) as Map<String, dynamic>;
    } catch (_) {
      args = {};
    }

    // generate_image → edit_image redirect when a prior image exists and the
    // chosen image model also supports edit. Mirrors the desktop reference.
    final hasPriorImage = ctx.sourceArtifacts.any((a) => a.kind == ArtifactKind.image) ||
        ctx.turnArtifacts.any((a) => a.kind == ArtifactKind.image);
    final editModel = toolModels['edit_image'];
    final effective = (call.name == 'generate_image' && hasPriorImage && editModel != null)
        ? 'edit_image'
        : call.name;

    switch (effective) {
      case 'generate_image':
        return _generate(args);
      case 'edit_image':
        return _edit(args, ctx);
      case 'text_to_speech':
        return _tts(args);
      case 'transcribe_audio':
        return _transcribe(args, ctx);
      case 'analyze_image':
        return _analyze(args, ctx);
      default:
        return ErrorResult("Unknown tool '${call.name}'");
    }
  }

  Future<ToolExecutionResult> _generate(Map<String, dynamic> args) async {
    final model = toolModels['generate_image'];
    if (model == null) return const ErrorResult('No image model is loaded.');

    final basePrompt = (args['image_prompt'] ?? args['prompt']) as String? ?? '';
    final style = args['style'] as String?;
    final prompt = _prependStyle(basePrompt, style);

    // aspect_ratio is the new schema; legacy `size` still works.
    final size = (args['size'] as String?) ?? _sizeForAspect(args['aspect_ratio'] as String?);

    final req = ImageGenerationRequest.bySize(
      model: model,
      prompt: prompt,
      size: size,
    );
    try {
      final resp = await client.images.generate(req);
      final first = resp.images.firstOrNull;
      if (first?.b64Json == null) {
        return const ErrorResult('Image generation returned no data.');
      }
      return ImageResult(
        base64Data: first!.b64Json!,
        mime: 'image/png',
        mode: 'generate',
      );
    } catch (e) {
      return ErrorResult('Image generation failed: $e');
    }
  }

  /// Lemonade's image endpoint takes a single `prompt` — there's no separate
  /// style field, so we fold style into the prompt text. Style tokens at the
  /// start of the prompt have a stronger weight in most diffusion models.
  String _prependStyle(String prompt, String? style) {
    if (style == null || style.isEmpty) return prompt;
    final modifier = switch (style) {
      'photographic' => 'photorealistic, photograph, sharp focus',
      'anime' => 'anime style, cel shaded',
      'digital_art' => 'digital art, concept art, trending on artstation',
      'sketch' => 'pencil sketch, hand-drawn, line art',
      _ => style,
    };
    return '$modifier, $prompt';
  }

  /// Translate the LLM-friendly `aspect_ratio` enum into the WxH string the
  /// image endpoint expects. Defaults to 1:1 when unset / unknown.
  String _sizeForAspect(String? aspect) {
    switch (aspect) {
      case '16:9':
        return '1024x576';
      case '9:16':
        return '576x1024';
      case '1:1':
      default:
        return '1024x1024';
    }
  }

  Future<ToolExecutionResult> _edit(
      Map<String, dynamic> args, ToolExecutionContext ctx) async {
    final model = toolModels['edit_image'] ?? toolModels['generate_image'];
    if (model == null) return const ErrorResult('No image model is loaded.');

    // Source: the most recent image in turn artifacts, then prior conversation.
    final source = [...ctx.turnArtifacts, ...ctx.sourceArtifacts]
        .where((a) => a.kind == ArtifactKind.image)
        .lastOrNull;
    if (source == null) {
      return const ErrorResult('No image in this conversation to edit.');
    }

    final bytes = base64Decode(source.base64Data);
    final req = ImageEditRequest(
      model: model,
      prompt: args['prompt'] as String? ?? '',
      sourceImageBytes: bytes,
      sourceImageMime: source.mime,
      sourceFilename: 'image.${source.mime.split('/').last}',
      size: args['size'] as String?,
    );
    try {
      final resp = await client.images.edit(req);
      final first = resp.images.firstOrNull;
      if (first?.b64Json == null) {
        return const ErrorResult('Image edit returned no data.');
      }
      return ImageResult(
        base64Data: first!.b64Json!,
        mime: 'image/png',
        mode: 'edit',
      );
    } catch (e) {
      return ErrorResult('Image edit failed: $e');
    }
  }

  Future<ToolExecutionResult> _tts(Map<String, dynamic> args) async {
    final model = toolModels['text_to_speech'];
    if (model == null) return const ErrorResult('No TTS model is loaded.');

    final input = (args['text_to_speak'] ?? args['input']) as String? ?? '';
    final voice = (args['voice'] as String?) ??
        _voiceForProfile(args['voice_profile'] as String?);

    final req = TextToSpeechRequest(
      model: model,
      input: input,
      voice: voice,
      responseFormat: 'mp3',
    );
    try {
      final result = await client.audio.speech(req);
      return AudioResult(
        base64Data: base64Encode(result.audioBytes),
        mime: result.mime,
      );
    } catch (e) {
      return ErrorResult('Text-to-speech failed: $e');
    }
  }

  /// Map the LLM-friendly voice_profile enum onto specific Kokoro voice IDs.
  /// Falls back to the long-standing default when nothing matches.
  String _voiceForProfile(String? profile) {
    switch (profile) {
      case 'calm_female':
        return 'af_bella';
      case 'energetic_male':
        return 'am_michael';
      case 'storyteller':
        return 'bm_george';
      case 'professional_neutral':
      default:
        return 'af_heart';
    }
  }

  Future<ToolExecutionResult> _transcribe(
      Map<String, dynamic> args, ToolExecutionContext ctx) async {
    final model = toolModels['transcribe_audio'];
    if (model == null) return const ErrorResult('No transcription model is loaded.');
    if (ctx.extractedAudio.isEmpty) {
      return const TextResult('No audio data was provided to transcribe.');
    }

    final audio = ctx.extractedAudio.first;
    final ext = _extensionFor(audio.mime);
    final bytes = base64Decode(audio.data);
    final req = TranscriptionRequest(
      model: model,
      audioBytes: bytes,
      audioFilename: 'audio$ext',
      audioMime: audio.mime,
      language: args['language'] as String?,
    );
    try {
      final result = await client.audio.transcribe(req);
      return TextResult('Transcription: ${result.text}');
    } catch (e) {
      return ErrorResult('Transcription failed: $e');
    }
  }

  Future<ToolExecutionResult> _analyze(
      Map<String, dynamic> args, ToolExecutionContext ctx) async {
    final model = toolModels['analyze_image'];
    if (model == null) {
      return const ErrorResult('No vision-capable model is loaded.');
    }

    String imageUrl = '';
    final raw = args['image_url'];
    if (raw is String && raw.startsWith('data:image/')) {
      imageUrl = raw;
    } else if (ctx.extractedImages.isNotEmpty) {
      imageUrl = ctx.extractedImages.last.dataUrl;
    } else if (ctx.sourceArtifacts.isNotEmpty) {
      final lastImage = ctx.sourceArtifacts
          .where((a) => a.kind == ArtifactKind.image)
          .lastOrNull;
      if (lastImage != null) {
        imageUrl = 'data:${lastImage.mime};base64,${lastImage.base64Data}';
      }
    }
    if (imageUrl.isEmpty) {
      return const TextResult('No image is available to analyze.');
    }

    final question = args['question'] as String? ?? 'Describe this image.';
    final req = ChatCompletionRequest(
      model: model,
      messages: [
        ApiChatMessage.userParts([
          ApiContentPart.imageUrl(imageUrl),
          ApiContentPart.text(question),
        ]),
      ],
      stream: false,
    );
    try {
      final resp = await client.chat.create(req);
      return TextResult(resp.message.content ?? '');
    } catch (e) {
      return ErrorResult('Image analysis failed: $e');
    }
  }

  String _extensionFor(String mime) {
    if (mime.contains('mp3') || mime.contains('mpeg')) return '.mp3';
    if (mime.contains('m4a') || mime.contains('mp4')) return '.m4a';
    if (mime.contains('ogg')) return '.ogg';
    if (mime.contains('flac')) return '.flac';
    if (mime.contains('webm')) return '.webm';
    return '.wav';
  }
}

/// Convert a raw image bytes payload into a base64 string. Used by callers
/// preparing tool execution context.
String encodeBytes(Uint8List bytes) => base64Encode(bytes);

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }

  T? get lastOrNull {
    T? last;
    for (final v in this) {
      last = v;
    }
    return last;
  }
}
