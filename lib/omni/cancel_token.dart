/// Local-only cancel flag for the **omni agent loop** (tool rounds).
///
/// This is not an OpenAI API concept — the Completions protocol has no
/// cancel request. Wire abort is [LemonadeApiClient.abortInFlight] (drop
/// the HTTP connection). This token only stops *our* multi-tool loop from
/// starting the next tool after the connection is already dead.
class CancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// Thrown when a turn is cancelled mid-agent-loop so the outer stream can
/// finish with whatever partial text/artifacts already exist.
class TurnCancelledException implements Exception {
  const TurnCancelledException();
  @override
  String toString() => 'TurnCancelledException';
}
