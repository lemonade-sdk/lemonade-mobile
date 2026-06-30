/// Hand-written immutable models for the Nexus gateway Account / Billing / Usage
/// API. snake_case JSON (from the C# Nexus Router) → camelCase Dart, with
/// `fromJson` factories. Pure value objects: no Flutter or network imports.
///
/// Defensive parsing (null-safe, tolerant of missing keys) so a partial server
/// payload never throws.
library;

// ─────────────────────────────────────────────────────────────────────────────
// Auth
// ─────────────────────────────────────────────────────────────────────────────

/// The signed-in user (owner/admin/member of an account).
class NexusUser {
  final String email;
  final String displayName;
  final String role; // Member | Admin | Owner
  final int? accountId;

  const NexusUser({
    required this.email,
    required this.displayName,
    required this.role,
    this.accountId,
  });

  factory NexusUser.fromJson(Map<String, dynamic> json) {
    return NexusUser(
      email: (json['email'] ?? '') as String,
      displayName: (json['display_name'] ?? json['displayName'] ?? '') as String,
      role: (json['role'] ?? 'Member') as String,
      accountId: _asInt(json['account_id'] ?? json['accountId']),
    );
  }

  Map<String, dynamic> toJson() => {
        'email': email,
        'display_name': displayName,
        'role': role,
        'account_id': accountId,
      };
}

/// A reference to the tenant Client (company / account) the user belongs to.
class NexusClient {
  final int id;
  final String name;

  const NexusClient({required this.id, required this.name});

