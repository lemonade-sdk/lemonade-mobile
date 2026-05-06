import 'dart:async';
import 'dart:convert';

import '../lemonade_client.dart';
import '../sse/sse_parser.dart';

/// Lemonade admin / management endpoints. See `docs/api/lemonade.md`.
class AdminEndpoint {
  final LemonadeApiClient _client;
  AdminEndpoint(this._client);

  // ---------------------------------------------------------------------------
  // Health / liveness
  // ---------------------------------------------------------------------------

  /// `GET /v1/health` — server status, version, loaded models, max_models, websocket_port.
  Future<Map<String, dynamic>> health() {
    return _client.getJson(_client.apiUriFor('/health'));
  }

  /// `GET /live` — root-mounted lightweight liveness probe.
  Future<bool> live() async {
    try {
      final body = await _client.getJson(_client.rootUriFor('/live'));
      return body['status'] == 'ok';
    } catch (_) {
      return false;
    }
  }

  /// `GET /v1/stats` — performance stats from the last request.
  Future<Map<String, dynamic>> stats() {
    return _client.getJson(_client.apiUriFor('/stats'));
  }

  /// `GET /v1/system-info` — hardware enumeration + recipe / backend states.
  Future<Map<String, dynamic>> systemInfo() {
    return _client.getJson(_client.apiUriFor('/system-info'));
  }

  // ---------------------------------------------------------------------------
  // Model lifecycle
  // ---------------------------------------------------------------------------

  /// `POST /v1/load`. Accepts recipe-specific options (ctx_size, llamacpp_backend,
  /// llamacpp_args, whispercpp_backend, whispercpp_args, steps, cfg_scale, width, height,
  /// save_options).
  Future<Map<String, dynamic>> load({
    required String modelName,
    int? ctxSize,
    String? llamacppBackend,
    String? llamacppArgs,
    String? whispercppBackend,
    String? whispercppArgs,
    int? steps,
    double? cfgScale,
    int? width,
    int? height,
    bool? saveOptions,
    Duration? timeout,
  }) {
    final body = <String, dynamic>{'model_name': modelName};
    if (ctxSize != null) body['ctx_size'] = ctxSize;
    if (llamacppBackend != null) body['llamacpp_backend'] = llamacppBackend;
    if (llamacppArgs != null) body['llamacpp_args'] = llamacppArgs;
    if (whispercppBackend != null) body['whispercpp_backend'] = whispercppBackend;
    if (whispercppArgs != null) body['whispercpp_args'] = whispercppArgs;
    if (steps != null) body['steps'] = steps;
    if (cfgScale != null) body['cfg_scale'] = cfgScale;
    if (width != null) body['width'] = width;
    if (height != null) body['height'] = height;
    if (saveOptions != null) body['save_options'] = saveOptions;
    return _client.postJson(
      _client.apiUriFor('/load'),
      body,
      timeout: timeout ?? const Duration(minutes: 10),
    );
  }

  /// `POST /v1/unload`. Pass [modelName] to unload a specific model, or omit to unload all.
  Future<Map<String, dynamic>> unload({String? modelName}) {
    final body = <String, dynamic>{};
    if (modelName != null) body['model_name'] = modelName;
    return _client.postJson(_client.apiUriFor('/unload'), body);
  }

  /// `POST /v1/delete` — remove a model from local storage.
  Future<Map<String, dynamic>> delete({required String modelName}) {
    return _client.postJson(
      _client.apiUriFor('/delete'),
      {'model_name': modelName},
    );
  }

  // ---------------------------------------------------------------------------
  // Pull (install)
  // ---------------------------------------------------------------------------

  /// `POST /v1/pull` (stream=false) — install/register a model.
  ///
  /// For an already-registered model, only [modelName] is required.
  /// To register-then-install from a HuggingFace checkpoint, also provide [checkpoint] + [recipe].
  Future<Map<String, dynamic>> pull({
    required String modelName,
    String? checkpoint,
    String? recipe,
    bool? reasoning,
    bool? vision,
    bool? embedding,
    bool? reranking,
    String? mmproj,
    Duration? timeout,
  }) {
    final body = _buildPullBody(
      modelName: modelName,
      checkpoint: checkpoint,
      recipe: recipe,
      reasoning: reasoning,
      vision: vision,
      embedding: embedding,
      reranking: reranking,
      mmproj: mmproj,
      stream: false,
    );
    return _client.postJson(
      _client.apiUriFor('/pull'),
      body,
      timeout: timeout ?? const Duration(minutes: 30),
    );
  }

