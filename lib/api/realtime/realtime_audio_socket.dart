import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../models/server_config.dart';
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
  final ServerConfig _server;
  WebSocketChannel? _channel;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _state = StreamController<RealtimeConnectionState>.broadcast();

  RealtimeConnectionState _currentState = RealtimeConnectionState.disconnected;

  /// The URI that last completed a handshake — automatic reconnects re-dial
  /// this exact endpoint instead of re-running candidate discovery.
  Uri? _connectedUri;
  String? _model;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;

  /// Bumped by [connect]/[close]/[dispose] so late async work from a
  /// superseded generation (candidate handshakes, reconnect dials) is
  /// discarded instead of attaching a stray channel.
  int _epoch = 0;
  bool _closedByUser = false;
  bool _disposed = false;

  static const int _maxReconnectAttempts = 5;

  RealtimeAudioSocket(this._server);

  /// Convenience constructor for call sites that already hold a
  /// [LemonadeApiClient] — pulls the server out of it.
  RealtimeAudioSocket.forClient(LemonadeApiClient client) : this(client.server);

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<RealtimeConnectionState> get state => _state.stream;
  RealtimeConnectionState get currentState => _currentState;

  Future<void> connect({required String model, int? port}) async {
    // Idempotent-safe: a second connect() supersedes (and closes) any
    // previous channel or in-flight reconnect instead of leaking it.
    final epoch = ++_epoch;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempts = 0;
    _closedByUser = false;
    _connectedUri = null;
    _model = model;
    final previous = _channel;
    _channel = null;
    if (previous != null) {
      try {
        await previous.sink.close();
      } catch (_) {}
    }

    _emitState(RealtimeConnectionState.connecting);
    final apiUri = Uri.parse(_server.apiUrl);
    final scheme = apiUri.scheme == 'https' ? 'wss' : 'ws';
    final httpPort =
        apiUri.hasPort ? apiUri.port : (scheme == 'wss' ? 443 : 80);

    // Candidate (port, path) pairs, tried in order:
    //   • the advertised websocket_port at `/realtime` (standalone Lemonade
    //     servers run the WS on its own dynamically-assigned port);
    //   • the HTTP port at `/realtime` and `/api/v1/realtime` — the Nexus
    //     gateway (and proxied setups) serve the WS as an HTTP upgrade on the
    //     regular API port under those paths.
    // Previously, when no port was advertised we dialed ONLY the HTTP port at
    // `/realtime`; against servers that don't route that path the API answers
    // with a plain HTTP response and the handshake fails with
    // "was not upgraded to websocket".
    final advertisedPort = port ?? httpPort;
    final candidates = <(int, String)>[
      (advertisedPort, '/realtime'),
      if (advertisedPort != httpPort) (httpPort, '/realtime'),
      (httpPort, '/api/v1/realtime'),
    ];

    // Lemonade's WS server rejects unauthenticated connections when an API
    // key is configured. It accepts the key via `Authorization: Bearer …`
    // header OR a `?api_key=` query param; the query param is the only way
    // that works portably with `web_socket_channel` across platforms. The
    // Nexus gateway wants the same credential as `?access_token=` — send
    // both, each side ignores the one it doesn't use.
    final apiKey = _server.apiKey ?? 'lemonade';

    Object? lastError;
    for (final (candidatePort, candidatePath) in candidates) {
      final uri = Uri(
        scheme: scheme,
        host: apiUri.host,
        port: candidatePort,
        path: candidatePath,
        queryParameters: {
          'model': model,
          'api_key': apiKey,
          'access_token': apiKey,
        },
      );
      final channel = WebSocketChannel.connect(uri);
      try {
        // .ready throws if the handshake fails. Without this we'd happily
        // declare success on a server that's never going to answer.
        await channel.ready.timeout(const Duration(seconds: 4));
      } catch (e) {
        lastError = e;
        // Cancel the candidate — a timed-out handshake would otherwise keep
        // a zombie socket dialing in the background.
        unawaited(channel.sink.close().catchError((_) => null));
        continue;
      }
      if (epoch != _epoch) {
        // connect()/close() superseded us mid-handshake.
        unawaited(channel.sink.close().catchError((_) => null));
        return;
      }
      _attach(channel, uri);
      return;
    }

    if (epoch == _epoch) _emitState(RealtimeConnectionState.error);
    final tried = candidates
        .map((c) => '${apiUri.host}:${c.$1}${c.$2}')
        .join(', ');
    throw StateError(
      'Could not open the realtime audio WebSocket (tried $tried). '
      'Last error: $lastError. '
      'Check that the server\'s WS port is reachable from this device — '
      'remote setups often need the WS port forwarded too, not just HTTP.',
    );
  }

  /// Wire up a freshly-handshaken [channel] and announce the session.
  void _attach(WebSocketChannel channel, Uri uri) {
    _channel = channel;
    _connectedUri = uri;
    var dropped = false;
    void onDrop() {
      // onError is typically followed by onDone — only react once, and only
      // if this channel is still the live one (not a superseded generation).
      if (dropped) return;
      dropped = true;
      if (!identical(_channel, channel)) return;
      _channel = null;
      if (_closedByUser || _disposed) return;
      _scheduleReconnect();
    }

    channel.stream.listen(
      _onMessage,
      onError: (Object _) => onDrop(),
      onDone: onDrop,
    );
    _emitState(RealtimeConnectionState.connected);
    _send({
      'type': 'session.update',
      'session': {'model': _model},
    });
  }

  /// The connection dropped mid-session: re-dial the last-connected URL with
  /// capped exponential backoff (0.5s/1s/2s/4s/4s). After
  /// [_maxReconnectAttempts] failures we give up and emit a terminal
  /// [RealtimeConnectionState.failed] so callers can fall back.
  void _scheduleReconnect() {
    final uri = _connectedUri;
    if (uri == null || _reconnectAttempts >= _maxReconnectAttempts) {
      _emitState(RealtimeConnectionState.failed);
      _emitEvent(RealtimeEvent.error('Connection to the server was lost.'));
      return;
    }
    final delay =
        Duration(milliseconds: math.min(500 * (1 << _reconnectAttempts), 4000));
    _reconnectAttempts += 1;
    _emitState(RealtimeConnectionState.reconnecting);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () => unawaited(_attemptReconnect(uri)));
  }

  Future<void> _attemptReconnect(Uri uri) async {
    if (_closedByUser || _disposed) return;
    final epoch = _epoch;
    final channel = WebSocketChannel.connect(uri);
    try {
      await channel.ready.timeout(const Duration(seconds: 4));
    } catch (_) {
      unawaited(channel.sink.close().catchError((_) => null));
      if (epoch == _epoch && !_closedByUser && !_disposed) {
        _scheduleReconnect();
      }
      return;
    }
    if (epoch != _epoch || _closedByUser || _disposed) {
      unawaited(channel.sink.close().catchError((_) => null));
      return;
    }
    _reconnectAttempts = 0;
    _attach(channel, uri);
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
    _closedByUser = true;
    _epoch++;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    final channel = _channel;
    _channel = null;
    if (channel != null) {
      try {
        await channel.sink.close();
      } catch (_) {}
    }
    _emitState(RealtimeConnectionState.disconnected);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
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
        _emitEvent(RealtimeEvent.delta(msg['delta'] as String? ?? ''));
        break;
      case 'conversation.item.input_audio_transcription.completed':
        _emitEvent(RealtimeEvent.completed(msg['transcript'] as String? ?? ''));
        break;
      case 'error':
        final err = msg['error'];
        final message = err is Map ? (err['message']?.toString() ?? 'unknown') : err?.toString();
        _emitEvent(RealtimeEvent.error(message ?? 'Unknown error'));
        break;
      default:
        _emitEvent(RealtimeEvent.info(type ?? 'unknown', msg));
    }
  }

  void _emitEvent(RealtimeEvent ev) {
    if (_events.isClosed) return;
    _events.add(ev);
  }

  void _emitState(RealtimeConnectionState s) {
    _currentState = s;
    if (_state.isClosed) return;
    _state.add(s);
  }
}

enum RealtimeConnectionState {
  disconnected,
  connecting,

  /// The connection dropped and automatic re-dialing is in progress.
  /// Callers should pause sending audio; a `connected` follows on success,
  /// a terminal `failed` when the backoff attempts are exhausted.
  reconnecting,
  connected,
  error,

  /// Automatic reconnection gave up — the socket is permanently dead for
  /// this session. Callers should fall back (e.g. HTTP transcription).
  failed,
}

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
