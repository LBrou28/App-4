import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/world/demo/demo_host.dart';
import 'package:app_4/world/demo/main.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class InvalidPositionHost extends DemoWorldHost {
  InvalidPositionHost(super.map);
  @override
  GameState get state => createContractFixture(
    position: WorldPosition(mapId: map.id, x: 6.9, y: 4.5),
  );
}

void main() {
  final map = createPrototypeMap();
  late DemoWorldHost host;
  setUp(() {
    host = DemoWorldHost(map);
  });
  tearDown(() => host.dispose());

  Future<void> mount(WidgetTester tester, {DemoWorldHost? override}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WorldView(
            map: map,
            host: override ?? host,
            changes: override ?? host,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> step(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 80));
  }

  testWidgets(
    'keyboard moves; key-up stops; ordinary rebuild keeps held input',
    (tester) async {
      await mount(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await step(tester);
      expect(host.state.position.x, greaterThan(2.5));
      final first = host.state.position.x;
      await mount(tester);
      await step(tester);
      expect(host.state.position.x, greaterThan(first));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      final stopped = host.state.position;
      await step(tester);
      expect(host.state.position, same(stopped));
      await tester.pumpWidget(const SizedBox());
      expect(host.hasSubscribers, isFalse);
    },
  );

  testWidgets('touch hold moves and pointer cancellation stops movement', (
    tester,
  ) async {
    await mount(tester);
    final pointer = await tester.startGesture(
      tester.getCenter(find.byKey(const ValueKey('move-right'))),
    );
    await step(tester);
    expect(host.state.position.x, greaterThan(2.5));
    await pointer.cancel();
    final stopped = host.state.position;
    await step(tester);
    expect(host.state.position, same(stopped));
  });

  testWidgets('pause/dialogue/battle/loading gate keyboard and held pointers', (
    tester,
  ) async {
    await mount(tester);
    for (final gate in DemoGate.values.where(
      (value) => value != DemoGate.exploration,
    )) {
      final pointer = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('move-right'))),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      host.setGate(gate);
      await tester.pump();
      final stopped = host.state.position;
      await step(tester);
      expect(host.state.position, same(stopped));
      host.setGate(DemoGate.exploration);
      await step(tester);
      expect(host.state.position, same(stopped));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await pointer.up();
    }
  });

  testWidgets('focus loss and application inactivity discard held keys', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await step(tester);
    FocusManager.instance.primaryFocus!.unfocus();
    await tester.pump();
    final stopped = host.state.position;
    await step(tester);
    expect(host.state.position, same(stopped));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.tap(find.byKey(const ValueKey('world-canvas')));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await step(tester);
    expect(host.state.position, same(stopped));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });

  testWidgets('replacement host detaches old notifier and clears input', (
    tester,
  ) async {
    await mount(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await step(tester);
    final replacement = DemoWorldHost(map);
    await mount(tester, override: replacement);
    expect(host.hasSubscribers, isFalse);
    await step(tester);
    expect(replacement.state.position.x, 2.5);
    host.setGate(DemoGate.pause);
    expect(find.text('Movement paused'), findsNothing);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.pumpWidget(const SizedBox());
    expect(replacement.hasSubscribers, isFalse);
    replacement.dispose();
  });

  testWidgets(
    'invalid restored footprint blocks movement and shows a useful error',
    (tester) async {
      final invalid = InvalidPositionHost(map);
      await mount(tester, override: invalid);
      expect(find.textContaining('does not fit this map'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await step(tester);
      expect(invalid.revision, 0);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      await tester.pumpWidget(const SizedBox());
      invalid.dispose();
    },
  );

  testWidgets(
    'demo fits target viewport and narrow window; optional review image',
    (tester) async {
      if (const bool.fromEnvironment('B1_CAPTURE')) {
        await tester.runAsync(() async {
          const fonts = {
            'Roboto': String.fromEnvironment('B1_TEXT_FONT'),
            'MaterialIcons': String.fromEnvironment('B1_ICON_FONT'),
          };
          for (final entry in fonts.entries) {
            final font = File(entry.value);
            if (entry.value.isEmpty || !font.existsSync()) {
              throw StateError(
                'B1_CAPTURE requires B1_TEXT_FONT and B1_ICON_FONT paths',
              );
            }
            final loader = FontLoader(entry.key)
              ..addFont(
                Future.value((await font.readAsBytes()).buffer.asByteData()),
              );
            await loader.load();
          }
        });
      }
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(key: boundaryKey, child: const B1Demo()),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final canvas = tester.getRect(find.byKey(const ValueKey('world-canvas')));
      final button = tester.getRect(find.byKey(const ValueKey('move-right')));
      expect(canvas.overlaps(button), isFalse);
      expect(button.bottom, lessThanOrEqualTo(720));
      if (const bool.fromEnvironment('B1_CAPTURE')) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('lib/world/evidence/b1-demo.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.view.physicalSize = const Size(480, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
