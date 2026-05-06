import '../lemonade_client.dart';
import '../types/model_info.dart';

class ModelsEndpoint {
  final LemonadeApiClient _client;
  ModelsEndpoint(this._client);

  /// Returns every model the server knows about, including ones that are
  /// available for download but not yet installed, plus Collections. **Only
  /// the admin console should use this** — every other surface in the app
  /// should call [installed] so the user never sees a model they can't run.
  Future<List<ApiModelInfo>> all() => _fetch(showAll: true);

  /// Returns only the models that have already been downloaded to the
  /// server. This is the default for every user-facing surface (chat picker,
  /// model override modal, server probe, etc.).
  Future<List<ApiModelInfo>> installed() async {
    final everything = await _fetch(showAll: true);
    return everything.where((m) => m.downloaded == true).toList();
  }

  Future<List<ApiModelInfo>> _fetch({required bool showAll}) async {
    final uri = _client.apiUriFor(
      '/models',
      query: showAll ? {'show_all': 'true'} : null,
    );
    final body = await _client.getJson(uri);
    final raw = body['data'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map<String, dynamic>>()
        .map(ApiModelInfo.fromJson)
        .toList();
  }

  /// Find a model whose `labels` contain any of [requiredLabels].
  /// Optionally restrict the search to a set of candidate IDs (e.g. a Collection's components).
  ApiModelInfo? findByLabels(
    List<ApiModelInfo> all,
    Iterable<String> requiredLabels, {
    Iterable<String>? candidates,
  }) {
    final wanted = requiredLabels.toSet();
    final pool = candidates == null
        ? all
        : all.where((m) => candidates.contains(m.id));
    for (final m in pool) {
      if (m.labels.any(wanted.contains)) return m;
    }
    return null;
  }
}
