import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/nav_provider.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../providers/voice_providers.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/nexus/nexus_ui.dart';

/// One IVR node. Mirrors the backend flow JSON: `{type, config:{...},
/// next:{branch->nodeId}}`. `config.label` is a client-side display name the
/// runner ignores (so it round-trips safely).
class _Node {
  String id;
  String type;
  final Map<String, String> config; // text/prompt/extension/number/target/…
  final Map<String, String?> branches; // fixed branches (next/timeout/open/…)
  final List<({String key, String target})> menu; // menu digit/key → nodeId

  _Node({
    required this.id,
    required this.type,
    Map<String, String>? config,
    Map<String, String?>? branches,
    List<({String key, String target})>? menu,
  })  : config = config ?? {},
        branches = branches ?? {},
        menu = menu ?? [];

  String get label =>
      (config['label']?.isNotEmpty ?? false) ? config['label']! : id;
}

/// IVR flow editor wired to the real backend schema (`/voice/ivr-flows`). Node
/// types and branches match `IvrRunner`: a **menu** node routes each pressed/
/// spoken key to another node, and a **dialExtension** node rings a chosen
/// extension — so "digit → dial extension" is an explicit, visible link.
class FlowEditorOverlay extends ConsumerStatefulWidget {
  final int? flowId;
  const FlowEditorOverlay({super.key, this.flowId});

  @override
  ConsumerState<FlowEditorOverlay> createState() => _FlowEditorOverlayState();
}

class _FlowEditorOverlayState extends ConsumerState<FlowEditorOverlay> {
  final _name = TextEditingController(text: 'New flow');
  final _scroll = ScrollController();
  final List<_Node> _nodes = [];
  final Map<String, TextEditingController> _ctrls = {};
  String? _entryId;
  bool _published = false;
  bool _loading = false;
  bool _saving = false;
  int _seq = 0;

  // type → (display label, branch keys it routes on, terminal?)
  static const _typeMeta = <String, ({String name, List<String> branches})>{
    'say': (name: 'Play message', branches: ['next']),
    'menu': (name: 'Menu (press / say)', branches: ['timeout', 'invalid']),
    'collectDigits': (name: 'Collect digits', branches: ['next', 'timeout']),
    'businessHours': (name: 'Business hours', branches: ['open', 'closed']),
    'dialExtension': (name: 'Dial extension', branches: ['noAnswer']),
    'dialExternal': (name: 'Dial external', branches: ['noAnswer']),
    'aiAgent': (name: 'AI agent', branches: ['done']),
    'voicemail': (name: 'Voicemail', branches: []),
    'goto': (name: 'Go to node', branches: []),
    'hangup': (name: 'Hang up', branches: []),
  };

