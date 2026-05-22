import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lemonade_mobile/api/lemonade_client.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/utils/model_utils.dart';

final modelsProvider = StateNotifierProvider<ModelsNotifier, List<ModelInfo>>(
  (ref) => ModelsNotifier(ref),
);

final selectedModelProvider = StateNotifierProvider<SelectedModelNotifier, String?>(
  (ref) => SelectedModelNotifier(),
);

class ModelInfo {
  final String id;
  final List<String> labels;
  final Set<ModelCapabilities> capabilities;
  /// True for server-side Lemonade Omni Models (recipe == 'collection.omni').
  /// These can't be sent as the `model` on /chat/completions — callers should
  /// substitute the planner LLM from [compositeModels] for the actual call.
  final bool isCollection;
  /// Component model ids when [isCollection] is true; empty otherwise.
  final List<String> compositeModels;

  ModelInfo(
    this.id,
    this.labels, {
    this.isCollection = false,
    this.compositeModels = const [],
  }) : capabilities = ModelUtils.detectCapabilities(id, labels);

  bool get supportsVision => ModelUtils.supportsVision(capabilities);
  bool get supportsImageGeneration => ModelUtils.supportsImageGeneration(capabilities);
  bool get supportsThinking => ModelUtils.supportsThinking(capabilities);
  bool get supportsAudio => ModelUtils.supportsAudio(capabilities);
  bool get supportsTts => ModelUtils.supportsTts(capabilities);
  bool get isTextOnly => ModelUtils.isTextOnly(capabilities);
}

class ModelsNotifier extends StateNotifier<List<ModelInfo>> {
  final Ref ref;

  ModelsNotifier(this.ref) : super([]) {
    // Watch for server changes and fetch models for the new server.
    ref.listen(selectedServerProvider, (previous, next) {
      if (next == null) {
        state = [];
        return;
      }
      // Only clear the saved model on a *real* server change. The initial
      // hydration from prefs is a null→server transition and would
      // otherwise wipe the user's persisted model (e.g. their selected
      // Omni Collection) on every app start.
      if (previous != null && previous.baseUrl != next.baseUrl) {
        ref.read(selectedModelProvider.notifier).clearSelection();
      }
      fetchModels();
    });
  }

  Future<void> fetchModels() async {
    final selectedServer = ref.read(selectedServerProvider);
    if (selectedServer == null) return;

    final client = LemonadeApiClient(selectedServer);
    try {
      final apiModels = await client.models.installed();
      final modelInfos = apiModels
          .map((m) => ModelInfo(
                m.id,
                m.labels,
                isCollection: m.isCollection,
                compositeModels: m.compositeModels,
              ))
          .toList();
      state = modelInfos;

      final selectedModelNotifier = ref.read(selectedModelProvider.notifier);
      // Wait for the persisted selection to finish loading before deciding
      // whether to auto-pick. Otherwise the first call after app start
      // wins the race and overwrites the saved model.
      await selectedModelNotifier.loaded;

      // If the saved model is no longer installed on this server, fall back
      // to auto-select.
      final saved = selectedModelNotifier.state;
      final savedStillValid =
          saved != null && modelInfos.any((m) => m.id == saved);

      if (!savedStillValid) {
        // Prefer a chat-shaped model — `modelInfos.first` is whatever the
        // server returned first, which is often an image-gen / TTS / ASR
        // model and would cause /chat/completions to 400 on first chat.
        final chatModel = modelInfos.firstWhere(
          (m) =>
              !m.supportsTts &&
              !m.supportsAudio &&
              !m.supportsImageGeneration,
          orElse: () => modelInfos.isNotEmpty
              ? modelInfos.first
              : ModelInfo('', const []),
        );
        if (chatModel.id.isNotEmpty) {
          await selectedModelNotifier.selectModel(chatModel.id);
        }
      }
    } catch (_) {
      state = [];
    } finally {
      client.close();
    }
  }
}

class SelectedModelNotifier extends StateNotifier<String?> {
  static const String _selectedModelKey = 'selected_model';

  /// Completes once the persisted selection has been read from prefs. Code
  /// that needs to decide "is this null because the user hasn't picked
  /// anything OR because we haven't loaded yet?" can await this.
  final Completer<void> _loadedCompleter = Completer<void>();
  Future<void> get loaded => _loadedCompleter.future;

  SelectedModelNotifier() : super(null) {
    _loadSelectedModel();
  }

  Future<void> _loadSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedModel = prefs.getString(_selectedModelKey);
      print('Loading selected model from prefs: $savedModel');
      state = savedModel;
    } catch (e) {
      print('Error loading selected model: $e');
      state = null;
    } finally {
      if (!_loadedCompleter.isCompleted) _loadedCompleter.complete();
    }
  }

  // Synchronous getter that tries to return the current state
  String? getSelectedModelSync() {
    return state;
  }

  // Helper method to check if a model is actually selected and available
  bool isModelSelectedAndAvailable(List<ModelInfo> availableModels) {
    return state != null && state!.isNotEmpty && availableModels.any((model) => model.id == state);
  }

  Future<void> _saveSelectedModel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (state != null) {
        await prefs.setString(_selectedModelKey, state!);
        print('Saved selected model to prefs: $state');
      } else {
        await prefs.remove(_selectedModelKey);
        print('Cleared selected model from prefs');
      }
    } catch (e) {
      print('Error saving selected model: $e');
    }
  }

  Future<void> selectModel(String model) async {
    print('Selecting model: $model');
    state = model;
    await _saveSelectedModel();
  }

  Future<void> clearSelection() async {
    print('Clearing model selection');
    state = null;
    await _saveSelectedModel();
  }
}
