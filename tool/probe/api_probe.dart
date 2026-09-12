import 'package:flutter/material.dart';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final b = WidgetsBinding.instance;
  b.renderView.physicalSize = const Size(1320, 2868);
  b.platformDispatcher.implicitView!.devicePixelRatio = 3.0;
  runApp(const MaterialApp(home: Text('x')));
  await Future<void>.delayed(const Duration(seconds: 2));
}
