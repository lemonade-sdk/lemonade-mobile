import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/constants/messages.dart';
import 'package:lemonade_mobile/models/model_defaults.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/providers/model_defaults_provider.dart';
import 'package:lemonade_mobile/screens/model_defaults_screen.dart';
import 'package:lemonade_mobile/screens/settings_screen.dart';
import 'package:lemonade_mobile/screens/transcription_screen.dart';
import 'package:lemonade_mobile/widgets/model_selector.dart';

class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatHistories = ref.watch(chatHistoryProvider);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            // Top padding for iPhone status bar
            const SizedBox(height: 20),

            // Scrollable content (moved from middle to top)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Model Selection
                    const ModelSelector(compact: false),

                    const Divider(),

                    // Threads Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Threads',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add),
                            tooltip: 'New Thread',
                            onPressed: () {
                              ref.read(chatHistoryProvider.notifier).createNewChat();
                              Navigator.pop(context);
                            },
                          ),
                        ],
                      ),
                    ),

                    // Threads List
                    if (chatHistories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No threads yet'),
                      )
                    else
                      ...chatHistories.map((chat) => ListTile(
                            title: Text(chat.displayTitle),
                            subtitle: Row(
                              children: [
                                Text(
                                  '${chat.messages.length} messages \u2022 ${chat.lastUpdated.toString().split(' ')[0]}',
                                ),
                                if (chat.modelOverrides != null && !chat.modelOverrides!.isEmpty)
                                  const Padding(
                                    padding: EdgeInsets.only(left: 4),
                                    child: Icon(Icons.tune, size: 14, color: Colors.amber),
                                  ),
                              ],
                            ),
                            selected: chat.isActive,
                            onTap: () {
                              ref.read(chatHistoryProvider.notifier).loadChat(chat.id);
                              Navigator.pop(context);
                            },
                            trailing: PopupMenuButton(
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  child: const Text(AppMessages.copySettings),
                                  onTap: () {
                                    final overrides = chat.modelOverrides ?? const ModelDefaults();
                                    ref.read(modelDefaultsClipboardProvider.notifier).state = overrides;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text(AppMessages.settingsCopied)),
                                    );
                                  },
                                ),
                                PopupMenuItem(
                                  child: const Text(AppMessages.pasteSettings),
                                  onTap: () {
                                    final clipboard = ref.read(modelDefaultsClipboardProvider);
                                    if (clipboard == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text(AppMessages.noSettingsToPaste)),
                                      );
                                    } else {
                                      ref.read(chatHistoryProvider.notifier)
                                          .updateChatOverrides(chat.id, clipboard);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text(AppMessages.settingsPasted)),
                                      );
                                    }
                                  },
                                ),
                                PopupMenuItem(
                                  child: const Text('Delete Thread'),
                                  onTap: () => ref.read(chatHistoryProvider.notifier).deleteChat(chat.id),
                                ),
                              ],
                            ),
                          )),

                    const Divider(),

                    // Transcription
                    ListTile(
                      leading: const Icon(Icons.mic),
                      title: const Text(AppMessages.transcription),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const TranscriptionScreen()),
                        );
                      },
                    ),

                    // Model Defaults
                    ListTile(
                      leading: const Icon(Icons.tune),
                      title: const Text(AppMessages.modelDefaults),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ModelDefaultsScreen()),
                        );
                      },
                    ),

                    // Settings
                    ListTile(
                      leading: const Icon(Icons.settings),
                      title: const Text('Settings'),
                      onTap: () {
                        Navigator.pop(context); // Close drawer
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const SettingsScreen()),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Footer with Logo and Title (moved from top to bottom)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                border: Border(
                  top: BorderSide(
                    color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/lemonade_logo.png',
                    height: 24,
                    width: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Lemonade Mobile',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
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


}
