import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemonade_mobile/themes/theme_registry.dart';
import 'package:lemonade_mobile/widgets/nexus/nexus_composer.dart';

void main() {
  testWidgets('a hide-keyboard button shows while typing and closes it', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: ThemeRegistry.byId(ThemeRegistry.nexusDarkId).buildTheme(),
        home: const Scaffold(body: Align(
          alignment: Alignment.bottomCenter,
          child: NexusComposer(),
        )),
      ),
    ));
    final hide = find.byIcon(Icons.keyboard_hide_outlined);
    expect(hide, findsNothing);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(hide, findsOneWidget);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(hide);
    await tester.pump();
    expect(hide, findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
