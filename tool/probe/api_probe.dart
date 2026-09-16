import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final renderView = RendererBinding.instance.renderViews.first;
  renderView.configuration = ViewConfiguration(
    physicalConstraints: BoxConstraints.tight(Size(1320, 2868)),
    logicalConstraints: BoxConstraints.tight(Size(440, 956)),
    devicePixelRatio: 3,
  );
  runApp(const MaterialApp(home: Text('x')));
  await Future<void>.delayed(const Duration(seconds: 2));
}
