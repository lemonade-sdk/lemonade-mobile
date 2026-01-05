import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/chat_provider.dart';
import 'package:lemonade_mobile/widgets/chat_input.dart';
import 'package:lemonade_mobile/widgets/message_bubble.dart';
import 'package:lemonade_mobile/widgets/server_selector.dart';
import 'package:lemonade_mobile/widgets/chat_drawer.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messages = ref.watch(chatProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Lemonade Chat'),
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => ref.read(chatProvider.notifier).clearChat(),
          ),
        ],
      ),
      drawer: const ChatDrawer(),
      body: Column(
        children: [
          const ServerSelector(),
          Expanded(
            child: messages.isEmpty
                ? const Center(
                    child: Text(
                      'Start a conversation by typing a message below.',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : NotificationListener<ScrollStartNotification>(
                    onNotification: (notification) {
                      // Dismiss keyboard when user starts scrolling
                      FocusManager.instance.primaryFocus?.unfocus();
                      return false; // Allow the notification to continue
                    },
                    child: ListView.builder(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return MessageBubble(message: message);
                      },
                    ),
                  ),
          ),
          const ChatInput(),
        ],
      ),
    );
  }
}
