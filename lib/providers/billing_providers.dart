import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/nexus/nexus_billing_models.dart';
import 'nexus_gateway_provider.dart';

/// Canonical billing state — the source of truth for capability gating. Empty
/// (no capabilities) when signed out. Invalidate on foreground / after any
/// Stripe web flow / after buy-cancel membership.
final entitlementsProvider =
    FutureProvider.autoDispose<NexusEntitlements>((ref) async {
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return const NexusEntitlements();
  return client.entitlements();
});

/// Convenience: whether a capability is currently granted (false while loading
/// or signed out). Gate the UI off this, but always handle 402/403 server-side.
final hasCapabilityProvider = Provider.autoDispose.family<bool, String>((ref, cap) {
  final ent = ref.watch(entitlementsProvider).valueOrNull;
  return ent?.capabilities.has(cap) ?? false;
});

/// Wallet balance (Personal).
final walletBalanceProvider =
    FutureProvider.autoDispose<NexusWalletBalance?>((ref) async {
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return null;
  return client.balance();
});

/// Wallet ledger (first page).
final walletTransactionsProvider =
    FutureProvider.autoDispose<List<NexusWalletTransaction>>((ref) async {
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return const [];
  return client.transactions();
});

/// Available wallet-billed memberships (Personal).
final availableMembershipsProvider =
    FutureProvider.autoDispose<List<NexusMembershipPlan>>((ref) async {
  final client = ref.watch(nexusBillingClientProvider);
  if (client == null) return const [];
  return client.availableMemberships();
});
