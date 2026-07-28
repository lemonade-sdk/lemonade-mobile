/// WebSocket client for the gateway's live call-events stream
/// (`/api/v1/voice/events`). The server pushes call-state transitions
/// (ringing / answered / held / parked / ended) and `voicemail.new`. Auth uses
/// the `?access_token=` query-param convention (browsers/WS can't set headers),
/// matching `realtime_audio_socket.dart`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../url_utils.dart';
import 'nexus_account_client.dart' show kNexusGatewayBaseUrl;
import 'nexus_voice_models.dart';

class NexusVoiceEventsSocket {
  final String token;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  StreamController<NexusCallEvent>? _controller;
  Timer? _retry;
  int _attempt = 0;
  // Bumped on every events()/close() so stale callbacks (old listeners,
  // pending retry timers) from a previous lifecycle become no-ops instead of
  // leaking a live channel.
  int _generation = 0;
  final _rng = Random();

  static const _maxBackoff = Duration(seconds: 30);

  NexusVoiceEventsSocket({required this.token});

  /// Builds the `wss://…/api/v1/voice/events?access_token=…` URL from the
  /// hardcoded gateway base.
  Uri get _wsUri => nexusGatewayWsUri(
        httpBase: kNexusGatewayBaseUrl,
        path: '/api/v1/voice/events',
        accessToken: token,
      );

  /// Opens the socket and yields parsed events. Malformed frames are dropped.
  /// Auto-reconnects with capped exponential backoff + jitter, re-emitting on
  /// the same stream. Calling again tears down the previous lifecycle and
  /// starts a fresh one.
  Stream<NexusCallEvent> events() {
    close(); // fresh lifecycle — never leak a previous channel
    final gen = ++_generation;
    final controller = StreamController<NexusCallEvent>.broadcast(
      onCancel: () {
        if (gen == _generation) close();
      },
    );
    _controller = controller;
    _attempt = 0;
    _connect(gen);
    return controller.stream;
  }

  void _connect(int gen) {
    if (gen != _generation) return;
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    try {
      final channel = WebSocketChannel.connect(_wsUri);
      _channel = channel;
      // Reset the backoff once a connection actually establishes.
      channel.ready.then((_) {
        if (gen == _generation) _attempt = 0;
      }).catchError((_) {});
      _sub = channel.stream.listen(
        (data) {
          if (gen != _generation || controller.isClosed) return;
          try {
            final decoded = jsonDecode(data as String);
            if (decoded is Map<String, dynamic>) {
              controller.add(NexusCallEvent.fromJson(decoded));
            }
          } catch (_) {
            // best-effort: ignore non-JSON / partial frames
          }
        },
        onError: (Object e) {
          debugPrint('[VoiceEvents] socket error: $e');
          _scheduleReconnect(gen);
        },
        onDone: () => _scheduleReconnect(gen),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[VoiceEvents] connect failed: $e');
      _scheduleReconnect(gen);
    }
  }

  void _scheduleReconnect(int gen) {
    if (gen != _generation) return;
    final controller = _controller;
    if (controller == null || controller.isClosed) return;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _attempt = min(_attempt + 1, 6);
    var delay = Duration(milliseconds: 500 * (1 << _attempt)) +
        Duration(milliseconds: _rng.nextInt(500));
    if (delay > _maxBackoff) delay = _maxBackoff;
    debugPrint('[VoiceEvents] reconnecting in ${delay.inMilliseconds}ms');
    _retry?.cancel();
    _retry = Timer(delay, () => _connect(gen));
  }

  /// Idempotent. Ends the current lifecycle; a later [events] call starts a
  /// new one on the same object.
  void close() {
    _generation++;
    _retry?.cancel();
    _retry = null;
    _sub?.cancel();
    _sub = null;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) controller.close();
  }
}
