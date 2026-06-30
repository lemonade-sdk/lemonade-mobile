/// DTOs for the billing & entitlements system: capability gating, the prepaid
/// wallet (Personal segment), and wallet-billed memberships. Source of truth is
/// `GET /api/v1/voice/entitlements`.
library;

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
int _intv(dynamic v) => v is num ? v.toInt() : (int.tryParse('$v') ?? 0);
int? _intn(dynamic v) => v == null ? null : (v is num ? v.toInt() : int.tryParse('$v'));
String _str(dynamic v) => v?.toString() ?? '';

/// What features the account may use. Server-enforced; the UI gates off these
/// but always handles 402/403 gracefully.
class NexusCapabilities {
  final bool calling;
  final bool numbers;
  final bool sms;
  final bool voicemail;
  final bool aiCallTasks;
  final bool pbx;

  const NexusCapabilities({
    this.calling = false,
    this.numbers = false,
    this.sms = false,
    this.voicemail = false,
    this.aiCallTasks = false,
    this.pbx = false,
  });

  bool has(String capability) => switch (capability) {
        'calling' => calling,
        'numbers' => numbers,
        'sms' => sms,
        'voicemail' => voicemail,
        'aiCallTasks' => aiCallTasks,
        'pbx' => pbx,
        _ => false,
      };

  factory NexusCapabilities.fromJson(Map<String, dynamic> j) =>
      NexusCapabilities(
        calling: j['calling'] == true,
        numbers: j['numbers'] == true,
        sms: j['sms'] == true,
        voicemail: j['voicemail'] == true,
        aiCallTasks: j['aiCallTasks'] == true,
        pbx: j['pbx'] == true,
      );
}

/// A wallet-billed membership (Personal segment), e.g. Consumer Phone Automation.
class NexusMembership {
  final int id;
  final String planKey;
  final String name;
  final int? phoneNumberId;
  final int priceCents;
  final String status;
  final bool recurring;
  final DateTime? renewalDate;

  const NexusMembership({
    required this.id,
    required this.planKey,
    this.name = '',
    this.phoneNumberId,
    this.priceCents = 0,
    this.status = '',
    this.recurring = false,
    this.renewalDate,
  });

  factory NexusMembership.fromJson(Map<String, dynamic> j) => NexusMembership(
        id: _intv(j['id']),
        planKey: _str(j['planKey']),
        name: _str(j['name']),
        phoneNumberId: _intn(j['phoneNumberId']),
        priceCents: _intv(j['priceCents']),
        status: _str(j['status']),
        recurring: j['recurring'] == true,
        renewalDate: _date(j['renewalDate']),
      );
}

/// `GET /voice/entitlements` — the canonical billing state.
class NexusEntitlements {
  final String segment; // Personal | Business
  final NexusCapabilities capabilities;
  final int balanceCents;
  final List<NexusMembership> memberships;

  const NexusEntitlements({
    this.segment = 'Personal',
    this.capabilities = const NexusCapabilities(),
    this.balanceCents = 0,
    this.memberships = const [],
  });

  bool get isPersonal => segment == 'Personal';
  bool get isBusiness => segment == 'Business';
  String get balanceLabel => '\$${(balanceCents / 100).toStringAsFixed(2)}';

  factory NexusEntitlements.fromJson(Map<String, dynamic> j) =>
      NexusEntitlements(
        segment: _str(j['segment']).isEmpty ? 'Personal' : _str(j['segment']),
        capabilities: j['capabilities'] is Map
            ? NexusCapabilities.fromJson(
                Map<String, dynamic>.from(j['capabilities'] as Map))
            : const NexusCapabilities(),
        balanceCents: _intv(j['balanceCents']),
        memberships: ((j['memberships'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(NexusMembership.fromJson)
            .toList(),
      );
}

/// `GET /voice/balance`.
class NexusWalletBalance {
  final int balanceCents;
  final String balance;
  final String currency;

  const NexusWalletBalance({
    this.balanceCents = 0,
    this.balance = '0.00',
    this.currency = 'usd',
  });

  factory NexusWalletBalance.fromJson(Map<String, dynamic> j) =>
      NexusWalletBalance(
        balanceCents: _intv(j['balanceCents']),
        balance: _str(j['balance']),
        currency: _str(j['currency']).isEmpty ? 'usd' : _str(j['currency']),
      );
}

/// A wallet ledger entry.
class NexusWalletTransaction {
  final int id;
  final int amountCents;
  final int balanceAfterCents;
  final String kind; // Topup|CallCharge|NumberCharge|MembershipCharge|Adjustment|Refund
  final String description;
  final String? callSessionId;
  final DateTime? createdAt;

  const NexusWalletTransaction({
    required this.id,
    this.amountCents = 0,
    this.balanceAfterCents = 0,
    this.kind = '',
    this.description = '',
    this.callSessionId,
    this.createdAt,
  });

  factory NexusWalletTransaction.fromJson(Map<String, dynamic> j) =>
      NexusWalletTransaction(
        id: _intv(j['id']),
        amountCents: _intv(j['amountCents']),
        balanceAfterCents: _intv(j['balanceAfterCents']),
        kind: _str(j['kind']),
        description: _str(j['description']),
        callSessionId: j['callSessionId']?.toString(),
        createdAt: _date(j['createdAt']),
      );
}

/// An available wallet-billed membership plan.
class NexusMembershipPlan {
  final String key;
  final String name;
  final String description;
  final int priceCents;

  const NexusMembershipPlan({
    required this.key,
    this.name = '',
    this.description = '',
    this.priceCents = 0,
  });

  String get priceLabel => '\$${(priceCents / 100).toStringAsFixed(2)}';

  factory NexusMembershipPlan.fromJson(Map<String, dynamic> j) =>
      NexusMembershipPlan(
        key: _str(j['key']),
        name: _str(j['name']),
        description: _str(j['description']),
        priceCents: _intv(j['priceCents']),
      );
}
