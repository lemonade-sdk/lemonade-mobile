import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/messages.dart';
import '../models/chat_history.dart';
import '../models/folder.dart';
import '../models/model_defaults.dart';
// import '../providers/account_provider.dart'; // account UI temporarily disabled
import '../providers/admin_mode_provider.dart';
import '../providers/chat_history_provider.dart';
import '../providers/folders_provider.dart';
import '../providers/model_defaults_provider.dart';
// import '../screens/account_screen.dart'; // account UI temporarily disabled
import '../screens/admin_console_screen.dart';
import '../screens/model_defaults_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/transcription_screen.dart';
import 'chat_overrides_modal.dart';
import 'model_selector.dart';
import 'server_selector.dart';

class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatHistoryProvider);
    final folders = ref.watch(foldersProvider);

    final scheme = Theme.of(context).colorScheme;

    final rootFolders =
        folders.where((f) => f.parentFolderId == null).toList(growable: false);
    final orphanChats = chats
        .where((c) => c.folderId == null || !folders.any((f) => f.id == c.folderId))
        .toList(growable: false);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const ServerSelector(),
                    const ModelSelector(compact: false),
                    const Divider(),

                    // Threads + Folders header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Conversations',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.create_new_folder_outlined),
                            tooltip: 'New folder',
                            onPressed: () => _newFolder(context, ref),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'New chat',
                            onPressed: () {
                              ref.read(chatHistoryProvider.notifier).createNewChat();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Folders + their chats
                    for (final folder in rootFolders)
                      _FolderNode(
                        folder: folder,
                        depth: 0,
                      ),

                    // Orphan chats (no folder)
                    if (orphanChats.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          'Unfiled',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      for (final chat in orphanChats)
                        _ChatTile(chat: chat, indent: 16),
                    ],

                    if (chats.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No conversations yet'),
                      ),

                    const Divider(),

                    // ── Account / subscription (temporarily disabled) ──
                    // Account / Log in / Register entry points are hidden for now.
                    // To re-enable, uncomment the Builder block below.
                    /*
                    Builder(builder: (context) {
                      final auth = ref.watch(authProvider);
                      return Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.account_circle_outlined),
                            title: const Text('Account'),
                            subtitle: Text(
                              auth.isSignedIn
                                  ? (auth.user?.email ?? 'Signed in')
                                  : 'Billing, plans & usage',
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => const AccountScreen()),
                              );
                            },
                          ),
                          if (auth.isSignedIn)
                            ListTile(
                              leading: const Icon(Icons.logout),
                              title: const Text('Log out'),
                              onTap: () => _confirmLogout(context, ref),
                            )
                          else
                            ListTile(
                              leading: const Icon(Icons.login),
                              title: const Text('Log in / Register'),
                              onTap: () {
                                Navigator.pop(context);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const AccountScreen()),
                                );
                              },
                            ),
                        ],
                      );
                    }),

                    const Divider(),
                    */

                    ListTile(
                      leading: const Icon(Icons.mic),
                      title: const Text(AppMessages.transcription),
                      subtitle: const Text('Live audio → text'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const TranscriptionScreen()),
                        );
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text(AppMessages.modelDefaults),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const ModelDefaultsScreen()),
                        );
                      },
                    ),
                    if (ref.watch(adminModeProvider))
                      ListTile(
                        leading: const Icon(Icons.admin_panel_settings),
                        title: const Text('Admin Console'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const AdminConsoleScreen()),
                          );
                        },
                      ),
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const SettingsScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.1),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/lemonade_logo.png', height: 24, width: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Lemonade Mobile',
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Logout flow temporarily disabled along with the account UI above.
  /*
  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
            'Your subscription server will be removed from the server list. '
            'Local servers are unaffected.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Log out')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(authProvider.notifier).logout();
      if (context.mounted) Navigator.pop(context);
    }
  }
  */

  Future<void> _newFolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Folder name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(foldersProvider.notifier).create(name: name);
  }
}

class _FolderNode extends ConsumerWidget {
  final Folder folder;
  final int depth;

