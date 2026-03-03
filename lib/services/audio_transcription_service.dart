import 'dart:convert';
import 'package:http/http.dart' as http;
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

  /// Discover WebSocket port from the health endpoint.
  /// Returns the port number or null if not available.
  Future<int?> discoverWebSocketPort() async {
    try {
      // Try the health endpoint
      final healthUrl = Uri.parse('$_apiUrl/health');
      final response = await http.get(
        healthUrl,
        headers: {'Authorization': _authHeader},
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        // Check for WebSocket port in response
        if (data['ws_port'] != null) {
          return data['ws_port'] as int;
        }
        if (data['websocket_port'] != null) {
          return data['websocket_port'] as int;
        }
      }
    } catch (e) {
      // Health endpoint not available
    }

    // Default: try using the same port as HTTP
    try {
      final uri = Uri.parse(server.baseUrl);
      return uri.port;
    } catch (e) {
      return null;
    }
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
