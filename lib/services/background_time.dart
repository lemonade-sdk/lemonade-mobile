import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Extra running time after the app leaves the foreground (iOS
/// beginBackgroundTask, about 30 s), so the mesh keeps running through a
/// quick switch to another app instead of being suspended at once. A no-op
/// on other platforms, where a backgrounded app keeps running.
class BackgroundTime {
  static const MethodChannel _channel = MethodChannel(
    'ai.nexus-projects.lemonade/background',
  );

  static Future<void> begin() => _call('begin');

  static Future<void> end() => _call('end');

  static Future<void> _call(String method) async {
    if (kIsWeb || !Platform.isIOS) return;
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Not wired up (tests, other embedders): nothing to extend.
    } catch (e) {
      debugPrint('Background time $method failed: $e');
    }
  }
}
