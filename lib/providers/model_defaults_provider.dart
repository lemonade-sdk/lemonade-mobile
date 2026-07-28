import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/models/chat_history.dart';
import 'package:lemonade_mobile/models/model_defaults.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';
import 'package:lemonade_mobile/storage/database.dart';

// Global model defaults persisted to SharedPreferences
final globalModelDefaultsProvider =
    StateNotifierProvider<GlobalModelDefaultsNotifier, ModelDefaults>(
  (ref) => GlobalModelDefaultsNotifier(),
);

// Clipboard for "Copy Settings" feature
final modelDefaultsClipboardProvider = StateProvider<ModelDefaults?>((ref) => null);

/// The active chat's per-chat overrides, derived from the chat list STATE.
/// The effective*ModelProviders must `ref.watch(chatHistoryProvider.select(…))`
/// through this — watching the *notifier* (which never changes identity) meant
/// they kept returning the previous chat's override after a chat switch or an
/// override edit until some unrelated dependency happened to change.
ModelDefaults? _activeChatOverrides(List<ChatHistory> chats) {
  for (final chat in chats) {
    if (chat.isActive) return chat.modelOverrides;
  }
  return null;
}

// Derived provider: effective model for a given type, merging per-chat override > global default > first available
final effectiveLlmModelProvider = Provider<String?>((ref) {
  final chatOverride = ref.watch(chatHistoryProvider
      .select((chats) => _activeChatOverrides(chats)?.llmModel));
  if (chatOverride != null) return chatOverride;

  final global = ref.watch(globalModelDefaultsProvider);
  if (global.llmModel != null) return global.llmModel;

  // Fall back to selected model
  return ref.watch(selectedModelProvider);
});

final effectiveAudioModelProvider = Provider<String?>((ref) {
  final chatOverride = ref.watch(chatHistoryProvider
      .select((chats) => _activeChatOverrides(chats)?.audioToTextModel));
  if (chatOverride != null) return chatOverride;

  final global = ref.watch(globalModelDefaultsProvider);
  if (global.audioToTextModel != null) return global.audioToTextModel;

  // Fall back to first audio-capable model
  final models = ref.watch(modelsProvider);
  final audioModels = models.where((m) => m.supportsAudio).toList();
  return audioModels.isNotEmpty ? audioModels.first.id : null;
});

final effectiveImageGenModelProvider = Provider<String?>((ref) {
  final chatOverride = ref.watch(chatHistoryProvider
      .select((chats) => _activeChatOverrides(chats)?.imageGenerationModel));
  if (chatOverride != null) return chatOverride;

  final global = ref.watch(globalModelDefaultsProvider);
  if (global.imageGenerationModel != null) return global.imageGenerationModel;

  final models = ref.watch(modelsProvider);
  final imageModels = models.where((m) => m.supportsImageGeneration).toList();
  return imageModels.isNotEmpty ? imageModels.first.id : null;
});

class GlobalModelDefaultsNotifier extends StateNotifier<ModelDefaults> {
  GlobalModelDefaultsNotifier() : super(const ModelDefaults()) {
    _load();
  }

  /// True once the user has changed anything — a late-resolving [_load] must
  /// not clobber their write with the stale snapshot it read (cold-start
  /// window).
  bool _userDirty = false;

  /// Serializes writes so [_save]'s read-modify-write against the defaults
  /// row can't interleave; the last write always carries the latest state.
  Future<void> _pendingSave = Future.value();

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
    final row = await AppDatabase.instance.readOrCreateDefaults();
    if (_userDirty) return;
    state = ModelDefaults(
      llmModel: row.llmModel,
      audioToTextModel: row.audioToTextModel,
      textToAudioModel: row.textToAudioModel,
      imageGenerationModel: row.imageGenerationModel,
    );
  }

  Future<void> _save() {
    _userDirty = true;
    final run = _pendingSave.then((_) => _writeNow());
    // Keep the chain alive even when a write fails.
    _pendingSave = run.catchError((_) {});
    return run;
  }

  Future<void> _writeNow() async {
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final row = await db.readOrCreateDefaults();
    row
      ..llmModel = state.llmModel
      ..audioToTextModel = state.audioToTextModel
      ..textToAudioModel = state.textToAudioModel
      ..imageGenerationModel = state.imageGenerationModel;
    await db.isar.writeTxn(() async => db.modelDefaults.put(row));
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
