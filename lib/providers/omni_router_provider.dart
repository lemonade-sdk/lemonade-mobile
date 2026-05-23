import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/types/model_info.dart';
import '../omni/capability_resolver.dart';
import '../omni/omni_workflow.dart';
import '../omni/tool_executor.dart';
import '../storage/database.dart';
import 'image_resolution_provider.dart';
import 'lemonade_client_provider.dart';
import 'model_defaults_provider.dart';
import 'models_provider.dart';

/// Whether OmniRouter mode is on. When true, chat goes through the agent loop
/// and tool calls are auto-executed against Lemonade endpoints. When false,
/// chat is plain streaming and the manual fallback toolbar is shown.
class OmniRouterEnabledNotifier extends StateNotifier<bool> {
  OmniRouterEnabledNotifier() : super(true) {
    _load();
  }

  Future<void> _load() async {
    if (!AppDatabase.isOpen) return;
    final prefs = await AppDatabase.instance.readOrCreatePrefs();
    state = prefs.omniRouterEnabled;
  }

  Future<void> setEnabled(bool value) async {
    state = value;
    if (!AppDatabase.isOpen) return;
    final db = AppDatabase.instance;
    final prefs = await db.readOrCreatePrefs();
    prefs.omniRouterEnabled = value;
    await db.isar.writeTxn(() async => db.appPrefs.put(prefs));
  }

  Future<void> toggle() => setEnabled(!state);
}

final omniRouterEnabledProvider =
    StateNotifierProvider<OmniRouterEnabledNotifier, bool>(
  (ref) => OmniRouterEnabledNotifier(),
);

/// Active OmniRouter workflow kind. Persisted in SharedPreferences (a single
/// scalar; the custom workflow's three model slots ride on the existing
/// globalModelDefaults Isar record so the user doesn't lose their picks when
/// they bounce between Lite / Ultra / Custom).
class OmniWorkflowKindNotifier extends StateNotifier<OmniWorkflowKind> {
  static const _prefsKey = 'omni_workflow_kind';

  OmniWorkflowKindNotifier() : super(OmniWorkflowKind.custom) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      state = _decode(raw);
    } catch (_) {
      // Fall back to the default already set in the constructor.
    }
  }

  Future<void> setKind(OmniWorkflowKind kind) async {
    state = kind;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, _encode(kind));
    } catch (_) {
      // Best-effort persistence; leaving in-memory state is still correct.
    }
  }

  static String _encode(OmniWorkflowKind k) => switch (k) {
        OmniWorkflowKind.custom => 'custom',
        OmniWorkflowKind.lite => 'lite',
        OmniWorkflowKind.ultra => 'ultra',
      };

  static OmniWorkflowKind _decode(String? s) => switch (s) {
        'lite' => OmniWorkflowKind.lite,
        'ultra' => OmniWorkflowKind.ultra,
        _ => OmniWorkflowKind.custom,
      };
}

final omniWorkflowKindProvider =
    StateNotifierProvider<OmniWorkflowKindNotifier, OmniWorkflowKind>(
  (ref) => OmniWorkflowKindNotifier(),
);

/// True when the user's selected "model" in the chat header is actually a
/// Collection (e.g. "Ultra Collection") rather than a runnable chat model.
/// Collections can't be sent to /chat/completions directly — the chat path
/// substitutes one of the collection's components instead.
final selectedIsCollectionProvider = Provider<bool>((ref) {
  final id = ref.watch(selectedModelProvider);
  if (id == null) return false;
  final models = ref.watch(modelsProvider);
  for (final m in models) {
    if (m.id == id) return m.isCollection;
  }
  return false;
});

