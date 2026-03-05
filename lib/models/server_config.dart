class ServerConfig {
  final String baseUrl;
  final String? apiKey;
  final String name;

  ServerConfig({
    required this.baseUrl,
    this.apiKey,
    required this.name,
  });

  /// Returns the base URL normalized for API use.
  /// Handles inputs like:
  ///   http://host:8000           -> http://host:8000/api/v1
  ///   http://host:8000/          -> http://host:8000/api/v1
  ///   http://host:8000/v1        -> http://host:8000/v1 (kept as-is for external APIs)
  ///   http://host:8000/api/v1    -> http://host:8000/api/v1
  ///   http://host:8000/api/v1/   -> http://host:8000/api/v1
  String get apiUrl {
    String url = baseUrl;
    // Strip trailing slashes
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/api/v1')) return url;
    if (url.endsWith('/v1')) return url;
    if (url.endsWith('/api')) {
      return '$url/v1';
    }
    return '$url/api/v1';
  }

  Map<String, dynamic> toJson() {
    return {
      'baseUrl': baseUrl,
      'apiKey': apiKey,
      'name': name,
    };
  }

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      baseUrl: json['baseUrl'],
      apiKey: json['apiKey'],
      name: json['name'],
    );
  }

  @override
  String toString() => name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ServerConfig &&
          runtimeType == other.runtimeType &&
          baseUrl == other.baseUrl &&
          apiKey == other.apiKey &&
          name == other.name;

  @override
  int get hashCode => baseUrl.hashCode ^ apiKey.hashCode ^ name.hashCode;
}
