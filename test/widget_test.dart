import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/game_app.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';
import 'package:app_4/world/world_view.dart';

WorldSession session() {
  final map = createPrototypeMap();
  return WorldSession(
    map: map,
    initialState: createContractFixture(position: map.spawns['entry']!),
    isClear: WorldCollision(map).isClear,
  );
}

void main() {
  testWidgets(
    'real world survives pause/rebuild; held movement does not replay',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        GameApp(loadWorld: () async => session(), buildWorld: worldViewBuilder),
      );
      expect(find.text('LANTERN WAKE'), findsOneWidget);
      expect(find.text('A tale from the Saltglass Coast'), findsOneWidget);
      await tester.tap(find.text('New Game'));
      await tester.pump();
      await tester.pump();
      final view = tester.widget<WorldView>(find.byType(WorldView));
      final mounted = tester.state(find.byType(WorldView));
      final host = view.host;
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(host.state.position.x, greaterThan(2.5));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyP);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyP);
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      expect(
        find.textContaining('an ancient bell has begun to stir'),
        findsOneWidget,
      );
      final stopped = host.state.position.x;
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.state.position.x, stopped);
      await tester.tap(find.text('Continue exploring'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(host.state.position.x, stopped);
      expect(tester.state(find.byType(WorldView)), same(mounted));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
      expect(host.state.position.x, greaterThan(stopped));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);

      await tester.tap(find.text('Pause'));
      await tester.pump();
      await tester.tap(find.text('End session'));
      await tester.pump();
      expect(find.text('New Game'), findsOneWidget);
      final oldRevision = host.revision;
      await tester.tap(find.text('New Game'));
      await tester.pump();
      await tester.pump();
      expect(tester.widget<WorldView>(find.byType(WorldView)).host, same(host));
      expect(host.revision, greaterThan(oldRevision));
      expect(host.state.position.x, 2.5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      expect(host.movementEnabled, isFalse);
    },
  );

  testWidgets(
    'shell fits narrow viewport and pauses when application loses focus',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('A2_CAPTURE')) {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': const String.fromEnvironment('A2_TEXT_FONT'),
            'MaterialIcons': const String.fromEnvironment('A2_ICON_FONT'),
          }.entries) {
            final loader = FontLoader(entry.key)
              ..addFont(
                Future.value(
                  (await File(entry.value).readAsBytes()).buffer.asByteData(),
                ),
              );
            await loader.load();
          }
        });
      }
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundaryKey,
          child: GameApp(
            loadWorld: () async => session(),
            buildWorld: worldViewBuilder,
          ),
        ),
      );
      await tester.tap(find.text('New Game'));
      await tester.pump();
      await tester.pump();
      if (const bool.fromEnvironment('A2_CAPTURE')) {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('docs/evidence/a2-world.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      final host = tester.widget<WorldView>(find.byType(WorldView)).host;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(host.movementEnabled, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(host.movementEnabled, isFalse);
      tester.view.physicalSize = const Size(480, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Continue exploring'));
      await tester.pump();
      expect(host.movementEnabled, isTrue);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('loading cancellation and failure/retry screens are usable', (
    tester,
  ) async {
    final pending = Completer<WorldSession>();
    var attempts = 0;
    await tester.pumpWidget(
      GameApp(
        loadWorld: () {
          attempts++;
          if (attempts == 1) return pending.future;
          if (attempts == 2) return Future.error(StateError('failed'));
          return Future.value(session());
        },
        buildWorld: worldViewBuilder,
      ),
    );
    await tester.tap(find.text('New Game'));
    await tester.pump();
    expect(find.text('Loading world'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    pending.complete(session());
    await tester.pump();
    expect(find.text('New Game'), findsOneWidget);
    await tester.tap(find.text('New Game'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Unable to start'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(WorldView), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