/// The model id that should actually be sent on the wire to
/// /chat/completions. Collapses Collections to their chat-shaped component
/// (since a Collection can't be loaded as a chat model — it's a meta-id).
/// Use this whenever you're about to make a chat request, NOT
/// `selectedModelProvider`.
final wireLlmModelProvider = Provider<String?>((ref) {
  final selectedId = ref.watch(selectedModelProvider);
  if (selectedId == null) return null;
  final models = ref.watch(modelsProvider);
  ModelInfo? selected;
  for (final m in models) {
    if (m.id == selectedId) {
      selected = m;
      break;
    }
  }
  if (selected == null || !selected.isCollection) return selectedId;

  for (final componentId in selected.compositeModels) {
    for (final m in models) {
      if (m.id != componentId) continue;
      if (m.supportsTts || m.supportsAudio || m.supportsImageGeneration) break;
      return componentId;
    }
  }
  // No chat-shaped component found locally — return the first component as a
  // last resort so the request at least references something concrete.
  return selected.compositeModels.isNotEmpty
      ? selected.compositeModels.first
      : selectedId;
});

/// Resolved view of the active workflow. When the user has a Collection
/// selected, the workflow is synthesized from that Collection's components
/// regardless of the kind picker — the user's intent ("use this bundle")
/// dominates. Otherwise we honor the kind picker as before.
final activeOmniWorkflowProvider = Provider<OmniWorkflow>((ref) {
  final selectedId = ref.watch(selectedModelProvider);
  final models = ref.watch(modelsProvider);
  ModelInfo? selectedCollection;
  if (selectedId != null) {
    for (final m in models) {
      if (m.id == selectedId && m.isCollection) {
        selectedCollection = m;
        break;
      }
    }
  }
  if (selectedCollection != null) {
    return _workflowForCollection(selectedCollection, models, ref);
  }

  final kind = ref.watch(omniWorkflowKindProvider);
  switch (kind) {
    case OmniWorkflowKind.lite:
      return OmniWorkflow.lite;
    case OmniWorkflowKind.ultra:
      return OmniWorkflow.ultra;
    case OmniWorkflowKind.custom:
      final defaults = ref.watch(globalModelDefaultsProvider);
      return OmniWorkflow(
        kind: OmniWorkflowKind.custom,
        // The Custom workflow's LLM is the same one the chat header is
        // pointing at — there's only ever one chat LLM in the app, so
        // surfacing it here as a 4th slot keeps the OmniRouter screen the
        // single place to set up "what does the assistant use to think".
        llmModel: ref.watch(selectedModelProvider),
        imageGenModel: defaults.imageGenerationModel,
        ttsModel: defaults.textToAudioModel,
        asrModel: defaults.audioToTextModel,
      );
  }
});

/// Build a workflow from an arbitrary Collection's components. If the
/// component set matches the canonical Lite or Ultra collections, the
/// matching template is returned so users get the curated LLM/TTS/ASR/image
/// slots. Otherwise we synthesize a Custom-shaped workflow whose slots are
/// inferred by capability across the collection's components.
OmniWorkflow _workflowForCollection(
  ModelInfo collection,
  List<ModelInfo> allModels,
  Ref ref,
) {
  final components = collection.compositeModels;
  final liteSet = OmniWorkflow.lite.collectionComponents.toSet();
  final ultraSet = OmniWorkflow.ultra.collectionComponents.toSet();
  if (components.toSet().containsAll(liteSet)) return OmniWorkflow.lite;
  if (components.toSet().containsAll(ultraSet)) return OmniWorkflow.ultra;

  String? llm;
  String? imageGen;
  String? tts;
  String? asr;
  for (final id in components) {
    ModelInfo? m;
    for (final candidate in allModels) {
      if (candidate.id == id) {
        m = candidate;
        break;
      }
    }
    if (m == null) continue;
    if (m.supportsImageGeneration) {
      imageGen ??= id;
    } else if (m.supportsTts) {
      tts ??= id;
    } else if (m.supportsAudio) {
      asr ??= id;
    } else {
      llm ??= id;
    }
  }
  return OmniWorkflow(
    kind: OmniWorkflowKind.custom,
    llmModel: llm,
    imageGenModel: imageGen,
    ttsModel: tts,
    asrModel: asr,
    collectionComponents: List.of(components),
  );
}

