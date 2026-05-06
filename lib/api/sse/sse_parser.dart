import 'dart:async';
import 'dart:convert';

/// A parsed Server-Sent Events frame.
class SseEvent {
  final String? event;
  final String data;
  final String? id;

  const SseEvent({this.event, required this.data, this.id});
}

/// Parse an HTTP body byte stream into [SseEvent]s.
///
/// Supports:
/// - Plain `data: ...` events (OpenAI-style).
/// - `event: <name>` typed events (Lemonade `/v1/pull` SSE).
/// - Multi-line `data:` field (per W3C, lines are joined with `\n`).
/// - Comment lines (`:` prefix) which are skipped.
///
/// Frames terminate on a blank line.
Stream<SseEvent> parseSseStream(Stream<List<int>> bytes) {
  return bytes.transform(utf8.decoder).transform(const LineSplitter()).transform(
        StreamTransformer<String, SseEvent>.fromHandlers(
          handleData: _SseLineHandler().handle,
          handleDone: (sink) => sink.close(),
        ),
      );
}

class _SseLineHandler {
  String? _event;
  final StringBuffer _data = StringBuffer();
  String? _id;
  bool _hasData = false;

  void handle(String line, EventSink<SseEvent> sink) {
    if (line.isEmpty) {
      if (_hasData || _event != null) {
        sink.add(SseEvent(event: _event, data: _data.toString(), id: _id));
      }
      _event = null;
      _data.clear();
      _id = null;
      _hasData = false;
      return;
    }

    if (line.startsWith(':')) {
      // comment — ignore
      return;
    }

    final colon = line.indexOf(':');
    final field = colon == -1 ? line : line.substring(0, colon);
    var value = colon == -1 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    switch (field) {
      case 'event':
        _event = value;
        break;
      case 'data':
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
        break;
      case 'id':
        _id = value;
        break;
      case 'retry':
        // ignored — not implementing reconnection backoff
        break;
    }
  }
}
