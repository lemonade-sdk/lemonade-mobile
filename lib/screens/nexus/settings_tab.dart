import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/account_provider.dart';
import '../../providers/app_mode_provider.dart';
import '../../providers/billing_providers.dart';
import '../../providers/models_provider.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../providers/omni_router_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/voice_providers.dart';
import '../../screens/nexus/agents_screen.dart';
import '../../screens/nexus/http_tools_screen.dart';
import '../../screens/nexus/knowledge_pages_screen.dart';
import '../../screens/nexus/plan_wallet_screen.dart';
import '../../screens/nexus/team_screen.dart';
import '../../screens/omni_router_screen.dart';
import '../../screens/servers_screen.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/gateway_gate.dart';
import '../../widgets/nexus/model_manager.dart';
import '../../widgets/nexus/nexus_ui.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appModeProvider);

    // Pull-to-refresh re-fetches the installed model list from the selected
    // server, so models installed/removed outside the app (e.g. via the
    // Lemonade server itself or another client) show up without a restart —
    // the list otherwise only updates on server/app-mode changes.
    return RefreshIndicator(
      onRefresh: () => ref.read(modelsProvider.notifier).fetchModels(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _profile(context, ref),
          const SizedBox(height: 18),
          if (mode.showsModelManager) ...[
            const ModelManager(),
            const SizedBox(height: 18),
          ],
          ..._groups(context, ref),
        ],
      ),
    );
  }

  Widget _profile(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final auth = ref.watch(authProvider);
    final name = auth.user?.displayName ?? 'Not signed in';
    final email = auth.user?.email ?? 'Subscription optional';
    final badge = auth.isSignedIn ? (auth.user?.role ?? 'MEMBER') : 'LOCAL';
    return NexusCard(
      radius: 16,
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF5B8CFF), Color(0xFF2F5BE0)]),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(_initials(name),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: Colors.white)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700, color: t.text)),
              Text(email, style: TextStyle(fontSize: 12.5, color: t.muted)),
            ],
          ),
        ),
        NexusPill(badge.toUpperCase(),
            color: Colors.white, bg: t.accent),
      ]),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '··';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  List<Widget> _groups(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final mode = ref.watch(appModeProvider);
    final auth = ref.watch(authProvider);
    final omni = ref.watch(omniRouterEnabledProvider);
    final theme = ref.watch(themeProvider);
    final voiceSettings = mode == AppMode.subscription
        ? ref.watch(voiceSettingsProvider).valueOrNull
        : null;
    final hasPbx = mode == AppMode.subscription &&
        ref.watch(hasCapabilityProvider('pbx'));

    return [
      // Account / subscription only belongs in Subscription mode.
      if (mode == AppMode.subscription)
        _group(context, 'Account', [
          if (auth.isSignedIn)
            _navRow(context, 'Plan & wallet',
                sub: 'Balance, top-up, plan & add-ons',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PlanWalletScreen()))),
          if (auth.isSignedIn && hasPbx)
            _navRow(context, 'Team',
                sub: 'Org members & roles',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const TeamScreen()))),
          _actionRow(
            context,
            auth.isSignedIn ? 'Sign out' : 'Sign in to Subscription',
            color: auth.isSignedIn ? t.danger : t.accent2,
            onTap: () {
              if (auth.isSignedIn) {
                ref.read(authProvider.notifier).logout();
              } else {
                SignInScreen.push(context);
              }
            },
          ),
        ]),
      _group(context, 'Inference', [
        _toggleRow(context, 'Lemonade Omni',
            sub: 'Agentic multimodal tool calls', value: omni, onChanged: (v) {
          ref.read(omniRouterEnabledProvider.notifier).toggle();
        }),
        _navRow(context, 'Omni workflow & models',
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const OmniRouterScreen()))),
        _navRow(context, 'Model defaults',
            onTap: () => Navigator.of(context).pushNamed('/model-defaults')),
      ]),
      _group(context, 'Servers', [
        _navRow(context, 'Manage servers',
            sub: 'Add, discover & test Lemonade servers',
            onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ServersScreen()))),
      ]),
      // Voice/PBX settings are gateway-only — Subscription mode.
      if (mode == AppMode.subscription)
        _group(context, 'Voice & calls', [
          _toggleRow(context, 'Record AI calls',
              sub: voiceSettings == null
                  ? 'Mixed-audio recording of AI call tasks'
                  : 'Caller ID: ${voiceSettings.callerIdName.isEmpty ? '—' : voiceSettings.callerIdName}',
              value: voiceSettings?.recordCalls ?? false,
              onChanged: (v) async {
                final client = ref.read(nexusVoiceClientProvider);
                if (client == null) return;
                try {
                  await client.updateSettings(recordCalls: v);
                  ref.invalidate(voiceSettingsProvider);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Couldn’t update recording: $e')));
                  }
                }
              }),
          if (voiceSettings != null)
            _valueRow(context, 'Channels',
                '${voiceSettings.channelLimit} · ${voiceSettings.timeZone}'),
          _navRow(context, 'Transcription history',
              onTap: () => Navigator.of(context).pushNamed('/transcription')),
        ]),
      // AI phone-agent configuration — requires the pbx capability.
      if (hasPbx)
        _group(context, 'AI phone agents', [
          _navRow(context, 'Agent profiles',
              sub: 'Personas, voices, tools, knowledge',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AgentsScreen()))),
          _navRow(context, 'HTTP tools',
              sub: 'Custom webhooks agents can call',
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HttpToolsScreen()))),
          _navRow(context, 'Agent knowledge',
              sub: 'Reference pages the agent cites',
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => const KnowledgePagesScreen()))),
        ]),
      _group(context, 'Privacy & notifications', [
        // Not wired to a backend yet — disabled so they don't read as real.
        _toggleRow(context, 'End-to-end encryption',
            sub: 'Coming soon', value: false, onChanged: null),
        _toggleRow(context, 'Push notifications',
            sub: 'Coming soon', value: false, onChanged: null),
      ]),
      _group(context, 'Appearance', [
        _valueRow(context, 'Theme', theme.displayName),
      ]),
    ];
  }

  Widget _group(BuildContext context, String header, List<Widget> rows) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NexusSectionLabel(header),
          const SizedBox(height: 9),
          NexusCard(
            padding: EdgeInsets.zero,
            radius: 15,
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  rows[i],
                  if (i != rows.length - 1) Divider(color: t.line, height: 1),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowShell(BuildContext context,
      {required Widget child, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        child: child,
      ),
    );
  }

  Widget _navRow(BuildContext context, String label,
      {String? sub, VoidCallback? onTap}) {
    final t = context.nexus;
    return _rowShell(
      context,
      onTap: onTap,
      child: Row(children: [
        Expanded(child: _labelSub(context, label, sub)),
        Icon(Icons.chevron_right, size: 18, color: t.faint),
      ]),
    );
  }

  Widget _toggleRow(BuildContext context, String label,
      {String? sub,
      required bool value,
      required ValueChanged<bool>? onChanged}) {
    return _rowShell(
      context,
      child: Row(children: [
        Expanded(child: _labelSub(context, label, sub)),
        Switch(value: value, onChanged: onChanged),
      ]),
    );
  }

  Widget _valueRow(BuildContext context, String label, String value) {
    final t = context.nexus;
    return _rowShell(
      context,
      child: Row(children: [
        Expanded(child: _labelSub(context, label, null)),
        Text(value, style: nexusMono(fontSize: 13, color: t.muted)),
      ]),
    );
  }

  Widget _actionRow(BuildContext context, String label,
      {required Color color, VoidCallback? onTap}) {
    return _rowShell(
      context,
      onTap: onTap,
      child: Text(label,
          style:
              TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Widget _labelSub(BuildContext context, String label, String? sub) {
    final t = context.nexus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w500, color: t.text)),
        if (sub != null && sub.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(sub, style: TextStyle(fontSize: 11, color: t.muted)),
          ),
      ],
    );
  }
}
