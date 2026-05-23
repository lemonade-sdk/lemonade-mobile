import 'dart:async';

import '../api/realtime/realtime_audio_socket.dart';
import '../models/server_config.dart';

/// Re-export the canonical connection-state enum so callers that already
/// imported it from this file keep compiling without changes.
export '../api/realtime/realtime_audio_socket.dart'
    show RealtimeConnectionState;

/// Higher-level wrapper around [RealtimeAudioSocket] for the standalone
/// transcription screen. Adds two things on top of the raw WS:
///
///   1. **Accumulated transcript** — concatenates partial deltas and
///      replaces the buffer with each `completed` event, so the UI just
///      listens to a single `Stream<String>` and gets "the current best
///      transcript" at any moment.
///   2. **Drain-on-commit** — `commitAndWaitForFinal` debounces final
///      events so a server that emits multiple completions for a long
///      utterance doesn't return half-finished text.
///
/// All the connect / auth / fallback / timeout logic lives in the
/// underlying socket — this file does not re-implement it.
class RealtimeTranscriptionService {
  final ServerConfig server;
  final RealtimeAudioSocket _socket;

  StreamSubscription<RealtimeEvent>? _eventSub;
  StreamSubscription<RealtimeConnectionState>? _stateSub;

  final _transcriptController = StreamController<String>.broadcast();
  final _errorController = StreamController<String>.broadcast();
  final _stateController = StreamController<RealtimeConnectionState>.broadcast();

  String _accumulatedText = '';
  RealtimeConnectionState _state = RealtimeConnectionState.disconnected;
  Completer<void>? _finalTranscriptCompleter;
  Timer? _drainTimer;

  RealtimeTranscriptionService(this.server)
      : _socket = RealtimeAudioSocket(server) {
    _eventSub = _socket.events.listen(_handleEvent);
    _stateSub = _socket.state.listen((s) {
      _state = s;
      _stateController.add(s);
    });
  }

  RealtimeConnectionState get state => _state;
  Stream<RealtimeConnectionState> get stateStream => _stateController.stream;
  Stream<String> get transcriptStream => _transcriptController.stream;
  Stream<String> get errorStream => _errorController.stream;
  String get accumulatedText => _accumulatedText;

  Future<void> connect({String? model, int? port}) async {
    if (_state == RealtimeConnectionState.connected ||
        _state == RealtimeConnectionState.connecting) {
      return;
    }
    _accumulatedText = '';
    try {
      await _socket.connect(model: model ?? 'whisper-1', port: port);
    } catch (e) {
      _errorController.add(e.toString());
    }
  }

  void sendAudioChunk(String base64Audio) {
    if (_state != RealtimeConnectionState.connected) return;
    _socket.appendAudio(base64Audio);
  }

  void commitAudioBuffer() {
    if (_state != RealtimeConnectionState.connected) return;
    _socket.commit();
  }

  /// Commit the audio buffer and wait for ALL pending transcriptions to finish.
  ///
  /// Each `completed` event resets a debounce timer; once no more arrive for
  /// [drainDelay] we resolve. The [timeout] is a hard ceiling so we never
  /// block indefinitely if the server stops responding mid-drain.
  Future<void> commitAndWaitForFinal({
    Duration timeout = const Duration(seconds: 45),
    Duration drainDelay = const Duration(seconds: 5),
  }) async {
    if (_state != RealtimeConnectionState.connected) return;

    _finalTranscriptCompleter = Completer<void>();
    _drainTimer?.cancel();
    commitAudioBuffer();

    // Resolve after drainDelay if no completion arrives at all.
    _drainTimer = Timer(drainDelay, () {
      if (!(_finalTranscriptCompleter?.isCompleted ?? true)) {
        _finalTranscriptCompleter!.complete();
      }
    });

    try {
      await _finalTranscriptCompleter!.future.timeout(timeout);
    } on TimeoutException {
      // Hard timeout — proceed with disconnect.
    }
    _drainTimer?.cancel();
    _drainTimer = null;
    _finalTranscriptCompleter = null;
  }

  Future<void> disconnect() async {
    await _socket.close();
  }

  void dispose() {
    _drainTimer?.cancel();
    _drainTimer = null;
    _eventSub?.cancel();
    _eventSub = null;
    _stateSub?.cancel();
    _stateSub = null;
    _socket.dispose();
    _transcriptController.close();
    _errorController.close();
    _stateController.close();
  }

  // ---------------------------------------------------------------------------
  // Event translation
  // ---------------------------------------------------------------------------

  void _handleEvent(RealtimeEvent ev) {
    switch (ev) {
      case RealtimeDelta():
        // Interim text — appended to whatever we've accumulated this turn.
        _accumulatedText += ev.text;
        _transcriptController.add(_accumulatedText);
      case RealtimeCompleted():
        // Final text for this utterance — replace the buffer outright; the
        // server's `completed` payload is authoritative.
        if (ev.transcript.isNotEmpty) {
          _accumulatedText = ev.transcript;
        }
        _transcriptController.add(_accumulatedText);
        // Drain debounce: each completion resets the timer. Once no more
        // arrive for 25s we resolve commitAndWaitForFinal.
        if (!(_finalTranscriptCompleter?.isCompleted ?? true)) {
          _drainTimer?.cancel();
          _drainTimer = Timer(const Duration(seconds: 25), () {
            if (!(_finalTranscriptCompleter?.isCompleted ?? true)) {
              _finalTranscriptCompleter!.complete();
            }
          });
        }
      case RealtimeError():
        _errorController.add(ev.message);
      case RealtimeInfo():
        // session.created / session.updated / speech_started etc — ignored
        // because nothing in the transcription UI cares about them.
        break;
    }
  }
}
