/// Store-screenshot harness, active only when built with
/// `--dart-define=STORE_SHOT=true` (see the top of main()).
///
/// Runs on the macOS desktop target: for the device named in the `SHOT_DEVICE`
/// environment variable it sizes the Flutter view to that device's exact
/// pixel dimensions, then renders each scene (real app screens with seeded
/// provider data) and saves a PNG per scene to `SHOT_OUT`.
///
/// Drive it with:
///   SHOT_DEVICE=iphone_pro_max SHOT_PT_W=440 SHOT_PT_H=956 \
///   SHOT_OUT=/path/to/assets/store_screenshots/iphone_pro_max \
///   ./build/macos/Build/Products/Debug/Lemonade\ Mobile.app/Contents/MacOS/Lemonade\ Mobile
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ProviderOverride/ProviderBase aren't in the public API surface, but the
// class is reachable via the src export and is stable. Using it directly lets
// us seed any provider with a value without the (private) notifier types.
// ignore: implementation_imports
import 'package:riverpod/src/framework.dart'
    show ProviderOverride, ProviderBase;

import '../api/lemonade_client.dart';
import '../api/nexus/nexus_call_tasks_models.dart';
import '../models/chat_history.dart';
import '../models/chat_message.dart';
import '../models/discovered_server.dart';
import '../models/server_config.dart';
import '../providers/account_provider.dart';
import '../providers/app_mode_provider.dart';
import '../providers/beacon_provider.dart';
import '../providers/call_tasks_providers.dart';
import '../providers/chat_history_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/device_stats_provider.dart';
import '../providers/image_resolution_provider.dart';
import '../providers/lemonade_client_provider.dart';
import '../providers/models_provider.dart';
import '../providers/nav_provider.dart';
import '../providers/omni_router_provider.dart';
import '../providers/servers_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/nexus/chat_tab.dart';
import '../screens/nexus/settings_tab.dart';
import '../shell/nexus_bottom_nav.dart';
import '../shell/nexus_header.dart';
import '../shell/overlays/auth_gate.dart';
import '../themes/nexus_tokens.dart';
import '../themes/theme_registry.dart';

class _ShotDevice {
  final int pxW, pxH;
  final double dpr;
  final TargetPlatform platform;
  // Status-bar / home-indicator insets in logical points, matching the device
  // so header & bottom-nav lay out like a real device (a zero-inset capture
  // makes content sit flush against the raw screen edges).
  final double topInset, bottomInset;
  const _ShotDevice(
    this.pxW,
    this.pxH,
    this.dpr,
    this.platform,
    this.topInset,
    this.bottomInset,
  );

  EdgeInsets get insets =>
      EdgeInsets.fromLTRB(0, topInset, 0, bottomInset);
}

const _devices = <String, _ShotDevice>{
  // iPhone 16/17 Pro Max — 440×956pt @3x (portrait). Notch ~54pt, home bar ~34pt.
  'iphone_pro_max': _ShotDevice(1320, 2868, 3.0, TargetPlatform.iOS, 54, 34),
  // iPad Pro 13" (M-series) — LANDSCAPE for the store: 1376×1032pt @2x
  // (2752×2064 px). Store listings are wide, not tall.
  'ipad_pro_13': _ShotDevice(2752, 2064, 2.0, TargetPlatform.iOS, 0, 0),
  // Pixel-class phone — ~412×915dp @2.625 (portrait). Status bar ~24dp, gesture bar ~20dp.
  'android_phone': _ShotDevice(1080, 2340, 2.625, TargetPlatform.android, 24, 20),
  // Galaxy Tab 12" class — LANDSCAPE for the store: 1280×800dp @2x
  // (2560×1600 px). Store listings are wide, not tall.
  'android_tablet': _ShotDevice(2560, 1600, 2.0, TargetPlatform.android, 0, 24),
};

final _boundaryKey = GlobalKey();

Future<void> runStoreShotMode() async {
  final deviceName = Platform.environment['SHOT_DEVICE'] ?? 'iphone_pro_max';
  final device = _devices[deviceName];
  if (device == null) {
    stderr.writeln('unknown SHOT_DEVICE: $deviceName '
        '(known: ${_devices.keys.join(', ')})');
    exit(2);
  }
  final outDir = Platform.environment['SHOT_OUT'] ??
      'assets/store_screenshots/$deviceName';
  Directory(outDir).createSync(recursive: true);

  final scenes = <String, WidgetBuilder>{
    '01_local_first': (context) => const AuthGate(),
    '02_chat': (context) => _ShellFrame(NexusTab.chat, const ChatTab()),
    '03_models': (context) => _ShellFrame(NexusTab.settings, const SettingsTab()),
  };

  // One scene per process (SHOT_SCENE) — re-rooting the app twice in one
  // desktop process doesn't reliably swap the tree, so the driver launches
  // the app once per scene. When SHOT_SCENE is unset, render every scene.
  final sceneName = Platform.environment['SHOT_SCENE'];
  List<String> toShoot;
  if (sceneName == null) {
    toShoot = scenes.keys.toList();
  } else if (scenes.containsKey(sceneName)) {
    toShoot = [sceneName];
  } else {
    stderr.writeln('unknown SHOT_SCENE: $sceneName '
        '(known: ${scenes.keys.join(', ')})');
    exit(2);
  }

  for (final name in toShoot) {
    await _shoot(name, scenes[name]!, device, outDir);
  }
  exit(0);
}

