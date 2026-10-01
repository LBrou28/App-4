import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/game_app.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/ui/dialogue_panel.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/demo/demo_host.dart';
import 'package:app_4/world/world_controller.dart';
import 'package:app_4/world/world_interactions.dart';
import 'package:app_4/world/world_map.dart';
import 'package:app_4/world/world_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InteractionWorld world;
  late AppController host;
  setUp(() async {
    world = InteractionWorld(
      DemoContent.decode(
        File('assets/data/lantern_wake.json').readAsStringSync(),
      ),
    );
    host = AppController(loadWorld: () async => world.session());
    await host.newGame();
  });
  tearDown(() => host.dispose());

  WorldController control() {
    final c = WorldController(
      host: host,
      collision: WorldCollision(host.map!),
      interactions: world.targets,
    );
    host.addListener(c.synchronize);
    addTearDown(() => host.removeListener(c.synchronize));
    return c;
  }

  void place(String map, double x, double y) {
    expect(
      host.updatePosition(
        WorldPosition(mapId: map, x: x, y: y),
        expectedRevision: host.revision,
      ),
      isTrue,
    );
  }

  void enterRoute() {
    place('map.bellwether', 22.5, 8.5);
    expect(
      host.useMapExit(
        'exit.harbor_to_causeway',
        expectedRevision: host.revision,
      ),
      isTrue,
    );
  }

  test(
    'every spawn clears footprint, every target is reachable from a spawn',
    () {
      for (final map in world.maps.values) {
        final collision = WorldCollision(map);
        final pending = [
          (map.spawns['entry']!.x.floor(), map.spawns['entry']!.y.floor()),
        ];
        final seen = <(int, int)>{};
        while (pending.isNotEmpty) {
          final point = pending.removeLast();
          if (seen.contains(point)) continue;
          if (point.$1 < 0 || point.$2 < 0) continue;
          if (!collision.isClear(
            WorldPosition(mapId: map.id, x: point.$1 + .5, y: point.$2 + .5),
          )) {
            continue;
          }
          seen.add(point);
          for (final delta in [(0, 1), (0, -1), (1, 0), (-1, 0)]) {
            pending.add((point.$1 + delta.$1, point.$2 + delta.$2));
          }
        }
        for (final spawn in map.spawns.values) {
          expect(collision.isClear(spawn), isTrue);
          expect(seen, contains((spawn.x.floor(), spawn.y.floor())));
          expect(
            world.targets.targets.where(
              (t) => t.kind == WorldTargetKind.exit && t.reachable(spawn),
            ),
            isEmpty,
          );
        }
        for (final target in world.targets.targets.where(
          (t) => t.mapId == map.id,
        )) {
          expect(
            seen.any(
              (p) => target.reachable(
                WorldPosition(mapId: map.id, x: p.$1 + .5, y: p.$2 + .5),
              ),
            ),
            isTrue,
            reason: target.id,
          );
        }
      }
    },
  );

  test(
    'NPC requires facing adjacency; dialogue pauses and does not auto reopen',
    () {
      final c = control();
      expect(c.interact(), isFalse);
      place('map.bellwether', 11.5, 8.5); // Mara is directly above.
      c.press('up', WalkDirection.up);
      expect(c.interactionTarget!.id, 'npc.mara');
      expect(c.interact(), isTrue);
      expect(host.mode, AppMode.dialogue);
      final token = host.activeDialogue!.token;
      final position = host.state.position;
      expect(c.advance(.1), isFalse);
      expect(c.interact(), isFalse);
      host.closeDialogue(token, expectedRevision: host.revision);
      expect(c.advance(.1), isFalse);
      expect(host.state.position, same(position));
      expect(host.activeDialogue, isNull);
      place('map.bellwether', 10.5, 9.5); // Diagonal cannot reach Mara.
      expect(c.interact(), isFalse);
      place('map.bellwether', 9.5, 10.5); // Distant cannot reach Mara.
      expect(c.interact(), isFalse);
    },
  );

  test(
    'movement onto an exit transitions once with preserved state and no bounce',
    () {
      place('map.bellwether', 21.8, 8.5);
      final c = control();
      final before = host.state;
      c.press('right', WalkDirection.right);
      expect(c.advance(.1), isTrue);
      expect(host.map!.id, 'map.salt_path');
      expect(host.state.position, same(host.map!.spawns['from_harbor']));
      expect(host.state.inventory, same(before.inventory));
      expect(host.state.quests, same(before.quests));
      expect(host.state.party, orderedEquals(before.party));
      expect(c.advance(.1), isFalse);
      final next = control();
      expect(next.advance(.1), isFalse);
      place('map.salt_path', 3.5, 14.8);
      next.press('down', WalkDirection.down);
      next.advance(.1);
      expect(host.map!.id, 'map.bellwether');
      expect(host.state.position, same(host.map!.spawns['from_causeway']));
    },
  );

  test('dungeon exits return to the named route spawn', () {
    enterRoute();
    place('map.salt_path', 25.8, 8.5);
    final c = control()..press('r', WalkDirection.right);
    c.advance(.1);
    expect(host.map!.id, 'map.tide_cistern');
    expect(host.state.position, same(host.map!.spawns['from_causeway']));
    place('map.tide_cistern', 2.1, 9.5);
    final d = control()..press('l', WalkDirection.left);
    d.advance(.1);
    expect(host.map!.id, 'map.salt_path');
    expect(host.state.position, same(host.map!.spawns['from_cistern']));
  });

  test('chest gives two authored salves once, even after map return and restored snapshot', () async {
    enterRoute();
    place('map.salt_path', 9.5, 4.5);
    final c = control()..press('up', WalkDirection.up);
    final before = host.state.inventory.quantities['item.salves'] ?? 0;
    expect(c.interact(), isTrue);
    expect(host.state.inventory.quantities['item.salves'], before + 2);
    expect(
      host.state.quests.openedChestIds,
      contains('chest.causeway_supplies'),
    );
    final granted = host.state;
    expect(c.interact(), isFalse);
    expect(host.state, same(granted));
    place('map.salt_path', 3.5, 15.5);
    host.useMapExit('exit.causeway_to_harbor', expectedRevision: host.revision);
    enterRoute();
    place('map.salt_path', 9.5, 4.5);
    expect(c.interact(), isFalse);
    final restored = host.state;
    final loaded = AppController(
      loadWorld: () async => world.session(restored: restored),
    );
    await loaded.newGame();
    expect(
      loaded.openChest(
        'chest.causeway_supplies',
        expectedRevision: loaded.revision,
      ),
      isFalse,
    );
    expect(loaded.state.inventory.quantities['item.salves'], before + 2);
    loaded.dispose();
  });

  test('paused and old B1-only hosts are harmless', () {
    final c = control()..press('up', WalkDirection.up);
    host.setPaused(true);
    expect(c.interact(), isFalse);
    expect(c.advance(.1), isFalse);
    expect(host.activeDialogue, isNull);
    final oldHost = DemoWorldHost(host.map!);
    final oldController = WorldController(
      host: oldHost,
      collision: WorldCollision(host.map!),
      interactions: world.targets,
    );
    oldController.press('up', WalkDirection.up);
    expect(oldController.interact(), isFalse);
    expect(world.targets.exitAfterMovement(oldHost), isFalse);
    oldHost.dispose();
  });

  testWidgets(
    'E opens one D dialogue; touch chest and exit update the real A shell',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('B2_CAPTURE')) {
        await tester.runAsync(() async {
          for (final e in {
            'Roboto': const String.fromEnvironment('B2_TEXT_FONT'),
            'MaterialIcons': const String.fromEnvironment('B2_ICON_FONT'),
          }.entries) {
            await (FontLoader(e.key)..addFont(
                  Future.value(
                    (await File(e.value).readAsBytes()).buffer.asByteData(),
                  ),
                ))
                .load();
          }
        });
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: GameApp(
            loadWorld: () async => world.session(),
            buildWorld: (map) =>
                (context, host, changes) => WorldView(
                  map: map,
                  host: host,
                  changes: changes,
                  interactions: world.targets,
                  landmarks: world.landmarks,
                  mapName: world.names[map.id],
                ),
          ),
        ),
      );
      await tester.tap(find.text('New Game'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Start exploring'));
      await tester.pump();
      final app =
          tester.widget<WorldView>(find.byType(WorldView)).host
              as AppController;
      app.updatePosition(
        WorldPosition(mapId: 'map.bellwether', x: 11.5, y: 8.5),
        expectedRevision: app.revision,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(DialoguePanel), findsOneWidget);
      expect(find.text('Keeper Mara'), findsWidgets);
      final captured = app.state.position;
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyE);
      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(app.movementEnabled, isTrue);
      expect(app.state.position, same(captured));
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyE);
      await tester.pump();
      expect(find.byType(DialoguePanel), findsNothing);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
      // Move close to the exit, then use actual keyboard travel to cross it.
      app.updatePosition(
        WorldPosition(mapId: 'map.bellwether', x: 21.8, y: 8.5),
        expectedRevision: app.revision,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        tester.widget<WorldView>(find.byType(WorldView)).map.id,
        'map.salt_path',
      );
      app.updatePosition(
        WorldPosition(mapId: 'map.salt_path', x: 9.5, y: 4.5),
        expectedRevision: app.revision,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.tap(find.text('Supply chest'));
      await tester.pump();
      expect(app.state.inventory.quantities['item.salves'], 2);
      await tester.tap(find.text('Supply chest'));
      await tester.pump();
      expect(app.state.inventory.quantities['item.salves'], 2);
      expect(find.textContaining('This chest is empty.'), findsOneWidget);
      if (const bool.fromEnvironment('B2_CAPTURE')) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('lib/world/evidence/b2-interactions.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(480, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
