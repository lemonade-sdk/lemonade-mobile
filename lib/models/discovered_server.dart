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