Future<void> _shoot(
    String scene, WidgetBuilder builder, _ShotDevice device, String outDir) async {
  // Capture real widget layout overflows (RenderFlex, etc.) to the console
  // so they're not lost when the scene renders offscreen. The UnconstrainedBox
  // that pins the scene to the device size logs a harmless "overflowed" note
  // vs. the small native window — ignore that, report everything else.
  final origOnError = FlutterError.onError;
  FlutterError.onError = (FlutterErrorDetails details) {
    final msg = details.exception.toString();
    final isReal = msg.contains('overflow') &&
        !msg.contains('RenderConstraintsTransformBox');
    if (isReal || msg.contains('RenderFlex')) {
      stderr.writeln('[LAYOUT OVERFLOW in $scene]');
      FlutterError.dumpErrorToConsole(details, forceReport: true);
    }
    origOnError?.call(details);
  };

  await _pumpApp(builder, device);
  // Fixed wait (not pumpAndSettle — status dots pulse forever).
  await Future<void>.delayed(const Duration(milliseconds: 2600));
  await Future<void>.delayed(const Duration(milliseconds: 400));

  // Debug: confirm the seed overrides are live.
  try {
    final c = ProviderContainer(overrides: _overrides);
    debugPrint('[seed] models=${c.read(modelsProvider).length} '
        'mode=${c.read(appModeProvider)} '
        'selected=${c.read(selectedModelProvider)} '
        'msgs=${c.read(chatProvider).length}');
  } catch (e) {
    debugPrint('[seed] DEBUG READ FAILED: $e');
  }

  final ctx = _boundaryKey.currentContext;
  if (ctx == null) {
    stderr.writeln('[$scene] boundary not found');
    return;
  }
  final boundary = ctx.findRenderObject()! as RenderRepaintBoundary;
  // The boundary is pinned to the device's exact logical size (see
  // _pumpApp); rasterize it at the device's real pixel ratio for
  // store-exact pixel dimensions, independent of the native window size.
  final image = await boundary.toImage(pixelRatio: device.dpr);
  final bytes =
      (await image.toByteData(format: ui.ImageByteFormat.png))!
          .buffer
          .asUint8List();
  final out = File('$outDir/$scene.png');
  out.writeAsBytesSync(bytes);
  print('[$scene] ${image.width}x${image.height} -> ${out.path} '
      '(${bytes.length} bytes)');
}

