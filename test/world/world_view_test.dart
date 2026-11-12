import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/ui/sprite_art.dart';
import 'package:app_4/world/demo/demo_host.dart';
import 'package:app_4/world/demo/main.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_camera.dart';
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

  testWidgets(
    'non-artwork map with artwork scene id aligns sprite overlay to tile scale',
    (tester) async {
      final content = DemoContent.decode(
        File('assets/data/lantern_wake.json').readAsStringSync(),
      );
      final nonArtwork = InteractionWorld(content, useArtwork: false);
      final bellwether = nonArtwork.maps['map.bellwether']!;
      final bellwetherHost = DemoWorldHost(bellwether);
      addTearDown(bellwetherHost.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorldView(
              map: bellwether,
              host: bellwetherHost,
              changes: bellwetherHost,
              interactions: nonArtwork.targets,
            ),
          ),
        ),
      );
      await tester.pump();

      final canvasFinder = find.byKey(const ValueKey('world-canvas'));
      final canvasRect = tester.getRect(canvasFinder);
      final painter =
          tester.widget<CustomPaint>(canvasFinder).painter! as WorldPainter;
      expect(painter.scene, isNull);
      expect(painter.unit, WorldPainter.tileSize);

      Offset expectedCamera(WorldPosition pos) => worldCameraOffset(
        viewport: canvasRect.size,
        mapSize: painter.mapSize,
        player: Offset(pos.x * painter.unit, pos.y * painter.unit),
      );

      final initialPos = bellwetherHost.state.position;
      final initialCamera = expectedCamera(initialPos);
      final heroTopLeft = tester.getTopLeft(find.byType(ExplorationHeroSprite));
      final expectedHero =
          canvasRect.topLeft +
          initialCamera +
          Offset(
            initialPos.x * WorldPainter.tileSize - 24,
            initialPos.y * WorldPainter.tileSize - 48,
          );
      expect(heroTopLeft.dx, closeTo(expectedHero.dx, 0.01));
      expect(heroTopLeft.dy, closeTo(expectedHero.dy, 0.01));

      final mara = nonArtwork.targets.targets.firstWhere(
        (target) => target.id == 'npc.mara',
      );
      final markerTopLeft = tester.getTopLeft(
        find.byKey(const ValueKey('quest-marker-mara')),
      );
      final expectedMarker =
          canvasRect.topLeft +
          initialCamera +
          Offset(
            (mara.x + .5) * WorldPainter.tileSize - 15,
            (mara.y + .5) * WorldPainter.tileSize - 74,
          );
      expect(markerTopLeft.dx, closeTo(expectedMarker.dx, 0.01));
      expect(markerTopLeft.dy, closeTo(expectedMarker.dy, 0.01));

      final maraSpriteTopLeft = tester.getTopLeft(
        find.byWidgetPredicate(
          (widget) =>
              widget is BellwetherTownspersonSprite && widget.variant == 0,
        ),
      );
      final expectedMaraSprite =
          canvasRect.topLeft +
          initialCamera +
          Offset(
            (mara.x + .5) * WorldPainter.tileSize - 18,
            (mara.y + .5) * WorldPainter.tileSize - 46,
          );
      expect(maraSpriteTopLeft.dx, closeTo(expectedMaraSprite.dx, 0.01));
      expect(maraSpriteTopLeft.dy, closeTo(expectedMaraSprite.dy, 0.01));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      await step(tester);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

      final movedPos = bellwetherHost.state.position;
      expect(movedPos.x, greaterThan(initialPos.x));
      final movedCamera = expectedCamera(movedPos);
      final movedHeroTopLeft = tester.getTopLeft(
        find.byType(ExplorationHeroSprite),
      );
      final expectedMovedHero =
          canvasRect.topLeft +
          movedCamera +
          Offset(
            movedPos.x * WorldPainter.tileSize - 24,
            movedPos.y * WorldPainter.tileSize - 48,
          );
      expect(movedHeroTopLeft.dx, closeTo(expectedMovedHero.dx, 0.01));
      expect(movedHeroTopLeft.dy, closeTo(expectedMovedHero.dy, 0.01));

      await tester.pumpWidget(const SizedBox());
    },
  );
}
