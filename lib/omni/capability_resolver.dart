import '../api/types/model_info.dart';
import '../api/types/tool_definition.dart';
import 'tool_definitions.dart';

/// Resolves which OmniRouter tools are available given the loaded models, and
/// which model each tool should target.
///
/// Selection precedence per tool, in order:
///   1. User-pinned override (per-tool model picker), if present and valid.
///   2. A component model from the active Collection (if [collectionComponents]
///      is supplied) whose labels match the tool's `requires_labels`.
///   3. The first available model whose labels match.
class OmniCapabilityResolver {
  final List<ApiModelInfo> allModels;
  final ApiModelInfo? activeLlm;
  final List<String>? collectionComponents;

  /// Per-tool user pins, keyed by tool name (e.g. 'generate_image' → 'SD-Turbo').
  final Map<String, String> userPins;

  OmniCapabilityResolver({
    required this.allModels,
    this.activeLlm,
    this.collectionComponents,
    this.userPins = const {},
  });

  /// Snapshot of resolved capabilities for the current configuration.
  CapabilitySnapshot resolve() {
    final tools = <ResolvedTool>[];

    for (final def in OmniToolCatalog.all) {
      // App-control tools (e.g. end_call) don't need any media model — they
      // operate on host-app state. Always advertise them to the LLM.
      if (def.isAppControl) {
        tools.add(ResolvedTool(definition: def, modelId: ''));
        continue;
      }

      // analyze_image: gated on the *LLM* having `vision`, no separate component model.
      if (def.requiresLlmLabels != null) {
        final llmLabels = activeLlm?.labels ?? const <String>[];
        if (llmLabels.any(def.requiresLlmLabels!.contains)) {
          tools.add(ResolvedTool(definition: def, modelId: activeLlm!.id));
        }
        continue;
      }

      final required = def.requiresLabels;
      if (required == null || required.isEmpty) continue;

      final pinned = userPins[def.name];
      if (pinned != null) {
        final match = allModels
            .where((m) => m.id == pinned)
            .where((m) => m.hasAnyLabel(required))
            .firstOrNull;
        if (match != null) {
          tools.add(ResolvedTool(definition: def, modelId: match.id));
          continue;
        }
      }

      // Try the active collection's components first.
      if (collectionComponents != null) {
        final fromCollection = allModels
            .where((m) => collectionComponents!.contains(m.id))
            .where((m) => m.hasAnyLabel(required))
            .firstOrNull;
        if (fromCollection != null) {
          tools.add(ResolvedTool(definition: def, modelId: fromCollection.id));
          continue;
        }
      }

      // Fall back to any model that matches.
      final any = allModels.where((m) => m.hasAnyLabel(required)).firstOrNull;
      if (any != null) {
        tools.add(ResolvedTool(definition: def, modelId: any.id));
      }
    }

    return CapabilitySnapshot(
      tools: tools,
      llmSupportsToolCalling:
          (activeLlm?.labels ?? const <String>[]).contains('tool-calling'),
    );
  }
}

class CapabilitySnapshot {
  final List<ResolvedTool> tools;
  final bool llmSupportsToolCalling;

  const CapabilitySnapshot({
    required this.tools,
    required this.llmSupportsToolCalling,
  });

  /// Get the model id assigned to a tool, or null if the tool isn't available.
  String? modelFor(String toolName) {
    for (final t in tools) {
      if (t.definition.name == toolName) return t.modelId;
    }
    return null;
  }

  /// True if at least one tool is enabled and the LLM advertises tool-calling.
  bool get isUsable => tools.isNotEmpty && llmSupportsToolCalling;

  /// Whether a specific tool name is enabled.
  bool has(String name) => tools.any((t) => t.definition.name == name);
}

class ResolvedTool {
  final ToolDefinition definition;
  final String modelId;
  const ResolvedTool({required this.definition, required this.modelId});
}

extension<T> on Iterable<T> {
  T? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
