import '../api/nexus/nexus_account_client.dart' show kNexusGatewayBaseUrl;
import '../api/url_utils.dart';
import '../models/server_config.dart';

/// Reserved display name used only for the server provisioned by account auth.
const String kSubscriptionServerName = 'Nexus Projects Subscription';

/// Whether [server] is the app-owned subscription route.
///
/// URL alone is not enough: users can add the same OpenAI-compatible Nexus
/// endpoint with their own API key and use it in Local AI mode.
bool isManagedSubscriptionServer(ServerConfig server) =>
    server.name == kSubscriptionServerName && isNexusGatewayEndpoint(server);

/// Whether this server points at the Nexus router, independent of who added it.
/// Used only for endpoint semantics such as `downloaded` meaning routable.
///
/// Compared by host: users paste the router as `…/v1`, `…/api/v1` or the bare
/// host, and an exact-URL match sent the `…/v1` form down the local-server
/// path, where the `downloaded` filter hid every model not loaded right now.
bool isNexusGatewayEndpoint(ServerConfig server) {
  final host = Uri.tryParse(withDefaultScheme(server.baseUrl, assumeHttps: true))
      ?.host
      .toLowerCase();
  return host != null &&
      host.isNotEmpty &&
      host == Uri.parse(kNexusGatewayBaseUrl).host.toLowerCase();
}
