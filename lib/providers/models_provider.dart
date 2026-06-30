import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lemonade_mobile/api/lemonade_client.dart';
import 'package:lemonade_mobile/api/nexus/nexus_account_client.dart'
    show kNexusGatewayBaseUrl;
import 'package:lemonade_mobile/providers/app_mode_provider.dart';
import 'package:lemonade_mobile/providers/servers_provider.dart';
import 'package:lemonade_mobile/utils/model_utils.dart';

final modelsProvider = StateNotifierProvider<ModelsNotifier, List<ModelInfo>>(
  (ref) => ModelsNotifier(ref),
);

/// Subscription (the managed Nexus gateway) is locked to the curated **NXS\***
/// collections — models whose id starts with `NXS`. Local/Mesh servers are
/// unrestricted.
bool isNxsCollection(ModelInfo m) => m.id.toUpperCase().startsWith('NXS');

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

  /// Static model-supported max context window (tokens), or 0 if unknown.
  final int maxContextWindow;

  ModelInfo(
    this.id,
    this.labels, {
    this.isCollection = false,
    this.compositeModels = const [],
    this.maxContextWindow = 0,
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
    // Re-evaluate the allowed model set when the inference mode changes
    // (Subscription locks to NXS*; Local/Mesh show everything).
    ref.listen(appModeProvider, (_, __) => fetchModels());
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

    // The NXS* lock applies only in Subscription mode AND only against the
    // managed gateway. Local AI / Mesh show every installed model.
    final isGateway = selectedServer.baseUrl.trim() == kNexusGatewayBaseUrl;
    final isSubscription = ref.read(appModeProvider) == AppMode.subscription;
    final restrictToNxs = isSubscription && isGateway;

    final client = LemonadeApiClient(selectedServer);
    try {
      // Fetch the full catalog (loaded + registry entries). The server may
      // attach `max_context_window` to the *loaded* entry (read from the GGUF)
      // rather than the registry entry that carries `downloaded:true`, so merge
      // the largest known context per model id before filtering to installed.
      final allModels = await client.models.all();
      final maxCtxById = <String, int>{};
      for (final m in allModels) {
        if (m.maxContextWindow > (maxCtxById[m.id] ?? 0)) {
          maxCtxById[m.id] = m.maxContextWindow;
        }
      }
      final apiModels = allModels.where((m) => m.downloaded == true).toList();
      final modelInfos = apiModels
          .map((m) => ModelInfo(
                m.id,
                m.labels,
                isCollection: m.isCollection,
                compositeModels: m.compositeModels,
                maxContextWindow: maxCtxById[m.id] ?? m.maxContextWindow,
              ))
          .toList();
      // In subscription, surface only the NXS* collections; elsewhere, all.
      state = restrictToNxs
          ? modelInfos.where(isNxsCollection).toList()
          : modelInfos;

      final selectedModelNotifier = ref.read(selectedModelProvider.notifier);
      // Wait for the persisted selection to finish loading before deciding
      // whether to auto-pick. Otherwise the first call after app start
      // wins the race and overwrites the saved model.
      await selectedModelNotifier.loaded;

      // The set of models the user is allowed to be on for this server.
      final allowed = state;

      // If the saved model isn't in the allowed set (not installed, or not an
      // NXS* collection on the gateway), auto-pick a valid default.
      final saved = selectedModelNotifier.state;
      final savedStillValid =
          saved != null && allowed.any((m) => m.id == saved);

      if (!savedStillValid) {
        final ModelInfo pick;
        if (restrictToNxs) {
          // Subscription is locked to NXS* collections.
          pick = _preferredNxs(allowed) ??
              (allowed.isNotEmpty ? allowed.first : ModelInfo('', const []));
        } else {
          // Prefer the default Halo collection; otherwise fall back to a
          // chat-shaped model — `modelInfos.first` is whatever the server
          // returned first, which is often an image-gen / TTS / ASR model and
          // would cause /chat/completions to 400 on first chat.
          pick = preferredDefault(modelInfos) ??
              modelInfos.firstWhere(
                (m) =>
                    !m.supportsTts &&
                    !m.supportsAudio &&
                    !m.supportsImageGeneration,
                orElse: () => modelInfos.isNotEmpty
                    ? modelInfos.first
                    : ModelInfo('', const []),
              );
        }
        if (pick.id.isNotEmpty) {
          await selectedModelNotifier.selectModel(pick.id);
        }
      }
    } catch (_) {
      state = [];
    } finally {
      client.close();
    }
  }

  /// Preferred NXS* default: an NXS *lite* collection, then any NXS collection,
  /// then the first NXS* model. Null if none.
  ModelInfo? _preferredNxs(List<ModelInfo> nxs) {
    for (final m in nxs) {
      if (m.isCollection && m.id.toLowerCase().contains('lite')) return m;
    }
    for (final m in nxs) {
      if (m.isCollection) return m;
    }
    return nxs.isNotEmpty ? nxs.first : null;
  }

  /// The preferred default model: a Halo-Lite collection first, then any Halo
  /// collection, then any Halo-Lite model, then any Halo model. Null if none
  /// match. Collections are preferred so Omni multimodal routing is on by
  /// default.
  ModelInfo? preferredDefault(List<ModelInfo> models) {
    bool idHas(ModelInfo m, String needle) =>
        m.id.toLowerCase().contains(needle);
    for (final m in models) {
      if (m.isCollection && idHas(m, 'halo-lite')) return m;
    }
    for (final m in models) {
      if (m.isCollection && idHas(m, 'halo')) return m;
    }
    for (final m in models) {
      if (idHas(m, 'halo-lite')) return m;
    }
    for (final m in models) {
      if (idHas(m, 'halo')) return m;
    }
    return null;
  }

  /// Refresh the model list for the current server, then force-select the
  /// preferred default collection. Called right after a subscription sign-in so
  /// the main screen shows the model list and a sensible default immediately.
  Future<void> refreshAndSelectPreferred() async {
    await fetchModels();
    final server = ref.read(selectedServerProvider);
    final isGateway =
        server != null && server.baseUrl.trim() == kNexusGatewayBaseUrl;
    final isSubscription = ref.read(appModeProvider) == AppMode.subscription;
    if (isSubscription && isGateway) {
      // Subscription: force one of the curated NXS* collections.
      final pick = _preferredNxs(state.where(isNxsCollection).toList());
      if (pick != null) {
        await ref.read(selectedModelProvider.notifier).selectModel(pick.id);
      }
      return;
    }
    final preferred = preferredDefault(state);
    if (preferred != null) {
      await ref.read(selectedModelProvider.notifier).selectModel(preferred.id);
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
