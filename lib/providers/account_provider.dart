import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/exceptions.dart';
import '../api/nexus/nexus_account_client.dart';
import '../api/nexus/nexus_account_models.dart';
import '../models/server_config.dart';
import '../storage/secure_storage.dart';
import '../utils/server_identity.dart';
import 'app_mode_provider.dart';
import 'models_provider.dart';
import 'servers_provider.dart';

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

  /// Bumped by every sign-in and sign-out. Launch-time hydration captures it
  /// and gives up if it changed: a sign-out (or a fresh sign-in) that landed
  /// while the keychain read was in flight must not be overwritten by the
  /// token that read returned.
  int _sessionGen = 0;

  /// Serializes every change the auth flow makes to the server list. Without
  /// it, a launch-time provision still waiting on the server list could
  /// finish AFTER a sign-out removed the gateway server — putting it back
  /// with the revoked token.
  Future<void> _serverOps = Future.value();

  Future<void> _serialServerOp(Future<void> Function() op) {
    final next = _serverOps.then((_) => op()).catchError((Object e) {
      debugPrint('[Account] server op failed: $e');
    });
    _serverOps = next;
    return next;
  }

  Future<void> _hydrate() async {
    final gen = _sessionGen;
    try {
      final token = await SecureKeyStore.readAccountToken();
      final identity = await SecureKeyStore.readAccountIdentity();
      if (gen != _sessionGen) return; // signed in/out meanwhile — theirs wins
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
        // The stored token may have been revoked (password change, sign-out
        // elsewhere) — check it instead of showing "online" while every
        // gateway call fails.
        unawaited(revalidate());
        return;
      }
    } catch (_) {
      // Keychain unavailable — fall through to signed-out.
    }
    if (gen != _sessionGen) return;
    state = const AuthState(busy: false);
  }

  /// Sign in with the typed credentials (POST /auth/login), sending this
  /// device's identity so the token is per-device. ALWAYS mints a token for
  /// THESE credentials — a token already in the keychain (a stale session,
  /// a failed logout) is replaced, never silently reused, so entering account
  /// B's credentials can't "sign in" as account A. Silent token reuse lives
  /// only in the launch-time [_hydrate] path.
  Future<void> login({required String email, required String password}) async {
    final device = await _deviceContext();
    final api = NexusAccountClient();
    try {
      final result = await api.login(
        email: email,
        password: password,
        deviceId: device.id,
        deviceName: device.name,
        appName: kNexusAppName,
      );
      await _persist(result);
    } finally {
      api.close();
    }
  }

  /// Register. Same always-use-typed-credentials rule as [login]. [segment] is
  /// the account type the user picked at signup: 'personal' or 'business'.
  Future<void> register({
    required String clientName,
    required String email,
    required String password,
    String segment = 'personal',
  }) async {
    final device = await _deviceContext();
    final api = NexusAccountClient();
    try {
      final result = await api.register(
        clientName: clientName,
        email: email,
        password: password,
        segment: segment,
        deviceId: device.id,
        deviceName: device.name,
        appName: kNexusAppName,
      );
      await _persist(result);
    } finally {
      api.close();
    }
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

  Future<void> _persist(AuthResult result) async {
    // Drop any previously stored credential first so a stale token/identity
    // from another account can never survive alongside the new one.
    try {
      await SecureKeyStore.clearAccount();
    } catch (e) {
      debugPrint('[Account] clearAccount before persist failed: $e');
    }
    await SecureKeyStore.writeAccountToken(result.token);
    await SecureKeyStore.writeAccountIdentity(result.user, result.client);
    _sessionGen++;
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
    _sessionGen++;
    state = const AuthState(busy: false);
    try {
      await SecureKeyStore.clearAccount();
    } catch (e) {
      debugPrint('[Account] clearAccount failed: $e');
    }
    // Queued behind any provision still in flight, so it always runs last.
    await _serialServerOp(_deprovisionSubscriptionServer);
  }

  /// Called by the UI when an authenticated call returns 401 — the token was
  /// rotated/revoked server-side (every login mints a new app token), so there
  /// is nothing to refresh: drop the session and let the user sign in again.
  Future<void> handleUnauthorized() async {
    if (!state.isSignedIn) return;
    await logout();
  }

  DateTime? _lastValidated;
  Future<void>? _validating;

  /// Confirm the stored token is still accepted (GET /account) and sign out
  /// if the server says it isn't. Called at launch, on app resume, and when a
  /// gateway call comes back 401 — [handleUnauthorized] was only wired to a
  /// screen nothing navigates to, so a revoked token was never noticed.
  ///
  /// Only a plain 401 counts: network errors, 5xx and plan-capability 401s
  /// (`capability_required`) leave the session alone. [minInterval] throttles
  /// repeat checks (resume can fire often).
  Future<void> revalidate({Duration minInterval = Duration.zero}) {
    if (!state.isSignedIn) return Future.value();
    final last = _lastValidated;
    if (last != null && DateTime.now().difference(last) < minInterval) {
      return Future.value();
    }
    return _validating ??= _revalidate().whenComplete(() => _validating = null);
  }

  Future<void> _revalidate() async {
    final token = state.token;
    if (token == null || token.isEmpty) return;
    final api = NexusAccountClient(token: token);
    try {
      await api.fetchAccount();
      _lastValidated = DateTime.now();
    } on UnauthorizedException catch (e) {
      final revoked = e.statusCode == 401 &&
          !e.message.contains('capability_required') &&
          // A sign-in that happened while this check was in flight owns the
          // session now; only drop the token we actually tested.
          state.token == token;
      if (revoked) {
        debugPrint('[Account] stored token rejected — signing out');
        await logout();
      }
    } catch (e) {
      debugPrint('[Account] token check skipped: $e');
    } finally {
      api.close();
    }
  }

  // ── Routed server provisioning ──────────────────────────────────────

  /// Upsert the subscription server into the list. [select] makes it the active
  /// server (done on a fresh sign-in). Best-effort and idempotent — a failure
  /// never blocks sign-in, and it tolerates the row already existing in the DB
  /// even before the in-memory server list has finished loading.
  Future<void> _provisionSubscriptionServer(
    String token, {
    required bool select,
  }) =>
      _serialServerOp(() async {
        // Signed out (or into another account) while this waited its turn —
        // provisioning now would resurrect the server with a dead token.
        if (state.token != token) return;
        await _provisionSubscriptionServerNow(token, select: select);
      });

  Future<void> _provisionSubscriptionServerNow(
    String token, {
    required bool select,
  }) async {
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
      // Only steal the selection when the app is actually in Subscription
      // mode. Signing in while in Local AI / Mesh must not force-switch the
      // user off their local server + model (app_mode_provider would fight
      // the selection right back, ending with the local model silently
      // replaced) — the gateway server is provisioned quietly and becomes
      // active the next time they enter Subscription mode.
      if (select && ref.read(appModeProvider) == AppMode.subscription) {
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
    // At cold start the list may still be loading — scanning it empty left
    // the gateway row in the database to reappear on the next launch.
    await serversNotifier.loaded;
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
// Read-only data providers (auto-dispose with a TTL — reopening a screen
// within the window shows cached data instantly; re-fetch on token change).
// ─────────────────────────────────────────────────────────────────────────────

/// Keeps an `.autoDispose` provider's state alive for [ttl] after its last
/// listener is removed, so reopening a screen inside the window renders the
/// cached data instantly instead of a full-screen spinner. `ref.invalidate` /
/// `ref.refresh` after a mutation still force an immediate refetch (and the
/// previous value is shown while it reloads).
extension CacheForExtension on Ref<Object?> {
  void cacheFor(Duration ttl) {
    final link = keepAlive();
    final timer = Timer(ttl, link.close);
    onDispose(timer.cancel);
  }
}

/// One shared [NexusAccountClient] (one underlying `http.Client`) per token.
/// The per-fetch clients this replaces were constructed on every rebuild and
/// never closed — a socket-pool leak. Rebuilt (old one closed) only when the
/// token itself changes, not on unrelated auth-state churn like `busy` flips.
final nexusAccountClientProvider = Provider<NexusAccountClient>((ref) {
  final token = ref.watch(authProvider.select((a) => a.token));
  final client = NexusAccountClient(token: token);
  ref.onDispose(client.close);
  return client;
});

/// GET /account — account + subscription summary (auth required).
final accountSummaryProvider = FutureProvider.autoDispose<AccountSummary>((
  ref,
) async {
  ref.cacheFor(const Duration(minutes: 5));
  final signedIn = ref.watch(authProvider.select((a) => a.isSignedIn));
  if (!signedIn) {
    throw UnauthorizedException('Not signed in', endpoint: '/account');
  }
  return ref.watch(nexusAccountClientProvider).fetchAccount();
});

/// GET /usage/agents — per-agent cost + token history for the current period.
/// This is also the source of "tokens used" — summed across agents — since the
/// router has no standalone /usage endpoint; capacity/limits come from /account.
final agentUsageProvider = FutureProvider.autoDispose<AgentUsageReport>((
  ref,
) async {
  ref.cacheFor(const Duration(minutes: 2));
  final signedIn = ref.watch(authProvider.select((a) => a.isSignedIn));
  if (!signedIn) {
    throw UnauthorizedException('Not signed in', endpoint: '/usage/agents');
  }
  return ref.watch(nexusAccountClientProvider).fetchAgentUsage();
});

/// GET /plans — public plan + add-on catalog (no auth). Static catalog, so it
/// gets the longest TTL.
final plansProvider = FutureProvider.autoDispose<PlanCatalog>((ref) async {
  ref.cacheFor(const Duration(minutes: 30));
  return ref.watch(nexusAccountClientProvider).fetchPlans();
});

/// GET /billing/subscription — current plan + ACTIVE add-on lines. Null when
/// signed out. Drives accurate per-add-on Add/Remove state in the plan picker.
/// Invalidate after any plan/add-on/cancel change.
final subscriptionDetailProvider =
    FutureProvider.autoDispose<SubscriptionDetail?>((ref) async {
      ref.cacheFor(const Duration(minutes: 5));
      final signedIn = ref.watch(authProvider.select((a) => a.isSignedIn));
      if (!signedIn) return null;
      return ref.watch(nexusAccountClientProvider).fetchSubscription();
    });
