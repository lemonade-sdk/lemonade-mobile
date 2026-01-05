class ServerConfig {
  final String baseUrl;
  final String? apiKey;
  final String name;

  ServerConfig({
    required this.baseUrl,
    this.apiKey,
    required this.name,
  });

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
