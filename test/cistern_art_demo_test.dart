import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/world/demo/cistern_art_main.dart';

void main() {
  testWidgets('Valve needs proximity, opens with E, and reset closes it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: CisternArtDemo()));
    await tester.pump();
    TextButton button(String label) =>
        tester.widget<TextButton>(find.widgetWithText(TextButton, label));
    expect(button('Turn valve (E)').onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.textContaining('Sluice: closed'), findsOneWidget);

    await tester.tap(find.text('Jump to area'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('Northwest valve'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(button('Turn valve (E)').onPressed, isNotNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.textContaining('Sluice: open'), findsOneWidget);
    expect(button('Valve activated').onPressed, isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();
    expect(find.textContaining('Sluice: open'), findsOneWidget);

    await tester.tap(find.text('Reset run'));
    await tester.pump();
    expect(find.textContaining('Sluice: closed'), findsOneWidget);
    expect(find.textContaining('Feet: 108, 1220'), findsOneWidget);
    expect(button('Turn valve (E)').onPressed, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
