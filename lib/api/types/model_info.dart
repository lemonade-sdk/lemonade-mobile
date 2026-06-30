/// Wire-format model entry from `GET /v1/models` (with `?show_all=true` to include collections).
class ApiModelInfo {
  final String id;
  final List<String> labels;
  final String? recipe;
  final List<String> compositeModels;
  final bool? downloaded;
  final String? checkpoint;
  final bool suggested;

  /// Static model-supported context window (`max_context_window`), when the
  /// server knows it; 0 otherwise.
  final int maxContextWindow;

  ApiModelInfo({
    required this.id,
    required this.labels,
    this.recipe,
    this.compositeModels = const [],
    this.downloaded,
    this.checkpoint,
    this.suggested = false,
    this.maxContextWindow = 0,
  });

  /// True when this is a Lemonade Omni Model — a bundle whose `recipe` is
  /// `collection.omni` and which lists its component models. This is the
  /// authoritative server signal for "this model is an Omni / tool-calling
  /// bundle"; matches the desktop app's `isCollectionRecipe` check.
  bool get isCollection =>
      (recipe == 'collection.omni' || recipe == 'collection') &&
      compositeModels.isNotEmpty;

  /// Returns true if this model has at least one of the requested labels.
  bool hasAnyLabel(Iterable<String> requested) {
    if (labels.isEmpty) return false;
    final wanted = requested.toSet();
    return labels.any(wanted.contains);
  }

  factory ApiModelInfo.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String? ?? '';
    final rawLabels = json['labels'];
    final labels = rawLabels is List
        ? rawLabels.whereType<String>().toList()
        : <String>[];
    // The Lemonade server emits the component list as `components`; older
    // builds (or alternate transports) may have used `composite_models`, so
    // accept either to stay compatible.
    final rawComponents = json['components'] ?? json['composite_models'];
    final composite = rawComponents is List
        ? rawComponents.whereType<String>().toList()
        : <String>[];

    return ApiModelInfo(
      id: id,
      labels: labels,
      recipe: json['recipe'] as String?,
      compositeModels: composite,
      downloaded: json['downloaded'] as bool?,
      checkpoint: json['checkpoint'] as String?,
      suggested: json['suggested'] as bool? ?? false,
      maxContextWindow: (json['max_context_window'] as num?)?.toInt() ?? 0,
    );
  }
}
