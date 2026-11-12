import 'dart:async';
import 'dart:io';

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/integration_preview.dart';
import 'package:app_4/app/world_operations.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

WorldSession session({WorldOperations? operations}) {
  final map = createPrototypeMap();
  return WorldSession(
    map: map,
    initialState: createContractFixture(position: map.spawns['entry']!),
    isClear: WorldCollision(map).isClear,
    operations: operations,
  );
}

BattleSession battle(BattleInput input) => BattleSession(
  input: input,
  heroStats: {
    for (final m in input.state.party)
      m.id: const CombatStats(attack: 20, defense: 0, speed: 5),
  },
  enemies: [
    combat.Combatant(
      id: 'enemy',
      side: combat.BattleSide.enemies,
      hp: 1,
      maxHp: 1,
      attack: 0,
      defense: 0,
      speed: 0,
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'shared combat gates writes until a correlated terminal result',
    () async {
      final c = AppController(
        loadWorld: () async => session(),
        battles: {'test': battle},
      );
      addTearDown(c.dispose);
      await c.newGame();
      expect(
        c.requestEncounter(
          EncounterRequest(definitionId: 'test'),
          expectedRevision: c.revision,
        ),
        isTrue,
      );
      expect(c.beginBattleHandoff(), isTrue);
      expect(c.handoffBattleToLanternLink(encounterId: 'shared-1'), isTrue);
      expect(c.mode, AppMode.battle);
      expect(c.activeBattle, isNull);
      expect(c.movementEnabled, isFalse);
      expect(
        c.updatePosition(c.state.position, expectedRevision: c.revision),
        isFalse,
      );
      expect(
        c.requestEncounter(
          EncounterRequest(definitionId: 'test'),
          expectedRevision: c.revision,
        ),
        isFalse,
      );
      expect(c.setPaused(true), isFalse);
      expect(await c.saveCurrent(), isA<SaveWriteFailed>());
      expect(
        await c.applyRemoteState(
          c.state,
          readOnly: false,
          encounterId: 'shared-1',
          encounterDefinitionId: 'test',
          outcome: BattleOutcome.victory,
        ),
        isTrue,
      );
      expect(c.movementEnabled, isTrue);
    },
  );

  test(
    'failed start releases the gate and allows the next encounter',
    () async {
      final c = AppController(
        loadWorld: () async => session(),
        battles: {'test': battle},
      );
      addTearDown(c.dispose);
      await c.newGame();
      expect(
        c.requestEncounter(
          EncounterRequest(definitionId: 'test'),
          expectedRevision: c.revision,
        ),
        isTrue,
      );
      expect(c.beginBattleHandoff(), isTrue);
      c.cancelBattleHandoff();
      expect(c.movementEnabled, isTrue);
      expect(c.activeBattle, isNull);
      expect(
        c.requestEncounter(
          EncounterRequest(definitionId: 'test'),
          expectedRevision: c.revision,
        ),
        isTrue,
      );
    },
  );

  test(
    'promoted guest gains authority only after disconnect pause ends',
    () async {
      final c = AppController(loadWorld: () async => session());
      addTearDown(c.dispose);
      final initial = session().initialState;
      expect(await c.applyRemoteState(initial), isTrue);
      expect(c.movementEnabled, isFalse);
      expect(
        await c.applyRemoteState(initial, readOnly: false, sessionPaused: true),
        isTrue,
      );
      expect(c.setPaused(false), isFalse);
      expect(c.movementEnabled, isFalse);
      expect(await c.applyRemoteState(initial, readOnly: false), isTrue);
      expect(c.movementEnabled, isTrue);
    },
  );

  test(
    'leaving cancels an in-flight remote load even from the title',
    () async {
      final pending = Completer<WorldSession>();
      final c = AppController(loadWorld: () => pending.future);
      addTearDown(c.dispose);
      final loading = c.applyRemoteState(session().initialState);
      c.returnToTitle();
      pending.complete(session());
      expect(await loading, isFalse);
      expect(c.mode, AppMode.title);
      expect(c.remoteReadOnly, isFalse);
    },
  );

  test('shared defeat commits final resources and reaches game over', () async {
    final c = AppController(loadWorld: () async => session());
    addTearDown(c.dispose);
    final initial = session().initialState;
    final defeated = GameState(
      position: initial.position,
      party: [
        for (final m in initial.party)
          PartyMember(
            id: m.id,
            jobId: m.jobId,
            hp: 0,
            maxHp: m.maxHp,
            mp: 0,
            maxMp: m.maxMp,
            level: m.level,
            experience: m.experience,
            jobProgress: m.jobProgress,
            equipment: m.equipment,
          ),
      ],
      inventory: Inventory({}),
      gold: 0,
      quests: initial.quests,
    );
    expect(
      await c.applyRemoteState(
        defeated,
        mode: AppMode.gameOver,
        encounterId: 'shared-1',
        outcome: BattleOutcome.defeat,
      ),
      isTrue,
    );
    expect(c.mode, AppMode.gameOver);
    expect(c.state.party.every((m) => m.hp == 0), isTrue);
    expect(c.state.inventory.quantities, isEmpty);
    expect(c.movementEnabled, isFalse);
    c.returnToTitle();
    await c.newGame();
    expect(c.movementEnabled, isTrue);
  });

  test(
    'shared quest victory grants its durable flag and followup exactly once',
    () async {
      final map = createPrototypeMap();
      final site = InteractionSite(mapId: map.id, canActivate: (_) => true);
      final step = WorldQuestStep(
        id: 'step.boss',
        interactionId: 'bell',
        site: site,
        dialogue: WorldDialogue(
          id: 'dialogue.bell',
          site: site,
          speaker: 'Keeper',
          lines: ['Recovered.'],
        ),
        encounterId: 'test',
        setsFlag: 'quest.bell_awake',
      );
      final c = AppController(
        loadWorld: () async =>
            session(operations: WorldOperations(questSteps: [step])),
        battles: {'test': battle},
      );
      addTearDown(c.dispose);
      await c.newGame();
      expect(c.openDialogue('bell', expectedRevision: c.revision), isTrue);
      expect(c.beginBattleHandoff(), isTrue);
      expect(c.handoffBattleToLanternLink(encounterId: 'shared-1'), isTrue);
      final remote = c.state;
      expect(
        await c.applyRemoteState(
          remote,
          readOnly: false,
          encounterId: 'shared-1',
          encounterDefinitionId: 'test',
          outcome: BattleOutcome.victory,
        ),
        isTrue,
      );
      expect(c.mode, AppMode.dialogue);
      final token = c.activeDialogue!.token;
      expect(c.state.quests.flags, contains('quest.bell_awake'));
      expect(
        await c.applyRemoteState(
          remote,
          readOnly: false,
          encounterId: 'shared-1',
          encounterDefinitionId: 'test',
          outcome: BattleOutcome.victory,
        ),
        isTrue,
      );
      expect(c.activeDialogue!.token, token);
      for (final paused in [true, false]) {
        expect(
          await c.applyRemoteState(
            remote,
            readOnly: false,
            sessionPaused: paused,
            encounterId: 'shared-1',
            encounterDefinitionId: 'test',
            outcome: BattleOutcome.victory,
          ),
          isTrue,
        );
        expect(c.paused, paused);
        expect(c.activeDialogue!.token, token);
        expect(c.state.quests.flags, contains('quest.bell_awake'));
      }
      expect(c.closeDialogue(token, expectedRevision: c.revision), isTrue);
      expect(c.openDialogue('bell', expectedRevision: c.revision), isFalse);
      expect(c.state.quests.flags, contains('quest.bell_awake'));
      final promoted = AppController(
        loadWorld: () async =>
            session(operations: WorldOperations(questSteps: [step])),
      );
      addTearDown(promoted.dispose);
      expect(
        await promoted.applyRemoteState(
          remote,
          encounterId: 'shared-1',
          encounterDefinitionId: 'test',
          outcome: BattleOutcome.victory,
        ),
        isTrue,
      );
      expect(promoted.state.quests.flags, isNot(contains('quest.bell_awake')));
      expect(
        await promoted.applyRemoteState(
          remote,
          readOnly: false,
          sessionPaused: true,
          encounterId: 'shared-1',
          encounterDefinitionId: 'test',
          outcome: BattleOutcome.victory,
        ),
        isTrue,
      );
      expect(promoted.state.quests.flags, contains('quest.bell_awake'));
      final promotedToken = promoted.activeDialogue!.token;
      expect(
        await promoted.applyRemoteState(
          remote,
          readOnly: false,
          encounterId: 'shared-1',
          encounterDefinitionId: 'test',
          outcome: BattleOutcome.victory,
        ),
        isTrue,
      );
      expect(promoted.activeDialogue!.token, promotedToken);
      expect(promoted.paused, isFalse);
    },
  );

  test(
    'remote collision uses quest flags including the loaded initial area',
    () async {
      final content = DemoContent.decode(
        File('assets/data/lantern_wake.json').readAsStringSync(),
      );
      final world = InteractionWorld(content, useArtwork: true);
      final position = WorldPosition(
        mapId: 'map.tide_cistern',
        x: 625 / 8,
        y: 480 / 8,
      );
      final base = createLanternInitialState(
        content,
        world.maps[position.mapId]!.spawns['entry']!,
      );
      final c = AppController(
        loadWorld: () async => world.session(restored: base),
      );
      addTearDown(c.dispose);
      GameState crossing(Set<String> flags) => GameState(
        position: position,
        party: base.party,
        inventory: base.inventory,
        gold: base.gold,
        quests: QuestFlags(flags: flags, openedChestIds: {}),
      );
      expect(await c.applyRemoteState(crossing({})), isFalse);
      expect(
        await c.applyRemoteState(crossing({'quest.cistern.sluice_open'})),
        isTrue,
      );
      expect(c.state.position.x, position.x);
      expect(c.state.position.y, position.y);
    },
  );
}
