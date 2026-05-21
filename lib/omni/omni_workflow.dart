/// Identifies which OmniRouter workflow is currently active.
///
/// `lite` and `ultra` are read-only mirror images of the server's
/// "Lite Collection" / "Ultra Collection" downloadable templates — their
/// model slots are hard-coded to the components those collections install.
///
/// `custom` is a single user-defined workflow stored locally on the device.
/// Its three model slots reuse the existing globalModelDefaults provider, so
/// the user's per-tool picks survive across workflow switches.
enum OmniWorkflowKind { custom, lite, ultra }

/// Resolved view of the active workflow. The capability_resolver consumes
/// [imageGenModel] / [ttsModel] / [asrModel] as user pins, and
/// [collectionComponents] as the preference order when a tool's pin doesn't
/// match any installed model.
class OmniWorkflow {
  final OmniWorkflowKind kind;
  final String? llmModel;
  final String? imageGenModel;
  final String? ttsModel;
  final String? asrModel;

  /// Component model IDs from the collection this workflow corresponds to.
  /// Empty for [OmniWorkflowKind.custom] (no collection backing).
  final List<String> collectionComponents;

  const OmniWorkflow({
    required this.kind,
    this.llmModel,
    this.imageGenModel,
    this.ttsModel,
    this.asrModel,
    this.collectionComponents = const [],
  });

  String get displayName => switch (kind) {
        OmniWorkflowKind.custom => 'Custom',
        OmniWorkflowKind.lite => 'Lite',
        OmniWorkflowKind.ultra => 'Ultra',
      };

  bool get isTemplate => kind != OmniWorkflowKind.custom;

  /// All model IDs this workflow expects to be installed (LLM + image + TTS
  /// + ASR). `null` slots are skipped — they fall back to whatever
  /// capability_resolver finds by label.
  List<String> get expectedModels => [
        if (llmModel != null) llmModel!,
        if (imageGenModel != null) imageGenModel!,
        if (ttsModel != null) ttsModel!,
        if (asrModel != null) asrModel!,
      ];

  /// Server-side "Lite Collection" template. Model IDs match
  /// `src/cpp/resources/server_models.json` in the lemonade-sdk repo.
  static const lite = OmniWorkflow(
    kind: OmniWorkflowKind.lite,
    llmModel: 'Qwen3.5-4B-GGUF',
    imageGenModel: 'SD-Turbo',
    ttsModel: 'kokoro-v1',
    asrModel: 'Whisper-Tiny',
    collectionComponents: [
      'Qwen3.5-4B-GGUF',
      'SD-Turbo',
      'Whisper-Tiny',
      'kokoro-v1',
    ],
  );

  /// Server-side "Ultra Collection" template.
  static const ultra = OmniWorkflow(
    kind: OmniWorkflowKind.ultra,
    llmModel: 'Qwen3.5-35B-A3B-GGUF',
    imageGenModel: 'Flux-2-Klein-9B-GGUF',
    ttsModel: 'kokoro-v1',
    asrModel: 'Whisper-Large-v3-Turbo',
    collectionComponents: [
      'Qwen3.5-35B-A3B-GGUF',
      'Flux-2-Klein-9B-GGUF',
      'Whisper-Large-v3-Turbo',
      'kokoro-v1',
    ],
  );
}
