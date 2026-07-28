/// Shared URL normalization for Lemonade servers and the Nexus gateway.
library;

/// Normalize a base URL to a versioned API root ending in `/api/v1` or `/v1`.
///
/// Handles:
///   `http://host:8000`         → `…/api/v1`
///   `http://host:8000/`        → `…/api/v1`
///   `http://host:8000/v1`      → kept (external OpenAI-style hosts)
///   `http://host:8000/api`     → `…/api/v1`
///   `http://host:8000/api/v1/` → `…/api/v1`
///
/// Optionally prepends `https://` when no scheme is present (gateway host
/// strings) when [assumeHttps] is true.
String normalizeApiV1Base(String raw, {bool assumeHttps = false}) {
  var url = raw.trim();
  if (assumeHttps && !url.contains('://')) url = 'https://$url';
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  if (url.endsWith('/api/v1')) return url;
  if (url.endsWith('/v1')) return url;
  if (url.endsWith('/api')) return '$url/v1';
  return '$url/api/v1';
}

/// Build a gateway WebSocket URI: `https→wss`, strip trailing slash, append
/// [path] and `?access_token=…`. Used by voice-events and call-takeover sockets.
Uri nexusGatewayWsUri({
  required String httpBase,
  required String path,
  required String accessToken,
  Map<String, String>? extraQuery,
}) {
  var base = httpBase.trim();
  base = base
      .replaceFirst('https://', 'wss://')
      .replaceFirst('http://', 'ws://');
  while (base.endsWith('/')) {
    base = base.substring(0, base.length - 1);
  }
  final rooted = path.startsWith('/') ? path : '/$path';
  final uri = Uri.parse('$base$rooted');
  return uri.replace(queryParameters: {
    ...uri.queryParameters,
    'access_token': accessToken,
    if (extraQuery != null) ...extraQuery,
  });
}
