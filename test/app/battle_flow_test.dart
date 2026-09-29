import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/integration_preview.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/battle/ui/battle_controller.dart';
import 'package:app_4/battle/ui/battle_screen.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';
import 'package:app_4/world/world_view.dart';
import 'package:app_4/world/world_controller.dart';
import 'package:app_4/world/world_encounters.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';

BattleSession factory(
  BattleInput input, {
  bool defeat = false,
  FleePolicy? flee,
}) => BattleSession(
  input: input,
  heroStats: {
    for (final m in input.state.party)
      m.id: const CombatStats(attack: 20, defense: 0, speed: 5),
  },
  enemies: [
    combat.Combatant(
      id: 'enemy',
      side: combat.BattleSide.enemies,
      hp: defeat ? 1000 : 1,
      maxHp: defeat ? 1000 : 1,
      attack: defeat ? 100 : 0,
      defense: 0,
      speed: 0,
    ),
  ],
  fleePolicy: flee,
);
Future<AppController> host({BattleFactory? battle}) async {
  final map = createPrototypeMap();
  final c = AppController(
    loadWorld: () async => WorldSession(
      map: map,
      initialState: createContractFixture(position: map.spawns['entry']!),
      isClear: WorldCollision(map).isClear,
    ),
    battles: {'test': battle ?? factory},
  );
  addTearDown(c.dispose);
  await c.newGame();
  return c;
}

bool launch(AppController c) => c.requestEncounter(
  EncounterRequest(definitionId: 'test'),
  expectedRevision: c.revision,
);
void resolve(BattleSession s) {
  s.resolve(s.snapshot.round, [
    for (final h in s.snapshot.combatants)
      if (h.side == combat.BattleSide.heroes && h.isAlive)
        combat.HeroCommand.attack(h.id, 'enemy'),
  ]);
}

class AlwaysRoll implements EncounterRandom {
  @override
  int nextInt(int max) => 0;
}

class _MemorySave implements SaveRepository {
  SaveData? data;
  @override
  Future<LoadResult> load() async =>
      data == null ? SaveMissing() : SaveLoaded(data!);
  @override
  Future<WriteResult> save(SaveData value) async {
    data = value;
    return SaveWritten();
  }
}

