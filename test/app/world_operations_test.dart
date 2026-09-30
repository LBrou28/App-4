import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:app_4/world/world_view.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/world_operations.dart';
import 'package:app_4/app/content_operations.dart';
import 'package:app_4/app/game_app.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/world_map.dart';

MapDefinition map(String id) => MapDefinition(
  id: id,
  width: 5,
  height: 5,
  blocked: List.filled(25, false),
  spawns: {'entry': WorldPosition(mapId: id, x: 2.5, y: 2.5)},
);
InteractionSite site(String id, {bool reachable = true}) =>
    InteractionSite(mapId: id, canActivate: (p) => reachable && p.x == 2.5);
WorldOperations operations({
  bool clear = true,
  String spawn = 'entry',
  bool reachable = true,
}) {
  final second = map('second');
  return WorldOperations(
    areas: [WorldArea(map: second, isClear: (_) => clear)],
    exits: [
      MapExit(
        id: 'exit',
        site: site('first', reachable: reachable),
        destinationMapId: 'second',
        spawnId: spawn,
      ),
      MapExit(
        id: 'back',
        site: site('second'),
        destinationMapId: 'first',
        spawnId: 'entry',
      ),
    ],
    dialogues: [
      WorldDialogue(
        id: 'npc',
        site: site('first', reachable: reachable),
        speaker: 'Test guide',
        lines: ['A fixture conversation.'],
      ),
    ],
    chests: [
      WorldChest(
        id: 'chest',
        site: site('first', reachable: reachable),
        itemId: 'fixture.item',
        quantity: 2,
      ),
    ],
    itemIds: {'fixture.item'},
  );
}

WorldSession session(WorldOperations ops, {GameState? state}) {
  final first = map('first');
  return WorldSession(
    map: first,
    initialState:
        state ?? createContractFixture(position: first.spawns['entry']!),
    isClear: WorldCollision(first).isClear,
    operations: ops,
  );
}

Future<AppController> controller(WorldOperations ops) async {
  final c = AppController(loadWorld: () async => session(ops));
  addTearDown(c.dispose);
  await c.newGame();
  return c;
}

BattleSession questBattle(BattleInput input) => BattleSession(
  input: input,
  heroStats: {
    for (final member in input.state.party)
      member.id: const CombatStats(attack: 20, defense: 0, speed: 5),
  },
  enemies: [
    combat.Combatant(
      id: 'enemy.hollow_bell',
      side: combat.BattleSide.enemies,
      hp: 1,
      maxHp: 1,
      attack: 0,
      defense: 0,
      speed: 0,
    ),
  ],
);

void win(BattleSession battle) => battle.resolve(battle.snapshot.round, [
  for (final combatant in battle.snapshot.combatants)
    if (combatant.side == combat.BattleSide.heroes && combatant.isAlive)
      combat.HeroCommand.attack(combatant.id, 'enemy.hollow_bell'),
]);

