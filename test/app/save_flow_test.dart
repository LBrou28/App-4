import 'dart:io';

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/world_operations.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/save/save_codec.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

final class MemorySave implements SaveRepository {
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

WorldSession session() {
  final map = createPrototypeMap();
  final spawn = map.spawns['entry']!;
  return WorldSession(
    map: map,
    initialState: createContractFixture(position: spawn),
    isClear: WorldCollision(map).isClear,
    contentVersion: 'test.content.1',
    validateSavedState: (state) =>
        state.quests.openedChestIds.every((id) => id == 'chest.test'),
    operations: WorldOperations(
      chests: [
        WorldChest(
          id: 'chest.test',
          site: InteractionSite(
            mapId: map.id,
            canActivate: (position) => identical(position, spawn),
          ),
          itemId: 'fixture.item',
          quantity: 3,
        ),
      ],
      itemIds: {'fixture.item'},
    ),
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
  test('B4 island route survives save and Continue in the Cistern', () async {
    final content = DemoContent.decode(
      File('assets/data/lantern_wake.json').readAsStringSync(),
    );
    final world = InteractionWorld(content);
    final saves = MemorySave();
    final c = AppController(
      loadWorld: () async => world.session(),
      saves: saves,
    );
    addTearDown(c.dispose);
    await c.newGame();
    expect(c.state.position, world.maps['map.bellwether']!.spawns['entry']);

    void walkToExit(String id) {
      final exit = world.targets.targets.singleWhere(
        (target) => target.id == id,
      );
      final map = world.maps[exit.mapId]!;
      final collision = WorldCollision(map);
      final start = (c.state.position.x.floor(), c.state.position.y.floor());
      final goal = (exit.x, exit.y);
      final pending = <(int, int)>[start];
      final previous = <(int, int), (int, int)?>{start: null};
      for (var i = 0; i < pending.length && !previous.containsKey(goal); i++) {
        final current = pending[i];
        for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
          final next = (current.$1 + dx, current.$2 + dy);
          if (previous.containsKey(next) ||
              !collision.isClear(
                WorldPosition(
                  mapId: exit.mapId,
                  x: next.$1 + .5,
                  y: next.$2 + .5,
                ),
              )) {
            continue;
          }
          previous[next] = current;
          pending.add(next);
        }
      }
      expect(previous, contains(goal), reason: id);
      final route = <(int, int)>[];
      for (var tile = goal; tile != start; tile = previous[tile]!) {
        route.add(tile);
      }
      for (final tile in route.reversed) {
        expect(
          c.updatePosition(
            WorldPosition(mapId: exit.mapId, x: tile.$1 + .5, y: tile.$2 + .5),
            expectedRevision: c.revision,
          ),
          isTrue,
        );
      }
      expect(c.useMapExit(id, expectedRevision: c.revision), isTrue);
    }

    walkToExit('exit.harbor_to_causeway');
    expect(c.state.position.mapId, 'map.salt_path');
    walkToExit('exit.causeway_to_cistern');
    expect(c.state.position.mapId, 'map.tide_cistern');
    final savedPosition = c.state.position;
    c.setPaused(true);
    expect(await c.saveCurrent(), isA<SaveWritten>());
    c.returnToTitle();
    expect(await c.continueGame(), isA<SaveLoaded>());
    expect(c.state.position.mapId, 'map.tide_cistern');
    expect(c.state.position.x, savedPosition.x);
    expect(c.state.position.y, savedPosition.y);
    walkToExit('exit.cistern_to_causeway');
    expect(c.state.position.mapId, 'map.salt_path');
  });

  test(
    'codec round trips the entire state and rejects bad schema or shape',
    () {
      final state = createContractFixture();
      final source = SaveCodec.encode(
        SaveData(contentVersion: 'test.1', state: state),
      );
      final decoded = SaveCodec.decode(source);
      expect(decoded.contentVersion, 'test.1');
      expect(
        decoded.state.party.map((m) => m.id),
        state.party.map((m) => m.id),
      );
      expect(decoded.state.inventory.quantities, state.inventory.quantities);
      expect(decoded.state.position.x, state.position.x);
      expect(decoded.state.quests.flags, state.quests.flags);
      expect(
        () => SaveCodec.decode(
          source.replaceFirst('"schemaVersion":1', '"schemaVersion":2'),
        ),
        throwsA(isA<UnsupportedSaveVersion>()),
      );
      expect(
        () => SaveCodec.decode(source.replaceFirst('"gold":0', '"gold":-1')),
        throwsArgumentError,
      );
      expect(() => SaveCodec.decode('{}'), throwsFormatException);
    },
  );

  test(
    'chest and battle state survives save, title and Continue exactly once',
    () async {
      final saves = MemorySave();
      final c = AppController(
        loadWorld: () async => session(),
        saves: saves,
        battles: {'test': battle},
      );
      addTearDown(c.dispose);
      await c.newGame();
      expect(c.openChest('chest.test', expectedRevision: c.revision), isTrue);
      expect(c.state.inventory.quantities['fixture.item'], 5);
      expect(
        c.requestEncounter(
          EncounterRequest(definitionId: 'test'),
          expectedRevision: c.revision,
        ),
        isTrue,
      );
      expect(await c.saveCurrent(), isA<SaveWriteFailed>());
      final active = c.activeBattle!;
      active.resolve(active.snapshot.round, [
        for (final hero in active.snapshot.combatants)
          if (hero.side == combat.BattleSide.heroes && hero.isAlive)
            combat.HeroCommand.attack(hero.id, 'enemy'),
      ]);
      expect(c.acceptBattleResult(active.result!), isTrue);
      c.setPaused(true);
      final revisionBeforeSave = c.revision;
      expect(await c.saveCurrent(), isA<SaveWritten>());
      expect(c.revision, revisionBeforeSave);
      c.returnToTitle();
      final oldRevision = c.revision;
      expect(await c.continueGame(), isA<SaveLoaded>());
      expect(c.revision, greaterThan(oldRevision));
      expect(c.state.quests.openedChestIds, {'chest.test'});
      expect(c.state.inventory.quantities['fixture.item'], 5);
      expect(c.openChest('chest.test', expectedRevision: c.revision), isFalse);
      expect(
        c.updatePosition(
          c.state.position,
          expectedRevision: revisionBeforeSave,
        ),
        isFalse,
      );
    },
  );

  test('incompatible and invalid saves do not replace current state', () async {
    final saves = MemorySave();
    final c = AppController(loadWorld: () async => session(), saves: saves);
    addTearDown(c.dispose);
    final original = c.state;
    saves.data = SaveData(
      contentVersion: 'old.content',
      state: createContractFixture(),
    );
    final revision = c.revision;
    expect(
      (await c.continueGame() as SaveUnreadable).reason,
      SaveReadFailure.unsupportedVersion,
    );
    expect(c.state, same(original));
    expect(c.revision, revision);
    saves.data = SaveData(
      contentVersion: 'test.content.1',
      state: createContractFixture(
        position: WorldPosition(mapId: 'fixture.room', x: 1.5, y: 1.5),
      ),
    );
    expect(
      (await c.continueGame() as SaveUnreadable).reason,
      SaveReadFailure.corrupt,
    );
    expect(c.mode, AppMode.title);
    expect(c.revision, revision);
  });
}
