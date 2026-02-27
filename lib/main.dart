import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/beacon_provider.dart';
import 'package:lemonade_mobile/screens/chat_screen.dart';
import 'package:lemonade_mobile/screens/settings_screen.dart';
import 'package:lemonade_mobile/utils/constants.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context) {
    // Initialize beacon listener by reading the provider
    ref.watch(discoveredServersProvider);

    // Listen for new server discoveries and show notification
    ref.listen(pendingBeaconNotificationProvider, (prev, next) {
      if (next != null) {
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text(
              'Server "${next.hostname}" found on network',
              style: const TextStyle(color: AppColors.white),
            ),
            action: SnackBarAction(
              label: 'View',
              textColor: AppColors.white,
              onPressed: () {
                _navigatorKey.currentState?.pushNamed('/settings');
              },
            ),
            backgroundColor: AppColors.beaconNotification,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
        Future.microtask(() {
          ref.read(pendingBeaconNotificationProvider.notifier).state = null;
        });
      }
    });

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
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