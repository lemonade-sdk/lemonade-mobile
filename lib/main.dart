import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lemonade_mobile/providers/account_provider.dart';
import 'package:lemonade_mobile/providers/beacon_provider.dart';
import 'package:lemonade_mobile/providers/billing_providers.dart';
import 'package:lemonade_mobile/providers/nav_provider.dart';
import 'package:lemonade_mobile/providers/theme_provider.dart';
import 'package:lemonade_mobile/screens/transcription_screen.dart';
import 'package:lemonade_mobile/screens/model_defaults_screen.dart';
import 'package:lemonade_mobile/shell/nexus_shell.dart';
import 'package:lemonade_mobile/storage/database.dart';
import 'package:lemonade_mobile/storage/legacy_migration.dart';
import 'package:lemonade_mobile/utils/constants.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDatabase.open();
  try {
    await LegacyMigration.runIfNeeded();
  } catch (e, st) {
    debugPrint('Legacy migration skipped: $e\n$st');
  }
  // Pre-read the saved theme id so the very first frame uses it — otherwise
  // we'd boot on the default (dark) theme and swap to the saved one on the
  // next frame, which makes Flutter's button text-style animations explode
  // when the two themes' TextStyles have different `inherit` values.
  final prefs = await AppDatabase.instance.readOrCreatePrefs();
  final initialThemeId = prefs.themeId;
  runApp(ProviderScope(
    overrides: [
      initialThemeIdProviderRef.overrideWithValue(initialThemeId),
    ],
    child: const MyApp(),
  ));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Capabilities / balance can change off-device (Stripe webhooks, top-ups);
    // refresh the billing source-of-truth when the app returns to foreground.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(entitlementsProvider);
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(accountSummaryProvider);
      ref.invalidate(subscriptionDetailProvider);
    }
  }

  // Currently-visible beacon snackbar, if any. ScaffoldMessenger queues
  // snackbars by default, so without tracking and dismissing the previous
  // one a burst of discoveries would stack a pile that takes minutes to
  // drain — making the "Server found" toast feel permanent.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _beaconSnackBar;
  Timer? _beaconSnackBarDismissTimer;

  static const _beaconSnackBarVisibleDuration = Duration(seconds: 4);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _beaconSnackBarDismissTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Initialize beacon listener by reading the provider
    ref.watch(discoveredServersProvider);

    // Listen for new server discoveries and show notification
    ref.listen(pendingBeaconNotificationProvider, (prev, next) {
      if (next == null) return;
      final messenger = _scaffoldMessengerKey.currentState;
      if (messenger == null) return;

      // If a beacon toast is already on screen, drop this one. Stacking a
      // second SnackBar on top of one mid-dismiss-animation has been the
      // smoking gun behind the "second toast stays forever" bug — the
      // framework re-anchors its visual on the new SnackBar without
      // restarting the dismissal timer. Better to show one toast cleanly
      // and let the user open the discovered list to see the rest.
      if (_beaconSnackBar != null) {
        Future.microtask(() {
          ref.read(pendingBeaconNotificationProvider.notifier).state = null;
        });
        return;
      }

      _beaconSnackBarDismissTimer?.cancel();
      messenger.clearSnackBars();

      _beaconSnackBar = messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Server "${next.hostname}" found on network',
            style: const TextStyle(color: AppColors.white),
          ),
          action: SnackBarAction(
            label: 'View',
            textColor: AppColors.white,
            onPressed: () {
              // Jump to the Settings tab (server management lives there now).
              ref.read(navTabProvider.notifier).state = NexusTab.settings;
            },
          ),
          backgroundColor: AppColors.beaconNotification,
          behavior: SnackBarBehavior.floating,
          duration: _beaconSnackBarVisibleDuration,
        ),
      );
      _beaconSnackBar?.closed.then((_) => _beaconSnackBar = null);

      // Belt-and-suspenders manual dismissal. Some platforms (notably macOS
      // desktop builds we've seen) leave a SnackBar visible past its
      // configured `duration` if the embedder pauses the frame scheduler
      // mid-animation; this timer guarantees the bar leaves at our cadence.
      _beaconSnackBarDismissTimer = Timer(_beaconSnackBarVisibleDuration, () {
        _beaconSnackBar?.close();
      });

      Future.microtask(() {
        ref.read(pendingBeaconNotificationProvider.notifier).state = null;
      });
    });

    final activeTheme = ref.watch(themeProvider);

    return MaterialApp(
      navigatorKey: _navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Lemonade Mobile',
      theme: activeTheme.buildTheme(),
      home: const NexusShell(),
      routes: {
        // Secondary screens still reachable via Navigator.push from the
        // redesigned Settings tab.
        '/transcription': (context) => const TranscriptionScreen(),
        '/model-defaults': (context) => const ModelDefaultsScreen(),
      },
    );
  }
}