Future<void> _pumpApp(WidgetBuilder home, _ShotDevice device) async {
  final logicalW = device.pxW / device.dpr;
  final logicalH = device.pxH / device.dpr;
  runApp(
    ProviderScope(
      overrides: _overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // Platform-adaptive widgets (sliders, switches) follow ThemeData.platform.
        theme: ThemeRegistry.byId(ThemeRegistry.nexusDarkId)
            .buildTheme()
            .copyWith(platform: device.platform),
        home: UnconstrainedBox(
          // The native window can't be reliably resized per device on this
          // sandboxed macOS build, so escape its size with an UnconstrainedBox
          // and pin the scene to the exact device logical size. (The box may
          // log a harmless "overflowed" note vs. the small window; the
          // captured boundary is still the full device frame.)
          child: RepaintBoundary(
            key: _boundaryKey,
            child: ConstrainedBox(
              constraints: BoxConstraints.tightFor(
                  width: logicalW, height: logicalH),
              child: Builder(
                builder: (context) {
                  final mq = MediaQuery.of(context);
                  return MediaQuery(
                    data: mq.copyWith(
                      padding: device.insets,
                      viewPadding: device.insets,
                      systemGestureInsets: EdgeInsets.only(
                          bottom: device.bottomInset),
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: home(context),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Full app chrome (header + tab + bottom nav) around a single tab, mirroring
/// the real shell without building the five sibling tabs.
class _ShellFrame extends StatelessWidget {
  final NexusTab tab;
  final Widget child;
  const _ShellFrame(this.tab, this.child);

  @override
  Widget build(BuildContext context) {
    return Builder(builder: (context) {
      final t = context.nexus;
      return Scaffold(
        backgroundColor: t.bg,
        body: Column(
          children: [
            const NexusHeader(),
            Expanded(child: child),
            const NexusBottomNav(),
          ],
        ),
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Seeded providers — the "curated" state every scene renders against.
// ---------------------------------------------------------------------------

/// A [StateNotifier] that just holds a fixed value.
class _ValueNotifier<T> extends StateNotifier<T> {
  _ValueNotifier(super.state);
}

/// Cross-kind ProviderOverride (e.g. Provider -> StateNotifierProvider) fails
// at runtime, so each seed keeps the SAME provider kind as its origin. These
// helpers build that matching-kind override with a value-holder create fn.

ProviderOverride _seedState<T>(ProviderBase<Object?> origin, T value) {
  return ProviderOverride(
    origin: origin,
    override: StateNotifierProvider<_ValueNotifier<T>, T>(
        (ref) => _ValueNotifier(value)),
  );
}

ProviderOverride _seedStateProvider<T>(ProviderBase<Object?> origin, T value) {
  return ProviderOverride(
    origin: origin,
    override: StateProvider<T>((ref) => value),
  );
}

ProviderOverride _seedProvider<T>(ProviderBase<Object?> origin, T value) {
  return ProviderOverride(
    origin: origin,
    override: Provider<T>((ref) => value),
  );
}

ProviderOverride _seedFuture<T>(ProviderBase<Object?> origin, T value) {
  return ProviderOverride(
    origin: origin,
    override: FutureProvider<T>((ref) => Future.value(value)),
  );
}

ProviderOverride _seedStream<T>(ProviderBase<Object?> origin, T value) {
  return ProviderOverride(
    origin: origin,
    override: StreamProvider<T>((ref) => Stream.value(value)),
  );
}

final List<Override> _overrides = [
  _seedState(themeProvider, ThemeRegistry.byId(ThemeRegistry.nexusDarkId)),
  _seedState(appModeProvider, AppMode.local),
  _seedState(authProvider, const AuthState()),
  _seedState(overlayProvider, const NexusOverlayState()),
  _seedState(serversProvider, const <ServerConfig>[]),
  _seedState(selectedServerProvider,
      ServerConfig(baseUrl: 'http://192.168.1.42:13305', name: 'Studio Mac')),
  _seedState(discoveredServersProvider, const <DiscoveredServer>[]),
  _seedProvider<LemonadeApiClient?>(lemonadeClientProvider, null),
  _seedFuture<Map<String, dynamic>?>(systemInfoProvider, <String, dynamic>{
    'Physical Memory': '24 GB',
    'Processor': 'Apple M4 Max',
    'devices': {'Metal': {'Name': 'Apple M4 Max'}},
  }),
  _seedStream<Map<String, dynamic>?>(systemStatsProvider, <String, dynamic>{
    'cpu_percent': 18.0,
    'gpu_percent': 64.0,
    'memory_gb': 9.6,
    'vram_gb': 2.1,
  }),
  _seedState(modelsProvider, [
    ModelInfo('Gemma-4-26B-A4B-it-GGUF-UD-Q6_K_XL', ['chat', 'vision'],
        maxContextWindow: 262144),
    ModelInfo('Qwen3-Coder-30B-A3B-Instruct-GGUF',
        ['chat', 'tool-calling'], maxContextWindow: 262144),
    ModelInfo('LFM2.5-8B-A1B-GGUF-Q8_0', ['chat'], maxContextWindow: 128000),
    ModelInfo('LMX-Omni-52B-Halo', ['chat', 'vision', 'tts'],
        isCollection: true,
        compositeModels: ['LMX-Omni-52B-chat', 'LMX-Omni-52B-tts']),
  ]),
  _seedState(selectedModelProvider, 'Gemma-4-26B-A4B-it-GGUF-UD-Q6_K_XL'),
  _seedState(omniRouterEnabledProvider, true),
  _seedState(imageResolutionProvider, ImageResolutionPreset.res1k),
  _seedState(chatProvider, [
    ChatMessage.text(
        role: MessageRole.user,
        text: 'What’s running on this server right now?'),
    ChatMessage.text(
        role: MessageRole.assistant,
        text: 'Gemma-4-26B is loaded and serving on :13305. The GPU is at 64% '
            'with about 2 GB of VRAM headroom, so there’s room for one more '
            'mid-size model. Want me to unload the older Qwen3 coder model to '
            'free space?'),
  ]),
  _seedStateProvider(chatStreamingProvider, false),
  _seedProvider<ChatHistory?>(activeChatProvider, null),
  _seedFuture<NexusCallTask?>(activeCallTaskProvider, null),
];
