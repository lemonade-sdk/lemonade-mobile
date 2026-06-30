/// Human-voice takeover WebSocket (`/api/v1/voice/tasks/{id}/takeover`).
/// Bidirectional 16 kHz / 16-bit / mono / little-endian PCM as binary frames:
/// send the operator's mic, receive the caller's audio. A text frame `release`
/// (or closing) hands the line back to the AI.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'nexus_account_client.dart' show kNexusGatewayBaseUrl;

class NexusCallTakeoverSocket {
  final String token;
  final int taskId;
  WebSocketChannel? _channel;
  final _inbound = StreamController<Uint8List>.broadcast();
  bool _closed = false;

  NexusCallTakeoverSocket({required this.token, required this.taskId});

  Uri get _wsUri {
    var base = kNexusGatewayBaseUrl.trim();
    base = base
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return Uri.parse(
        '$base/api/v1/voice/tasks/$taskId/takeover?access_token=$token');
  }

  /// Caller audio (PCM16 16 kHz mono) as it arrives.
  Stream<Uint8List> get inbound => _inbound.stream;

  /// Opens the socket. The operator's voice is live as soon as [sendPcm] starts.
  void connect() {
    try {
      _channel = WebSocketChannel.connect(_wsUri);
      _channel!.stream.listen(
        (data) {
          if (data is Uint8List) {
            _inbound.add(data);
          } else if (data is List<int>) {
            _inbound.add(Uint8List.fromList(data));
          }
          // text frames (if any) are control echoes — ignore.
        },
        onError: (e) {
          debugPrint('[Takeover] socket error: $e');
          close();
        },
        onDone: close,
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('[Takeover] connect failed: $e');
      close();
    }
  }

  /// Stream a chunk of the operator's mic (PCM16 16 kHz mono, little-endian).
  void sendPcm(Uint8List pcm) {
    if (_closed) return;
    try {
      _channel?.sink.add(pcm);
    } catch (_) {}
  }

  /// Hand the line back to the AI without closing the socket.
  void release() {
    if (_closed) return;
    try {
      _channel?.sink.add('release');
    } catch (_) {}
  }

  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _channel?.sink.close();
    } catch (_) {}
    _inbound.close();
  }
}
