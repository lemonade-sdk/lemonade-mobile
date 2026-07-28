import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/endpoints/admin_endpoint.dart';
import '../../providers/lemonade_client_provider.dart';
import '../../providers/models_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import 'device_stats_card.dart';
import 'model_picker_sheet.dart';
import 'nexus_ui.dart';

/// On-device Model Manager (Local AI / Mesh), faithful to the design:
/// loaded-model hero + unload, context-size slider, installed models
/// (load/unload/remove), Hugging Face search → install with progress, and the
/// inference-backends list. Wires the Lemonade admin endpoints.
class ModelManager extends ConsumerStatefulWidget {
  const ModelManager({super.key});

  @override
  ConsumerState<ModelManager> createState() => _ModelManagerState();
}

class _HfVariant {
  final String name;
  final int sizeBytes;
  const _HfVariant(this.name, this.sizeBytes);
}

class _ModelManagerState extends ConsumerState<ModelManager> {
  // Context size (tokens), applied as ctx_size on the next load. A ValueNotifier
  // (not setState) so dragging the slider rebuilds only the slider + ctx label,
  // not the whole Model Manager (device polling, model lists, backends) — which
  // made the drag janky.
  final ValueNotifier<int> _ctx = ValueNotifier<int>(8192);
  String? _busyId; // model id currently load/unload/removing
  // HF search
  final _hf = TextEditingController();
  bool _searching = false;
  String? _hfRecipe;
  String? _hfSuggestedName;
  List<String> _hfMmproj = const [];
  List<String> _hfLabels = const [];
  List<_HfVariant> _variants = const [];
  String? _installing; // variant name being installed
  double _installPct = 0;
  // backends
  final Set<String> _expandedRecipes = {}; // recipe groups open in the UI
  Map<String, dynamic>? _systemInfo;
  bool _loadedSysInfo = false;
  String? _backendBusy; // "recipe/backend" currently installing/removing

  @override
  void initState() {
    super.initState();
    _fetchSystemInfo();
  }

  @override
  void dispose() {
    _hf.dispose();
    _ctx.dispose();
    super.dispose();
  }

  AdminEndpoint? get _admin => ref.read(lemonadeClientProvider)?.admin;

  Future<void> _fetchSystemInfo() async {
    try {
      final info = await _admin?.systemInfo();
      if (mounted) setState(() => _systemInfo = info);
    } catch (_) {
      // best effort
    } finally {
      if (mounted) setState(() => _loadedSysInfo = true);
    }
  }

