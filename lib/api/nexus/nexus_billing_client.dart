/// Client for the billing & entitlements system: capability state, the prepaid
/// wallet (Personal), and wallet-billed memberships. All under
/// `/api/v1/voice/...`. Stripe subscription (Business) reuses
/// `NexusAccountClient` (/plans, /billing/checkout, /billing/portal, /account).
library;

import 'nexus_billing_models.dart';
import 'nexus_gateway_base.dart';

class NexusBillingClient extends NexusGatewayClient {
  NexusBillingClient({required super.token, super.client});

  /// GET /voice/entitlements — the canonical billing state (segment,
  /// capabilities, balance, memberships).
  Future<NexusEntitlements> entitlements() async {
    final json = await getJson(uri('/voice/entitlements'));
    return NexusEntitlements.fromJson(json);
  }

  // ── Wallet (Personal) ───────────────────────────────────────────────

  Future<NexusWalletBalance> balance() async {
    final json = await getJson(uri('/voice/balance'));
    return NexusWalletBalance.fromJson(json);
  }

  Future<List<NexusWalletTransaction>> transactions({int page = 1}) async {
    final json = await getJson(uri('/voice/balance/transactions', {'page': page}));
    return ((json['transactions'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusWalletTransaction.fromJson)
        .toList();
  }

  /// POST /voice/balance/topup — returns a Stripe Checkout url to open in a
  /// browser. Min 500 ($5), max 50000 ($500). Crediting is async (webhook).
  Future<String> topup(int amountCents) async {
    final json =
        await postJson(uri('/voice/balance/topup'), {'amountCents': amountCents});
    return (json['url'] ?? '').toString();
  }

  // ── Memberships (Personal, wallet-billed) ───────────────────────────

  Future<List<NexusMembershipPlan>> availableMemberships() async {
    final json = await getJson(uri('/voice/memberships/available'));
    return ((json['plans'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(NexusMembershipPlan.fromJson)
        .toList();
  }

  /// POST /voice/memberships. Throws on non-2xx; the caller inspects a
  /// [ServerException] with statusCode 402 for `insufficient_balance`.
  Future<NexusMembership> buyMembership(String planKey) async {
    final json =
        await postJson(uri('/voice/memberships'), {'planKey': planKey});
    return NexusMembership.fromJson(json);
  }

  Future<void> cancelMembership(int id) =>
      delete(uri('/voice/memberships/$id'));
}
