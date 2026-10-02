import 'dart:io';

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/integration_preview.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/artwork_world.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/world_interactions.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySave implements SaveRepository {
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
  late InteractionWorld world;
  late ArtworkWorld art;
  setUp(() {
    world = InteractionWorld(
      DemoContent.decode(
        File('assets/data/lantern_wake.json').readAsStringSync(),
      ),
      useArtwork: true,
    );
    art = world.artwork!;
  });

  Set<(int, int)> reached(String mapId, {bool open = false}) {
    final collision = art.collision(
      mapId,
      flags: () => {if (open) ArtworkWorld.sluiceFlag},
    );
    final spawn = world.maps[mapId]!.spawns['entry']!;
    final pending = [(spawn.x.floor(), spawn.y.floor())];
    final seen = <(int, int)>{};
    while (pending.isNotEmpty) {
      final p = pending.removeLast();
      if (seen.contains(p) || p.$1 < 0 || p.$2 < 0) continue;
      final position = WorldPosition(mapId: mapId, x: p.$1 + .5, y: p.$2 + .5);
      if (!collision.isClear(position)) continue;
      seen.add(p);
      for (final (dx, dy) in [(0, 1), (0, -1), (1, 0), (-1, 0)]) {
        pending.add((p.$1 + dx, p.$2 + dy));
      }
    }
    return seen;
  }

  test('every art spawn, exit and pre-boss interaction is reachable', () {
    for (final map in world.maps.values) {
      final cells = reached(map.id);
      final collision = art.collision(map.id);
      for (final spawn in map.spawns.values) {
        expect(
          collision.isClear(spawn),
          isTrue,
          reason: 'spawn ${map.id}: ${spawn.x},${spawn.y}',
        );
        expect(
          cells,
          contains((spawn.x.floor(), spawn.y.floor())),
          reason: map.id,
        );
        expect(
          art.targets.targets.where(
            (t) => t.kind == WorldTargetKind.exit && t.reachable(spawn),
          ),
          isEmpty,
        );
      }
      for (final target in art.targets.targets.where(
        (t) => t.mapId == map.id && t.id != 'quest.cistern.bell',
      )) {
        expect(
          cells.any(
            (p) => target.reachable(
              WorldPosition(mapId: map.id, x: p.$1 + .5, y: p.$2 + .5),
            ),
          ),
          isTrue,
          reason: target.id,
        );
      }
    }
  });

  test('closed sluice isolates the boss; opening joins chamber and keeps other water blocked', () {
    final boss = art.targets.targets.firstWhere(
      (t) => t.id == 'quest.cistern.bell',
    );
    bool canReach(Set<(int, int)> cells) => cells.any(
      (p) => boss.reachable(
        WorldPosition(mapId: boss.mapId, x: p.$1 + .5, y: p.$2 + .5),
      ),
    );
    expect(canReach(reached(ArtworkWorld.dungeon)), isFalse);
    expect(canReach(reached(ArtworkWorld.dungeon, open: true)), isTrue);
    final scene = ArtworkWorld.scenes[ArtworkWorld.dungeon]!;
    final passage = scene.position(const Offset(625, 480));
    expect(art.isClear(passage, {}), isFalse);
    expect(art.isClear(passage, {ArtworkWorld.sluiceFlag}), isTrue);
    expect(
      art.isClear(scene.position(const Offset(800, 820)), {
        ArtworkWorld.sluiceFlag,
      }),
      isFalse,
    );
    // No large movement can jump over a cliff or the closed central gate.
    final before = scene.position(const Offset(627, 560));
    final stop = art.collision(scene.id).move(before, WalkDirection.up, 30);
    expect(scene.pixels(stop).dy, greaterThan(420));
  });

  test('real main host transitions, chest and durable valve survive save/Continue', () async {
    final saves = MemorySave();
    final initial = createLanternInitialState(
      art.content,
      world.maps[ArtworkWorld.town]!.spawns['entry']!,
    );
    final host = AppController(
      loadWorld: () async => world.session(restored: initial),
      saves: saves,
    );
    addTearDown(host.dispose);
    await host.newGame();
    expect(host.mode, AppMode.exploration);
    WorldPosition approach(String id) {
      final target = art.targets.targets.firstWhere((t) => t.id == id);
      final cells = reached(
        target.mapId,
        open: host.state.quests.flags.contains(ArtworkWorld.sluiceFlag),
      );
      final candidates = cells
          .map(
            (p) =>
                WorldPosition(mapId: target.mapId, x: p.$1 + .5, y: p.$2 + .5),
          )
          .where(target.reachable)
          .toList();
      candidates.sort(
        (a, b) =>
            ((a.x - target.x) * (a.x - target.x) +
                    (a.y - target.y) * (a.y - target.y))
                .compareTo(
                  (b.x - target.x) * (b.x - target.x) +
                      (b.y - target.y) * (b.y - target.y),
                ),
      );
      return candidates.first;
    }

    void move(String id) => expect(
      host.updatePosition(approach(id), expectedRevision: host.revision),
      isTrue,
      reason: id,
    );
    void exit(String id) {
      move(id);
      expect(host.useMapExit(id, expectedRevision: host.revision), isTrue);
    }

    exit('exit.harbor_to_causeway');
    move('chest.causeway_supplies');
    expect(
      host.openChest(
        'chest.causeway_supplies',
        expectedRevision: host.revision,
      ),
      isTrue,
    );
    final salves = host.state.inventory.quantities['item.salves'];
    expect(
      host.openChest(
        'chest.causeway_supplies',
        expectedRevision: host.revision,
      ),
      isFalse,
    );
    exit('exit.causeway_to_cistern');
    final scene = ArtworkWorld.scenes[ArtworkWorld.dungeon]!;
    final passage = scene.position(const Offset(625, 480));
    expect(
      host.updatePosition(passage, expectedRevision: host.revision),
      isFalse,
    );
    move('quest.cistern.valve');
    expect(
      host.openDialogue('quest.cistern.valve', expectedRevision: host.revision),
      isTrue,
    );
    final cancelled = host.activeDialogue!.token;
    expect(
      host.closeDialogue(cancelled, expectedRevision: host.revision),
      isTrue,
    );
    expect(host.state.quests.flags, isNot(contains(ArtworkWorld.sluiceFlag)));
    expect(
      host.openDialogue('quest.cistern.valve', expectedRevision: host.revision),
      isTrue,
    );
    expect(
      host.completeDialogue(
        host.activeDialogue!.token,
        expectedRevision: host.revision,
      ),
      isTrue,
    );
    expect(
      host.updatePosition(passage, expectedRevision: host.revision),
      isTrue,
    );
    host.setPaused(true);
    expect(await host.saveCurrent(), isA<SaveWritten>());
    host.returnToTitle();
    expect(await host.continueGame(), isA<SaveLoaded>());
    expect(host.state.quests.flags, contains(ArtworkWorld.sluiceFlag));
    expect(host.state.position.x, passage.x);
    expect(host.state.inventory.quantities['item.salves'], salves);
    exit('exit.cistern_to_causeway');
    exit('exit.causeway_to_harbor');
    expect(
      host.state.position,
      same(world.maps[ArtworkWorld.town]!.spawns['from_causeway']),
    );
    // A saved position in the center cannot be restored without its gate flag.
    saves.data = SaveData(
      contentVersion: art.content.version,
      state: GameState(
        position: passage,
        party: host.state.party,
        inventory: host.state.inventory,
        gold: host.state.gold,
        quests: QuestFlags(flags: {}, openedChestIds: {}),
      ),
    );
    host.returnToTitle();
    expect(await host.continueGame(), isA<SaveUnreadable>());
    expect(host.mode, AppMode.title);
  });
}
