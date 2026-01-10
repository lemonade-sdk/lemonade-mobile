import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/chat_provider.dart';
import 'package:lemonade_mobile/widgets/chat_input.dart';
import 'package:lemonade_mobile/widgets/message_bubble.dart';
import 'package:lemonade_mobile/widgets/server_selector.dart';
import 'package:lemonade_mobile/widgets/chat_drawer.dart';
import 'package:lemonade_mobile/widgets/model_selector.dart';
import 'package:lemonade_mobile/constants/colors.dart';

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll to bottom when screen is first opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
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
          const ModelSelector(compact: true),
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
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Start a conversation by typing a message below.',
                          style: TextStyle(fontSize: 16, color: AppColors.hintText),
                          textAlign: TextAlign.center,
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Use / for commands like /image or /draw',
                          style: TextStyle(fontSize: 14, color: AppColors.hintText),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      // Dismiss keyboard when user starts scrolling
                      FocusManager.instance.primaryFocus?.unfocus();
                      return false; // Allow the notification to continue
                    },
                    child: ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[index];
                        return MessageBubble(message: message);
                      },
                    ),
                  ),
          ),
          ChatInput(scrollController: _scrollController),
        ],
      ),
    );
  }
}
