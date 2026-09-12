// Probe for the store-screenshot harness: verifies that flutter_tester
// (run directly, WITHOUT --use-test-fonts) renders real system fonts, can
// set its view size, loads asset images, and can save a PNG.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('PROBE start');

  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Column(children: [
        Center(
          child: Text('Hello 你好 · Lemonade 4.0',
              style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700)),
        ),
        Center(child: Image.asset('assets/lemonade_logo.png', width: 120)),
      ]),
    ),
  ));

  // Set the view size after the first frame exists.
  try {
    final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
    view.physicalSize = const Size(1320, 2868);
    view.devicePixelRatio = 3.0;
    debugPrint('PROBE sized via implicitView: ${view.physicalSize}');
  } catch (e) {
    debugPrint('PROBE implicitView sizing failed: $e');
  }

  await Future<void>.delayed(const Duration(milliseconds: 2500));
  debugPrint('PROBE settled');
  exit(0);
}
