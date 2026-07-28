import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints/admin_endpoint.dart';
import 'lemonade_client_provider.dart';

/// Per-model in-flight download. `progress` is null until the first
/// progress event arrives, then 0..1.
class ModelDownloadEntry {
  final double? progress;
  const ModelDownloadEntry({this.progress});
}

/// Snapshot of a finished pull. UI watches this via `ref.listen` to react
/// (snackbar, refresh installed list) when a download wraps up. `seq` makes
/// re-downloads of the same id distinguishable.
class ModelDownloadFinish {
  final int seq;
  final String? error;
  const ModelDownloadFinish(this.seq, this.error);
}

class ModelDownloadsState {
  final Map<String, ModelDownloadEntry> active;
  final Map<String, ModelDownloadFinish> finished;

  const ModelDownloadsState({
    this.active = const {},
    this.finished = const {},
  });

  ModelDownloadsState copyWith({
    Map<String, ModelDownloadEntry>? active,
    Map<String, ModelDownloadFinish>? finished,
  }) =>
      ModelDownloadsState(
        active: active ?? this.active,
        finished: finished ?? this.finished,
      );
}

/// Owns model-pull stream subscriptions. Lives above the navigator so a
/// download keeps running (and progress keeps updating) when the user
/// leaves the screen that started it.
class ModelDownloadsNotifier extends StateNotifier<ModelDownloadsState> {
  ModelDownloadsNotifier(this._ref) : super(const ModelDownloadsState()) {
    _ref.listen(lemonadeClientProvider, (_, __) => _cancelAll());
  }

  final Ref _ref;
  final Map<String, StreamSubscription<PullEvent>> _subs = {};
  int _seq = 0;

  void start(String modelId) {
    if (_subs.containsKey(modelId)) return;
    final client = _ref.read(lemonadeClientProvider);
    if (client == null) return;

    final clearedFinished = Map<String, ModelDownloadFinish>.from(state.finished)
      ..remove(modelId);
    state = state.copyWith(
      active: {...state.active, modelId: const ModelDownloadEntry()},
      finished: clearedFinished,
    );

    final sub = client.admin.pullStream(modelName: modelId).listen(
      (ev) {
        switch (ev) {
          case PullProgress():
            if (ev.percent != null) {
              state = state.copyWith(active: {
                ...state.active,
                modelId: ModelDownloadEntry(progress: ev.percent! / 100.0),
              });
            }
          case PullComplete():
            break;
          case PullError():
            _finish(modelId, error: ev.message);
        }
      },
      onError: (e) => _finish(modelId, error: e.toString()),
      onDone: () => _finish(modelId),
      cancelOnError: true,
    );
    _subs[modelId] = sub;
  }

  void cancel(String modelId) {
    _subs.remove(modelId)?.cancel();
    if (state.active.containsKey(modelId)) {
      final next = Map<String, ModelDownloadEntry>.from(state.active)
        ..remove(modelId);
      state = state.copyWith(active: next);
    }
  }

  void _finish(String modelId, {String? error}) {
    _subs.remove(modelId);
    if (!state.active.containsKey(modelId)) return;
    final nextActive = Map<String, ModelDownloadEntry>.from(state.active)
      ..remove(modelId);
    final nextFinished = Map<String, ModelDownloadFinish>.from(state.finished)
      ..[modelId] = ModelDownloadFinish(++_seq, error);
    state = state.copyWith(active: nextActive, finished: nextFinished);
  }

  /// Cancel every in-flight pull (the active server changed, so the streams
  /// point at the wrong server). Unlike a user-initiated [cancel], this EMITS
  /// a finish entry per dropped download so listeners (snackbar / installed
  /// refresh) fire — a 90%-done pull used to just silently vanish.
  void _cancelAll() {
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    if (state.active.isEmpty) return;
    final nextFinished = Map<String, ModelDownloadFinish>.from(state.finished);
    for (final id in state.active.keys) {
      nextFinished[id] =
          ModelDownloadFinish(++_seq, 'Cancelled — the active server changed');
    }
    state = state.copyWith(active: const {}, finished: nextFinished);
  }

  @override
  void dispose() {
    // No state writes here — just release the subscriptions.
    for (final s in _subs.values) {
      s.cancel();
    }
    _subs.clear();
    super.dispose();
  }
}

final modelDownloadsProvider =
    StateNotifierProvider<ModelDownloadsNotifier, ModelDownloadsState>(
  (ref) => ModelDownloadsNotifier(ref),
);
