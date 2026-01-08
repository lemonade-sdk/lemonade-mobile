import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lemonade_mobile/services/openai_service.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';

final modelsProvider = StateNotifierProvider<ModelsNotifier, List<ModelInfo>>(
  (ref) => ModelsNotifier(ref),
);

final selectedModelProvider = StateNotifierProvider<SelectedModelNotifier, String?>(
  (ref) => SelectedModelNotifier(),
);

class ModelInfo {
  final String id;
  final ModelCapabilities capabilities;

  ModelInfo(this.id) : capabilities = _detectCapabilities(id);

  static ModelCapabilities _detectCapabilities(String modelId) {
    final lowerId = modelId.toLowerCase();

    // Vision-capable models
    if (lowerId.contains('vision') ||
        lowerId.contains('gpt-4v') ||
        lowerId.contains('gpt-4-turbo') ||
        lowerId.contains('claude-3') ||
        lowerId.contains('gemini-1.5') ||
        lowerId.contains('llava') ||
        lowerId.contains('bakllava') ||
        lowerId.contains('moondream') ||
        lowerId.contains('qwen') && lowerId.contains('vl') ||
        lowerId.contains('internvl')) {
      return ModelCapabilities.vision;
    }

    // Image generation models
    if (lowerId.contains('dall-e') ||
        lowerId.contains('stable-diffusion') ||
        lowerId.contains('sdxl') ||
        lowerId.contains('flux') ||
        lowerId.contains('midjourney') ||
        lowerId.contains('kandinsky')) {
      return ModelCapabilities.imageGeneration;
    }

    // Text-only models (default)
    return ModelCapabilities.textOnly;
  }

  bool get supportsVision => capabilities == ModelCapabilities.vision;
  bool get supportsImageGeneration => capabilities == ModelCapabilities.imageGeneration;
  bool get isTextOnly => capabilities == ModelCapabilities.textOnly;
}

enum ModelCapabilities {
  textOnly,
  vision,
  imageGeneration,
}

class ModelsNotifier extends StateNotifier<List<ModelInfo>> {
  final Ref ref;

  ModelsNotifier(this.ref) : super([]) {
    // Watch for server changes and clear models (don't auto-fetch)
    ref.listen(selectedServerProvider, (previous, next) {
      if (next == null) {
        state = [];
      }
      // Don't automatically fetch models - let UI request them when needed
    });
  }

  Future<void> fetchModels() async {
    final selectedServer = ref.read(selectedServerProvider);
    if (selectedServer == null) return;

    try {
      final openaiService = OpenaiService(selectedServer);
      final modelIds = await openaiService.fetchModels();
      final modelInfos = modelIds.map((id) => ModelInfo(id)).toList();
      state = modelInfos;
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
