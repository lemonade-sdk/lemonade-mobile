import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/chat_history_provider.dart';
import 'package:lemonade_mobile/providers/models_provider.dart';
import 'package:lemonade_mobile/screens/settings_screen.dart';

class ChatDrawer extends ConsumerWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatHistories = ref.watch(chatHistoryProvider);
    final selectedModel = ref.watch(selectedModelProvider);
    final availableModels = ref.watch(modelsProvider);

    return Drawer(
      child: Column(
        children: [
          // Header with Logo
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Image.asset(
                  'assets/lemonade_logo.png',
                  height: 32,
                  width: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  'Lemonade Chat',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  // Model Selection
                  ExpansionTile(
                    title: const Text('Model'),
                    subtitle: Text(selectedModel ?? 'Select a model'),
                    onExpansionChanged: (expanded) {
                      if (expanded && availableModels.isEmpty) {
                        // Fetch models when expanding if we don't have them yet
                        ref.read(modelsProvider.notifier).fetchModels();
                      }
                    },
                    children: [
                      if (availableModels.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Loading models...'),
                        )
                      else
                        ...availableModels.map((model) => ListTile(
                              title: Text(model),
                              selected: model == selectedModel,
                              onTap: () {
                                ref.read(selectedModelProvider.notifier).selectModel(model);
                                Navigator.pop(context); // Close drawer
                              },
                            )),
                    ],
                  ),

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
                          subtitle: Text(
                            '${chat.messages.length} messages • ${chat.lastUpdated.toString().split(' ')[0]}',
                          ),
                          selected: chat.isActive,
                          onTap: () {
                            ref.read(chatHistoryProvider.notifier).loadChat(chat.id);
                            Navigator.pop(context);
                          },
                          trailing: PopupMenuButton(
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                child: const Text('Delete Thread'),
                                onTap: () => ref.read(chatHistoryProvider.notifier).deleteChat(chat.id),
                              ),
                            ],
                          ),
                        )),

                  const Divider(),

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
        ],
      ),
    );
  }
}
