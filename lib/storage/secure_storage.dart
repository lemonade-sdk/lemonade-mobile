import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../api/nexus/nexus_account_models.dart';

/// Thin wrapper around flutter_secure_storage. API keys are keyed by server name.
/// Plaintext API keys never touch SharedPreferences or Isar.
class SecureKeyStore {
  static const _store = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    // macOS: use the legacy file-based keychain. The modern data-protection
    // keychain requires a keychain-access-groups entitlement that Flutter's
    // ad-hoc-signed debug builds can't carry, which fails with
    // errSecMissingEntitlement (-34018). The legacy keychain needs no
    // entitlement and works in both debug and signed release builds.
    mOptions: MacOsOptions(useDataProtectionKeyChain: false),
  );

  // ── In-memory cache ─────────────────────────────────────────────────
  // Every distinct `_store.read()` on the macOS keychain pops its own
  // "allow access" password prompt (and on ad-hoc-signed debug builds the
  // "Always Allow" choice doesn't stick across rebuilds). Launch touches the
  // device id, account token + identity, and each server's API key — that's a
  // pile of prompts. Loading the whole keychain ONCE via `readAll()` collapses
  // that to a single prompt; everything else is served from this cache.
  static Map<String, String> _cache = {};
  static Future<void>? _loading;

  static Future<void> _ensureLoaded() => _loading ??= _load();

  static Future<void> _load() async {
    try {
      _cache = await _store.readAll();
    } catch (_) {
      _cache = {};
    }
  }

  /// Read a key: cache first, then a direct keychain read as a fallback. The
  /// macOS legacy keychain doesn't reliably enumerate items via `readAll()`, so
  /// a value that's genuinely stored (e.g. the account token) can be absent from
  /// the cache — without this fallback the app would look logged out on launch
  /// even though the token persisted.
  static Future<String?> _get(String key) async {
    await _ensureLoaded();
    if (_cache.containsKey(key)) return _cache[key];
    try {
      final v = await _store.read(key: key);
      if (v != null) _cache[key] = v;
      return v;
    } catch (_) {
      return null;
    }
  }

  /// Write through the store and update the cache.
  static Future<void> _put(String key, String value) async {
    await _ensureLoaded();
    await _store.write(key: key, value: value);
    _cache[key] = value;
  }

  /// Delete from the store and the cache.
  static Future<void> _remove(String key) async {
    await _ensureLoaded();
    await _store.delete(key: key);
    _cache.remove(key);
  }

  static String _key(String serverName) => 'apikey/$serverName';

  // ── Device identity ─────────────────────────────────────────────────
  // A stable, opaque per-install id used as the Nexus token ROTATION KEY
  // (per-device token minting). Generated once on first use and reused on every
  // sign-in; never regenerated on logout/login. Persists across logout (it is
  // NOT cleared by clearAccount).
  static const _deviceIdKey = 'nexus/device_id';

  /// Single-flight memo: concurrent deviceId() callers must all get the same
  /// generated id — a get-then-put race would mint two rotation keys.
  static Future<String>? _deviceIdInFlight;

  static Future<String> deviceId() =>
      _deviceIdInFlight ??= _readOrCreateDeviceId();

  static Future<String> _readOrCreateDeviceId() async {
    try {
      final existing = await _get(_deviceIdKey);
      if (existing != null && existing.isNotEmpty) return existing;
      final id = const Uuid().v4();
      await _put(_deviceIdKey, id);
      return id;
    } catch (_) {
      // Don't memoize a failure (e.g. keychain hiccup) — allow a retry.
      _deviceIdInFlight = null;
      rethrow;
    }
  }

  // ── Nexus account credential ────────────────────────────────────────
  // The subscription bearer token + a cached copy of the user/client JSON so
  // the UI can hydrate on launch without a round-trip. Never touches Isar.
  static const _accountTokenKey = 'nexus/account_token';
  static const _accountIdentityKey = 'nexus/account_identity';

  static Future<String?> readAccountToken() => _get(_accountTokenKey);

  static Future<void> writeAccountToken(String token) =>
      _put(_accountTokenKey, token);

  static Future<void> deleteAccountToken() => _remove(_accountTokenKey);

  /// Persist a compact JSON of the signed-in user + client for fast hydration.
  static Future<void> writeAccountIdentity(NexusUser user, NexusClient client) {
    final json = jsonEncode({'user': user.toJson(), 'client': client.toJson()});
    return _put(_accountIdentityKey, json);
  }

  /// Reads the cached identity, or null if absent/corrupt.
  static Future<({NexusUser user, NexusClient client})?>
      readAccountIdentity() async {
    final raw = await _get(_accountIdentityKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final user =
            NexusUser.fromJson(Map<String, dynamic>.from(decoded['user'] as Map));
        final client = NexusClient.fromJson(
            Map<String, dynamic>.from(decoded['client'] as Map));
        return (user: user, client: client);
      }
    } catch (_) {}
    return null;
  }

  /// Clear all account credentials on sign-out.
  static Future<void> clearAccount() async {
    await _remove(_accountTokenKey);
    await _remove(_accountIdentityKey);
  }

  static Future<String?> readApiKey(String serverName) =>
      _get(_key(serverName));

  static Future<void> writeApiKey(String serverName, String apiKey) {
    return _put(_key(serverName), apiKey);
  }

  static Future<void> deleteApiKey(String serverName) {
    return _remove(_key(serverName));
  }

  /// Rename the secure-storage entry when a server is renamed.
  static Future<void> renameApiKey(String oldName, String newName) async {
    final value = await readApiKey(oldName);
    if (value == null) return;
    await writeApiKey(newName, value);
    await deleteApiKey(oldName);
  }
}