/// Resolves which OmniRouter tools are usable for the current configuration.
/// Re-derived whenever the model list, the selected LLM, or the active
/// workflow changes.
final omniCapabilitiesProvider = Provider<CapabilitySnapshot?>((ref) {
  final modelsRaw = ref.watch(modelsProvider);
  // Use the wire-LLM — when a Collection is selected this resolves to the
  // chat-shaped component, so the resolver's `tool-calling` check looks at
  // a real model instead of the Collection meta-model.
  final selectedLlmId = ref.watch(wireLlmModelProvider);
  final selectedRawId = ref.watch(selectedModelProvider);
  final workflow = ref.watch(activeOmniWorkflowProvider);
  if (modelsRaw.isEmpty) return null;

  // If the user has an Omni Model (recipe='collection.omni') selected, the
  // server itself advertises this as a tool-calling bundle. Treat the recipe
  // as the authoritative "Lemonade Omni" signal — no need to second-guess
  // the planner LLM's labels.
  bool selectedIsOmniRecipe = false;
  for (final m in modelsRaw) {
    if (m.id == selectedRawId && m.isCollection) {
      selectedIsOmniRecipe = true;
      break;
    }
  }

  // Convert UI ModelInfo back to ApiModelInfo for resolver, preserving the
  // `tool-calling` label on the planner LLM when the selection is an Omni
  // Model — even if the server's component listing omits that label, the
  // recipe implies it.
  final apiModels = modelsRaw
      .map((m) => ApiModelInfo(
            id: m.id,
            labels: m.labels,
          ))
      .toList(growable: false);

  // Only treat the LLM as "known" if it's actually in the loaded models list.
  // Synthesizing an empty-label ApiModelInfo here would flip the tool-calling
  // check to false and surface a misleading warning while the models list is
  // still loading or stale — return null instead so the UI suppresses the
  // warning until we have real label data.
  ApiModelInfo? activeLlm;
  if (selectedLlmId != null) {
    for (final m in apiModels) {
      if (m.id == selectedLlmId) {
        activeLlm = m;
        break;
      }
    }
    if (activeLlm == null) return null;

    // Force the tool-calling label on when the selection is an Omni Model.
    // The Omni recipe is the contract for tool-calling support; if the
    // planner component's label list happens to be missing it, the recipe
    // still wins.
    if (selectedIsOmniRecipe &&
        !activeLlm.labels.contains('tool-calling')) {
      activeLlm = ApiModelInfo(
        id: activeLlm.id,
        labels: [...activeLlm.labels, 'tool-calling'],
      );
    }
  }

  // Translate the active workflow's slots into per-tool pins. For Lite/Ultra
  // these come from the collection template; for Custom they come from the
  // user's stored picks. `generate_image` and `edit_image` share a slot.
  final pins = <String, String>{};
  if (workflow.imageGenModel != null) {
    pins['generate_image'] = workflow.imageGenModel!;
    pins['edit_image'] = workflow.imageGenModel!;
  }
  if (workflow.asrModel != null) {
    pins['transcribe_audio'] = workflow.asrModel!;
  }
  if (workflow.ttsModel != null) {
    pins['text_to_speech'] = workflow.ttsModel!;
  }

  return OmniCapabilityResolver(
    allModels: apiModels,
    activeLlm: activeLlm,
    collectionComponents:
        workflow.collectionComponents.isEmpty ? null : workflow.collectionComponents,
    userPins: pins,
  ).resolve();
});

/// Tool executor wired to the active server's API client and the resolved
/// per-tool model assignments.
final omniToolExecutorProvider = Provider<OmniToolExecutor?>((ref) {
  final client = ref.watch(lemonadeClientProvider);
  final caps = ref.watch(omniCapabilitiesProvider);
  if (client == null || caps == null) return null;
  final toolModels = <String, String>{
    for (final t in caps.tools) t.definition.name: t.modelId,
  };
  final resolution = ref.watch(imageResolutionProvider);
  return OmniToolExecutor(
    client: client,
    toolModels: toolModels,
    imageBaseResolutionPx: resolution.basePx,
  );
});