void main() {
  test('exit publishes map and named spawn atomically and invalidates old movement', () async {
    final c = await controller(operations());
    final original = c.state;
    final revision = c.revision;
    var notices = 0;
    c.addListener(() {
      notices++;
      expect(c.state.position.mapId, c.map!.id);
      expect(c.revision, greaterThan(revision));
      expect(c.openChest('chest', expectedRevision: c.revision), isFalse);
    });
    expect(c.useMapExit('exit', expectedRevision: revision), isTrue);
    expect(c.state.position, same(c.map!.spawns['entry']));
    expect(c.state.inventory, same(original.inventory));
    expect(c.state.quests, same(original.quests));
    expect(c.state.party, orderedEquals(original.party));
    expect(c.state.gold, original.gold);
    expect(
      c.updatePosition(original.position, expectedRevision: revision),
      isFalse,
    );
    expect(c.useMapExit('back', expectedRevision: c.revision), isTrue);
    expect(c.map!.id, 'first');
    expect(notices, 2);
  });
  test('bad spawn, full-footprint collision, reach and unknown IDs reject unchanged', () async {
    for (final ops in [
      operations(clear: false),
      operations(spawn: 'missing'),
      operations(reachable: false),
      WorldOperations(),
    ]) {
      final c = await controller(ops);
      final before = c.state;
      final revision = c.revision;
      var notices = 0;
      c.addListener(() => notices++);
      expect(c.useMapExit('exit', expectedRevision: revision), isFalse);
      expect(c.state, same(before));
      expect(c.revision, revision);
      expect(c.map!.id, 'first');
      expect(notices, 0);
    }
  });
  test('all interactions reject stale revisions, pause, wrong maps and unreachable sites', () async {
    final c = await controller(operations());
    final stale = c.revision;
    c.setPaused(true);
    for (final r in [stale, c.revision]) {
      expect(c.useMapExit('exit', expectedRevision: r), isFalse);
      expect(c.openDialogue('npc', expectedRevision: r), isFalse);
      expect(c.openChest('chest', expectedRevision: r), isFalse);
    }
    c.setPaused(false);
    expect(c.openDialogue('npc', expectedRevision: stale), isFalse);
    expect(c.openChest('chest', expectedRevision: stale), isFalse);
    c.useMapExit('exit', expectedRevision: c.revision);
    expect(c.openDialogue('npc', expectedRevision: c.revision), isFalse);
    expect(c.openChest('chest', expectedRevision: c.revision), isFalse);
    final unreachable = await controller(operations(reachable: false));
    expect(
      unreachable.openDialogue('npc', expectedRevision: unreachable.revision),
      isFalse,
    );
    expect(
      unreachable.openChest('chest', expectedRevision: unreachable.revision),
      isFalse,
    );
  });
  test('quest dialogue flags are completion-only and boss victory opens its finale', () async {
    final first = map('first');
    final questSite = InteractionSite(
      mapId: first.id,
      canActivate: (position) => position.x == 2.5 && position.y == 2.5,
    );
    WorldDialogue dialogue(String id) => WorldDialogue(
      id: id,
      site: questSite,
      speaker: 'Keeper Mara',
      lines: ['A quest moment.'],
    );
    final ops = WorldOperations(
      questSteps: [
        WorldQuestStep(
          id: 'step.accept',
          interactionId: 'npc.mara',
          site: questSite,
          dialogue: dialogue('dialogue.call'),
          setsFlag: 'quest.accepted',
        ),
        WorldQuestStep(
          id: 'step.bell',
          interactionId: 'quest.bell',
          site: questSite,
          dialogue: dialogue('dialogue.bell'),
          requiresFlags: {'quest.accepted'},
          setsFlag: 'quest.bell_awake',
          encounterId: 'enemy.hollow_bell',
        ),
        WorldQuestStep(
          id: 'step.return',
          interactionId: 'npc.mara',
          site: questSite,
          dialogue: dialogue('dialogue.ending'),
          requiresFlags: {'quest.bell_awake'},
          setsFlag: 'quest.complete',
        ),
      ],
    );
    final c = AppController(
      loadWorld: () async => WorldSession(
        map: first,
        initialState: createContractFixture(position: first.spawns['entry']!),
        isClear: WorldCollision(first).isClear,
        operations: ops,
      ),
      battles: {'enemy.hollow_bell': questBattle},
    );
    addTearDown(c.dispose);
    await c.newGame();

    expect(c.openDialogue('npc.mara', expectedRevision: c.revision), isTrue);
    final accept = c.activeDialogue!.token;
    expect(c.closeDialogue(accept, expectedRevision: c.revision), isTrue);
    expect(c.state.quests.flags, isEmpty);
    expect(c.openDialogue('quest.bell', expectedRevision: c.revision), isFalse);

    expect(c.openDialogue('npc.mara', expectedRevision: c.revision), isTrue);
    expect(
      c.completeDialogue(c.activeDialogue!.token, expectedRevision: c.revision),
      isTrue,
    );
    expect(c.state.quests.flags, {'quest.accepted'});

    expect(c.openDialogue('quest.bell', expectedRevision: c.revision), isTrue);
    expect(c.mode, AppMode.battle);
    final firstBattle = c.activeBattle!;
    win(firstBattle);
    expect(c.acceptBattleResult(firstBattle.result!), isTrue);
    expect(c.mode, AppMode.dialogue);
    expect(c.activeDialogue!.dialogue.id, 'dialogue.bell');
    expect(
      c.closeDialogue(c.activeDialogue!.token, expectedRevision: c.revision),
      isTrue,
    );
    expect(c.state.quests.flags, {'quest.accepted'});

    expect(c.openDialogue('quest.bell', expectedRevision: c.revision), isTrue);
    final retry = c.activeBattle!;
    win(retry);
    expect(c.acceptBattleResult(retry.result!), isTrue);
    expect(
      c.completeDialogue(c.activeDialogue!.token, expectedRevision: c.revision),
      isTrue,
    );
    expect(c.state.quests.flags, {'quest.accepted', 'quest.bell_awake'});
    expect(c.openDialogue('npc.mara', expectedRevision: c.revision), isTrue);
    expect(c.activeDialogue!.dialogue.id, 'dialogue.ending');
    expect(
      c.completeDialogue(c.activeDialogue!.token, expectedRevision: c.revision),
      isTrue,
    );
    expect(c.state.quests.flags, {
      'quest.accepted',
      'quest.bell_awake',
      'quest.complete',
    });
    expect(c.openDialogue('npc.mara', expectedRevision: c.revision), isFalse);
  });
  test('chest grant and opened flag publish exactly once including listener reentry', () async {
    final c = await controller(operations());
    final before = c.state;
    final revision = c.revision;
    var notices = 0;
    c.addListener(() {
      notices++;
      expect(c.state.inventory.quantities['fixture.item'], 4);
      expect(c.state.quests.openedChestIds, contains('chest'));
      expect(c.openChest('chest', expectedRevision: c.revision), isFalse);
    });
    expect(c.openChest('chest', expectedRevision: revision), isTrue);
    expect(c.state.position, same(before.position));
    expect(c.state.party, orderedEquals(before.party));
    expect(c.state.quests.flags, unorderedEquals(before.quests.flags));
    expect(c.state.gold, before.gold);
    final granted = c.state;
    for (final r in [revision, c.revision]) {
      expect(c.openChest('chest', expectedRevision: r), isFalse);
    }
    expect(c.state, same(granted));
    expect(notices, 1);
    // A future load supplies the authoritative opened flags; no reset here.
    final restored = AppController(
      loadWorld: () async => session(operations(), state: granted),
    );
    addTearDown(restored.dispose);
    await restored.newGame();
    expect(
      restored.openChest('chest', expectedRevision: restored.revision),
      isFalse,
    );
    expect(restored.state.inventory.quantities['fixture.item'], 4);
  });
  test('dialogue gates immediately, token prevents late close, pause survives dismissal', () async {
    final c = await controller(operations());
    final state = c.state;
    expect(c.openDialogue('npc', expectedRevision: c.revision), isTrue);
    final token = c.activeDialogue!.token;
    final opened = c.revision;
    expect(c.movementEnabled, isFalse);
    expect(c.openDialogue('npc', expectedRevision: opened), isFalse);
    expect(c.openChest('chest', expectedRevision: opened), isFalse);
    expect(c.useMapExit('exit', expectedRevision: opened), isFalse);
    expect(c.updatePosition(state.position, expectedRevision: opened), isFalse);
    c.setPaused(true);
    expect(c.closeDialogue(token, expectedRevision: opened), isFalse);
    expect(c.closeDialogue(token, expectedRevision: c.revision), isTrue);
    expect(c.movementEnabled, isFalse);
    expect(c.state, same(state));
    c.setPaused(false);
    c.openDialogue('npc', expectedRevision: c.revision);
    expect(c.activeDialogue!.token, greaterThan(token));
    expect(c.closeDialogue(token, expectedRevision: c.revision), isFalse);
    c.returnToTitle();
    await c.newGame();
    c.openDialogue('npc', expectedRevision: c.revision);
    expect(c.closeDialogue(token, expectedRevision: c.revision), isFalse);
  });
  test('throwing and reentrant reach callbacks fail closed', () async {
    late AppController c;
    final ops = WorldOperations(
      dialogues: [
        WorldDialogue(
          id: 'npc',
          site: InteractionSite(
            mapId: 'first',
            canActivate: (_) {
              expect(c.setPaused(true), isFalse);
              expect(
                c.openDialogue('npc', expectedRevision: c.revision),
                isFalse,
              );
              throw StateError('broken placement');
            },
          ),
          speaker: 'Guide',
          lines: ['Hello'],
        ),
      ],
    );
    c = await controller(ops);
    final revision = c.revision;
    expect(c.openDialogue('npc', expectedRevision: revision), isFalse);
    expect(c.revision, revision);
    expect(c.movementEnabled, isTrue);
  });
  test('registry copies collections and rejects duplicate IDs and unknown chest items', () {
    final exits = <MapExit>[];
    final ops = WorldOperations(exits: exits);
    exits.add(
      MapExit(
        id: 'x',
        site: site('first'),
        destinationMapId: 'second',
        spawnId: 'entry',
      ),
    );
    expect(ops.exits, isEmpty);
    expect(
      () => WorldOperations(exits: [exits.first, exits.first]),
      throwsArgumentError,
    );
    expect(
      () => WorldOperations(
        chests: [
          WorldChest(
            id: 'c',
            site: site('first'),
            itemId: 'unknown',
            quantity: 1,
          ),
        ],
      ),
      throwsArgumentError,
    );
  });
  test('real D content adapters use authored rewards and require matching explicit B placements', () {
    final content = DemoContent.decode(
      File('assets/data/lantern_wake.json').readAsStringSync(),
    );
    final empty = contentOperations(content: content, sites: {});
    expect(empty.dialogues, isEmpty);
    expect(empty.chests, isEmpty);
    final ops = contentOperations(
      content: content,
      sites: {
        'npc.mara': site('map.bellwether'),
        'chest.causeway_supplies': site('map.salt_path'),
      },
    );
    expect(
      ops.dialogues['npc.mara']!.lines,
      content.find('dialogues', 'dialogue.call').strings('lines'),
    );
    expect(ops.chests['chest.causeway_supplies']!.itemId, 'item.salves');
    expect(ops.chests['chest.causeway_supplies']!.quantity, 2);
    expect(
      () => contentOperations(
        content: content,
        sites: {'npc.mara': site('first')},
      ),
      throwsArgumentError,
    );
    expect(
      () => contentOperations(
        content: content,
        sites: {'unknown': site('first')},
      ),
      throwsArgumentError,
    );
  });
  testWidgets(
    'D dialogue routes close, restore focus gate and ignore old routes on restart',
    (tester) async {
      late AppController c;
      await tester.pumpWidget(
        GameApp(
          loadWorld: () async => session(operations()),
          buildWorld: (_) => (context, host, changes) {
            c = host as AppController;
            return const ColoredBox(color: Colors.green);
          },
        ),
      );
      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();
      c.openDialogue('npc', expectedRevision: c.revision);
      await tester.pumpAndSettle();
      expect(find.text('A fixture conversation.'), findsOneWidget);
      expect(c.movementEnabled, isFalse);
      c.setPaused(true);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(c.mode, AppMode.exploration);
      expect(c.paused, isTrue);
      expect(find.text('Paused'), findsOneWidget);
      await tester.tap(find.text('Continue exploring'));
      await tester.pumpAndSettle();
      expect(c.movementEnabled, isTrue);
      c.openDialogue('npc', expectedRevision: c.revision);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(c.movementEnabled, isTrue);
      c.openDialogue('npc', expectedRevision: c.revision);
      await tester.pumpAndSettle();
      c.returnToTitle();
      await c.newGame();
      c.openDialogue('npc', expectedRevision: c.revision);
      final latest = c.activeDialogue!.token;
      await tester.pumpAndSettle();
      expect(c.activeDialogue!.token, latest);
      expect(find.text('A fixture conversation.'), findsOneWidget);
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(c.movementEnabled, isTrue);
    },
  );
  testWidgets('real B view follows exit and D dialogue clears held movement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('A2_INTERACTION_CAPTURE')) {
      await tester.runAsync(() async {
        for (final entry in {
          'Roboto': const String.fromEnvironment('A2_TEXT_FONT'),
          'MaterialIcons': const String.fromEnvironment('A2_ICON_FONT'),
        }.entries) {
          await (FontLoader(entry.key)..addFont(
                Future.value(
                  (await File(entry.value).readAsBytes()).buffer.asByteData(),
                ),
              ))
              .load();
        }
      });
    }
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: GameApp(
          loadWorld: () async => session(operations()),
          buildWorld: worldViewBuilder,
        ),
      ),
    );
    await tester.tap(find.text('New Game'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final c =
        tester.widget<WorldView>(find.byType(WorldView)).host as AppController;
    expect(c.useMapExit('exit', expectedRevision: c.revision), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.widget<WorldView>(find.byType(WorldView)).map.id, 'second');
    expect(c.useMapExit('back', expectedRevision: c.revision), isTrue);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    c.openDialogue('npc', expectedRevision: c.revision);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final position = c.state.position;
    await tester.pump(const Duration(milliseconds: 400));
    if (const bool.fromEnvironment('A2_INTERACTION_CAPTURE')) {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        await File('docs/evidence/a2-dialogue.png')
            .writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.tap(find.text('Finish'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.state.position, same(position));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(c.state.position.x, greaterThan(position.x));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
