import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lemonade_mobile/models/model_defaults.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';

// Global model defaults persisted to SharedPreferences
final globalModelDefaultsProvider =
    StateNotifierProvider<GlobalModelDefaultsNotifier, ModelDefaults>(
  (ref) => GlobalModelDefaultsNotifier(),
);

// Clipboard for "Copy Settings" feature
final modelDefaultsClipboardProvider = StateProvider<ModelDefaults?>((ref) => null);

// Derived provider: effective model for a given type, merging per-chat override > global default > first available
final effectiveLlmModelProvider = Provider<String?>((ref) {
  final activeChat = ref.watch(chatHistoryProvider.notifier).getActiveChat();
  final chatOverride = activeChat?.modelOverrides?.llmModel;
  if (chatOverride != null) return chatOverride;

  final global = ref.watch(globalModelDefaultsProvider);
  if (global.llmModel != null) return global.llmModel;

  // Fall back to selected model
  return ref.watch(selectedModelProvider);
});

final effectiveAudioModelProvider = Provider<String?>((ref) {
  final activeChat = ref.watch(chatHistoryProvider.notifier).getActiveChat();
  final chatOverride = activeChat?.modelOverrides?.audioToTextModel;
  if (chatOverride != null) return chatOverride;

  final global = ref.watch(globalModelDefaultsProvider);
  if (global.audioToTextModel != null) return global.audioToTextModel;

  // Fall back to first audio-capable model
  final models = ref.watch(modelsProvider);
  final audioModels = models.where((m) => m.supportsAudio).toList();
  return audioModels.isNotEmpty ? audioModels.first.id : null;
});

final effectiveImageGenModelProvider = Provider<String?>((ref) {
  final activeChat = ref.watch(chatHistoryProvider.notifier).getActiveChat();
  final chatOverride = activeChat?.modelOverrides?.imageGenerationModel;
  if (chatOverride != null) return chatOverride;

  final global = ref.watch(globalModelDefaultsProvider);
  if (global.imageGenerationModel != null) return global.imageGenerationModel;

  final models = ref.watch(modelsProvider);
  final imageModels = models.where((m) => m.supportsImageGeneration).toList();
  return imageModels.isNotEmpty ? imageModels.first.id : null;
});

class GlobalModelDefaultsNotifier extends StateNotifier<ModelDefaults> {
  static const String _prefsKey = 'global_model_defaults';

  GlobalModelDefaultsNotifier() : super(const ModelDefaults()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_prefsKey);
    if (json != null) {
      state = ModelDefaults.fromJson(jsonDecode(json));
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(state.toJson()));
  }

  Future<void> setLlmModel(String? model) async {
    state = ModelDefaults(
      llmModel: model,
      audioToTextModel: state.audioToTextModel,
      textToAudioModel: state.textToAudioModel,
      imageGenerationModel: state.imageGenerationModel,
    );
    await _save();
  }

  Future<void> setAudioToTextModel(String? model) async {
    state = ModelDefaults(
      llmModel: state.llmModel,
      audioToTextModel: model,
      textToAudioModel: state.textToAudioModel,
      imageGenerationModel: state.imageGenerationModel,
    );
    await _save();
  }

  Future<void> setTextToAudioModel(String? model) async {
    state = ModelDefaults(
      llmModel: state.llmModel,
      audioToTextModel: state.audioToTextModel,
      textToAudioModel: model,
      imageGenerationModel: state.imageGenerationModel,
    );
    await _save();
  }

  Future<void> setImageGenerationModel(String? model) async {
    state = ModelDefaults(
      llmModel: state.llmModel,
      audioToTextModel: state.audioToTextModel,
      textToAudioModel: state.textToAudioModel,
      imageGenerationModel: model,
    );
    await _save();
  }

  Future<void> resetAll() async {
    state = const ModelDefaults();
    await _save();
  }

  Future<void> setDefaults(ModelDefaults defaults) async {
    state = defaults;
    await _save();
  }
}
