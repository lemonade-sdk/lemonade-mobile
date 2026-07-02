import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/exceptions.dart';
import '../api/nexus/nexus_account_client.dart';
import '../api/nexus/nexus_account_models.dart';
import '../models/server_config.dart';
import '../storage/secure_storage.dart';
import 'models_provider.dart';
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
        state = AuthState(
          token: token,
          user: identity?.user,
          client: identity?.client,
          busy: false,
        );
        // Make sure the subscription server is present in the list on every
        // cold start (it may not have been added, or may have been removed).
        await _provisionSubscriptionServer(token, select: false);
        return;
      }
    } catch (_) {
      // Keychain unavailable — fall through to signed-out.
    }
    state = const AuthState(busy: false);
  }

  /// Sign in. If this device already holds a Nexus app token, reuse it instead
  /// of minting a new one; only mint (POST /auth/login) when none exists. When
  /// minting, sends this device's identity so the token is per-device.
  Future<void> login({required String email, required String password}) async {
    if (await _reuseExistingToken()) return;
    final device = await _deviceContext();
    final result = await NexusAccountClient().login(
      email: email,
      password: password,
      deviceId: device.id,
      deviceName: device.name,
      appName: kNexusAppName,
    );
    await _persist(result);
  }

  /// Register. Same reuse-then-mint rule as [login]. [segment] is the account
  /// type the user picked at signup: 'personal' or 'business'.
  Future<void> register({
    required String clientName,
    required String email,
    required String password,
    String segment = 'personal',
  }) async {
    if (await _reuseExistingToken()) return;
    final device = await _deviceContext();
    final result = await NexusAccountClient().register(
      clientName: clientName,
      email: email,
      password: password,
      segment: segment,
      deviceId: device.id,
      deviceName: device.name,
      appName: kNexusAppName,
    );
    await _persist(result);
  }

  /// The stable per-device id (rotation key) + a friendly display label. The id
  /// is generated once and persisted; the label is best-effort.
  Future<({String id, String name})> _deviceContext() async {
    final id = await SecureKeyStore.deviceId();
    String name = '';
    try {
      name = Platform.localHostname;
    } catch (_) {
      // localHostname can throw on some platforms — fall back to the OS name.
    }
    if (name.isEmpty || name == 'localhost') {
      try {
        name = Platform.operatingSystem;
      } catch (_) {}
    }
    return (id: id, name: name);
  }

  /// If a Nexus app token is already stored on this device, adopt it (and the
  /// cached identity) and provision the subscription server — no new token is
  /// minted. Returns true when an existing token was used.
  Future<bool> _reuseExistingToken() async {
    String? existing;
    try {
      existing = await SecureKeyStore.readAccountToken();
    } catch (_) {
      return false;
    }
    if (existing == null || existing.isEmpty) return false;
    final identity = await SecureKeyStore.readAccountIdentity();
    state = AuthState(
      token: existing,
      user: identity?.user,
      client: identity?.client,
      busy: false,
    );
    await _provisionSubscriptionServer(existing, select: true);
    return true;
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
    await _provisionSubscriptionServer(result.token, select: true);
  }

  /// Clear the credential and remove the routed server. State is cleared FIRST
  /// so the UI flips to signed-out immediately even if cleanup hiccups.
  Future<void> logout() async {
    state = const AuthState(busy: false);
    try {
      await SecureKeyStore.clearAccount();
    } catch (e) {
      debugPrint('[Account] clearAccount failed: $e');
    }
    try {
      await _deprovisionSubscriptionServer();
    } catch (e) {
      debugPrint('[Account] deprovision failed: $e');
    }
  }

  /// Called by the UI when an authenticated call returns 401 — the token was
  /// rotated/revoked server-side (every login mints a new app token), so there
  /// is nothing to refresh: drop the session and let the user sign in again.
  Future<void> handleUnauthorized() async {
    if (!state.isSignedIn) return;
    await logout();
  }

  // ── Routed server provisioning ──────────────────────────────────────

  /// Upsert the subscription server into the list. [select] makes it the active
  /// server (done on a fresh sign-in). Best-effort and idempotent — a failure
  /// never blocks sign-in, and it tolerates the row already existing in the DB
  /// even before the in-memory server list has finished loading.
  Future<void> _provisionSubscriptionServer(String token,
      {required bool select}) async {
    final serversNotifier = ref.read(serversProvider.notifier);
    final cfg = ServerConfig(
      name: kSubscriptionServerName,
      baseUrl: kNexusGatewayBaseUrl,
      apiKey: token,
    );

    try {
      final exists = ref
          .read(serversProvider)
          .any((s) => s.name == kSubscriptionServerName);
      if (exists) {
        await serversNotifier.updateServer(cfg, cfg);
      } else {
        try {
          await serversNotifier.addServer(cfg);
        } catch (_) {
          // Row already in the DB (added in a prior run but not yet loaded into
          // the in-memory list) — update it in place instead.
          await serversNotifier.updateServer(cfg, cfg);
        }
      }
      if (select) {
        await ref.read(selectedServerProvider.notifier).selectServer(cfg);
        // Pull the subscription server's model list now and default to the
        // preferred Halo collection, so the main screen is ready right after
        // sign-in instead of showing an empty/stale model picker.
        await ref.read(modelsProvider.notifier).refreshAndSelectPreferred();
      }
    } catch (e) {
      debugPrint('[Account] provision subscription server failed: $e');
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

/// GET /usage/agents — per-agent cost + token history for the current period.
/// This is also the source of "tokens used" — summed across agents — since the
/// router has no standalone /usage endpoint; capacity/limits come from /account.
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

/// GET /billing/subscription — current plan + ACTIVE add-on lines. Null when
/// signed out. Drives accurate per-add-on Add/Remove state in the plan picker.
/// Invalidate after any plan/add-on/cancel change.
final subscriptionDetailProvider =
    FutureProvider.autoDispose<SubscriptionDetail?>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.isSignedIn) return null;
  return NexusAccountClient(token: auth.token).fetchSubscription();
});