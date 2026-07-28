import 'dart:async';
import 'dart:convert';

import '../exceptions.dart';
import '../lemonade_client.dart';
import '../sse/tool_call_assembler.dart';
import '../types/chat_request.dart';
import '../types/chat_response.dart';

class ChatEndpoint {
  final LemonadeApiClient _client;
  ChatEndpoint(this._client);

  /// `POST /v1/chat/completions` with `stream: false`.
  Future<ChatCompletion> create(
    ChatCompletionRequest request, {
    Duration? timeout,
  }) async {
    if (request.stream) {
      throw StreamProtocolException(
        'create() does not support stream:true; use stream() instead.',
      );
    }
    final body = await _client.postJson(
      _client.apiUriFor('/chat/completions'),
      request.toWireJson(),
      // Non-streaming completions block for the full generation (and possibly
      // a model cold-load) — needs far more headroom than the JSON default.
      timeout: timeout ?? const Duration(minutes: 4),
    );
    return ChatCompletion.fromJson(body);
  }

  /// `POST /v1/chat/completions` with `stream: true`.
  ///
  /// Yields events incrementally:
  /// - [ChatContentDelta] for each new content fragment.
  /// - [ChatToolCallDelta] for each tool-call slot that just received an update.
  /// - [ChatStreamFinish] when the stream signals `finish_reason`.
  ///
  /// The `[DONE]` sentinel ends the stream cleanly even if no finish chunk arrived.
  ///
  /// Truncation contract: if the stream ends or errors WITHOUT a
  /// `finish_reason`/`[DONE]`, the final [ChatStreamFinish] carries
  /// `finishReason: 'interrupted'` with everything accumulated so far —
  /// consumers treat 'interrupted' as retryable, never as a completed answer.
  /// A mid-stream error after content/tool-calls arrived is folded into that
  /// 'interrupted' finish; an error before anything arrived is rethrown as a
  /// typed [LemonadeApiException].
  Stream<ChatStreamEvent> stream(ChatCompletionRequest request) async* {
    final req = ChatCompletionRequest(
      model: request.model,
      messages: request.messages,
      tools: request.tools,
      stream: true,
      temperature: request.temperature,
      topP: request.topP,
      topK: request.topK,
      repeatPenalty: request.repeatPenalty,
      maxCompletionTokens: request.maxCompletionTokens,
      stop: request.stop,
      enableThinking: request.enableThinking,
      extra: request.extra,
    );

    final assembler = ToolCallAssembler();
    final contentBuf = StringBuffer();
    String? finishReason;
    var sawFinish = false;
    var sawDone = false;

    final sse = _client.streamSseFromJsonPost(
      _client.apiUriFor('/chat/completions'),
      req.toWireJson(),
    );

    try {
      await for (final event in sse) {
        final data = event.data.trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') {
          sawDone = true;
          break;
        }

        Map<String, dynamic> chunk;
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map<String, dynamic>) continue;
          chunk = decoded;
        } catch (_) {
          // Skip malformed chunks rather than crashing the stream.
          continue;
        }

        final choices = chunk['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map<String, dynamic>) continue;

        final delta = first['delta'];
        if (delta is Map<String, dynamic>) {
          final content = delta['content'];
          if (content is String && content.isNotEmpty) {
            contentBuf.write(content);
            yield ChatContentDelta(content);
          }
          if (delta['tool_calls'] is List) {
            final touched = assembler.observe(delta);
            if (touched.isNotEmpty) yield ChatToolCallDelta(touched);
          }
        }

        final fr = first['finish_reason'];
        if (fr is String) {
          finishReason = fr;
          sawFinish = true;
        }
      }
    } on LemonadeApiException {
      // streamSseFromJsonPost guarantees typed exceptions. If nothing was
      // accumulated the caller's normal error path handles it; otherwise fold
      // the failure into an 'interrupted' finish so partial content survives.
      if (contentBuf.isEmpty && assembler.isEmpty) rethrow;
    }

    // A stream that ends without finish_reason/[DONE] (drop, idle timeout,
    // transport error) was truncated — report 'interrupted', not 'stop', so
    // consumers can retry instead of presenting a partial answer as complete.
    yield ChatStreamFinish(
      finishReason:
          finishReason ?? (sawDone || sawFinish ? 'stop' : 'interrupted'),
      toolCalls: assembler.finalize(),
      contentSoFar: contentBuf.toString(),
    );
  }
}
