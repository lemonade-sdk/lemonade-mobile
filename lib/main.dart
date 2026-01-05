import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/screens/chat_screen.dart';
import 'package:lemonade_mobile/screens/settings_screen.dart';
import 'package:lemonade_mobile/utils/constants.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lemonade Chat',
      theme: AppTheme.darkTheme,
      initialRoute: '/',
      routes: {
        '/': (context) => const ChatScreen(),
        '/settings': (context) => const SettingsScreen(),
      },
    );
  }
}