  /// `POST /v1/pull` (stream=true) — install with progress events.
  ///
  /// Yields [PullEvent.progress] frames during download and a final [PullEvent.complete]
  /// or [PullEvent.error]. The stream ends after the terminal event.
  Stream<PullEvent> pullStream({
    required String modelName,
    String? checkpoint,
    String? recipe,
    bool? reasoning,
    bool? vision,
    bool? embedding,
    bool? reranking,
    String? mmproj,
  }) async* {
    final body = _buildPullBody(
      modelName: modelName,
      checkpoint: checkpoint,
      recipe: recipe,
      reasoning: reasoning,
      vision: vision,
      embedding: embedding,
      reranking: reranking,
      mmproj: mmproj,
      stream: true,
    );
    final sse = _client.streamSseFromJsonPost(
      _client.apiUriFor('/pull'),
      body,
    );

    await for (final SseEvent ev in sse) {
      final data = ev.data.trim();
      if (data.isEmpty) continue;
      Map<String, dynamic>? payload;
      try {
        final decoded = jsonDecode(data);
        if (decoded is Map<String, dynamic>) payload = decoded;
      } catch (_) {}
      if (payload == null) continue;

      switch (ev.event) {
        case 'progress':
          yield PullEvent.progress(
            file: payload['file'] as String?,
            fileIndex: (payload['file_index'] as num?)?.toInt(),
            totalFiles: (payload['total_files'] as num?)?.toInt(),
            bytesDownloaded: (payload['bytes_downloaded'] as num?)?.toInt(),
            bytesTotal: (payload['bytes_total'] as num?)?.toInt(),
            percent: (payload['percent'] as num?)?.toDouble(),
          );
          break;
        case 'complete':
          yield PullEvent.complete(
            fileIndex: (payload['file_index'] as num?)?.toInt(),
            totalFiles: (payload['total_files'] as num?)?.toInt(),
          );
          return;
        case 'error':
          yield PullEvent.error(payload['error']?.toString() ?? 'Unknown error');
          return;
        default:
          // Unknown event type — skip.
          break;
      }
    }
  }

  /// `GET /v1/pull/variants?checkpoint=<owner/repo>` — list GGUF variants on a HF repo.
  Future<Map<String, dynamic>> pullVariants({required String checkpoint}) {
    final uri = _client.apiUriFor(
      '/pull/variants',
      query: {'checkpoint': checkpoint},
    );
    return _client.getJson(uri);
  }

  Map<String, dynamic> _buildPullBody({
    required String modelName,
    String? checkpoint,
    String? recipe,
    bool? reasoning,
    bool? vision,
    bool? embedding,
    bool? reranking,
    String? mmproj,
    required bool stream,
  }) {
    final body = <String, dynamic>{'model_name': modelName, 'stream': stream};
    if (checkpoint != null) body['checkpoint'] = checkpoint;
    if (recipe != null) body['recipe'] = recipe;
    if (reasoning != null) body['reasoning'] = reasoning;
    if (vision != null) body['vision'] = vision;
    if (embedding != null) body['embedding'] = embedding;
    if (reranking != null) body['reranking'] = reranking;
    if (mmproj != null) body['mmproj'] = mmproj;
    return body;
  }

  // ---------------------------------------------------------------------------
  // Backend lifecycle
  // ---------------------------------------------------------------------------

  /// `POST /v1/install` — install or update a recipe/backend pair.
  Future<Map<String, dynamic>> install({
    required String recipe,
    required String backend,
    bool force = false,
    Duration? timeout,
  }) {
    return _client.postJson(
      _client.apiUriFor('/install'),
      {
        'recipe': recipe,
        'backend': backend,
        'stream': false,
        if (force) 'force': true,
      },
      timeout: timeout ?? const Duration(minutes: 30),
    );
  }

  /// `POST /v1/uninstall` — remove a backend.
  Future<Map<String, dynamic>> uninstall({
    required String recipe,
    required String backend,
  }) {
    return _client.postJson(
      _client.apiUriFor('/uninstall'),
      {'recipe': recipe, 'backend': backend},
    );
  }
}

/// Streaming events from `POST /v1/pull` with `stream: true`.
sealed class PullEvent {
  const PullEvent();

  factory PullEvent.progress({
    String? file,
    int? fileIndex,
    int? totalFiles,
    int? bytesDownloaded,
    int? bytesTotal,
    double? percent,
  }) = PullProgress;

  factory PullEvent.complete({int? fileIndex, int? totalFiles}) = PullComplete;
  factory PullEvent.error(String message) = PullError;
}

class PullProgress extends PullEvent {
  final String? file;
  final int? fileIndex;
  final int? totalFiles;
  final int? bytesDownloaded;
  final int? bytesTotal;
  final double? percent;

  const PullProgress({
    this.file,
    this.fileIndex,
    this.totalFiles,
    this.bytesDownloaded,
    this.bytesTotal,
    this.percent,
  });
}

class PullComplete extends PullEvent {
  final int? fileIndex;
  final int? totalFiles;
  const PullComplete({this.fileIndex, this.totalFiles});
}

class PullError extends PullEvent {
  final String message;
  const PullError(this.message);
}
