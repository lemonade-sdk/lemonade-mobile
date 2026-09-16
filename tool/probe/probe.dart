// Probe for the store-screenshot harness: verifies that flutter_tester
// (run directly, WITHOUT --use-test-fonts) renders real system fonts, can
// set its view size, loads asset images, and can save a PNG.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('PROBE start');

  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark(),
    home: Scaffold(
      body: Column(children: [
        const Center(
          child: Text('Hello 你好 · Lemonade 4.0',
              style: TextStyle(fontSize: 56, fontWeight: FontWeight.w700)),
        ),
        Center(child: Image.asset('assets/lemonade_logo.png', width: 120)),
      ]),
    ),
  ));

  // Set the view size after the first frame exists.
  try {
    final renderView = RendererBinding.instance.renderViews.first;
    renderView.configuration = ViewConfiguration(
      physicalConstraints: BoxConstraints.tight(Size(1320, 2868)),
      logicalConstraints: BoxConstraints.tight(Size(440, 956)),
      devicePixelRatio: 3,
    );
    debugPrint('PROBE sized render view to 1320x2868');
  } catch (e) {
    debugPrint('PROBE implicitView sizing failed: $e');
  }

  await Future<void>.delayed(const Duration(milliseconds: 2500));
  debugPrint('PROBE settled');
  exit(0);
}
