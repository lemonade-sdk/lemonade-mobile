import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:lemonade_mobile/models/server_config.dart';

class AudioTranscriptionService {
  final ServerConfig server;

  AudioTranscriptionService(this.server);

  String get _apiUrl => server.apiUrl;

  String get _authHeader => 'Bearer ${server.apiKey ?? "lemonade"}';

  /// Transcribe an audio file via HTTP POST multipart/form-data.
  /// Returns the transcribed text.
  Future<String> transcribeFile(String filePath, {String? model}) async {
    final url = Uri.parse('$_apiUrl/audio/transcriptions');

    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = _authHeader;

    request.files.add(await http.MultipartFile.fromPath('file', filePath));
    request.fields['model'] = (model != null && model.isNotEmpty) ? model : 'whisper-1';
    request.fields['response_format'] = 'json';

    final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Transcription failed with status ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['text'] as String? ?? '';
  }

  /// Transcribe in-memory WAV [bytes] via HTTP POST multipart/form-data.
  /// Used by the non-WebSocket call-mode fallback. Returns the transcript.
  Future<String> transcribeWavBytes(List<int> bytes, {String? model}) async {
    final url = Uri.parse('$_apiUrl/audio/transcriptions');

    final request = http.MultipartRequest('POST', url);
    request.headers['Authorization'] = _authHeader;
    request.files.add(http.MultipartFile.fromBytes(
      'file',
      bytes,
      filename: 'audio.wav',
      contentType: MediaType('audio', 'wav'),
    ));
    request.fields['model'] = (model != null && model.isNotEmpty) ? model : 'whisper-1';
    request.fields['response_format'] = 'json';

    final streamedResponse = await request.send().timeout(const Duration(minutes: 5));
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('Transcription failed with status ${response.statusCode}: ${response.body}');
    }

    final data = jsonDecode(response.body);
    return data['text'] as String? ?? '';
  }

  /// Discover the dedicated WebSocket port from the server's health endpoint.
  /// Returns null when the server doesn't advertise one — callers must NOT
  /// treat the HTTP API port as a discovered WS port. (The old fallback
  /// returned the HTTP port here, so the realtime socket dialed the plain
  /// HTTP API and failed with "was not upgraded to websocket";
  /// RealtimeAudioSocket.connect handles its own same-port upgrade attempts.)
  Future<int?> discoverWebSocketPort() async {
    // Lemonade serves health under the API base; some builds also expose it
    // at the server root. Check both.
    final baseNoSlash = server.baseUrl.replaceAll(RegExp(r'/+$'), '');
    for (final healthUrl in ['$_apiUrl/health', '$baseNoSlash/health']) {
      try {
        final response = await http.get(
          Uri.parse(healthUrl),
          headers: {'Authorization': _authHeader},
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final port = data['ws_port'] ?? data['websocket_port'];
          if (port is int) return port;
          if (port is String) return int.tryParse(port);
        }
      } catch (e) {
        // Health endpoint not available at this path — try the next.
      }
    }
    return null;
  }

  /// Get the base URL host for WebSocket connections.
  String get wsHost {
    final uri = Uri.parse(server.baseUrl);
    return uri.host;
  }

  /// Get the base URL port for WebSocket connections.
  int get wsPort {
    final uri = Uri.parse(server.baseUrl);
    return uri.port != 0 ? uri.port : (uri.scheme == 'https' ? 443 : 80);
  }

  /// Check if the transcription endpoint is available.
  Future<bool> isAvailable() async {
    try {
      // Try an OPTIONS or small GET to check availability
      final url = Uri.parse('$_apiUrl/audio/transcriptions');
      final response = await http.head(
        url,
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 5));
      // Accept any non-error status
      return response.statusCode < 500;
    } catch (e) {
      return false;
    }
  }
}
