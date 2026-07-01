import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_voice_models.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../widgets/nexus/nexus_form.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// Org team members (`GET /voice/team`). Read-only; extension assignment is done
/// per-extension in PBX.
class TeamScreen extends ConsumerWidget {
  const TeamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.nexus;
    final team = ref.watch(voiceTeamProvider);
    return NexusPage(
      title: 'Team',
      body: team.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$e',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.danger)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => ref.invalidate(voiceTeamProvider),
                  child: Text('Retry', style: TextStyle(color: t.accent2)),
                ),
              ],
            ),
          ),
        ),
        data: (members) => members.isEmpty
            ? Center(
                child: Text('No team members.',
                    style: TextStyle(color: t.muted)))
            : Scrollbar(
                child: ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                      16, 16, 16, 16 + MediaQuery.of(context).padding.bottom),
                  itemCount: members.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _row(context, members[i]),
                ),
              ),
      ),
    );
  }

  Widget _row(BuildContext context, NexusTeamMember m) {
    final t = context.nexus;
    final name = m.displayName.isEmpty ? m.email : m.displayName;
    final (roleColor, roleBg) = switch (m.role) {
      'Owner' => (Colors.white, t.accent),
      'Admin' => (t.accent2, t.accentSoft),
      _ => (t.muted, t.surface2),
    };
    return NexusCard(
      radius: 14,
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF5B8CFF), Color(0xFF2F5BE0)]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(_initials(name),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Colors.white)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: t.text)),
              Text(m.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: t.muted)),
            ],
          ),
        ),
        NexusPill(m.role.toUpperCase(), color: roleColor, bg: roleBg),
      ]),
    );
  }

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first
          .substring(0, parts.first.length >= 2 ? 2 : 1)
          .toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}