  factory NexusClient.fromJson(Map<String, dynamic> json) {
    return NexusClient(
      id: _asInt(json['id']) ?? 0,
      name: (json['name'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}

/// Result of register / login: the bearer token plus the user + client it maps
/// to. The token is the SAME credential used for inference; persist it securely.
class AuthResult {
  final String token;
  final String prefix;
  final NexusUser user;
  final NexusClient client;

  const AuthResult({
    required this.token,
    required this.prefix,
    required this.user,
    required this.client,
  });

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      token: (json['token'] ?? '') as String,
      prefix: (json['prefix'] ?? '') as String,
      user: NexusUser.fromJson(_asMap(json['user'])),
      client: NexusClient.fromJson(_asMap(json['client'])),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Plans / Add-ons catalog
// ─────────────────────────────────────────────────────────────────────────────

class Plan {
  final String key;
  final String name;
  final String? description;
  final int priceCents;
  final int monthlyTokens;
  final int monthlyImages;
  final int agentSessions;
  final int sortOrder;

  /// "Both" | "Personal" | "Business" — which segment this tier targets.
  final String audience;

  const Plan({
    required this.key,
    required this.name,
    this.description,
    required this.priceCents,
    required this.monthlyTokens,
    required this.monthlyImages,
    required this.agentSessions,
    required this.sortOrder,
    this.audience = 'Both',
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    return Plan(
      key: (json['key'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      priceCents: _asInt(json['price_cents']) ?? 0,
      monthlyTokens: _asInt(json['monthly_tokens']) ?? 0,
      monthlyImages: _asInt(json['monthly_images']) ?? 0,
      agentSessions: _asInt(json['agent_sessions']) ?? 0,
      sortOrder: _asInt(json['sort_order']) ?? 0,
      audience: (json['audience'] ?? 'Both') as String,
    );
  }
}

class AddOn {
  final String key;
  final String name;
  final String? description;
  final int priceCents;
  final int bonusTokens;
  final int bonusImages;
  final int bonusAgentSessions;
  final int sortOrder;
  final String audience;

  const AddOn({
    required this.key,
    required this.name,
    this.description,
    required this.priceCents,
    required this.bonusTokens,
    required this.bonusImages,
    required this.bonusAgentSessions,
    required this.sortOrder,
    this.audience = 'Both',
  });

  factory AddOn.fromJson(Map<String, dynamic> json) {
    return AddOn(
      key: (json['key'] ?? '') as String,
      name: (json['name'] ?? '') as String,
      description: json['description'] as String?,
      priceCents: _asInt(json['price_cents']) ?? 0,
      bonusTokens: _asInt(json['bonus_tokens']) ?? 0,
      bonusImages: _asInt(json['bonus_images']) ?? 0,
      bonusAgentSessions: _asInt(json['bonus_agent_sessions']) ?? 0,
      sortOrder: _asInt(json['sort_order']) ?? 0,
      audience: (json['audience'] ?? 'Both') as String,
    );
  }
}

/// The public catalog returned by GET /plans (plans + add-ons), each sorted by
/// its sort_order for display.
class PlanCatalog {
  final List<Plan> plans;
  final List<AddOn> addons;

  const PlanCatalog({required this.plans, required this.addons});

  factory PlanCatalog.fromJson(Map<String, dynamic> json) {
    final plans = _asList(json['plans'])
        .map((e) => Plan.fromJson(_asMap(e)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final addons = _asList(json['addons'])
        .map((e) => AddOn.fromJson(_asMap(e)))
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return PlanCatalog(plans: plans, addons: addons);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Usage
// ─────────────────────────────────────────────────────────────────────────────

/// A single metered resource (tokens or images) within the current period.
class UsageMeter {
  final int used;
  final int limit;
  final int remaining;
  final double percent; // 0–100+

  const UsageMeter({
    required this.used,
    required this.limit,
    required this.remaining,
    required this.percent,
  });

  factory UsageMeter.fromJson(Map<String, dynamic> json) {
    return UsageMeter(
      used: _asInt(json['used']) ?? 0,
      limit: _asInt(json['limit']) ?? 0,
      remaining: _asInt(json['remaining']) ?? 0,
      percent: _asDouble(json['percent']) ?? 0,
    );
  }

  /// percent clamped to 0..1 for a [LinearProgressIndicator].
  double get fraction => (percent / 100.0).clamp(0.0, 1.0);
}

/// Current-period usage snapshot vs. entitlements (GET /usage).
class UsageSnapshot {
  final String status; // "ok", "tokensexceeded", ...
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final UsageMeter tokens;
  final UsageMeter images;
  final int maxConcurrentConnections;
  final bool throttled;
  final int? throttleTps;

  const UsageSnapshot({
    required this.status,
    this.periodStart,
    this.periodEnd,
    required this.tokens,
    required this.images,
    required this.maxConcurrentConnections,
    required this.throttled,
    this.throttleTps,
  });

  factory UsageSnapshot.fromJson(Map<String, dynamic> json) {
    return UsageSnapshot(
      status: (json['status'] ?? '') as String,
      periodStart: _asDate(json['period_start']),
      periodEnd: _asDate(json['period_end']),
      tokens: UsageMeter.fromJson(_asMap(json['tokens'])),
      images: UsageMeter.fromJson(_asMap(json['images'])),
      maxConcurrentConnections: _asInt(json['max_concurrent_connections']) ?? 0,
      throttled: (json['throttled'] ?? false) as bool,
      throttleTps: _asInt(json['throttle_tps']),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Account / Subscription
// ─────────────────────────────────────────────────────────────────────────────

class Subscription {
  final String status; // None | Trialing | Active | PastDue | Canceled | Incomplete | Paused
  final String? planKey;
  final DateTime? currentPeriodStart;
  final DateTime? currentPeriodEnd;
  final int tokenLimit;
  final int imageLimit;
  final int agentLimit;

  const Subscription({
    required this.status,
    this.planKey,
    this.currentPeriodStart,
    this.currentPeriodEnd,
    required this.tokenLimit,
    required this.imageLimit,
    required this.agentLimit,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      status: (json['status'] ?? 'None') as String,
      planKey: json['plan_key'] as String?,
      currentPeriodStart: _asDate(json['current_period_start']),
      currentPeriodEnd: _asDate(json['current_period_end']),
      tokenLimit: _asInt(json['token_limit']) ?? 0,
      imageLimit: _asInt(json['image_limit']) ?? 0,
      agentLimit: _asInt(json['agent_limit']) ?? 0,
    );
  }

  bool get isActive => status == 'Active' || status == 'Trialing';
}

/// The signed-in user's account summary (GET /account).
class AccountSummary {
  final NexusUser user;
  final NexusClient client;
  final Subscription subscription;

  const AccountSummary({
    required this.user,
    required this.client,
    required this.subscription,
  });

  factory AccountSummary.fromJson(Map<String, dynamic> json) {
    return AccountSummary(
      user: NexusUser.fromJson(_asMap(json['user'])),
      client: NexusClient.fromJson(_asMap(json['client'])),
      subscription: Subscription.fromJson(_asMap(json['subscription'])),
    );
  }
}

/// One agent's usage roll-up from GET /usage/agents. `agent` is the
/// X-Nexus-Agent label, or "(unattributed)" for calls sent without it.
class AgentUsageRow {
  final String agent;
  final int calls;
  final int inputTokens;
  final int outputTokens;
  final int totalTokens;
  final double cost;

  const AgentUsageRow({
    required this.agent,
    required this.calls,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTokens,
    required this.cost,
  });

  factory AgentUsageRow.fromJson(Map<String, dynamic> json) {
    final input = _asInt(json['input_tokens']) ?? 0;
    final output = _asInt(json['output_tokens']) ?? 0;
    return AgentUsageRow(
      agent: (json['agent'] as String?)?.trim().isNotEmpty == true
          ? json['agent'] as String
          : '(unattributed)',
      calls: _asInt(json['calls']) ?? 0,
      inputTokens: input,
      outputTokens: output,
      totalTokens: _asInt(json['total_tokens']) ?? (input + output),
      cost: _asDouble(json['cost']) ?? 0,
    );
  }
}

/// Response of GET /usage/agents: per-agent cost over the chosen window.
class AgentUsageReport {
  final DateTime? since;
  final double totalCost;
  final List<AgentUsageRow> agents;

  const AgentUsageReport({
    required this.since,
    required this.totalCost,
    required this.agents,
  });

  factory AgentUsageReport.fromJson(Map<String, dynamic> json) {
    return AgentUsageReport(
      since: _asDate(json['since']),
      totalCost: _asDouble(json['total_cost']) ?? 0,
      agents: _asList(json['agents'])
          .map((e) => AgentUsageRow.fromJson(_asMap(e)))
          .toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Parsing helpers (tolerant of int/double/string/null variations)
// ─────────────────────────────────────────────────────────────────────────────

int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

DateTime? _asDate(Object? v) {
  if (v == null) return null;
  if (v is DateTime) return v;
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}

Map<String, dynamic> _asMap(Object? v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return const {};
}

List<dynamic> _asList(Object? v) {
  if (v is List) return v;
  return const [];
}