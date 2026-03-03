import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:lemonade_mobile/models/server_config.dart';

enum RealtimeConnectionState {
  disconnected,
  connecting,
  connected,
  error,
}

class RealtimeTranscriptionService {
  final ServerConfig server;

  WebSocketChannel? _channel;
  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;
  final _stateController = StreamController<RealtimeConnectionState>.broadcast();
  final _transcriptController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  String _accumulatedText = '';
  Completer<void>? _finalTranscriptCompleter;
  Timer? _drainTimer;

  RealtimeTranscriptionService(this.server);

  RealtimeConnectionState get state => _state;
  Stream<RealtimeConnectionState> get stateStream => _stateController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get errorStream => _errorController.stream;
  String get accumulatedText => _accumulatedText;

  /// Connect to the WebSocket realtime transcription endpoint.
  Future<void> connect({String? model, int? port}) async {
    if (_state == RealtimeConnectionState.connected ||
        _state == RealtimeConnectionState.connecting) {
      return;
    }

    _setState(RealtimeConnectionState.connecting);
    _accumulatedText = '';

    try {
      final uri = _buildWsUri(model: model, port: port);
      _channel = WebSocketChannel.connect(uri);

      // Wait for connection
      await _channel!.ready;
      _setState(RealtimeConnectionState.connected);

      // Send session configuration
      _sendSessionUpdate(model: model);

      // Listen for messages
      _channel!.stream.listen(
        _handleMessage,
        onError: (error) {
          _errorController.add('WebSocket error: $error');
          _setState(RealtimeConnectionState.error);
        },
        onDone: () {
          _setState(RealtimeConnectionState.disconnected);
        },
      );
    } catch (e) {
      _errorController.add('Connection failed: $e');
      _setState(RealtimeConnectionState.error);
    }
  }

  /// Send a base64-encoded audio chunk to the WebSocket.
  void sendAudioChunk(String base64Audio) {
    if (_state != RealtimeConnectionState.connected) return;

    final message = jsonEncode({
      'type': 'input_audio_buffer.append',
      'audio': base64Audio,
    });
    _channel?.sink.add(message);
  }

  /// Commit the audio buffer (signal end of speech segment).
  void commitAudioBuffer() {
    if (_state != RealtimeConnectionState.connected) return;

    final message = jsonEncode({
      'type': 'input_audio_buffer.commit',
    });
    _channel?.sink.add(message);
  }

  /// Commit the audio buffer and wait for ALL pending transcriptions to finish.
  ///
  /// Uses a debounce: each time a `completed` message arrives, a short drain
  /// timer is reset. Once no more `completed` messages arrive for [drainDelay],
  /// the future resolves. A hard [timeout] ensures we don't wait forever.
  Future<void> commitAndWaitForFinal({
    Duration timeout = const Duration(seconds: 45),
    Duration drainDelay = const Duration(seconds: 5),
  }) async {
    if (_state != RealtimeConnectionState.connected) return;

    _finalTranscriptCompleter = Completer<void>();
    _drainTimer?.cancel();
    commitAudioBuffer();

    // Start initial drain timer — if no completed arrives at all,
    // the drain timer fires after drainDelay and resolves.
    _drainTimer = Timer(drainDelay, () {
      if (_finalTranscriptCompleter != null &&
          !_finalTranscriptCompleter!.isCompleted) {
        _finalTranscriptCompleter!.complete();
      }
    });

    try {
      await _finalTranscriptCompleter!.future.timeout(timeout);
    } on TimeoutException {
      // Hard timeout — proceed with disconnect anyway
    }
    _drainTimer?.cancel();
    _drainTimer = null;
    _finalTranscriptCompleter = null;
  }

  /// Disconnect from the WebSocket.
  Future<void> disconnect() async {
    if (_channel != null) {
      await _channel!.sink.close();
      _channel = null;
    }
    _setState(RealtimeConnectionState.disconnected);
  }

  Uri _buildWsUri({String? model, int? port}) {
    final httpUri = Uri.parse(server.baseUrl);
    final scheme = httpUri.scheme == 'https' ? 'wss' : 'ws';
    // WebSocket runs on a separate port discovered via /health endpoint
    final effectivePort = port ?? httpUri.port;
    final effectiveModel = model ?? 'whisper-1';
    return Uri(
      scheme: scheme,
      host: httpUri.host,
      port: effectivePort,
      path: '/',
      queryParameters: {
        'model': effectiveModel,
      },
    );
  }

  void _sendSessionUpdate({String? model}) {
    final effectiveModel = model ?? 'whisper-1';
    final session = <String, dynamic>{
      'type': 'session.update',
      'session': {
        'model': effectiveModel,
      },
    };
    _channel?.sink.add(jsonEncode(session));
  }

  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String);
      final type = data['type'] as String?;

      switch (type) {
        case 'conversation.item.input_audio_transcription.delta':
          // Interim/partial transcription while speech is ongoing
          final delta = data['delta'] as String?;
          if (delta != null) {
            _accumulatedText += delta;
            _transcriptController.add(_accumulatedText);
          }
          break;
        case 'conversation.item.input_audio_transcription.completed':
          // Final transcription after speech ends or commit
          final transcript = data['transcript'] as String?;
          if (transcript != null) {
            _accumulatedText = transcript;
            _transcriptController.add(_accumulatedText);
          }
          // Reset the drain timer — wait for more completeds before resolving.
          // Each completed resets the timer so we catch all in-flight results.
          if (_finalTranscriptCompleter != null &&
              !_finalTranscriptCompleter!.isCompleted) {
            _drainTimer?.cancel();
            _drainTimer = Timer(const Duration(seconds: 25), () {
              if (_finalTranscriptCompleter != null &&
                  !_finalTranscriptCompleter!.isCompleted) {
                _finalTranscriptCompleter!.complete();
              }
            });
          }
          break;
        case 'error':
          final errorMsg = data['error']?['message'] as String? ?? 'Unknown error';
          _errorController.add(errorMsg);
          break;
        case 'session.created':
        case 'session.updated':
        case 'input_audio_buffer.speech_started':
        case 'input_audio_buffer.speech_stopped':
        case 'input_audio_buffer.committed':
        case 'input_audio_buffer.cleared':
          // Informational events
          break;
      }
    } catch (e) {
      _errorController.add('Failed to parse message: $e');
    }
  }

  void _setState(RealtimeConnectionState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _drainTimer?.cancel();
    _drainTimer = null;
    disconnect();
    _stateController.close();
    _transcriptController.close();
    _errorController.close();
  }
}
