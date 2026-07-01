import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/exceptions.dart';
import '../api/nexus/nexus_account_client.dart';
import '../api/nexus/nexus_account_models.dart';
import '../providers/account_provider.dart';

/// Account / subscription home. Signing in is entirely optional — the app works
/// without it. When signed out this shows Login / Register; when signed in it
/// shows billing, plans, usage meters, and per-agent history.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        actions: [
          if (auth.isSignedIn)
            IconButton(
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
              onPressed: () => _confirmSignOut(context, ref),
            ),
        ],
      ),
      body: auth.busy
          ? const Center(child: CircularProgressIndicator())
          : auth.isSignedIn
              ? const _AccountDashboard()
              : const _AuthForms(),
    );
  }

  static Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            'Your subscription server will be removed from the server list. '
            'Local servers are unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signed-out: Login / Register
// ─────────────────────────────────────────────────────────────────────────────

class _AuthForms extends ConsumerStatefulWidget {
  const _AuthForms();

  @override
  ConsumerState<_AuthForms> createState() => _AuthFormsState();
}

class _AuthFormsState extends ConsumerState<_AuthForms> {
  bool _registerMode = false;
  bool _busy = false;
  String? _error;
  bool _obscure = true;

  final _company = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _company.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Email and password are required.');
      return;
    }
    if (_registerMode && _company.text.trim().isEmpty) {
      setState(() => _error = 'Company name is required to register.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final notifier = ref.read(authProvider.notifier);
      if (_registerMode) {
        await notifier.register(
          clientName: _company.text.trim(),
          email: email,
          password: password,
        );
      } else {
        await notifier.login(email: email, password: password);
      }
      // On success the screen rebuilds into the dashboard automatically.
    } on LemonadeApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).padding.bottom),
      children: [
        const SizedBox(height: 8),
        Icon(Icons.account_circle_outlined, size: 64, color: scheme.primary),
        const SizedBox(height: 12),
        Text(
          _registerMode ? 'Create an account' : 'Welcome back',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 4),
        Text(
          'A subscription is optional — sign in to manage billing, plans, and '
          'use the Nexus Projects hosted models.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),

        // Login / Register toggle
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Log in')),
            ButtonSegment(value: true, label: Text('Register')),
          ],
          selected: {_registerMode},
          onSelectionChanged: _busy
              ? null
              : (s) => setState(() {
                    _registerMode = s.first;
                    _error = null;
                  }),
        ),
        const SizedBox(height: 20),

        if (_registerMode) ...[
          TextField(
            controller: _company,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Company / account name',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.business_outlined),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _email,
          enabled: !_busy,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.email_outlined),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          enabled: !_busy,
          obscureText: _obscure,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _busy ? null : _submit(),
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            helperText: _registerMode
                ? 'Min 8 characters, with an uppercase letter and a symbol.'
                : null,
            helperMaxLines: 2,
          ),
        ),

        if (_error != null) ...[
          const SizedBox(height: 16),
          _ErrorBanner(_error!),
        ],

        const SizedBox(height: 20),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_registerMode ? 'Create account' : 'Log in'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Signed-in: dashboard
// ─────────────────────────────────────────────────────────────────────────────

class _AccountDashboard extends ConsumerWidget {
  const _AccountDashboard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final account = ref.watch(accountSummaryProvider);
    final agentUsage = ref.watch(agentUsageProvider);