  @override
  void initState() {
    super.initState();
    if (widget.flowId != null) {
      _load();
    } else {
      final n = _Node(id: _newId(), type: 'say', config: {'label': 'Greeting'});
      _nodes.add(n);
      _entryId = n.id;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _scroll.dispose();
    for (final c in _ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _newId() => 'n${++_seq}';

  /// Persistent controller per (node, field) so the cursor doesn't jump.
  TextEditingController _c(String nodeId, String field, String initial) =>
      _ctrls.putIfAbsent(
          '$nodeId:$field', () => TextEditingController(text: initial));

  Future<void> _load() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null) return;
    setState(() => _loading = true);
    try {
      final flow = await client.getFlow(widget.flowId!);
      _name.text = flow.name;
      _published = flow.isPublished;
      final json = flow.flowJson;
      if (json != null) {
        _entryId = json['entry']?.toString();
        final nodes = json['nodes'];
        if (nodes is Map) {
          nodes.forEach((id, raw) {
            if (raw is! Map) return;
            final type = (raw['type'] ?? 'say').toString();
            final config = <String, String>{};
            final cfg = raw['config'];
            if (cfg is Map) {
              cfg.forEach((k, v) => config['$k'] = '$v');
            }
            final branches = <String, String?>{};
            final menu = <({String key, String target})>[];
            final next = raw['next'];
            if (next is Map) {
              final fixed = _typeMeta[type]?.branches ?? const [];
              next.forEach((k, v) {
                final key = '$k';
                if (type == 'menu' && !fixed.contains(key)) {
                  menu.add((key: key, target: '$v'));
                } else {
                  branches[key] = '$v';
                }
              });
            }
            _nodes.add(_Node(
                id: '$id',
                type: type,
                config: config,
                branches: branches,
                menu: menu));
          });
        }
        for (final n in _nodes) {
          final num = int.tryParse(n.id.replaceAll(RegExp(r'\D'), ''));
          if (num != null && num > _seq) _seq = num;
        }
      }
    } catch (e) {
      _toast(friendlyError(e, action: 'load the flow'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _toJson() {
    const numeric = {'maxDigits', 'timeoutSec', 'maxRetries', 'maxTurns'};
    final nodes = <String, dynamic>{};
    for (final n in _nodes) {
      final config = <String, dynamic>{};
      n.config.forEach((k, v) {
        if (v.trim().isEmpty) return;
        config[k] = numeric.contains(k) ? (int.tryParse(v) ?? v) : v;
      });
      final next = <String, dynamic>{};
      n.branches.forEach((k, v) {
        if (v != null && v.isNotEmpty) next[k] = v;
      });
      for (final mi in n.menu) {
        if (mi.key.trim().isNotEmpty && mi.target.isNotEmpty) {
          next[mi.key.trim()] = mi.target;
        }
      }
      nodes[n.id] = {
        'type': n.type,
        if (config.isNotEmpty) 'config': config,
        if (next.isNotEmpty) 'next': next,
      };
    }
    return {
      'entry': _entryId ?? (_nodes.isNotEmpty ? _nodes.first.id : ''),
      'nodes': nodes,
    };
  }

  Future<void> _save() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client == null || _saving) return;
    if (_nodes.isEmpty) {
      _toast('Add at least one node before saving.');
      return;
    }
    if (_entryId == null || !_nodes.any((n) => n.id == _entryId)) {
      _toast('Set an entry node before saving.');
      return;
    }
    setState(() => _saving = true);
    try {
      final json = _toJson();
      final name =
          _name.text.trim().isEmpty ? 'Untitled flow' : _name.text.trim();
      final saved = widget.flowId == null
          ? await client.createFlow(name, json)
          : await client.updateFlow(widget.flowId!, name, json);
      if (_published && !saved.isPublished) {
        await client.publishFlow(saved.id);
      }
      ref.invalidate(voiceFlowsProvider);
      if (mounted) ref.read(overlayProvider.notifier).close();
    } catch (e) {
      _toast(friendlyError(e, action: 'save the flow'));
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteFlow() async {
    final client = ref.read(nexusVoiceClientProvider);
    if (client != null && widget.flowId != null) {
      try {
        await client.deleteFlow(widget.flowId!);
        ref.invalidate(voiceFlowsProvider);
      } catch (e) {
        _toast(friendlyError(e, action: 'delete the flow'));
      }
    }
    if (mounted) ref.read(overlayProvider.notifier).close();
  }

  Future<void> _addNode() async {
    final t = context.nexus;
    final type = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.bg2,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SafeArea(
        // Scrollable so the chip grid doesn't clip on short screens.
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add a node',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: t.text)),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    for (final e in _typeMeta.entries)
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, e.key),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                              color: t.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: t.line2)),
                          child: Text(e.value.name,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: t.text)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (type == null) return;
    setState(() => _nodes.add(_Node(id: _newId(), type: type)));
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return Material(
      color: t.bg,
      child: SafeArea(
        child: Column(
          children: [
            _header(context),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : Scrollbar(
                      controller: _scroll,
                      child: ListView(
                        controller: _scroll,
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final n in _nodes) _nodeCard(context, n),
                          GestureDetector(
                            onTap: _addNode,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: t.line2, width: 1.5),
                              ),
                              child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add, size: 16, color: t.accent2),
                                    const SizedBox(width: 8),
                                    Text('Add node',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: t.accent2)),
                                  ]),
                            ),
                          ),
                          if (widget.flowId != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 18),
                              child: GestureDetector(
                                onTap: _deleteFlow,
                                child: Center(
                                  child: Text('Delete this flow',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: t.danger)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    final t = context.nexus;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: t.bg2,
        border: Border(bottom: BorderSide(color: t.line)),
      ),
      child: Row(children: [
        NexusIconButton(
            icon: Icons.arrow_back_ios_new,
            size: 36,
            onTap: () => ref.read(overlayProvider.notifier).close()),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('IVR FLOW · EDITING',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: t.faint)),
              TextField(
                controller: _name,
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: t.text),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => setState(() => _published = !_published),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
                color: _published ? t.good.withValues(alpha: 0.16) : t.surface2,
                borderRadius: BorderRadius.circular(10)),
            child: Text(_published ? 'Published' : 'Draft',
                style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: _published ? t.good : t.muted)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _save,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(10)),
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Save',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
          ),
        ),
      ]),
    );
  }

  Widget _nodeCard(BuildContext context, _Node n) {
    final t = context.nexus;
    final isEntry = n.id == _entryId;
    return Container(
      margin: const EdgeInsets.only(bottom: 13),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isEntry ? t.good : t.line2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NexusPill((_typeMeta[n.type]?.name ?? n.type).toUpperCase(),
                color: t.accent2, outlined: true),
            const SizedBox(width: 8),
            if (isEntry)
              NexusPill('ENTRY', color: const Color(0xFF04140D), bg: t.good),
            const Spacer(),
            if (!isEntry)
              GestureDetector(
                onTap: () => setState(() => _entryId = n.id),
                child: Text('Set entry',
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: t.accent2)),
              ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => setState(() {
                _nodes.remove(n);
                if (_entryId == n.id) {
                  _entryId = _nodes.isNotEmpty ? _nodes.first.id : null;
                }
              }),
              child: Icon(Icons.delete_outline, size: 18, color: t.danger),
            ),
          ]),
          const SizedBox(height: 10),
          // label (display only — runner ignores config.label)
          _textField(n, 'label', 'Node label', bold: true),
          const SizedBox(height: 8),
          ..._configFields(context, n),
          ..._transitions(context, n),
        ],
      ),
    );
  }

  /// Config inputs specific to the node type.
  List<Widget> _configFields(BuildContext context, _Node n) {
    switch (n.type) {
      case 'say':
        return [_textField(n, 'text', 'What Lemonade says…', lines: 2)];
      case 'menu':
        return [_textField(n, 'prompt', 'Menu prompt — "Press 1 for sales…"', lines: 2)];
      case 'collectDigits':
        return [
          _textField(n, 'prompt', 'Prompt'),
          const SizedBox(height: 8),
          _textField(n, 'maxDigits', 'Max digits (e.g. 4)'),
        ];
      case 'businessHours':
        return [_textField(n, 'timezone', 'Timezone — e.g. America/Los_Angeles')];
      case 'dialExtension':
        return [_extensionPicker(context, n)];
      case 'dialExternal':
        return [_textField(n, 'number', 'External number — +1 415 555 0123')];
      case 'voicemail':
        return [
          _extensionPicker(context, n),
          const SizedBox(height: 8),
          _textField(n, 'greeting', 'Voicemail greeting (optional)', lines: 2),
        ];
      case 'aiAgent':
        return [
          _textField(n, 'systemPrompt', 'Agent instructions / objective', lines: 3),
          const SizedBox(height: 8),
          _textField(n, 'maxTurns', 'Max turns (optional)'),
        ];
      case 'goto':
        return [_nodeDropdown(context, 'Jump to', n.config['target'],
            (v) => setState(() => n.config['target'] = v ?? ''), n)];
      case 'hangup':
        return [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text('Ends the call.',
                style: TextStyle(fontSize: 11, color: context.nexus.faint)),
          )
        ];
      default:
        return const [];
    }
  }

  /// Branch transitions (the wiring to other nodes).
  List<Widget> _transitions(BuildContext context, _Node n) {
    final t = context.nexus;
    final widgets = <Widget>[];

    if (n.type == 'menu') {
      widgets.add(const SizedBox(height: 10));
      widgets.add(Text('Options — key the caller presses / says → goes to',
          style: TextStyle(fontSize: 11, color: t.faint)));
      widgets.add(const SizedBox(height: 6));
      for (var i = 0; i < n.menu.length; i++) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(
              width: 40,
              child: TextField(
                controller: _c('${n.id}:menukey', '$i', n.menu[i].key),
                onChanged: (v) =>
                    n.menu[i] = (key: v, target: n.menu[i].target),
                textAlign: TextAlign.center,
                style: nexusMono(
                    fontSize: 13, fontWeight: FontWeight.w700, color: t.accent2),
                decoration: _miniDeco(context, '1'),
              ),
            ),
            const SizedBox(width: 6),
            Icon(Icons.arrow_forward, size: 14, color: t.faint),
            const SizedBox(width: 6),
            Expanded(
              child: _nodeDropdown(context, 'target', n.menu[i].target,
                  (v) => setState(() =>
                      n.menu[i] = (key: n.menu[i].key, target: v ?? '')),
                  n),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 15, color: t.danger),
              onPressed: () => setState(() => n.menu.removeAt(i)),
            ),
          ]),
        ));
      }
      widgets.add(GestureDetector(
        onTap: () => setState(() => n.menu.add((key: '', target: ''))),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: t.line2)),
          child: Text('+ Add option',
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: t.accent2)),
        ),
      ));
    }

    // Fixed branches for the type.
    final fixed = _typeMeta[n.type]?.branches ?? const [];
    for (final br in fixed) {
      widgets.add(const SizedBox(height: 9));
      widgets.add(Row(children: [
        SizedBox(
          width: 78,
          child: Text(_branchLabel(br),
              style: TextStyle(fontSize: 11, color: t.faint)),
        ),
        Expanded(
          child: _nodeDropdown(context, _branchLabel(br), n.branches[br],
              (v) => setState(() => n.branches[br] = v), n),
        ),
      ]));
    }
    return widgets;
  }

  String _branchLabel(String br) => switch (br) {
        'next' => 'Then go to',
        'timeout' => 'On timeout',
        'invalid' => 'On invalid',
        'noAnswer' => 'No answer',
        'open' => 'If open',
        'closed' => 'If closed',
        'done' => 'When done',
        _ => br,
      };

  Widget _extensionPicker(BuildContext context, _Node n) {
    final t = context.nexus;
    final exts = ref.watch(voiceExtensionsProvider).valueOrNull ?? const [];
    final current = n.config['extension'];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: t.line)),
      child: DropdownButton<String>(
        isExpanded: true,
        value: exts.any((e) => e.number == current) ? current : null,
        hint: Text('Choose extension to dial',
            style: TextStyle(color: t.muted, fontSize: 13)),
        dropdownColor: t.bg2,
        underline: const SizedBox.shrink(),
        items: [
          for (final e in exts)
            DropdownMenuItem(
                value: e.number,
                child: Text('${e.number} · ${e.displayName}',
                    style: TextStyle(color: t.text, fontSize: 13))),
        ],
        onChanged: (v) => setState(() => n.config['extension'] = v ?? ''),
      ),
    );
  }

  Widget _nodeDropdown(BuildContext context, String hint, String? value,
      ValueChanged<String?> onChanged, _Node self) {
    final t = context.nexus;
    final others = _nodes.where((x) => x.id != self.id).toList();
    final valid = others.any((o) => o.id == value) ? value : null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 2),
      decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.line2)),
      child: DropdownButton<String?>(
        isExpanded: true,
        value: valid,
        hint: Text(hint, style: TextStyle(color: t.muted, fontSize: 12.5)),
        dropdownColor: t.bg2,
        underline: const SizedBox.shrink(),
        items: [
          const DropdownMenuItem(value: null, child: Text('— end call —')),
          for (final o in others)
            DropdownMenuItem(
                value: o.id,
                child: Text(o.label,
                    style: TextStyle(color: t.accent2, fontSize: 12.5))),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _textField(_Node n, String field, String hint,
      {int lines = 1, bool bold = false}) {
    final t = context.nexus;
    return TextField(
      controller: _c(n.id, field, n.config[field] ?? ''),
      onChanged: (v) => n.config[field] = v,
      minLines: lines,
      maxLines: lines,
      style: bold
          ? TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w600, color: t.text)
          : (field == 'maxDigits' || field == 'maxTurns'
              ? nexusMono(fontSize: 12.5, color: t.text)
              : TextStyle(fontSize: 12.5, color: t.text)),
      decoration: _miniDeco(context, hint),
    );
  }

  InputDecoration _miniDeco(BuildContext context, String hint) {
    final t = context.nexus;
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: t.bg,
      hintStyle: TextStyle(color: t.faint, fontSize: 12.5),
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: t.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: t.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide(color: t.accent),
      ),
    );
  }
}
