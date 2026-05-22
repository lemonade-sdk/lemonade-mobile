class DiscoveredServer {
  final String hostname;
  final String url;
  final DateTime lastSeen;
  final String address;

  DiscoveredServer({
    required this.hostname,
    required this.url,
    required this.lastSeen,
    required this.address,
  });

  /// Cosmetically-normalized hostname used for grouping. `Lemonade`,
  /// `lemonade.local`, `lemonade.` all collapse to `lemonade`. Used when
  /// dedup'ing notifications and when consolidating multi-NIC servers into
  /// a single row in the UI.
  String get hostnameKey => normalizeHostname(hostname);

  static String normalizeHostname(String raw) {
    var s = raw.trim().toLowerCase();
    if (s.endsWith('.local')) s = s.substring(0, s.length - '.local'.length);
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  DiscoveredServer copyWith({DateTime? lastSeen}) {
    return DiscoveredServer(
      hostname: hostname,
      url: url,
      lastSeen: lastSeen ?? this.lastSeen,
      address: address,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiscoveredServer &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;
}