import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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

  static String _key(String serverName) => 'apikey/$serverName';

  // ── Nexus account credential ────────────────────────────────────────
  // The subscription bearer token + a cached copy of the user/client JSON so
  // the UI can hydrate on launch without a round-trip. Never touches Isar.
  static const _accountTokenKey = 'nexus/account_token';
  static const _accountIdentityKey = 'nexus/account_identity';

  static Future<String?> readAccountToken() =>
      _store.read(key: _accountTokenKey);

  static Future<void> writeAccountToken(String token) =>
      _store.write(key: _accountTokenKey, value: token);

  static Future<void> deleteAccountToken() =>
      _store.delete(key: _accountTokenKey);

  /// Persist a compact JSON of the signed-in user + client for fast hydration.
  static Future<void> writeAccountIdentity(NexusUser user, NexusClient client) {
    final json = jsonEncode({'user': user.toJson(), 'client': client.toJson()});
    return _store.write(key: _accountIdentityKey, value: json);
  }

  /// Reads the cached identity, or null if absent/corrupt.
  static Future<({NexusUser user, NexusClient client})?>
      readAccountIdentity() async {
    final raw = await _store.read(key: _accountIdentityKey);
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
    await deleteAccountToken();
    await _store.delete(key: _accountIdentityKey);
  }

  static Future<String?> readApiKey(String serverName) {
    return _store.read(key: _key(serverName));
  }

  static Future<void> writeApiKey(String serverName, String apiKey) {
    return _store.write(key: _key(serverName), value: apiKey);
  }

  static Future<void> deleteApiKey(String serverName) {
    return _store.delete(key: _key(serverName));
  }

  /// Rename the secure-storage entry when a server is renamed.
  static Future<void> renameApiKey(String oldName, String newName) async {
    final value = await readApiKey(oldName);
    if (value == null) return;
    await writeApiKey(newName, value);
    await deleteApiKey(oldName);
  }
}
