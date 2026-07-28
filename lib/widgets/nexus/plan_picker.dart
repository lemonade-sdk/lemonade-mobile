import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/exceptions.dart';
import '../../api/nexus/nexus_account_client.dart';
import '../../api/nexus/nexus_account_models.dart';
import '../../api/nexus/nexus_billing_models.dart';
import '../../providers/account_provider.dart';
import '../../providers/billing_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import 'error_retry.dart';
import 'nexus_form.dart';

/// Plan + add-on picker, pulled from `GET /plans` (the live catalog).
///
/// • Not subscribed → pick a plan + add-ons, single **Checkout** (one Stripe
///   session with everything).
/// • Already subscribed → switch the AI tier in place (`/billing/change-plan`)
///   and add/remove add-ons in place (`/billing/add-package` ·
///   `/billing/remove-package`), all prorated; portal stays for cancel /
///   payment method.
///
/// Entries are filtered by the account's `audience` segment. Set
/// [includePersonalAudience] to false when a separate wallet/membership section
/// already covers the Personal-audience (wallet-billed) plans — e.g. on the
/// Plan & Wallet screen — so this picker shows only the Stripe AI tiers.
///
/// Renders a [Column] (mainAxisSize.min) so it can be dropped into a sheet or a
/// scrolling screen. Self-contained: no overlay dependency.
class PlanPicker extends ConsumerStatefulWidget {
  final bool showHeader;
  final bool includePersonalAudience;

  const PlanPicker({
    super.key,
    this.showHeader = true,
    this.includePersonalAudience = true,
  });

  @override
  ConsumerState<PlanPicker> createState() => _PlanPickerState();
}

class _PlanPickerState extends ConsumerState<PlanPicker> {
  String? _selectedPlan;
  final Set<String> _selectedAddons = {}; // new-checkout selection
  bool _busy = false;
  String? _busyKey; // per-add-on busy

  bool _visibleFor(String audience, String? segment) {
    if (!widget.includePersonalAudience && audience == 'Personal') return false;
    return audience == 'Both' || segment == null || audience == segment;
  }

  /// Whether an add-on is currently on the subscription. Uses the authoritative
  /// active-add-on list from GET /billing/subscription; before it loads — or
  /// when the account's subscription-item lines were never backfilled (older
  /// subscriptions predate that table) — falls back to inferring the PBX
  /// `phone_system` add-on from the `pbx` capability.
  bool _activeAddon(String key, SubscriptionDetail? detail, NexusCapabilities caps) {
    if (detail != null && detail.addons.isNotEmpty) {
      return detail.activeAddonKeys.contains(key);
    }
    return key == 'phone_system' && caps.pbx;
  }

