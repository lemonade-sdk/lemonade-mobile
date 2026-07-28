/// Human-voice takeover WebSocket (`/api/v1/voice/tasks/{id}/takeover`).
/// Bidirectional 16 kHz / 16-bit / mono / little-endian PCM as binary frames:
/// send the operator's mic, receive the caller's audio. A text frame `release`
/// (or closing) hands the line back to the AI.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../url_utils.dart';
import 'nexus_account_client.dart' show kNexusGatewayBaseUrl;

/// Connection lifecycle of the takeover socket.
enum TakeoverSocketPhase { connecting, connected, reconnecting, closed }

/// A phase plus, when the socket closed abnormally, the error that killed it.
/// [error] is null for a clean, caller-initiated close.
class TakeoverSocketState {
  final TakeoverSocketPhase phase;
  final Object? error;
  const TakeoverSocketState(this.phase, [this.error]);
}

class NexusCallTakeoverSocket {
  final String token;
  final int taskId;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  final _inbound = StreamController<Uint8List>.broadcast();
  final _states = StreamController<TakeoverSocketState>.broadcast();
  TakeoverSocketState _state =
      const TakeoverSocketState(TakeoverSocketPhase.connecting);
  bool _disposed = false;
  int _attempt = 0;

  static const _connectTimeout = Duration(seconds: 10);
  // Backoff before each retry: 0.5s / 1s / 2s / 4s, then give up. Voice is
  // realtime — anything longer than that and the caller has hung up anyway.
  static const _maxReconnectAttempts = 4;

  NexusCallTakeoverSocket({required this.token, required this.taskId});

  Uri get _wsUri => nexusGatewayWsUri(
        httpBase: kNexusGatewayBaseUrl,
        path: '/api/v1/voice/tasks/$taskId/takeover',
        accessToken: token,
      );

  /// Caller audio (PCM16 16 kHz mono) as it arrives.
  Stream<Uint8List> get inbound => _inbound.stream;

  /// Connection state transitions (connecting / connected / reconnecting /
  /// closed). A closed state with a non-null error means the link died and
  /// reconnection was exhausted — the takeover is over.
  Stream<TakeoverSocketState> get states => _states.stream;

  /// Latest known state.
  TakeoverSocketState get state => _state;

  /// Opens the socket and waits for the WebSocket handshake to complete.
  /// Throws if the server can't be reached within [_connectTimeout] — the
  /// caller must not go "live" until this returns.
  Future<void> connect() async {
    if (_disposed) throw StateError('Takeover socket is closed.');
    _setState(const TakeoverSocketState(TakeoverSocketPhase.connecting));
    try {
      await _open();
    } catch (e) {
      debugPrint('[Takeover] connect failed: $e');
      close(error: e);
      rethrow;
    }
  }

  Future<void> _open() async {
    final channel = WebSocketChannel.connect(_wsUri);
    _channel = channel;
    try {
      await channel.ready.timeout(_connectTimeout);
    } catch (e) {
      _channel = null;
      try {
        channel.sink.close();
      } catch (_) {}
      rethrow;
    }
    if (_disposed) {
      try {
        channel.sink.close();
      } catch (_) {}
      return;
    }
    _attempt = 0;
    _sub = channel.stream.listen(
      (data) {
        if (data is Uint8List) {
          _inbound.add(data);
        } else if (data is List<int>) {
          _inbound.add(Uint8List.fromList(data));
        }
        // text frames (if any) are control echoes — ignore.
      },
      onError: (Object e) {
        debugPrint('[Takeover] socket error: $e');
        _onDrop(e);
      },
      onDone: () => _onDrop(null),
      cancelOnError: true,
    );
    _setState(const TakeoverSocketState(TakeoverSocketPhase.connected));
  }

  void _onDrop(Object? cause) {
    if (_disposed) return;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _reconnect(cause);
  }

  Future<void> _reconnect(Object? cause) async {
    while (!_disposed && _attempt < _maxReconnectAttempts) {
      _attempt++;
      _setState(TakeoverSocketState(TakeoverSocketPhase.reconnecting, cause));
      // Nothing is buffered while down — dropped PCM is gone, voice is
      // realtime.
      await Future.delayed(Duration(milliseconds: 500 * (1 << (_attempt - 1))));
      if (_disposed) return;
      try {
        await _open();
        return;
      } catch (e) {
        debugPrint('[Takeover] reconnect attempt $_attempt failed: $e');
        cause = e;
      }
    }
    if (!_disposed) {
      close(error: cause ?? WebSocketChannelException('connection lost'));
    }
  }

  /// Stream a chunk of the operator's mic (PCM16 16 kHz mono, little-endian).
  /// Chunks are dropped while the socket is down or reconnecting.
  void sendPcm(Uint8List pcm) {
    if (_state.phase != TakeoverSocketPhase.connected) return;
    try {
      _channel?.sink.add(pcm);
    } catch (_) {}
  }

  /// Hand the line back to the AI without closing the socket.
  void release() {
    if (_state.phase != TakeoverSocketPhase.connected) return;
    try {
      _channel?.sink.add('release');
    } catch (_) {}
  }

  void _setState(TakeoverSocketState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Terminal: tears the socket down. [error] is set when the close is a
  /// connection failure rather than a caller-initiated shutdown.
  void close({Object? error}) {
    if (_disposed) return;
    _disposed = true;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _setState(TakeoverSocketState(TakeoverSocketPhase.closed, error));
    _inbound.close();
    _states.close();
  }
}
