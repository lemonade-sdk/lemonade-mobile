import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../api/lemonade_client.dart';
import '../api/types/audio_request.dart';
import '../models/server_config.dart';

/// ASR helpers for the active Lemonade server: HTTP transcription (via the
/// shared [AudioEndpoint]) and realtime WebSocket port discovery.
///
/// HTTP paths used to open a raw [http.MultipartRequest] that bypassed
/// timeouts, auth headers (`X-Nexus-Agent`), and typed error mapping — so a
/// 401/500 from ASR looked different than the same failure from tools.
class AudioTranscriptionService {
  final LemonadeApiClient client;

  AudioTranscriptionService(this.client);

  ServerConfig get server => client.server;

  String get _apiUrl => server.apiUrl;

  /// Transcribe an audio file via `POST /v1/audio/transcriptions`.
  Future<String> transcribeFile(String filePath, {String? model}) async {
    final bytes = await File(filePath).readAsBytes();
    final name = filePath.split('/').last.toLowerCase();
    final mime = name.endsWith('.wav')
        ? 'audio/wav'
        : name.endsWith('.m4a') || name.endsWith('.mp4')
            ? 'audio/mp4'
            : name.endsWith('.mp3')
                ? 'audio/mpeg'
                : 'application/octet-stream';
    return _transcribe(
      bytes: bytes,
      filename: filePath.split('/').last,
      mime: mime,
      model: model,
    );
  }

  /// Transcribe in-memory WAV [bytes]. Used by the non-WebSocket call-mode
  /// fallback.
  Future<String> transcribeWavBytes(List<int> bytes, {String? model}) =>
      _transcribe(
        bytes: bytes,
        filename: 'audio.wav',
        mime: 'audio/wav',
        model: model,
      );

  Future<String> _transcribe({
    required List<int> bytes,
    required String filename,
    required String mime,
    String? model,
  }) async {
    final result = await client.audio.transcribe(TranscriptionRequest(
      model: (model != null && model.isNotEmpty) ? model : 'whisper-1',
      audioBytes: bytes,
      audioFilename: filename,
      audioMime: mime,
      responseFormat: 'json',
    ));
    return result.text;
  }

  /// Discovered WS ports per API base URL. Probing can cost ~10s against
  /// servers without a `/health` endpoint and the answer doesn't change
  /// while the server is up, so cache it (including "no port advertised" —
  /// stored as null). Invalidated via [invalidateWebSocketPortCache] when a
  /// realtime connect subsequently fails.
  static final Map<String, int?> _wsPortCache = <String, int?>{};

  /// Drop the cached WS port for [server] (e.g. after a realtime WebSocket
  /// connect failure) so the next call re-probes the health endpoint.
  static void invalidateWebSocketPortCache(ServerConfig server) {
    _wsPortCache.remove(server.apiUrl);
  }

  /// Discover the dedicated WebSocket port from the server's health endpoint.
  /// Returns null when the server doesn't advertise one — callers must NOT
  /// treat the HTTP API port as a discovered WS port.
  Future<int?> discoverWebSocketPort() async {
    if (_wsPortCache.containsKey(_apiUrl)) return _wsPortCache[_apiUrl];

    final auth = 'Bearer ${server.apiKey ?? "lemonade"}';
    final baseNoSlash = server.baseUrl.replaceAll(RegExp(r'/+$'), '');
    for (final healthUrl in ['$_apiUrl/health', '$baseNoSlash/health']) {
      try {
        final response = await http.get(
          Uri.parse(healthUrl),
          headers: {'Authorization': auth},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final port = data['ws_port'] ?? data['websocket_port'];
          final resolved =
              port is int ? port : (port is String ? int.tryParse(port) : null);
          if (resolved != null) {
            _wsPortCache[_apiUrl] = resolved;
            return resolved;
          }
        }
      } catch (_) {
        // Health endpoint not available at this path — try the next.
      }
    }
    _wsPortCache[_apiUrl] = null;
    return null;
  }

  /// Get the base URL host for WebSocket connections.
  String get wsHost => Uri.parse(server.baseUrl).host;

  /// Get the base URL port for WebSocket connections.
  int get wsPort {
    final uri = Uri.parse(server.baseUrl);
    return uri.port != 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  }
}