    // A 401 on the authenticated calls means the app token was rotated/revoked
    // server-side (each login mints a fresh one). There is no refresh — drop the
    // session so the user is shown the sign-in form again.
    ref.listen(accountSummaryProvider, (_, next) {
      if (next.hasError && next.error is UnauthorizedException) {
        ref.read(authProvider.notifier).handleUnauthorized();
      }
    });

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(accountSummaryProvider);
        ref.invalidate(agentUsageProvider);
        ref.invalidate(plansProvider);
        await ref
            .read(accountSummaryProvider.future)
            .catchError((_) => _noAccount);
      },
      child: ListView(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
        children: [
          // Identity header (uses cached identity, always available).
          _IdentityHeader(
            email: auth.user?.email ?? '',
            company: auth.client?.name ?? '',
            role: auth.user?.role ?? '',
          ),
          const SizedBox(height: 20),

          // Usage vs. capacity — "used" is summed from /usage/agents, the
          // limits come from /account (the router has no /usage endpoint).
          _SectionTitle('Tokens & capacity', icon: Icons.donut_large_outlined),
          account.when(
            data: (a) => _UsageCard(
              subscription: a.subscription,
              usage: agentUsage.asData?.value,
            ),
            loading: () => const _LoadingCard(),
            error: (e, _) => _AuthAwareError(e),
          ),
          const SizedBox(height: 20),

          // Subscription summary.
          _SectionTitle('Subscription', icon: Icons.workspace_premium_outlined),
          account.when(
            data: (a) => _SubscriptionCard(a.subscription),
            loading: () => const _LoadingCard(),
            error: (e, _) => _AuthAwareError(e),
          ),
          const SizedBox(height: 12),
          _BillingButtons(token: auth.token!),
          const SizedBox(height: 20),

          // Plans + add-ons.
          _SectionTitle('Plans & add-ons', icon: Icons.sell_outlined),
          _PlansSection(
            token: auth.token!,
            currentPlanKey: account.asData?.value.subscription.planKey,
          ),
          const SizedBox(height: 20),

          // Per-agent history.
          _SectionTitle('Usage history', icon: Icons.history),
          const _AgentUsageSection(),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static const AccountSummary _noAccount = AccountSummary(
    user: NexusUser(email: '', displayName: '', role: ''),
    client: NexusClient(id: 0, name: ''),
    subscription: Subscription(
        status: 'None', tokenLimit: 0, imageLimit: 0, agentLimit: 0),
  );
}

class _IdentityHeader extends StatelessWidget {
  final String email;
  final String company;
  final String role;
  const _IdentityHeader(
      {required this.email, required this.company, required this.role});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial =
        email.isNotEmpty ? email[0].toUpperCase() : '?';
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: scheme.primaryContainer,
          child: Text(initial,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: scheme.onPrimaryContainer)),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(email.isEmpty ? 'Signed in' : email,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              if (company.isNotEmpty)
                Text(company, style: TextStyle(color: scheme.onSurfaceVariant)),
              if (role.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Chip(
                    label: Text(role),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Tokens used vs. capacity. "Used" is summed from the per-agent usage report
/// (the router has no /usage endpoint); limits come from the subscription.
class _UsageCard extends StatelessWidget {
  final Subscription subscription;
  final AgentUsageReport? usage;
  const _UsageCard({required this.subscription, this.usage});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usedTokens =
        usage?.agents.fold<int>(0, (sum, a) => sum + a.totalTokens) ?? 0;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Meter(
            label: 'Tokens',
            icon: Icons.toll_outlined,
            used: usedTokens,
            limit: subscription.tokenLimit,
            knownUsed: usage != null,
          ),
          const SizedBox(height: 14),
          _CapacityRow(
            icon: Icons.image_outlined,
            label: 'Image capacity',
            value: _fmtInt(subscription.imageLimit),
          ),
          const SizedBox(height: 8),
          _CapacityRow(
            icon: Icons.smart_toy_outlined,
            label: 'Agent sessions',
            value: _fmtInt(subscription.agentLimit),
          ),
          if (usage != null) ...[
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text('Spend this period',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
                Text('\$${usage!.totalCost.toStringAsFixed(2)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
          if (subscription.currentPeriodEnd != null) ...[
            const SizedBox(height: 10),
            Text('Resets ${_fmtDate(subscription.currentPeriodEnd!)}',
                style:
                    TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  final String label;
  final IconData icon;
  final int used;
  final int limit;

  /// When false the "used" figure isn't available yet (usage still loading).
  final bool knownUsed;

  const _Meter({
    required this.label,
    required this.icon,
    required this.used,
    required this.limit,
    this.knownUsed = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final frac = limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
    final pct = limit > 0 ? (used / limit * 100) : 0.0;
    final over = limit > 0 && used > limit;
    final color = over ? scheme.error : scheme.primary;
    final remaining = (limit - used) > 0 ? (limit - used) : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const Spacer(),
            Text(
              knownUsed
                  ? '${_fmtInt(used)} / ${_fmtInt(limit)}'
                  : '— / ${_fmtInt(limit)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: frac,
            minHeight: 8,
            backgroundColor: scheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          !knownUsed
              ? 'Capacity ${_fmtInt(limit)} tokens'
              : over
                  ? '${pct.toStringAsFixed(0)}% — over limit'
                  : '${_fmtInt(remaining)} remaining (${pct.toStringAsFixed(1)}%)',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _CapacityRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _CapacityRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// Renders a friendly "session expired" message for 401s, otherwise the error.
class _AuthAwareError extends StatelessWidget {
  final Object error;
  const _AuthAwareError(this.error);

  @override
  Widget build(BuildContext context) {
    if (error is UnauthorizedException) {
      return const _ErrorBanner(
          'Your session has expired. Please sign in again.');
    }
    return _ErrorBanner(_msg(error));
  }
}

class _SubscriptionCard extends StatelessWidget {
  final Subscription sub;
  const _SubscriptionCard(this.sub);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                sub.planKey?.toUpperCase() ?? 'NO PLAN',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 10),
              _StatusChip(sub.status, active: sub.isActive),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Token limit', _fmtInt(sub.tokenLimit)),
          _kv('Image limit', _fmtInt(sub.imageLimit)),
          _kv('Agent sessions', _fmtInt(sub.agentLimit)),
          if (sub.currentPeriodEnd != null)
            _kv('Renews', _fmtDate(sub.currentPeriodEnd!)),
          if (!sub.isActive) ...[
            const SizedBox(height: 8),
            Text(
              'No active subscription — the app still works with local servers. '
              'Pick a plan below to add hosted capacity.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(k)),
            Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  final String status;
  final bool active;
  const _StatusChip(this.status, {required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = active ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final fg = active ? scheme.onPrimaryContainer : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _BillingButtons extends ConsumerStatefulWidget {
  final String token;
  const _BillingButtons({required this.token});

  @override
  ConsumerState<_BillingButtons> createState() => _BillingButtonsState();
}

class _BillingButtonsState extends ConsumerState<_BillingButtons> {
  bool _busy = false;

  Future<void> _openPortal() async {
    setState(() => _busy = true);
    try {
      final url =
          await NexusAccountClient(token: widget.token).openBillingPortal();
      if (mounted) await _launch(context, url);
    } on LemonadeApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (e) {
      if (mounted) _snack(context, 'Could not open billing portal: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _openPortal,
      icon: _busy
          ? const SizedBox(
              height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.receipt_long_outlined),
      label: const Text('Manage billing'),
    );
  }
}

class _PlansSection extends ConsumerStatefulWidget {
  final String token;
  final String? currentPlanKey;
  const _PlansSection({required this.token, this.currentPlanKey});

  @override
  ConsumerState<_PlansSection> createState() => _PlansSectionState();
}

class _PlansSectionState extends ConsumerState<_PlansSection> {
  final Set<String> _selectedAddons = {};
  String? _checkoutBusyPlan;

  Future<void> _subscribe(Plan plan) async {
    setState(() => _checkoutBusyPlan = plan.key);
    try {
      final url = await NexusAccountClient(token: widget.token).startCheckout(
        plan: plan.key,
        addons: _selectedAddons.toList(),
      );
      if (mounted) await _launch(context, url);
    } on LemonadeApiException catch (e) {
      if (mounted) _snack(context, e.message);
    } catch (e) {
      if (mounted) _snack(context, 'Checkout failed: $e');
    } finally {
      if (mounted) setState(() => _checkoutBusyPlan = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(plansProvider);
    final scheme = Theme.of(context).colorScheme;

    return catalog.when(
      loading: () => const _LoadingCard(),
      error: (e, _) => _ErrorBanner(_msg(e)),
      data: (cat) {
        if (cat.plans.isEmpty) {
          return _Card(
              child: Text('No plans available right now.',
                  style: TextStyle(color: scheme.onSurfaceVariant)));
        }
        return Column(
          children: [
            for (final plan in cat.plans)
              _PlanCard(
                plan: plan,
                isCurrent: plan.key == widget.currentPlanKey,
                busy: _checkoutBusyPlan == plan.key,
                onSubscribe: _checkoutBusyPlan == null
                    ? () => _subscribe(plan)
                    : null,
              ),
            if (cat.addons.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Add-ons (applied at checkout)',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
              ),
              for (final addon in cat.addons)
                CheckboxListTile(
                  value: _selectedAddons.contains(addon.key),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selectedAddons.add(addon.key);
                    } else {
                      _selectedAddons.remove(addon.key);
                    }
                  }),
                  contentPadding: EdgeInsets.zero,
                  title: Text(addon.name),
                  subtitle: Text(_addonSubtitle(addon)),
                  secondary: Text(_price(addon.priceCents)),
                ),
            ],
          ],
        );
      },
    );
  }

  String _addonSubtitle(AddOn a) {
    final parts = <String>[];
    if (a.bonusTokens > 0) parts.add('+${_fmtInt(a.bonusTokens)} tokens');
    if (a.bonusImages > 0) parts.add('+${_fmtInt(a.bonusImages)} images');
    if (a.bonusAgentSessions > 0) {
      parts.add('+${a.bonusAgentSessions} sessions');
    }
    return parts.isEmpty ? (a.description ?? '') : parts.join(' · ');
  }
}

class _PlanCard extends StatelessWidget {
  final Plan plan;
  final bool isCurrent;
  final bool busy;
  final VoidCallback? onSubscribe;
  const _PlanCard({
    required this.plan,
    required this.isCurrent,
    required this.busy,
    required this.onSubscribe,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrent ? scheme.primary : scheme.outlineVariant,
          width: isCurrent ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(plan.name,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              Text(_price(plan.priceCents),
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: scheme.primary)),
            ],
          ),
          if (plan.description != null && plan.description!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(plan.description!,
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _pill(context, '${_fmtInt(plan.monthlyTokens)} tokens'),
              _pill(context, '${_fmtInt(plan.monthlyImages)} images'),
              _pill(context, '${plan.agentSessions} sessions'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: isCurrent
                ? OutlinedButton(
                    onPressed: null,
                    child: const Text('Current plan'),
                  )
                : FilledButton(
                    onPressed: onSubscribe,
                    child: busy
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Subscribe'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 12)),
    );
  }
}

class _AgentUsageSection extends ConsumerWidget {
  const _AgentUsageSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(agentUsageProvider);
    final scheme = Theme.of(context).colorScheme;

    return report.when(
      loading: () => const _LoadingCard(),
      error: (e, _) => _ErrorBanner(_msg(e)),
      data: (r) {
        if (r.agents.isEmpty) {
          return _Card(
              child: Text('No usage recorded yet this period.',
                  style: TextStyle(color: scheme.onSurfaceVariant)));
        }
        return _Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final row in r.agents) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row.agent,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          Text(
                            '${row.calls} calls · ${_fmtInt(row.totalTokens)} tokens',
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text('\$${row.cost.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
                const Divider(height: 16),
              ],
              Row(
                children: [
                  const Expanded(
                      child: Text('Total',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  Text('\$${r.totalCost.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small shared widgets / helpers
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String title;
  final IconData icon;
  const _SectionTitle(this.title, {required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => const _Card(
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: CircularProgressIndicator(),
          ),
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: scheme.onErrorContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

String _msg(Object e) =>
    e is LemonadeApiException ? e.message : e.toString();

String _price(int cents) {
  if (cents == 0) return 'Free';
  final dollars = cents / 100.0;
  final text = dollars == dollars.roundToDouble()
      ? dollars.toStringAsFixed(0)
      : dollars.toStringAsFixed(2);
  return '\$$text/mo';
}

String _fmtInt(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return (n < 0 ? '-' : '') + buf.toString();
}

String _fmtDate(DateTime d) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  final local = d.toLocal();
  return '${months[local.month - 1]} ${local.day}, ${local.year}';
}

Future<void> _launch(BuildContext context, String url) async {
  if (url.isEmpty) {
    _snack(context, 'No URL returned by the server.');
    return;
  }
  final uri = Uri.tryParse(url);
  if (uri == null ||
      !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
    if (context.mounted) _snack(context, 'Could not open the browser.');
  }
}

void _snack(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}