void main() {
  test('launch publishes gate/input atomically and rejects stale/unknown/reentrant requests', () async {
    final c = await host();
    final before = c.state;
    final old = c.revision;
    var notices = 0;
    c.addListener(() {
      notices++;
      expect(c.movementEnabled, isFalse);
      expect(c.activeBattle!.input.state, same(before));
      expect(c.activeBattle!.input.baseRevision, c.revision);
      expect(launch(c), isFalse);
    });
    expect(
      c.requestEncounter(
        EncounterRequest(definitionId: 'unknown'),
        expectedRevision: old,
      ),
      isFalse,
    );
    expect(
      c.requestEncounter(
        EncounterRequest(definitionId: 'test'),
        expectedRevision: old - 1,
      ),
      isFalse,
    );
    expect(launch(c), isTrue);
    expect(notices, 1);
    expect(
      c.updatePosition(before.position, expectedRevision: c.revision),
      isFalse,
    );
  });
  test(
    'failed or mismatched factory leaves state, revision and gate unchanged',
    () async {
      for (final BattleFactory create in [
        (_) => throw StateError('bad definition'),
        (input) => createTrainingBattle(
          BattleInput(
            encounterId: 'wrong',
            baseRevision: 0,
            request: input.request,
            state: input.state,
            seed: 0,
          ),
        ),
      ]) {
        final c = await host(battle: create);
        final before = c.state;
        final revision = c.revision;
        expect(launch(c), isFalse);
        expect(c.state, same(before));
        expect(c.revision, revision);
        expect(c.movementEnabled, isTrue);
        expect(c.activeBattle, isNull);
      }
    },
  );
  test('victory commits only the active session result once and preserves world state', () async {
    final c = await host();
    final before = c.state;
    launch(c);
    final session = c.activeBattle!;
    resolve(session);
    final result = session.result!;
    final forged = BattleResult(
      encounterId: result.encounterId,
      baseRevision: result.baseRevision,
      outcome: result.outcome,
      party: result.party,
      inventory: Inventory({'extra': 999}),
      gold: 999,
    );
    expect(c.acceptBattleResult(forged), isFalse);
    c.setPaused(true);
    expect(c.acceptBattleResult(result), isFalse);
    c.setPaused(false);
    final revision = c.revision;
    expect(c.acceptBattleResult(result), isTrue);
    expect(c.revision, revision + 1);
    expect(c.state.position, same(before.position));
    expect(c.state.quests, same(before.quests));
    expect(c.state.inventory, same(before.inventory));
    expect(c.state.gold, before.gold);
    expect(c.movementEnabled, isTrue);
    expect(c.acceptBattleResult(result), isFalse);
    expect(c.revision, revision + 1);
  });
  test(
    'restart invalidates old result and never reuses encounter identity',
    () async {
      final c = await host();
      launch(c);
      final first = c.activeBattle!;
      resolve(first);
      final oldResult = first.result!;
      c.returnToTitle();
      await c.newGame();
      launch(c);
      expect(c.activeBattle!.input.encounterId, isNot(first.input.encounterId));
      expect(c.acceptBattleResult(oldResult), isFalse);
      expect(c.mode, AppMode.battle);
    },
  );
  test(
    'defeat reaches game over with final HP and restart restores a new party',
    () async {
      final c = await host(battle: (i) => factory(i, defeat: true));
      launch(c);
      final s = c.activeBattle!;
      for (var i = 0; i < 10 && s.result == null; i++) {
        resolve(s);
      }
      expect(s.result!.outcome, BattleOutcome.defeat);
      expect(c.acceptBattleResult(s.result!), isTrue);
      expect(c.mode, AppMode.gameOver);
      expect(c.movementEnabled, isFalse);
      expect(c.state.party.every((m) => m.hp == 0), isTrue);
      await c.newGame();
      expect(c.state.party.every((m) => m.hp > 0), isTrue);
    },
  );
  test('flee returns without rewards and delayed old escape cannot replace restarted state', () async {
    final pending = Completer<bool>();
    final c = await host(
      battle: (i) => factory(i, flee: (_) => pending.future),
    );
    launch(c);
    final s = c.activeBattle!;
    final fleeing = s.flee();
    c.returnToTitle();
    await c.newGame();
    final current = c.state;
    pending.complete(true);
    await fleeing;
    expect(c.acceptBattleResult(s.result!), isFalse);
    expect(c.state, same(current));
    launch(c);
    final next = c.activeBattle!;
    await next.flee();
    expect(c.acceptBattleResult(next.result!), isTrue);
    expect(c.state.inventory, same(current.inventory));
    expect(c.state.gold, current.gold);
  });
  test(
    'B accepted travel launches real C battle and cooldown survives return',
    () async {
      final c = await host();
      final stepper = EncounterStepper(
        zones: [
          EncounterZone(
            mapId: c.map!.id,
            left: 1,
            top: 1,
            width: 14,
            height: 10,
            definitionId: 'test',
            rollDenominator: 3,
            rollThreshold: 1,
          ),
        ],
        random: AlwaysRoll(),
      );
      final world = WorldController(
        host: c,
        collision: WorldCollision(c.map!),
        encounters: stepper,
      );
      c.addListener(world.synchronize);
      world.press('key', WalkDirection.right);
      for (var i = 0; i < 4; i++) {
        world.advance(.1);
      }
      expect(c.mode, AppMode.battle);
      final returnPosition = c.state.position;
      expect(stepper.remainingCooldown, 3);
      resolve(c.activeBattle!);
      c.acceptBattleResult(c.activeBattle!.result!);
      expect(c.state.position, same(returnPosition));
      expect(world.direction, isNull);
      for (var i = 0; i < 3; i++) {
        expect(stepper.recordAcceptedStep(c), isFalse);
      }
      expect(launch(c), isTrue);
    },
  );
  testWidgets(
    'battle playback and input wait for explicit resume, disposal releases waits',
    (tester) async {
      final c = await host();
      launch(c);
      final screen = BattleController(
        c.activeBattle!,
        pauseSignal: c,
        eventDelay: const Duration(milliseconds: 100),
      );
      while (screen.active != null) {
        screen.attack();
        screen.target('enemy');
      }
      final pending = screen.submit();
      await tester.pump();
      c.setPaused(true);
      final count = screen.events.length;
      await tester.pump(const Duration(seconds: 2));
      expect(screen.events.length, count);
      expect(screen.busy, isTrue);
      expect(screen.canChoose, isFalse);
      c.setPaused(false);
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      await pending;
      expect(screen.result, isNotNull);
      c.setPaused(true);
      expect(screen.takeResult(), isNull);
      c.setPaused(false);
      expect(screen.takeResult(), isNotNull);
      screen.dispose();
      c.returnToTitle();
      await c.newGame();
      launch(c);
      final disposed = BattleController(c.activeBattle!, pauseSignal: c);
      while (disposed.active != null) {
        disposed.defend();
      }
      final abandoned = disposed.submit();
      c.setPaused(true);
      await tester.pump();
      disposed.dispose();
      await tester.pump(const Duration(seconds: 1));
      await abandoned;
    },
  );
  testWidgets(
    'default preview connects B world, training battle, lifecycle pause and return',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('A5_CAPTURE')) {
        await tester.runAsync(() async {
          for (final e in {
            'Roboto': const String.fromEnvironment('A5_TEXT_FONT'),
            'MaterialIcons': const String.fromEnvironment('A5_ICON_FONT'),
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
      final key = GlobalKey();
      final saves = _MemorySave();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: buildIntegrationPreview(saves: saves),
        ),
      );
      await tester.tap(find.text('New Game'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      // Asset loading may require asynchronous IO in the test harness.
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      await tester.pump();
      final view = tester.widget<WorldView>(find.byType(WorldView));
      final c = view.host as AppController;
      final position = c.state.position;
      expect(view.map.id, 'map.bellwether');
      await tester.tap(find.text('Training battle'));
      await tester.pump();
      expect(find.byType(BattleScreen), findsOneWidget);
      expect(c.movementEnabled, isFalse);
      if (const bool.fromEnvironment('A5_CAPTURE')) {
        await tester.pump(const Duration(milliseconds: 500));
        await tester.runAsync(() async {
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('docs/evidence/a5-battle.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Paused'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(c.paused, isTrue);
      await tester.tap(find.text('Continue battle'));
      await tester.pump();
      await tester.tap(find.text('Flee'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump();
      expect(c.mode, AppMode.exploration);
      expect(c.state.position, same(position));
      expect(tester.widget<WorldView>(find.byType(WorldView)).host, same(c));
      await tester.tap(find.text('Pause'));
      await tester.pump();
      await tester.tap(find.text('Save game'));
      await tester.pump();
      await tester.pump();
      expect(saves.data?.state.position, same(c.state.position));
      await tester.tap(find.text('End session'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Continue'), findsOneWidget);
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.pump();
      expect(c.mode, AppMode.exploration);
      expect(c.state.position.x, position.x);
      expect(c.state.position.y, position.y);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