  void _toast(String m) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
    }
  }

  Future<void> _load(String id) async {
    final admin = _admin;
    if (admin == null) return;
    setState(() => _busyId = id);
    // Select it as the active/default model FIRST so the choice sticks even when
    // the server load is component-wise (collections) or errors — otherwise a
    // failed load would silently drop the selection.
    await ref.read(selectedModelProvider.notifier).selectModel(id);
    try {
      // Clamp the requested context to the model's supported window.
      final model =
          ref.read(modelsProvider).where((m) => m.id == id).firstOrNull;
      final maxCtx = (model?.maxContextWindow ?? 0) > 0
          ? model!.maxContextWindow
          : 131072;
      final ctx = _ctx.value.clamp(1024, maxCtx);
      await admin.load(modelName: id, ctxSize: ctx);
    } catch (e) {
      // The selection sticks even when the server-side load fails.
      _toast(friendlyError(e, action: 'load the model on the server'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  /// Change the default model / collection (the one new chats start with) via
  /// the searchable picker.
  Future<void> _pickDefault() async {
    final current = ref.read(selectedModelProvider);
    final picked = await ModelPickerSheet.show(context, current: current);
    if (picked != null && picked != current) {
      await ref.read(selectedModelProvider.notifier).selectModel(picked);
    }
  }

  Future<void> _unload([String? id]) async {
    final admin = _admin;
    if (admin == null) return;
    setState(() => _busyId = id ?? '__all');
    try {
      await admin.unload(modelName: id);
    } catch (e) {
      _toast(friendlyError(e, action: 'unload the model'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _remove(String id) async {
    final admin = _admin;
    if (admin == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove model?'),
        content: Text('Delete $id from local storage?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Remove',
                  style: TextStyle(color: context.nexus.danger))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busyId = id);
    try {
      await admin.delete(modelName: id);
      ref.read(modelsProvider.notifier).fetchModels();
    } catch (e) {
      _toast(friendlyError(e, action: 'remove the model'));
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  Future<void> _search() async {
    final admin = _admin;
    final checkpoint = _hf.text.trim();
    if (admin == null || checkpoint.isEmpty || _searching) return;
    if (!checkpoint.contains('/')) {
      _toast('Enter a Hugging Face repo as owner/name (e.g. unsloth/Qwen3-8B-GGUF)');
      return;
    }
    setState(() {
      _searching = true;
      _variants = const [];
    });
    try {
      final res = await admin.pullVariants(checkpoint: checkpoint);
      if (!mounted) return;
      final variants = (res['variants'] as List?) ?? const [];
      setState(() {
        _hfRecipe = res['recipe']?.toString();
        _hfSuggestedName = res['suggested_name']?.toString();
        _hfMmproj = ((res['mmproj_files'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        _hfLabels = ((res['suggested_labels'] as List?) ?? const [])
            .map((e) => '$e')
            .toList();
        _variants = variants
            .whereType<Map>()
            .map((v) => _HfVariant(
                '${v['name']}', (v['size_bytes'] as num?)?.toInt() ?? 0))
            .toList();
      });
      if (_variants.isEmpty) _toast('No GGUF variants found for $checkpoint');
    } catch (e) {
      _toast(friendlyError(e, action: 'search Hugging Face'));
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _install(_HfVariant variant) async {
    final admin = _admin;
    final name = _hfSuggestedName;
    if (admin == null || name == null || _installing != null) return;
    final modelName = 'user.$name-${variant.name}';
    setState(() {
      _installing = variant.name;
      _installPct = 0;
    });
    try {
      await for (final ev in admin.pullStream(
        modelName: modelName,
        checkpoint: _hf.text.trim(),
        recipe: _hfRecipe,
        vision: _hfLabels.contains('vision'),
        mmproj: _hfMmproj.isNotEmpty ? _hfMmproj.first : null,
      )) {
        if (ev is PullProgress && ev.percent != null) {
          if (mounted) setState(() => _installPct = ev.percent! / 100);
        } else if (ev is PullComplete) {
          _toast('Installed $modelName');
          ref.read(modelsProvider.notifier).fetchModels();
        } else if (ev is PullError) {
          _toast('Install failed: ${ev.message}');
        }
      }
    } catch (e) {
      _toast(friendlyError(e, action: 'install the model'));
    } finally {
      if (mounted) setState(() => _installing = null);
    }
  }

  String _fmtCtx(double v) {
    final k = v / 1024;
    return k >= 1 ? '${k.round()}K' : '${v.round()}';
  }

  String _fmtSize(int bytes) {
    if (bytes <= 0) return '';
    final gb = bytes / 1e9;
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    return '${(bytes / 1e6).round()} MB';
  }

  @override
  Widget build(BuildContext context) {
    final models = ref.watch(modelsProvider);
    final selected = ref.watch(selectedModelProvider);

    // The context-size ceiling is the selected model's supported window.
    final selectedModel = models.where((m) => m.id == selected).firstOrNull;
    final maxCtx = (selectedModel?.maxContextWindow ?? 0) > 0
        ? selectedModel!.maxContextWindow
        : 131072;

    final collections = models.where((m) => m.isCollection).toList();
    final plainModels = models.where((m) => !m.isCollection).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DeviceStatsCard(),
        const SizedBox(height: 16),
        _loadedHero(context, selected, maxCtx),
        const SizedBox(height: 16),
        _contextSlider(context, maxCtx),
        const SizedBox(height: 16),
        if (models.isEmpty)
          _info(context,
              'No models — pick a server in Settings → Servers, or install one below.')
        else ...[
          const NexusSectionLabel('Models'),
          const SizedBox(height: 10),
          if (plainModels.isEmpty)
            _info(context, 'No standalone models installed.')
          else
            for (final m in plainModels) ...[
              _installedTile(context, m, m.id == selected),
              const SizedBox(height: 10),
            ],
          if (collections.isNotEmpty) ...[
            const SizedBox(height: 8),
            const NexusSectionLabel('Collections'),
            const SizedBox(height: 10),
            for (final m in collections) ...[
              _installedTile(context, m, m.id == selected),
              const SizedBox(height: 10),
            ],
          ],
        ],
        const SizedBox(height: 6),
        const NexusSectionLabel('Available · Hugging Face'),
        const SizedBox(height: 10),
        _hfSearch(context),
        if (_variants.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final v in _variants) ...[
            _variantTile(context, v),
            const SizedBox(height: 10),
          ],
        ],
        const SizedBox(height: 6),
        _backends(context),
      ],
    );
  }

  Widget _loadedHero(BuildContext context, String? selected, int maxCtx) {
    final t = context.nexus;
    final has = selected != null && selected.isNotEmpty;
    return NexusCard(
      radius: 16,
      onTap: _pickDefault,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [t.accentSoft, t.surface],
      ),
      borderColor: t.accent.withValues(alpha: 0.32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('DEFAULT MODEL · NEW CHATS',
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.7,
                    color: t.accent2)),
            const Spacer(),
            Row(children: [
              Text('Change',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: t.accent2)),
              Icon(Icons.expand_more, size: 14, color: t.accent2),
            ]),
          ]),
          const SizedBox(height: 7),
          if (has)
            Row(children: [
              NexusStatusDot(color: t.good, size: 9),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(selected,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nexusMono(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: t.text)),
                    ValueListenableBuilder<int>(
                      valueListenable: _ctx,
                      builder: (_, ctx, __) => Text(
                          'Serving on :13305 · ctx ${_fmtCtx(ctx.clamp(1024, maxCtx).toDouble())}',
                          style: TextStyle(fontSize: 11, color: t.muted)),
                    ),
                  ],
                ),
              ),
              _miniBtn(context, _busyId == '__all' ? '…' : 'Unload',
                  () => _unload()),
            ])
          else
            Text('No model loaded — tap Load on one below.',
                style: TextStyle(fontSize: 13, color: t.muted)),
        ],
      ),
    );
  }

  Widget _contextSlider(BuildContext context, int maxCtx) {
    final t = context.nexus;
    // Context is always a multiple of 1024 (one division per 1024 tokens), and
    // can't exceed the selected model's supported window.
    final maxD = maxCtx.toDouble();
    final divisions = ((maxCtx - 1024) ~/ 1024).clamp(1, 100000);
    return ValueListenableBuilder<int>(
      valueListenable: _ctx,
      builder: (_, ctxVal, __) {
        final value = ctxVal.clamp(1024, maxCtx).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text('CONTEXT SIZE',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: t.faint)),
              const Spacer(),
              Text(_fmtCtx(value),
                  style: nexusMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.accent2)),
            ]),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: t.accent,
                inactiveTrackColor: t.surface2,
                thumbColor: Colors.white,
                overlayColor: t.accent.withValues(alpha: 0.15),
                trackHeight: 6,
              ),
              child: Slider(
                value: value,
                min: 1024,
                max: maxD,
                divisions: divisions,
                onChanged: (v) => _ctx.value = (v / 1024).round() * 1024,
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('1K', style: nexusMono(fontSize: 10, color: t.faint)),
                Text(_fmtCtx(maxD),
                    style: nexusMono(fontSize: 10, color: t.faint)),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _installedTile(BuildContext context, ModelInfo m, bool isLoaded) {
    final t = context.nexus;
    final busy = _busyId == m.id;
    final badge = _badge(m);
    return NexusCard(
      radius: 14,
      borderColor: isLoaded ? t.accent.withValues(alpha: 0.5) : t.line,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            NexusPill(badge.$2, color: badge.$1, outlined: true),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.id,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: nexusMono(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.text)),
                  Text(_capabilityLine(m),
                      style: TextStyle(fontSize: 10.5, color: t.muted)),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: busy ? null : () => isLoaded ? _unload(m.id) : _load(m.id),
                child: Container(
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: isLoaded ? t.accent : t.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : Text(isLoaded ? 'Loaded · Unload' : 'Load',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: isLoaded ? Colors.white : t.accent2)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: busy ? null : () => _remove(m.id),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.line2)),
                child: Text('Remove',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.danger)),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _hfSearch(BuildContext context) {
    final t = context.nexus;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: t.line2),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 13),
          child: Row(children: [
            Icon(Icons.search, size: 16, color: t.faint),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _hf,
                onSubmitted: (_) => _search(),
                style: TextStyle(fontSize: 13.5, color: t.text),
                decoration: InputDecoration(
                  isCollapsed: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  hintText: 'Hugging Face repo — owner/name…',
                  hintStyle: TextStyle(color: t.faint, fontSize: 13.5),
                  border: InputBorder.none,
                  filled: false,
                ),
              ),
            ),
            if (_searching)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              GestureDetector(
                onTap: _search,
                child: Text('Search',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: t.accent2)),
              ),
          ]),
        ),
      ],
    );
  }

  Widget _variantTile(BuildContext context, _HfVariant v) {
    final t = context.nexus;
    final installing = _installing == v.name;
    return NexusCard(
      radius: 14,
      child: Row(children: [
        NexusPill(_hfRecipe?.toUpperCase() ?? 'GGUF',
            color: t.accent2, outlined: true),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${_hfSuggestedName ?? ''} · ${v.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: nexusMono(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.text)),
              Text(_fmtSize(v.sizeBytes),
                  style: TextStyle(fontSize: 10.5, color: t.muted)),
            ],
          ),
        ),
        if (installing)
          Text('${(_installPct * 100).round()}%',
              style: nexusMono(fontSize: 12, color: t.accent2))
        else
          GestureDetector(
            onTap: () => _install(v),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                  color: t.accentSoft, borderRadius: BorderRadius.circular(10)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.download, size: 14, color: t.accent2),
                const SizedBox(width: 5),
                Text('Get',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.accent2)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _backends(BuildContext context) {
    final t = context.nexus;
    if (!_loadedSysInfo) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()));
    }
    final recipes = (_systemInfo?['recipes'] as Map?) ?? const {};
    if (recipes.isEmpty) return const SizedBox.shrink();

    // Group backends by recipe instead of one flat wall of rows. Only
    // backends this machine can actually run are shown. Each backend has a
    // `state`: unsupported | installable | update_required | installed —
    // anything `unsupported` (or missing) is hidden.
    final groups = <_BackendGroup>[];
    recipes.forEach((recipe, info) {
      if (info is! Map) return;
      final backends = (info['backends'] as Map?) ?? const {};
      final entries = <_BackendEntry>[];
      backends.forEach((backend, binfo) {
        if (binfo is! Map) return;
        final state = (binfo['state'] ?? '').toString();
        if (state.isEmpty || state == 'unsupported') return;
        final device = (binfo['device'] ?? binfo['status'] ?? '').toString();
        entries.add(_BackendEntry('$backend', device, state));
      });
      if (entries.isEmpty) return;
      // Installed first, then updates, then installable; alphabetical within.
      int rank(_BackendEntry e) => e.state == 'installed'
          ? 0
          : e.state == 'update_required'
              ? 1
              : 2;
      entries.sort((a, b) {
        final r = rank(a).compareTo(rank(b));
        return r != 0 ? r : a.backend.compareTo(b.backend);
      });
      groups.add(_BackendGroup('$recipe', entries));
    });
    if (groups.isEmpty) return const SizedBox.shrink();

    // Recipes with something installed float to the top.
    groups.sort((a, b) {
      final r = (b.installedCount > 0 ? 1 : 0) -
          (a.installedCount > 0 ? 1 : 0);
      return r != 0 ? r : a.recipe.compareTo(b.recipe);
    });
    final totalInstalled =
        groups.fold<int>(0, (n, g) => n + g.installedCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const NexusSectionLabel('Inference backends'),
            const Spacer(),
            Text(
                '$totalInstalled installed · '
                '${groups.length} engine${groups.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 11, color: t.muted)),
          ],
        ),
        const SizedBox(height: 10),
        for (final g in groups) ...[
          _recipeGroup(context, g),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _recipeGroup(BuildContext context, _BackendGroup g) {
    final t = context.nexus;
    final expanded = _expandedRecipes.contains(g.recipe) ||
        // Keep the group open while one of its backends is installing.
        (_backendBusy?.startsWith('${g.recipe}/') ?? false);
    final updates = g.updateCount;

    return NexusCard(
      padding: EdgeInsets.zero,
      radius: 15,
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => setState(() {
            expanded
                ? _expandedRecipes.remove(g.recipe)
                : _expandedRecipes.add(g.recipe);
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              if (g.installedCount > 0) ...[
                NexusStatusDot(color: t.good, size: 6, pulse: false),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(g.recipe,
                        style: nexusMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text)),
                    const SizedBox(height: 2),
                    Text(
                        g.installedCount > 0
                            ? '${g.installedCount} of ${g.entries.length} installed'
                            : '${g.entries.length} available',
                        style: TextStyle(fontSize: 11, color: t.muted)),
                  ],
                ),
              ),
              if (updates > 0)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: t.accentSoft,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                      updates == 1 ? 'update' : '$updates updates',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: t.warn)),
                ),
              AnimatedRotation(
                turns: expanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(Icons.expand_more, size: 19, color: t.faint),
              ),
            ]),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 180),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox(width: double.infinity),
          secondChild: Column(children: [
            Divider(color: t.line, height: 1),
            for (final e in g.entries)
              _backendRow(context, g.recipe, e.backend, e.device, e.state),
          ]),
        ),
      ]),
    );
  }

  Future<void> _backendAction(
      String recipe, String backend, bool installed, bool needsUpdate) async {
    final admin = _admin;
    if (admin == null || _backendBusy != null) return;
    setState(() => _backendBusy = '$recipe/$backend');
    try {
      if (installed) {
        await admin.uninstall(recipe: recipe, backend: backend);
      } else {
        await admin.install(
            recipe: recipe, backend: backend, force: needsUpdate);
      }
      await _fetchSystemInfo();
    } catch (e) {
      _toast(friendlyError(e,
          action: installed ? 'remove the backend' : 'install the backend'));
    } finally {
      if (mounted) setState(() => _backendBusy = null);
    }
  }

  Widget _backendRow(BuildContext context, String recipe, String backend,
      String device, String state) {
    final t = context.nexus;
    final installed = state == 'installed';
    final needsUpdate = state == 'update_required';
    final busy = _backendBusy == '$recipe/$backend';
    final (label, color, bg, border) = installed
        ? ('Remove', t.danger, t.surface2, true)
        : needsUpdate
            ? ('Update', t.warn, t.accentSoft, false)
            : ('Install', t.accent2, t.accentSoft, false);
    return Opacity(
      opacity: busy ? 0.6 : 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(backend,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: nexusMono(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: t.text)),
                  ),
                  if (installed) ...[
                    const SizedBox(width: 7),
                    NexusStatusDot(color: t.good, size: 6, pulse: false),
                  ],
                ]),
                if (device.isNotEmpty)
                  Text(device, style: TextStyle(fontSize: 11, color: t.muted)),
              ],
            ),
          ),
          GestureDetector(
            // One backend operation at a time; the busy row shows a spinner.
            onTap: _backendBusy != null
                ? null
                : () => _backendAction(recipe, backend, installed, needsUpdate),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                  border: border ? Border.all(color: t.line2) : null),
              child: busy
                  ? SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: color))
                  : Text(label,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color)),
            ),
          ),
        ]),
      ),
    );
  }

  // capability badge (color, label)
  (Color, String) _badge(ModelInfo m) {
    final t = context.nexus;
    if (m.isCollection) return (t.accent2, 'OMNI');
    if (m.supportsImageGeneration) return (t.warn, 'IMAGE');
    if (m.supportsTts) return (t.good, 'TTS');
    if (m.supportsAudio) return (t.good, 'ASR');
    if (m.supportsVision) return (t.accent2, 'VISION');
    return (t.muted, 'LLM');
  }

  String _capabilityLine(ModelInfo m) {
    final caps = <String>[];
    if (m.isCollection) caps.add('collection');
    if (m.supportsVision) caps.add('vision');
    if (m.supportsImageGeneration) caps.add('image-gen');
    if (m.supportsTts) caps.add('tts');
    if (m.supportsAudio) caps.add('audio');
    if (m.supportsThinking) caps.add('thinking');
    if (caps.isEmpty) caps.add('text');
    return caps.join(' · ');
  }

  Widget _miniBtn(BuildContext context, String label, VoidCallback onTap) {
    final t = context.nexus;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.line2)),
        child: Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: t.text)),
      ),
    );
  }

  Widget _info(BuildContext context, String msg) {
    final t = context.nexus;
    return NexusCard(
      radius: 14,
      padding: const EdgeInsets.all(20),
      child: Center(
          child: Text(msg,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: t.muted))),
    );
  }
}

/// One recipe's runnable backends, pre-sorted for display.
class _BackendGroup {
  final String recipe;
  final List<_BackendEntry> entries;
  _BackendGroup(this.recipe, this.entries);

  int get installedCount =>
      entries.where((e) => e.state == 'installed').length;
  int get updateCount =>
      entries.where((e) => e.state == 'update_required').length;
}

class _BackendEntry {
  final String backend;
  final String device;
  final String state;
  _BackendEntry(this.backend, this.device, this.state);
}
