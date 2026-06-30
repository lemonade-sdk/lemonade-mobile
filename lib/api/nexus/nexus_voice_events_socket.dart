/// WebSocket client for the gateway's live call-events stream
/// (`/api/v1/voice/events`). The server pushes call-state transitions
/// (ringing / answered / held / parked / ended) and `voicemail.new`. Auth uses
/// the `?access_token=` query-param convention (browsers/WS can't set headers),
/// matching `realtime_audio_socket.dart`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'nexus_account_client.dart' show kNexusGatewayBaseUrl;
import 'nexus_voice_models.dart';

class NexusVoiceEventsSocket {
  final String token;
  WebSocketChannel? _channel;
  StreamController<NexusCallEvent>? _controller;
  bool _closed = false;

  NexusVoiceEventsSocket({required this.token});

  /// Builds the `wss://…/api/v1/voice/events?access_token=…` URL from the
  /// hardcoded gateway base.
  Uri get _wsUri {
    var base = kNexusGatewayBaseUrl.trim();
    base = base.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse('$base/api/v1/voice/events?access_token=$token');
  }

  /// Opens the socket and yields parsed events. Malformed frames are dropped.
  Stream<NexusCallEvent> events() {
    _controller = StreamController<NexusCallEvent>.broadcast(
      onCancel: close,
    );
    try {
      _channel = WebSocketChannel.connect(_wsUri);
      _channel!.stream.listen(
        (data) {
          try {
            final decoded = jsonDecode(data as String);
            if (decoded is Map<String, dynamic>) {
              _controller?.add(NexusCallEvent.fromJson(decoded));
            }
          } catch (_) {
            // best-effort: ignore non-JSON / partial frames
          }
        },
        onError: (e) {
          debugPrint('[VoiceEvents] socket error: $e');
          _controller?.close();
        },
        onDone: () => _controller?.close(),
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[VoiceEvents] connect failed: $e');
      _controller?.close();
    }
    return _controller!.stream;
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _controller?.close();
  }
}
