import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/exceptions.dart';
import '../../api/nexus/nexus_billing_models.dart';
import '../../providers/account_provider.dart';
import '../../providers/billing_providers.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';
import '../../widgets/nexus/plan_picker.dart';

/// Plan & wallet. Personal → prepaid wallet (balance, top-up, memberships,
/// ledger). Business → Stripe subscription summary + manage.
class PlanWalletScreen extends ConsumerStatefulWidget {
  const PlanWalletScreen({super.key});

  @override
  ConsumerState<PlanWalletScreen> createState() => _PlanWalletScreenState();
}

class _PlanWalletScreenState extends ConsumerState<PlanWalletScreen> {
  bool _busy = false;
  static const _topupAmounts = [500, 1000, 2000, 5000];

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  void _refresh() {
    ref.invalidate(entitlementsProvider);
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(walletTransactionsProvider);
    ref.invalidate(availableMembershipsProvider);
    ref.invalidate(accountSummaryProvider);
  }

  Future<void> _topup(int amountCents) async {
    final client = ref.read(nexusBillingClientProvider);
    if (client == null || _busy) return;
    setState(() => _busy = true);
    try {
      final url = await client.topup(amountCents);
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _toast('Finish in the browser, then pull to refresh.');
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _buy(String key) async {
    final client = ref.read(nexusBillingClientProvider);
    if (client == null || _busy) return;
    setState(() => _busy = true);
    try {
      await client.buyMembership(key);
      _refresh();
      _toast('Membership active.');
    } on ServerException catch (e) {
      _toast(e.statusCode == 402
          ? 'Not enough balance — add funds first.'
          : e.message);
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(int id) async {
    final client = ref.read(nexusBillingClientProvider);
    if (client == null) return;
    try {
      await client.cancelMembership(id);
      _refresh();
    } catch (e) {
      _toast('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final entAsync = ref.watch(entitlementsProvider);
    return NexusPage(
      title: 'Plan & wallet',
      body: RefreshIndicator(
        onRefresh: () async => _refresh(),
        child: entAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            Padding(
                padding: const EdgeInsets.all(24),
                child: Text('$e', style: TextStyle(color: t.danger)))
          ]),
          data: (ent) => ListView(
            padding: const EdgeInsets.all(16),
            children:
                ent.isBusiness ? _business(context) : _personal(context, ent),
          ),
        ),
      ),
    );
  }

  // ── Personal ────────────────────────────────────────────────────────
  List<Widget> _personal(BuildContext context, NexusEntitlements ent) {
    final t = context.nexus;
    final available =
        ref.watch(availableMembershipsProvider).valueOrNull ?? const [];
    final txns = ref.watch(walletTransactionsProvider).valueOrNull ?? const [];
    return [
      NexusCard(
        radius: 16,
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [t.accentSoft, t.surface]),
        borderColor: t.accent.withValues(alpha: 0.32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('WALLET BALANCE',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: t.accent2)),
            const SizedBox(height: 6),
            Text(ent.balanceLabel,
                style: TextStyle(
                    fontSize: 30, fontWeight: FontWeight.w700, color: t.text)),
          ],
        ),
      ),
      const SizedBox(height: 14),
      const NexusSectionLabel('Add funds'),
      const SizedBox(height: 9),
      Wrap(spacing: 9, runSpacing: 9, children: [
        for (final amt in _topupAmounts)
          GestureDetector(
            onTap: _busy ? null : () => _topup(amt),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
              decoration: BoxDecoration(
                  color: t.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.line2)),
              child: Text('\$${(amt / 100).toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
            ),
          ),
      ]),
      if (ent.memberships.isNotEmpty) ...[
        const SizedBox(height: 18),
        const NexusSectionLabel('Your memberships'),
        const SizedBox(height: 9),
        for (final m in ent.memberships)
          NexusCard(
            radius: 14,
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.name.isEmpty ? m.planKey : m.name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: t.text)),
                    Text(
                        '\$${(m.priceCents / 100).toStringAsFixed(2)}/mo · ${m.status}',
                        style: TextStyle(fontSize: 11.5, color: t.muted)),
                  ],
                ),
              ),
              TextButton(
                  onPressed: () => _cancel(m.id),
                  child: Text('Cancel', style: TextStyle(color: t.danger))),
            ]),
          ),
      ],
      if (available.isNotEmpty) ...[
        const SizedBox(height: 18),
        const NexusSectionLabel('Available'),
        const SizedBox(height: 9),
        for (final p in available)
          if (!ent.memberships.any((m) => m.planKey == p.key))
            NexusCard(
              radius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(p.name,
                            style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: t.text))),
                    Text('${p.priceLabel}/mo',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
                  ]),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(p.description,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: t.muted)),
                  ],
                  const SizedBox(height: 12),
                  NexusButton(
                      label: 'Start — ${p.priceLabel}/mo',
                      busy: _busy,
                      onTap: () => _buy(p.key)),
                ],
              ),
            ),
      ],
      const SizedBox(height: 18),
      const NexusSectionLabel('Subscription plans'),
      const SizedBox(height: 4),
      Text(
          'AI subscription tiers (tokens, images & agent sessions) — billed via card, separate from your wallet.',
          style: TextStyle(fontSize: 12, height: 1.4, color: t.muted)),
      const SizedBox(height: 12),
      const PlanPicker(showHeader: false, includePersonalAudience: false),
      const SizedBox(height: 18),
      const NexusSectionLabel('Recent activity'),
      const SizedBox(height: 9),
      if (txns.isEmpty)
        NexusCard(
            radius: 14,
            padding: const EdgeInsets.all(20),
            child: Center(
                child: Text('No transactions yet.',
                    style: TextStyle(color: t.muted))))
      else
        NexusCard(
          padding: EdgeInsets.zero,
          radius: 14,
          child: Column(children: [
            for (var i = 0; i < txns.length; i++)
              _txnRow(context, txns[i], last: i == txns.length - 1),
          ]),
        ),
      const SizedBox(height: 24),
    ];
  }

  Widget _txnRow(BuildContext context, NexusWalletTransaction tx,
      {required bool last}) {
    final t = context.nexus;
    final credit = tx.amountCents >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
      decoration: BoxDecoration(
          border: last ? null : Border(bottom: BorderSide(color: t.line))),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tx.description.isEmpty ? tx.kind : tx.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, color: t.text)),
              Text(tx.kind, style: TextStyle(fontSize: 11, color: t.faint)),
            ],
          ),
        ),
        Text(
            '${credit ? '+' : '-'}\$${(tx.amountCents.abs() / 100).toStringAsFixed(2)}',
            style: nexusMono(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: credit ? t.good : t.text)),
      ]),
    );
  }

  // ── Business ────────────────────────────────────────────────────────
  List<Widget> _business(BuildContext context) {
    final t = context.nexus;
    final account = ref.watch(accountSummaryProvider).valueOrNull;
    final sub = account?.subscription;
    final status = sub?.status ?? 'None';
    final subscribed = status == 'Active' ||
        status == 'Trialing' ||
        status == 'PastDue' ||
        status == 'Paused';
    return [
      NexusCard(
        radius: 16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('SUBSCRIPTION',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: t.accent2)),
            const SizedBox(height: 8),
            Row(children: [
              Text(sub?.planKey?.toUpperCase() ?? 'NO PLAN',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: t.text)),
              const Spacer(),
              NexusPill(status.toUpperCase(),
                  color: subscribed ? t.good : t.muted,
                  bg: subscribed ? t.good.withValues(alpha: 0.14) : t.surface2),
            ]),
            if (sub != null) ...[
              const SizedBox(height: 10),
              Text(
                  '${_fmt(sub.tokenLimit)} tokens · ${sub.imageLimit} images',
                  style: TextStyle(fontSize: 12.5, color: t.muted)),
            ],
          ],
        ),
      ),
      const SizedBox(height: 16),
      const NexusSectionLabel('Plans & add-ons'),
      const SizedBox(height: 12),
      const PlanPicker(showHeader: false, includePersonalAudience: false),
    ];
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(0)}K';
    return '$n';
  }
}
