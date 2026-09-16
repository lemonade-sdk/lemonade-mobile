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
bool isNexusGatewayEndpoint(ServerConfig server) =>
    normalizeApiV1Base(server.baseUrl, assumeHttps: true) ==
    normalizeApiV1Base(kNexusGatewayBaseUrl, assumeHttps: true);
