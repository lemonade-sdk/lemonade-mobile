import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/nexus/nexus_knowledge_models.dart';
import '../../providers/knowledge_providers.dart';
import '../../providers/nexus_gateway_provider.dart';
import '../../themes/nexus_tokens.dart';
import '../../utils/friendly_error.dart';
import '../../widgets/nexus/error_retry.dart';
import '../../widgets/nexus/gateway_gate.dart';
import '../../widgets/nexus/nexus_ui.dart';

class DocsTab extends ConsumerStatefulWidget {
  const DocsTab({super.key});

  @override
  ConsumerState<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends ConsumerState<DocsTab> {
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _uploading = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _upload() async {
    final client = ref.read(nexusKnowledgeClientProvider);
    final collections = ref.read(kbCollectionsProvider).valueOrNull ?? const [];
    if (client == null || collections.isEmpty || _uploading) {
      if (collections.isEmpty && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Create a collection first.')));
      }
      return;
    }
    final selectedId = ref.read(selectedCollectionIdProvider);
    final collection = collections.firstWhere((c) => c.id == selectedId,
        orElse: () => collections.first);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'txt', 'md'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
    setState(() => _uploading = true);
    try {
      await client.uploadDocument(
        collectionId: collection.id,
        filename: file.name,
        bytes: bytes,
        title: file.name,
      );
      ref.invalidate(kbDocumentsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, action: 'upload the document'))));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return GatewayGate(
      icon: Icons.description_outlined,
      feature: 'Docs',
      child: RefreshIndicator(
        // Pull-to-refresh re-checks collections + indexing status.
        onRefresh: () async {
          ref.invalidate(kbCollectionsProvider);
          ref.invalidate(kbDocumentsProvider);
        },
        child: Scrollbar(
          controller: _scrollCtrl,
          child: ListView(
            controller: _scrollCtrl,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              // search
              TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    ref.read(kbQueryTextProvider.notifier).state = v,
                style: TextStyle(fontSize: 14, color: t.text),
                decoration: InputDecoration(
                  hintText: 'Search docs — keyword + semantic…',
                  prefixIcon: Icon(Icons.search, size: 18, color: t.faint),
                ),
              ),
              const SizedBox(height: 16),
              _collections(context),
              const SizedBox(height: 16),
              _dropzone(context),
              const SizedBox(height: 16),
              _body(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _collections(BuildContext context) {
    final t = context.nexus;
    final async = ref.watch(kbCollectionsProvider);
    return async.when(
      loading: () => const SizedBox(height: 34),
      // Keep "+ New" reachable even when collections fail to load — otherwise
      // uploads become impossible.
      error: (e, _) => SizedBox(
        height: 34,
        child: Row(children: [
          Expanded(
            child: Text('Couldn’t load collections',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: t.danger)),
          ),
          GestureDetector(
            onTap: () => ref.invalidate(kbCollectionsProvider),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: t.surface,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: t.line2),
              ),
              child: Row(children: [
                Icon(Icons.refresh, size: 13, color: t.accent2),
                const SizedBox(width: 5),
                Text('Retry',
                    style: TextStyle(fontSize: 12.5, color: t.accent2)),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          _newCollectionBtn(context),
        ]),
      ),
      data: (collections) {
        final selectedId = ref.watch(selectedCollectionIdProvider);
        final activeId = selectedId ??
            (collections.isNotEmpty ? collections.first.id : null);
        return SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final c in collections)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref
                        .read(selectedCollectionIdProvider.notifier)
                        .state = c.id,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 7),
                      decoration: BoxDecoration(
                        color: c.id == activeId ? t.accent : t.surface,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                            color: c.id == activeId ? t.accent : t.line2),
                      ),
                      child: Text(c.name,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color:
                                  c.id == activeId ? Colors.white : t.muted)),
                    ),
                  ),
                ),
              _newCollectionBtn(context),
            ],
          ),
        );
      },
    );
  }

  Widget _newCollectionBtn(BuildContext context) {
    final t = context.nexus;
    return GestureDetector(
      onTap: _createCollection,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: t.line2),
        ),
        child: Row(children: [
          Icon(Icons.add, size: 13, color: t.accent2),
          const SizedBox(width: 5),
          Text('New', style: TextStyle(fontSize: 12.5, color: t.accent2)),
        ]),
      ),
    );
  }

  Future<void> _createCollection() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCollectionDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final client = ref.read(nexusKnowledgeClientProvider);
    try {
      final created = await client?.createCollection(name);
      if (!mounted) return;
      ref.invalidate(kbCollectionsProvider);
      if (created != null) {
        ref.read(selectedCollectionIdProvider.notifier).state = created.id;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(friendlyError(e, action: 'create the collection'))));
      }
    }
  }

  Widget _dropzone(BuildContext context) {
    final t = context.nexus;
    return GestureDetector(
      onTap: _upload,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: t.accentSoft.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: t.line2, style: BorderStyle.solid, width: 1.5),
        ),
        child: Column(children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: t.accent, borderRadius: BorderRadius.circular(13)),
            child: _uploading
                ? const Padding(
                    padding: EdgeInsets.all(11),
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.upload, color: Colors.white, size: 20),
          ),
          const SizedBox(height: 9),
          Text(_uploading ? 'Uploading…' : 'Upload a PDF',
              style: TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w700, color: t.text)),
          const SizedBox(height: 4),
          Text(
              'Lemonade chunks, embeds & indexes it, then links it to your AI & PBX agents',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.45, color: t.muted)),
        ]),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final query = ref.watch(kbQueryTextProvider).trim();
    if (query.isNotEmpty) return _searchResults(context);
    return _docList(context);
  }

  Widget _searchResults(BuildContext context) {
    final t = context.nexus;
    final async = ref.watch(kbSearchProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'search your docs',
          onRetry: () => ref.invalidate(kbSearchProvider)),
      data: (hits) {
        if (hits.isEmpty) {
          return _empty(context, 'No matches.');
        }
        return Column(
          children: [
            for (final h in hits) ...[
              NexusCard(
                radius: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(h.title.isEmpty ? 'Result' : h.title,
                            style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                                color: t.text)),
                      ),
                      Text(h.score.toStringAsFixed(2),
                          style: nexusMono(fontSize: 11, color: t.accent2)),
                    ]),
                    const SizedBox(height: 6),
                    Text(h.text,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, height: 1.4, color: t.muted)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _docList(BuildContext context) {
    final async = ref.watch(kbDocumentsProvider);
    return async.when(
      loading: () => const _Loading(),
      error: (e, _) => ErrorRetry(
          error: e,
          action: 'load your documents',
          onRetry: () => ref.invalidate(kbDocumentsProvider)),
      data: (docs) {
        if (docs.isEmpty) {
          return _empty(context, 'No documents yet — upload a PDF.');
        }
        return Column(
          children: [
            for (final d in docs) ...[
              _docCard(context, d),
              const SizedBox(height: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _docCard(BuildContext context, NexusDocument d) {
    final t = context.nexus;
    final (statusColor, statusLabel) = _status(context, d.status);
    return NexusCard(
      radius: 15,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.line2)),
            child: Text('PDF',
                style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: t.danger)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(d.title.isEmpty ? (d.originalFilename ?? 'Document') : d.title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: t.text)),
                const SizedBox(height: 3),
                Text('${d.chunkCount} chunks · ${d.embeddingModel ?? 'pending'}',
                    style: nexusMono(fontSize: 11, color: t.muted)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(statusLabel,
              style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                  color: statusColor)),
        ],
      ),
    );
  }

  (Color, String) _status(BuildContext context, DocStatus s) {
    final t = context.nexus;
    return switch (s) {
      DocStatus.embedded => (t.good, 'INDEXED'),
      DocStatus.keywordOnly => (t.warn, 'KEYWORD'),
      DocStatus.pending => (t.accent2, 'INDEXING'),
      DocStatus.noText => (t.faint, 'NO TEXT'),
      DocStatus.failed => (t.danger, 'FAILED'),
      DocStatus.unknown => (t.faint, '—'),
    };
  }

  Widget _empty(BuildContext context, String msg) {
    final t = context.nexus;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
          child: Text(msg, style: TextStyle(fontSize: 13, color: t.muted))),
    );
  }

}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
      padding: EdgeInsets.all(24),
      child: Center(child: CircularProgressIndicator()));
}

/// "New collection" name prompt. A StatefulWidget so the text controller is
/// owned — and disposed — with the dialog itself.
class _NewCollectionDialog extends StatefulWidget {
  const _NewCollectionDialog();

  @override
  State<_NewCollectionDialog> createState() => _NewCollectionDialogState();
}

class _NewCollectionDialogState extends State<_NewCollectionDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.nexus;
    return AlertDialog(
      title: const Text('New collection'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Collection name'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
            child: Text('Create', style: TextStyle(color: t.accent))),
      ],
    );
  }
}
