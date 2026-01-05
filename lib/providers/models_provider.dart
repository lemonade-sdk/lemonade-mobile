import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lemonade_mobile/services/openai_service.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';

final modelsProvider = StateNotifierProvider<ModelsNotifier, List<String>>(
  (ref) => ModelsNotifier(ref),
);

final selectedModelProvider = StateNotifierProvider<SelectedModelNotifier, String?>(
  (ref) => SelectedModelNotifier(),
);

class ModelsNotifier extends StateNotifier<List<String>> {
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
      final models = await openaiService.fetchModels();
      state = models;

      // If we have a saved selected model and it's in the loaded models, keep it selected
      final selectedModel = ref.read(selectedModelProvider);
      if (selectedModel != null && !models.contains(selectedModel)) {
        // Clear selection if the saved model is not available
        ref.read(selectedModelProvider.notifier).clearSelection();
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
    _loadSelectedModel();
  }

  Future<void> _loadSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_selectedModelKey);
  }

  Future<void> _saveSelectedModel() async {
    final prefs = await SharedPreferences.getInstance();
    if (state != null) {
      await prefs.setString(_selectedModelKey, state!);
    } else {
      await prefs.remove(_selectedModelKey);
    }
  }

  Future<void> selectModel(String model) async {
    state = model;
    await _saveSelectedModel();
  }

  Future<void> clearSelection() async {
    state = null;
    await _saveSelectedModel();
  }
}
