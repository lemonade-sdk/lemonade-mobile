import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_billing_models.dart';
import 'account_provider.dart' show CacheForExtension;
import 'nexus_gateway_provider.dart';

/// Canonical billing state — the source of truth for capability gating. Empty
/// (no capabilities) when signed out. Invalidate on foreground / after any
/// Stripe web flow / after buy-cancel membership.
final entitlementsProvider =
    FutureProvider.autoDispose<NexusEntitlements>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return const NexusEntitlements();
  return client.entitlements();
});

/// Convenience: whether a capability is currently granted (false while loading
/// or signed out). Gate the UI off this, but always handle 402/403 server-side.
///
/// `valueOrNull` carries the previous data through a refresh/reload (Riverpod
/// copies the last value into the new `AsyncLoading`), and the TTL keepAlive
/// on [entitlementsProvider] keeps it warm between screens — so gated features
/// only read locked on a true cold load, never as a flash during a refetch.
final hasCapabilityProvider = Provider.autoDispose.family<bool, String>((ref, cap) {
  final ent = ref.watch(entitlementsProvider).valueOrNull;
  return ent?.capabilities.has(cap) ?? false;
});

/// Wallet balance (Personal).
final walletBalanceProvider =
    FutureProvider.autoDispose<NexusWalletBalance?>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return null;
  return client.balance();
});

/// Wallet ledger (first page).
final walletTransactionsProvider =
    FutureProvider.autoDispose<List<NexusWalletTransaction>>((ref) async {
  ref.cacheFor(const Duration(minutes: 2));
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return const [];
  return client.transactions();
});

/// Available wallet-billed memberships (Personal).
final availableMembershipsProvider =
    FutureProvider.autoDispose<List<NexusMembershipPlan>>((ref) async {
  ref.cacheFor(const Duration(minutes: 5));
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return const [];
  return client.availableMemberships();
});