  const _FolderNode({required this.folder, required this.depth});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider);
    final chats = ref.watch(chatHistoryProvider);
    final children = folders
        .where((f) => f.parentFolderId == folder.id)
        .toList(growable: false);
    final folderChats = chats
        .where((c) => c.folderId == folder.id)
        .toList(growable: false);
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(left: depth * 12.0),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          childrenPadding: EdgeInsets.zero,
          leading: Icon(Icons.folder_outlined, color: scheme.primary),
          title: Text(folder.name, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (action) async {
              switch (action) {
                case 'rename':
                  await _rename(context, ref);
                case 'new-chat':
                  await ref
                      .read(chatHistoryProvider.notifier)
                      .createNewChat(folderId: folder.id);
                  if (context.mounted) Navigator.pop(context);
                case 'new-subfolder':
                  await _newSubfolder(context, ref);
                case 'delete':
                  await ref.read(foldersProvider.notifier).remove(folder.id);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new-chat', child: Text('New chat here')),
              PopupMenuItem(value: 'new-subfolder', child: Text('New subfolder')),
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete folder')),
            ],
          ),
          initiallyExpanded: true,
          children: [
            for (final c in children) _FolderNode(folder: c, depth: depth + 1),
            for (final chat in folderChats)
              _ChatTile(chat: chat, indent: 32 + depth * 12.0),
            if (children.isEmpty && folderChats.isEmpty)
              Padding(
                padding: EdgeInsets.fromLTRB(32 + depth * 12.0, 4, 16, 8),
                child: Text(
                  'Empty',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: folder.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename folder'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(foldersProvider.notifier).rename(folder.id, name);
  }

  Future<void> _newSubfolder(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('New subfolder in "${folder.name}"'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await ref.read(foldersProvider.notifier).create(
          parentFolderId: folder.id,
          name: name,
        );
  }
}

class _ChatTile extends ConsumerWidget {
  final ChatHistory chat;
  final double indent;

  const _ChatTile({required this.chat, required this.indent});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: EdgeInsets.only(left: indent),
      child: ListTile(
        dense: true,
        title: Text(chat.displayTitle, overflow: TextOverflow.ellipsis),
        subtitle: Row(
          children: [
            Text(
              '${chat.messages.length} messages',
              style: const TextStyle(fontSize: 11),
            ),
            if (chat.modelOverrides != null && !chat.modelOverrides!.isEmpty)
              const Padding(
                padding: EdgeInsets.only(left: 4),
                child: Icon(Icons.tune, size: 12, color: Colors.amber),
              ),
          ],
        ),
        selected: chat.isActive,
        onTap: () {
          ref.read(chatHistoryProvider.notifier).loadChat(chat.id);
          Navigator.pop(context);
        },
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_horiz, size: 18),
          onSelected: (action) async {
            switch (action) {
              case 'edit-overrides':
                await ChatOverridesModal.show(context, chat);
              case 'copy':
                final overrides = chat.modelOverrides ?? const ModelDefaults();
                ref.read(modelDefaultsClipboardProvider.notifier).state = overrides;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text(AppMessages.settingsCopied)),
                );
              case 'paste':
                final clipboard = ref.read(modelDefaultsClipboardProvider);
                if (clipboard == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text(AppMessages.noSettingsToPaste)),
                  );
                } else {
                  await ref
                      .read(chatHistoryProvider.notifier)
                      .updateChatOverrides(chat.id, clipboard);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text(AppMessages.settingsPasted)),
                    );
                  }
                }
              case 'move':
                await _moveToFolder(context, ref);
              case 'delete':
                await ref.read(chatHistoryProvider.notifier).deleteChat(chat.id);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit-overrides', child: Text('Edit model overrides…')),
            PopupMenuItem(value: 'move', child: Text('Move to folder…')),
            PopupMenuItem(value: 'copy', child: Text(AppMessages.copySettings)),
            PopupMenuItem(value: 'paste', child: Text(AppMessages.pasteSettings)),
            PopupMenuItem(value: 'delete', child: Text('Delete chat')),
          ],
        ),
      ),
    );
  }

  Future<void> _moveToFolder(BuildContext context, WidgetRef ref) async {
    final folders = ref.read(foldersProvider);
    final selected = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Move to folder'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, '__none__'),
            child: const Text('— Unfiled (no folder) —'),
          ),
          for (final f in folders)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, f.id),
              child: Text(f.name),
            ),
        ],
      ),
    );
    if (selected == null) return;
    final target = selected == '__none__' ? null : selected;
    await ref.read(chatHistoryProvider.notifier).moveChatToFolder(chat.id, target);
  }
}
