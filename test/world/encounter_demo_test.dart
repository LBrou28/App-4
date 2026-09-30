import 'package:app_4/world/demo/encounter_main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('walk into encounter, return, and require fresh movement input', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const B3Demo());
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    for (var i = 0; i < 45; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Encounter!').evaluate().isNotEmpty) break;
    }
    expect(find.text('Encounter!'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    final before = tester
        .widget<Text>(find.textContaining(' · encounters '))
        .data;
    await tester.tap(find.text('Return to exploration'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Encounter!'), findsNothing);
    expect(
      tester.widget<Text>(find.textContaining(' · encounters ')).data,
      before,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