  void _refresh() {
    ref.invalidate(accountSummaryProvider);
    ref.invalidate(subscriptionDetailProvider);
    ref.invalidate(entitlementsProvider);
    ref.invalidate(walletBalanceProvider);
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final plans = ref.watch(plansProvider);
    final account = ref.watch(accountSummaryProvider);
    final sub = account.valueOrNull?.subscription;
    final currentPlanKey = sub?.planKey;
    final status = sub?.status ?? 'None';
    final subscribed = status == 'Active' ||
        status == 'Trialing' ||
        status == 'PastDue' ||
        status == 'Paused';
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    final segment = ent?.segment;
    final caps = ent?.capabilities ?? const NexusCapabilities();
    final detail = ref.watch(subscriptionDetailProvider).valueOrNull;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showHeader) ...[
          Text(subscribed ? 'Change plan & add-ons' : 'Choose your plan',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 4),
          Text(
              subscribed
                  ? 'Switch tiers or add/remove add-ons — applied immediately, prorated.'
                  : 'Routed cloud inference. Add any add-ons, then check out together.',
              style: TextStyle(fontSize: 12.5, color: t.muted)),
          const SizedBox(height: 16),
        ],
        plans.when(
          loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator())),
          error: (e, _) => ErrorRetry(
              error: e,
              action: 'load the plans',
              onRetry: () => ref.invalidate(plansProvider)),
          data: (catalog) {
            // Anything the account already OWNS is always visible, even when
            // the audience/segment filter would hide it — e.g. a Personal
            // account holding the Business phone add-on must still see (and
            // be able to manage) it.
            final visiblePlans = [
              for (final p in catalog.plans)
                if (_visibleFor(p.audience, segment) ||
                    p.key == currentPlanKey)
                  p
            ];
            final addons = [
              for (final a in catalog.addons)
                if (_visibleFor(a.audience, segment) ||
                    _activeAddon(a.key, detail, caps))
                  a
            ];
            if (visiblePlans.isEmpty && addons.isEmpty) {
              return Text('No plans available for your account.',
                  style: TextStyle(color: t.muted, fontSize: 12.5));
            }
            // The plan you're subscribed to reads as selected by default;
            // tapping another plan moves the radio (and offers the switch
            // CTA). Before this, the current plan only got a tiny CURRENT
            // chip and the radio sat empty — it looked unsubscribed.
            final effectiveSelected = _selectedPlan ?? currentPlanKey;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final p in visiblePlans)
                  _planCard(context, p, p.key == currentPlanKey,
                      selected: p.key == effectiveSelected),
                if (subscribed) _changePlanCta(context, currentPlanKey),
                if (addons.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text('ADD-ONS',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: t.faint)),
                  const SizedBox(height: 10),
                  for (final a in addons)
                    _addonCard(context, a, subscribed, detail, caps),
                ],
                const SizedBox(height: 6),
                if (!subscribed)
                  _checkoutCta(context)
                else ...[
                  _cancelButton(context, detail),
                  const SizedBox(height: 9),
                  _portalButton(
                      context, 'Manage billing / payment method (portal)'),
                ],
              ],
            );
          },
        ),
      ],
    );
  }

  // ── CTAs ────────────────────────────────────────────────────────────

  Widget _checkoutCta(BuildContext context) {
    final t = context.nexus;
    final ready = _selectedPlan != null;
    final n = _selectedAddons.length;
    return NexusButton(
      label: !ready
          ? 'Select a plan'
          : (n == 0 ? 'Checkout' : 'Checkout + $n add-on${n == 1 ? '' : 's'}'),
      busy: _busy,
      color: ready ? null : t.surface2,
      onTap: ready ? () => _checkout(_selectedPlan!) : null,
    );
  }

  Widget _portalButton(BuildContext context, String label,
      {bool danger = false}) {
    final t = context.nexus;
    return GestureDetector(
      onTap: _openPortal,
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
              color: danger ? t.danger.withValues(alpha: 0.5) : t.line2),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: danger ? t.danger : t.accent2)),
      ),
    );
  }

  Widget _cancelButton(BuildContext context, SubscriptionDetail? detail) {
    final t = context.nexus;
    final scheduled = detail?.cancelAtPeriodEnd ?? false;
    return GestureDetector(
      onTap: _busy ? null : () => _confirmCancel(detail),
      child: Container(
        width: double.infinity,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: t.danger.withValues(alpha: 0.5)),
        ),
        child: Text(
            scheduled
                ? 'Cancellation scheduled at period end'
                : 'Cancel subscription',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: t.danger)),
      ),
    );
  }

  Widget _changePlanCta(BuildContext context, String? currentPlanKey) {
    final target = _selectedPlan;
    if (target == null || target == currentPlanKey) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: NexusButton(
        label: 'Switch to this plan now',
        busy: _busy,
        onTap: () => _changePlan(target),
      ),
    );
  }

  // ── Cards ───────────────────────────────────────────────────────────

  Widget _planCard(BuildContext context, Plan p, bool current,
      {required bool selected}) {
    final t = context.nexus;
    final price =
        '\$${(p.priceCents / 100).toStringAsFixed(p.priceCents % 100 == 0 ? 0 : 2)}';
    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = p.key),
      child: Container(
        margin: const EdgeInsets.only(bottom: 11),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: selected ? t.accentSoft : t.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? t.accent : t.line2, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 18,
                  color: selected ? t.accent : t.faint),
              const SizedBox(width: 9),
              Flexible(
                child: Text(p.name,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text)),
              ),
              if (current) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(6)),
                  child: Text('CURRENT',
                      style: TextStyle(
                          fontSize: 8.5,
                          fontWeight: FontWeight.w700,
                          color: t.accent2)),
                ),
              ],
              const Spacer(),
              Text('$price/mo',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
            ]),
            const SizedBox(height: 11),
            if (p.description != null && p.description!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(p.description!,
                    style: TextStyle(fontSize: 12, height: 1.4, color: t.muted)),
              ),
            if (p.monthlyTokens > 0)
              _feature(context, '${_fmt(p.monthlyTokens)} tokens / mo'),
            if (p.monthlyImages > 0)
              _feature(context, '${p.monthlyImages} images / mo'),
            if (p.agentSessions > 0)
              _feature(context, '${p.agentSessions} agent sessions'),
          ],
        ),
      ),
    );
  }

  Widget _addonCard(BuildContext context, AddOn a, bool subscribed,
      SubscriptionDetail? detail, NexusCapabilities caps) {
    final t = context.nexus;
    final price =
        '\$${(a.priceCents / 100).toStringAsFixed(a.priceCents % 100 == 0 ? 0 : 2)}';
    final bonuses = <String>[
      if (a.bonusTokens > 0) '+${_fmt(a.bonusTokens)} tokens',
      if (a.bonusImages > 0) '+${a.bonusImages} images',
      if (a.bonusAgentSessions > 0) '+${a.bonusAgentSessions} sessions',
    ];
    final active = _activeAddon(a.key, detail, caps);
    final qty = detail?.addon(a.key)?.quantity ?? 1;
    final selectedForCheckout = _selectedAddons.contains(a.key);
    final busy = _busyKey == a.key;

    Widget trailing;
    if (!subscribed) {
      trailing = Icon(
          selectedForCheckout
              ? Icons.check_box
              : Icons.check_box_outline_blank,
          size: 22,
          color: selectedForCheckout ? t.accent : t.faint);
    } else if (busy) {
      trailing = const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2));
    } else {
      // Add & remove are both immediate/prorated in-app.
      trailing = GestureDetector(
        onTap: () => active ? _removePackage(a.key) : _addPackage(a.key),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: BoxDecoration(
            color: active ? t.surface2 : t.accentSoft,
            borderRadius: BorderRadius.circular(10),
            border: active ? Border.all(color: t.line2) : null,
          ),
          child: Text(active ? 'Remove' : 'Add',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: active ? t.danger : t.accent2)),
        ),
      );
    }

    return GestureDetector(
      onTap: subscribed
          ? null
          : () => setState(() => selectedForCheckout
              ? _selectedAddons.remove(a.key)
              : _selectedAddons.add(a.key)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (!subscribed && selectedForCheckout) || active
              ? t.accentSoft
              : t.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: (!subscribed && selectedForCheckout) || active
                  ? t.accent
                  : t.line2,
              width: 1.5),
        ),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(a.name,
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
                  ),
                  if (active && qty > 1) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                          color: t.surface2,
                          borderRadius: BorderRadius.circular(5)),
                      child: Text('×$qty',
                          style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: t.accent2)),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text('$price/mo',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: t.muted)),
                ]),
                if (a.description != null && a.description!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(a.description!,
                        style: TextStyle(
                            fontSize: 11.5, height: 1.35, color: t.muted)),
                  ),
                if (bonuses.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(bonuses.join(' · '),
                        style: TextStyle(fontSize: 11, color: t.accent2)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ]),
      ),
    );
  }

  Widget _feature(BuildContext context, String label) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(children: [
        Text('✓ ', style: TextStyle(color: t.good, fontSize: 12)),
        Text(label, style: TextStyle(fontSize: 12, color: t.muted)),
      ]),
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }

  // ── Actions ─────────────────────────────────────────────────────────

  Future<void> _checkout(String plan) async {
    final token = ref.read(authProvider).token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      final url = await NexusAccountClient(token: token)
          .startCheckout(plan: plan, addons: _selectedAddons.toList());
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } on ServerException catch (e) {
      if (e.statusCode == 409) {
        await _openPortal();
      } else {
        _toast('Checkout failed: ${e.message}');
      }
    } catch (e) {
      _toast(friendlyError(e, action: 'start checkout'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changePlan(String plan) async {
    final token = ref.read(authProvider).token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      await NexusAccountClient(token: token).changePlan(plan);
      _refresh();
      _toast('Plan changed to $plan.');
    } catch (e) {
      _toast(friendlyError(e, action: 'change the plan'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPackage(String key) async {
    final token = ref.read(authProvider).token;
    if (token == null || _busyKey != null) return;
    setState(() => _busyKey = key);
    try {
      await NexusAccountClient(token: token).addPackage(key);
      _refresh();
      _toast('Added.');
    } catch (e) {
      _toast(friendlyError(e, action: 'add the add-on'));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _removePackage(String key) async {
    final token = ref.read(authProvider).token;
    if (token == null || _busyKey != null) return;
    setState(() => _busyKey = key);
    try {
      await NexusAccountClient(token: token).removePackage(key);
      _refresh();
      _toast('Removed.');
    } catch (e) {
      _toast(friendlyError(e, action: 'remove the add-on'));
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
    ];
    final l = d.toLocal();
    return '${months[l.month - 1]} ${l.day}, ${l.year}';
  }

  /// Cancel the whole subscription. Offers period-end (keep access) or now.
  Future<void> _confirmCancel(SubscriptionDetail? detail) async {
    final t = context.nexus;
    final end = detail?.currentPeriodEnd;
    final endLabel = end != null ? _fmtDate(end) : 'the end of the billing period';
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: t.bg2,
        title: Text('Cancel subscription?',
            style: TextStyle(color: t.text, fontWeight: FontWeight.w700)),
        content: Text(
            'Cancel at period end keeps full access until $endLabel. '
            'End now stops it immediately.',
            style: TextStyle(color: t.muted, fontSize: 13, height: 1.4)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Keep plan', style: TextStyle(color: t.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'now'),
              child: Text('End now', style: TextStyle(color: t.danger))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'period'),
              child: Text('At period end',
                  style: TextStyle(color: t.accent2))),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    final token = ref.read(authProvider).token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      await NexusAccountClient(token: token)
          .cancelSubscription(atPeriodEnd: choice == 'period');
      _refresh();
      _toast(choice == 'period'
          ? 'Subscription will cancel at period end.'
          : 'Subscription canceled.');
    } catch (e) {
      _toast(friendlyError(e, action: 'cancel the subscription'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openPortal() async {
    final token = ref.read(authProvider).token;
    if (token == null) return;
    try {
      final url = await NexusAccountClient(token: token).openBillingPortal();
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      _toast(friendlyError(e, action: 'open the billing portal'));
    }
  }
}
