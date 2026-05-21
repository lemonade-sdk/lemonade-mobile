import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../lemonade_client.dart';

/// Typed wrapper over Lemonade's WebSocket audio-transcription protocol.
///
/// Lifecycle:
///   1. [connect] — opens the WS and sends `session.update` with the chosen model.
///   2. [appendAudio] — stream PCM16 (or supported audio) chunks as base64.
///   3. [commit] — signal end of an audio buffer; server emits a final transcription.
///   4. [close] — tear down.
///
/// Streams [events] for parsed messages and [state] for connection lifecycle.
class RealtimeAudioSocket {
  final LemonadeApiClient _client;
  WebSocketChannel? _channel;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _state = StreamController<RealtimeConnectionState>.broadcast();

  RealtimeConnectionState _currentState = RealtimeConnectionState.disconnected;

  RealtimeAudioSocket(this._client);

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeConnectionState> get state => _state.stream;
  RealtimeConnectionState get currentState => _currentState;

  Future<void> connect({required String model, int? port}) async {
    _emitState(RealtimeConnectionState.connecting);
    final apiUri = Uri.parse(_client.server.apiUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final effectivePort = port ?? (apiUri.hasPort ? apiUri.port : (scheme == 'wss' ? 443 : 80));
    final uri = Uri(
      scheme: scheme,
      host: apiUri.host,
      port: effectivePort,
      path: '/',
      queryParameters: {'model': model},
    );

    _channel = WebSocketChannel.connect(uri);

    _channel!.stream.listen(
      _onMessage,
      onError: (err) {
        _events.add(RealtimeEvent.error(err.toString()));
        _emitState(RealtimeConnectionState.error);
      },
      onDone: () => _emitState(RealtimeConnectionState.disconnected),
    );

    _emitState(RealtimeConnectionState.connected);

    _send({
      'type': 'session.update',
      'session': {'model': model},
    });
  }

  /// Append a chunk of audio to the input buffer.
  void appendAudio(String base64Audio) {
    _send({'type': 'input_audio_buffer.append', 'audio': base64Audio});
  }

  /// Signal the end of the input buffer; the server will emit a `completed` event.
  void commit() {
    _send({'type': 'input_audio_buffer.commit'});
  }

  Future<void> close() async {
    await _channel?.sink.close();
    _channel = null;
    _emitState(RealtimeConnectionState.disconnected);
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
    await _state.close();
  }

  void _send(Map<String, dynamic> message) {
    final ch = _channel;
    if (ch == null) return;
    ch.sink.add(jsonEncode(message));
  }

  void _onMessage(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> msg;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      msg = decoded;
    } catch (_) {
      return;
    }

    final type = msg['type'] as String?;
    switch (type) {
      case 'conversation.item.input_audio_transcription.delta':
        _events.add(RealtimeEvent.delta(msg['delta'] as String? ?? ''));
        break;
      case 'conversation.item.input_audio_transcription.completed':
        _events.add(RealtimeEvent.completed(msg['transcript'] as String? ?? ''));
        break;
      case 'error':
        final err = msg['error'];
        final message = err is Map ? (err['message']?.toString() ?? 'unknown') : err?.toString();
        _events.add(RealtimeEvent.error(message ?? 'Unknown error'));
        break;
      default:
        _events.add(RealtimeEvent.info(type ?? 'unknown', msg));
    }
  }

  void _emitState(RealtimeConnectionState s) {
    _currentState = s;
    _state.add(s);
  }
}

enum RealtimeConnectionState { disconnected, connecting, connected, error }

sealed class RealtimeEvent {
  const RealtimeEvent();

  factory RealtimeEvent.delta(String text) = RealtimeDelta;
  factory RealtimeEvent.completed(String transcript) = RealtimeCompleted;
  factory RealtimeEvent.error(String message) = RealtimeError;
  factory RealtimeEvent.info(String type, Map<String, dynamic> raw) = RealtimeInfo;
}

class RealtimeDelta extends RealtimeEvent {
  final String text;
  const RealtimeDelta(this.text);
}

class RealtimeCompleted extends RealtimeEvent {
  final String transcript;
  const RealtimeCompleted(this.transcript);
}

class RealtimeError extends RealtimeEvent {
  final String message;
  const RealtimeError(this.message);
}

class RealtimeInfo extends RealtimeEvent {
  final String type;
  final Map<String, dynamic> raw;
  const RealtimeInfo(this.type, this.raw);
}
