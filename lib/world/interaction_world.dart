import '../app/app_controller.dart';
import '../app/content_operations.dart';
import '../app/world_operations.dart';
import '../core/contracts.dart';
import '../core/fixtures/contract_fixture.dart';
import '../ui/content/demo_content.dart';
import 'world_interactions.dart';
import 'world_map.dart';

/// B4's playable tutorial-island geometry. It deliberately supplies no new
/// story effects; D's content and A's operations own those later handoffs.
final class InteractionWorld {
  InteractionWorld(DemoContent content) {
    _content = content;
    WorldTarget target(
      String id,
      String map,
      int x,
      int y,
      WorldTargetKind kind,
      String label,
    ) => WorldTarget(id: id, mapId: map, x: x, y: y, kind: kind, label: label);
    const town = 'map.bellwether';
    const route = 'map.salt_path';
    const dungeon = 'map.tide_cistern';
    targets = WorldInteractions([
      target(
        'npc.mara',
        town,
        11,
        7,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.mara'),
      ),
      target(
        'npc.orrin',
        town,
        5,
        9,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.orrin'),
      ),
      target(
        'npc.sable',
        route,
        8,
        10,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.sable'),
      ),
      target(
        'chest.causeway_supplies',
        route,
        9,
        3,
        WorldTargetKind.chest,
        'Supply chest',
      ),
      target(
        'exit.harbor_to_causeway',
        town,
        22,
        8,
        WorldTargetKind.exit,
        'Saltglass Causeway',
      ),
      target(
        'exit.causeway_to_harbor',
        route,
        3,
        15,
        WorldTargetKind.exit,
        'Bellwether Harbor',
      ),
      target(
        'exit.causeway_to_cistern',
        route,
        26,
        8,
        WorldTargetKind.exit,
        'Tide Cistern',
      ),
      target(
        'exit.cistern_to_causeway',
        dungeon,
        1,
        9,
        WorldTargetKind.exit,
        'Saltglass Causeway',
      ),
    ]);
    landmarks = List.unmodifiable([
      WorldLandmark(
        id: 'landmark.bellwether.rest_house',
        mapId: town,
        x: 4,
        y: 4,
        label: 'Rest house',
        kind: WorldLandmarkKind.rest,
      ),
      WorldLandmark(
        id: 'landmark.bellwether.lantern',
        mapId: town,
        x: 11,
        y: 6,
        label: 'Harbor lantern',
        kind: WorldLandmarkKind.lantern,
      ),
      WorldLandmark(
        id: 'landmark.bellwether.dock',
        mapId: town,
        x: 19,
        y: 8,
        label: 'Eastern dock',
        kind: WorldLandmarkKind.dock,
      ),
      WorldLandmark(
        id: 'landmark.saltglass.supplies',
        mapId: route,
        x: 9,
        y: 4,
        label: 'Supply spur',
        kind: WorldLandmarkKind.supplies,
      ),
      WorldLandmark(
        id: 'landmark.saltglass.shelter',
        mapId: route,
        x: 8,
        y: 11,
        label: 'Sheltered bench',
        kind: WorldLandmarkKind.shelter,
      ),
      WorldLandmark(
        id: 'landmark.cistern.rest',
        mapId: dungeon,
        x: 5,
        y: 4,
        label: 'Rest alcove',
        kind: WorldLandmarkKind.rest,
      ),
      WorldLandmark(
        id: 'landmark.cistern.threshold',
        mapId: dungeon,
        x: 16,
        y: 9,
        label: 'Marked threshold',
        kind: WorldLandmarkKind.threshold,
      ),
      WorldLandmark(
        id: 'landmark.cistern.bell',
        mapId: dungeon,
        x: 20,
        y: 9,
        label: 'Bell chamber',
        kind: WorldLandmarkKind.bell,
      ),
    ]);
    maps = Map.unmodifiable({
      town: _map(
        town,
        24,
        16,
        {'entry': (19, 8), 'from_causeway': (19, 8)},
        {
          for (var x = 2; x <= 7; x++)
            if (x != 4) ...{(x, 2), (x, 6)},
          for (var y = 3; y <= 5; y++) ...{(2, y), (7, y)},
          for (var x = 14; x <= 17; x++) ...{(x, 3), (x, 12)},
          for (var y = 4; y <= 11; y++) ...{(14, y), (17, y)},
        },
      ),
      route: _map(
        route,
        28,
        18,
        {'entry': (3, 13), 'from_harbor': (3, 13), 'from_cistern': (24, 8)},
        {
          for (var x = 12; x <= 16; x++)
            for (var y = 5; y <= 12; y++) (x, y),
          for (var x = 5; x <= 7; x++) ...{(x, 6), (x, 8)},
          for (var y = 7; y <= 8; y++) (5, y),
        },
      ),
      dungeon: _map(
        dungeon,
        24,
        18,
        {'entry': (3, 9), 'from_causeway': (3, 9)},
        {
          for (var y = 1; y < 17; y++)
            if (y != 8 && y != 9) (10, y),
          for (var x = 3; x <= 7; x++)
            if (x != 5) ...{(x, 2), (x, 6)},
          for (var y = 3; y <= 5; y++) ...{(3, y), (7, y)},
          for (var x = 18; x <= 21; x++) ...{(x, 6), (x, 12)},
          for (var y = 7; y <= 11; y++)
            if (y != 9) ...{(18, y), (21, y)},
        },
      ),
    });
    names = Map.unmodifiable({
      for (final id in maps.keys) id: content.find('maps', id).name,
    });
    final byId = {for (final t in targets.targets) t.id: t};
    InteractionSite site(WorldTarget t) =>
        InteractionSite(mapId: t.mapId, canActivate: t.reachable);
    MapExit exit(String id, String to, String spawn) => MapExit(
      id: id,
      site: site(byId[id]!),
      destinationMapId: to,
      spawnId: spawn,
    );
    operations = contentOperations(
      content: content,
      sites: {
        for (final t in targets.targets)
          if (t.kind != WorldTargetKind.exit) t.id: site(t),
      },
      areas: [
        for (final map in maps.values)
          WorldArea(map: map, isClear: WorldCollision(map).isClear),
      ],
      exits: [
        exit('exit.harbor_to_causeway', route, 'from_harbor'),
        exit('exit.causeway_to_harbor', town, 'from_causeway'),
        exit('exit.causeway_to_cistern', dungeon, 'from_causeway'),
        exit('exit.cistern_to_causeway', route, 'from_cistern'),
      ],
    );
    for (final t in targets.targets) {
      final map = maps[t.mapId]!;
      if (t.x >= map.width || t.y >= map.height) {
        throw StateError('Target outside map: ${t.id}');
      }
      if (t.kind == WorldTargetKind.exit &&
          !WorldCollision(
            map,
          ).isClear(WorldPosition(mapId: t.mapId, x: t.x + .5, y: t.y + .5))) {
        throw StateError('Exit is blocked: ${t.id}');
      }
    }
  }

