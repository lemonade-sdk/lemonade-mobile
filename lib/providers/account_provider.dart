import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/exceptions.dart';
import '../api/nexus/nexus_account_client.dart';
import '../api/nexus/nexus_account_models.dart';
import '../models/server_config.dart';
import '../storage/secure_storage.dart';
import 'servers_provider.dart';

/// Display name of the auto-provisioned subscription inference server. It lives
/// in the normal server list so the user can freely switch to a local server.
const String kSubscriptionServerName = 'Nexus Projects Subscription';

/// Immutable auth state for the Nexus subscription account.
///
/// Subscription is entirely optional — the app works fully without ever signing
/// in. This only drives the Account screen + the auto-provisioned routed server.
class AuthState {
  final String? token;
  final NexusUser? user;
  final NexusClient? client;

  /// True while hydrating the token from secure storage on launch — lets the UI
  /// show a spinner instead of flashing the login form.
  final bool busy;

  const AuthState({this.token, this.user, this.client, this.busy = false});

  bool get isSignedIn => token != null && token!.isNotEmpty;

  AuthState copyWith({
    String? token,
    NexusUser? user,
    NexusClient? client,
    bool? busy,
  }) {
    return AuthState(
      token: token ?? this.token,
      user: user ?? this.user,
      client: client ?? this.client,
      busy: busy ?? this.busy,
    );
  }
}

class _AuthNotifier extends StateNotifier<AuthState> {
  final Ref ref;

  _AuthNotifier(this.ref) : super(const AuthState(busy: true)) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    try {
      final token = await SecureKeyStore.readAccountToken();
      final identity = await SecureKeyStore.readAccountIdentity();
      if (token != null && token.isNotEmpty) {
        // The subscription server itself rehydrates from the DB on its own
        // (ServersNotifier loads it + its token from secure storage), so no
        // re-provisioning is needed here.
        state = AuthState(
          token: token,
          user: identity?.user,
          client: identity?.client,
          busy: false,
        );
        return;
      }
    } catch (_) {
      // Keychain unavailable — fall through to signed-out.
    }
    state = const AuthState(busy: false);
  }

  /// POST /auth/login, persist token + identity, provision the routed server.
  Future<void> login({required String email, required String password}) async {
    final result =
        await NexusAccountClient().login(email: email, password: password);
    await _persist(result);
  }

  /// POST /auth/register, then same as [login].
  Future<void> register({
    required String clientName,
    required String email,
    required String password,
  }) async {
    final result = await NexusAccountClient()
        .register(clientName: clientName, email: email, password: password);
    await _persist(result);
  }

  Future<void> _persist(AuthResult result) async {
    await SecureKeyStore.writeAccountToken(result.token);
    await SecureKeyStore.writeAccountIdentity(result.user, result.client);
    state = AuthState(
      token: result.token,
      user: result.user,
      client: result.client,
      busy: false,
    );
    await _provisionSubscriptionServer(result.token);
  }

  /// Clear the credential and remove the routed server.
  Future<void> logout() async {
    await SecureKeyStore.clearAccount();
    await _deprovisionSubscriptionServer();
    state = const AuthState(busy: false);
  }

  // ── Routed server provisioning ──────────────────────────────────────

  /// Upsert the subscription server into the list and make it the active server.
  /// Best-effort: a provisioning failure never blocks a successful sign-in.
  Future<void> _provisionSubscriptionServer(String token) async {
    final serversNotifier = ref.read(serversProvider.notifier);
    final cfg = ServerConfig(
      name: kSubscriptionServerName,
      baseUrl: kNexusGatewayBaseUrl,
      apiKey: token,
    );

    try {
      ServerConfig? existing;
      for (final s in ref.read(serversProvider)) {
        if (s.name == kSubscriptionServerName) existing = s;
      }
      if (existing != null) {
        await serversNotifier.updateServer(existing, cfg);
      } else {
        await serversNotifier.addServer(cfg);
      }
      await ref.read(selectedServerProvider.notifier).selectServer(cfg);
    } catch (_) {
      // Server list unavailable (e.g. DB closed). The account is still signed
      // in; the user can add/select the server manually later.
    }
  }

  /// Remove the subscription server; if it was selected, fall back to whatever
  /// local server remains (or none).
  Future<void> _deprovisionSubscriptionServer() async {
    final serversNotifier = ref.read(serversProvider.notifier);
    final selected = ref.read(selectedServerProvider);
    final wasSelected = selected?.name == kSubscriptionServerName;

    for (final s in ref.read(serversProvider)) {
      if (s.name == kSubscriptionServerName) {
        await serversNotifier.removeServer(s);
      }
    }

    if (wasSelected) {
      final remaining = ref.read(serversProvider);
      await ref
          .read(selectedServerProvider.notifier)
          .selectServer(remaining.isNotEmpty ? remaining.first : null);
    }
  }
}

/// Auth state for the optional Nexus subscription account.
final authProvider = StateNotifierProvider<_AuthNotifier, AuthState>(
  (ref) => _AuthNotifier(ref),
);

// ─────────────────────────────────────────────────────────────────────────────
// Read-only data providers (auto-dispose; re-fetch whenever the token changes).
// ─────────────────────────────────────────────────────────────────────────────

/// GET /account — account + subscription summary (auth required).
final accountSummaryProvider =
    FutureProvider.autoDispose<AccountSummary>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) {
    throw UnauthorizedException('Not signed in', endpoint: '/account');
  }
  return NexusAccountClient(token: auth.token).fetchAccount();
});

/// GET /usage — current-period usage vs. entitlements (auth required).
final usageSnapshotProvider =
    FutureProvider.autoDispose<UsageSnapshot>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) {
    throw UnauthorizedException('Not signed in', endpoint: '/usage');
  }
  return NexusAccountClient(token: auth.token).fetchUsage();
});

/// GET /usage/agents — per-agent cost history for the current period.
final agentUsageProvider =
    FutureProvider.autoDispose<AgentUsageReport>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) {
    throw UnauthorizedException('Not signed in', endpoint: '/usage/agents');
  }
  return NexusAccountClient(token: auth.token).fetchAgentUsage();
});

/// GET /plans — public plan + add-on catalog (no auth).
final plansProvider = FutureProvider.autoDispose<PlanCatalog>((ref) async {
  return NexusAccountClient().fetchPlans();
});