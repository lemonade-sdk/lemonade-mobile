import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lemonade_mobile/services/openai_service.dart';
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

  ModelInfo(this.id, this.labels) : capabilities = ModelUtils.detectCapabilities(id, labels);

  bool get supportsVision => ModelUtils.supportsVision(capabilities);
  bool get supportsImageGeneration => ModelUtils.supportsImageGeneration(capabilities);
  bool get supportsThinking => ModelUtils.supportsThinking(capabilities);
  bool get isTextOnly => ModelUtils.isTextOnly(capabilities);
}

class ModelsNotifier extends StateNotifier<List<ModelInfo>> {
  final Ref ref;

  ModelsNotifier(this.ref) : super([]) {
    // Watch for server changes and fetch models for the new server
    ref.listen(selectedServerProvider, (previous, next) {
      if (next == null) {
        state = [];
      } else {
        // Clear selected model when switching servers since each server has its own models
        ref.read(selectedModelProvider.notifier).clearSelection();
        // Automatically fetch models when server changes
        fetchModels();
      }
    });
  }

  Future<void> fetchModels() async {
    final selectedServer = ref.read(selectedServerProvider);
    if (selectedServer == null) return;

    try {
      final openaiService = OpenaiService(selectedServer);
      final modelsData = await openaiService.fetchModels();
      final modelInfos = modelsData.map((data) => ModelInfo(data['id'] as String, data['labels'] as List<String>)).toList();
      state = modelInfos;

      // Auto-select first model if no model is currently selected
      final selectedModelNotifier = ref.read(selectedModelProvider.notifier);
      if (selectedModelNotifier.state == null || selectedModelNotifier.state!.isEmpty) {
        if (modelInfos.isNotEmpty) {
          await selectedModelNotifier.selectModel(modelInfos.first.id);
        }
      }
    } catch (e) {
      // If fetching fails, set empty list - no default models
      state = [];
    }
  }
}

class SelectedModelNotifier extends StateNotifier<String?> {
  static const String _selectedModelKey = 'selected_model';

  SelectedModelNotifier() : super(null) {
    _loadSelectedModelSync();
  }

  void _loadSelectedModelSync() {
    try {
      // Note: SharedPreferences.getInstance() is async, but we need sync loading
      // For now, we'll load it async and the UI will handle the delay
      _loadSelectedModel();
    } catch (e) {
      print('Error initializing selected model: $e');
      state = null;
    }
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
