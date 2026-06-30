import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/exceptions.dart';
import '../../api/nexus/nexus_account_client.dart';
import '../../providers/account_provider.dart';
import '../../providers/billing_providers.dart';
import '../../providers/nav_provider.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Implements the "Unlock this feature" decision tree (§5): Personal →
/// wallet-billed membership (+ top-up on 402); Business → Stripe portal/checkout.
class UnlockSheet extends ConsumerStatefulWidget {
  final String capability; // 'pbx' | 'aiCallTasks' | …
  final String feature;
  const UnlockSheet({super.key, required this.capability, required this.feature});

  static Future<void> show(BuildContext context,
      {required String capability, required String feature}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => UnlockSheet(capability: capability, feature: feature),
    );
  }

  @override
  ConsumerState<UnlockSheet> createState() => _UnlockSheetState();
}

class _UnlockSheetState extends ConsumerState<UnlockSheet> {
  bool _busy = false;
  bool _topupView = false;
  String? _info;

  static const _topupAmounts = [500, 1000, 2000, 5000];

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _buy(String planKey) async {
    final client = ref.read(nexusBillingClientProvider);
    if (client == null || _busy) return;
    setState(() {
      _busy = true;
      _info = null;
    });
    try {
      await client.buyMembership(planKey);
      ref.invalidate(entitlementsProvider);
      ref.invalidate(walletBalanceProvider);
      _toast('Unlocked ${widget.feature}.');
      if (mounted) Navigator.of(context).pop();
    } on ServerException catch (e) {
      if (e.statusCode == 402) {
        setState(() {
          _topupView = true;
          _info = 'Not enough balance — add funds, then try again.';
        });
      } else {
        _toast(e.message);
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _topup(int amountCents) async {
    final client = ref.read(nexusBillingClientProvider);
    if (client == null || _busy) return;
    setState(() => _busy = true);
    try {
      final url = await client.topup(amountCents);
      if (url.isNotEmpty) {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        _info =
            'Finish payment in the browser, then pull to refresh — crediting is automatic.';
        setState(() {});
      }
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Business + subscribed: add the Phone System package in place.
  Future<void> _addPhoneSystem() async {
    final token = ref.read(authProvider).token;
    if (token == null || _busy) return;
    setState(() => _busy = true);
    try {
      await NexusAccountClient(token: token).addPackage('phone_system');
      ref.invalidate(entitlementsProvider);
      _toast('Phone System added.');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _toast('$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    final ent = ref.watch(entitlementsProvider).valueOrNull;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            18, 4, 18, MediaQuery.of(context).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    color: t.accentSoft, borderRadius: BorderRadius.circular(11)),
                child: Icon(Icons.lock_open, color: t.accent2, size: 19),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text('Unlock ${widget.feature}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: t.text)),
              ),
            ]),
            const SizedBox(height: 14),
            if (ent == null)
              const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()))
            else if (ent.isBusiness)
              _business(context)
            else if (_topupView)
              _topupSection(context, ent)
            else
              _personal(context, ent),
            if (_info != null) ...[
              const SizedBox(height: 12),
              Text(_info!, style: TextStyle(fontSize: 12.5, color: t.muted)),
            ],
          ],
        ),
      ),
    );
  }

  // Personal: wallet-billed membership.
  Widget _personal(BuildContext context, ent) {
    final t = context.nexus;
    final plans = ref.watch(availableMembershipsProvider).valueOrNull ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '${widget.feature} unlocks with a Consumer Phone Automation membership, billed from your wallet.',
            style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
        const SizedBox(height: 8),
        Text('Wallet balance: ${ent.balanceLabel}',
            style: nexusMono(
                fontSize: 12.5, fontWeight: FontWeight.w600, color: t.accent2)),
        const SizedBox(height: 14),
        if (plans.isEmpty)
          Text('No membership plans available right now.',
              style: TextStyle(fontSize: 13, color: t.muted))
        else
          for (final p in plans) ...[
            NexusCard(
              radius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(p.name,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: t.text)),
                    ),
                    Text('${p.priceLabel}/mo',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
                  ]),
                  if (p.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(p.description,
                        style:
                            TextStyle(fontSize: 12.5, height: 1.4, color: t.muted)),
                  ],
                  const SizedBox(height: 12),
                  NexusButton(
                      label: 'Unlock — ${p.priceLabel}/mo',
                      busy: _busy,
                      onTap: () => _buy(p.key)),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        TextButton(
            onPressed: () => setState(() => _topupView = true),
            child: Text('Add funds to wallet',
                style: TextStyle(color: t.accent2))),
      ],
    );
  }

  Widget _topupSection(BuildContext context, ent) {
    final t = context.nexus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Add funds',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: t.text)),
        const SizedBox(height: 4),
        Text('Balance: ${ent.balanceLabel}. Min \$5, max \$500.',
            style: TextStyle(fontSize: 12.5, color: t.muted)),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final amt in _topupAmounts)
              GestureDetector(
                onTap: _busy ? null : () => _topup(amt),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  decoration: BoxDecoration(
                    color: t.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.line2),
                  ),
                  child: Text('\$${(amt / 100).toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: t.text)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton(
            onPressed: () => setState(() => _topupView = false),
            child: Text('Back', style: TextStyle(color: t.accent2))),
      ],
    );
  }

  // Business: Stripe subscription / add-ons.
  Widget _business(BuildContext context) {
    final t = context.nexus;
    final account = ref.watch(accountSummaryProvider).valueOrNull;
    final status = account?.subscription.status ?? 'None';
    final subscribed = status == 'Active' ||
        status == 'Trialing' ||
        status == 'PastDue' ||
        status == 'Paused';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
            '${widget.feature} is part of the Phone System package on your business plan.',
            style: TextStyle(fontSize: 13, height: 1.45, color: t.muted)),
        const SizedBox(height: 16),
        if (subscribed)
          NexusButton(
              label: 'Add Phone System',
              busy: _busy,
              onTap: _addPhoneSystem)
        else
          NexusButton(
              label: 'Choose a plan',
              onTap: () {
                Navigator.of(context).pop();
                ref
                    .read(overlayProvider.notifier)
                    .openSubSheet(section: 'plan');
              }),
      ],
    );
  }
}