  late final WorldInteractions targets;
  late final List<WorldLandmark> landmarks;
  late final DemoContent _content;
  late final Map<String, MapDefinition> maps;
  late final Map<String, String> names;
  late final WorldOperations operations;

  MapDefinition _map(
    String id,
    int width,
    int height,
    Map<String, (int, int)> spawns,
    Set<(int, int)> walls,
  ) {
    final solids = {
      ...walls,
      for (final t in targets.targets)
        if (t.mapId == id && t.kind != WorldTargetKind.exit) (t.x, t.y),
    };
    return MapDefinition(
      id: id,
      width: width,
      height: height,
      blocked: [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            x == 0 ||
                y == 0 ||
                x == width - 1 ||
                y == height - 1 ||
                solids.contains((x, y)),
      ],
      spawns: {
        for (final s in spawns.entries)
          s.key: WorldPosition(
            mapId: id,
            x: s.value.$1 + .5,
            y: s.value.$2 + .5,
          ),
      },
    );
  }

  /// The fixture party is retained until C supplies real stat/state mappings.
  WorldSession session({GameState? restored}) {
    final map = maps[restored?.position.mapId ?? 'map.bellwether']!;
    return WorldSession(
      map: map,
      initialState:
          restored ?? createContractFixture(position: map.spawns['entry']!),
      isClear: WorldCollision(map).isClear,
      operations: operations,
      contentVersion: _content.version,
      validateSavedState: (state) {
        final ids = _content.sharedItems.keys.toSet()..add('fixture.item');
        final jobs = _content.sharedJobs.keys.toSet()..add('fixture.job');
        return state.inventory.quantities.keys.every(ids.contains) &&
            state.party.every(
              (member) =>
                  jobs.contains(member.jobId) &&
                  member.jobProgress.keys.every(jobs.contains) &&
                  member.equipment.values.every(ids.contains),
            ) &&
            state.quests.flags.every(_content.flags.contains) &&
            state.quests.openedChestIds.every(operations.chests.containsKey);
      },
    );
  }
}
