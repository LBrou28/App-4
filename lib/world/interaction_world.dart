import '../app/app_controller.dart';
import '../app/content_operations.dart';
import '../app/world_operations.dart';
import '../core/contracts.dart';
import '../core/fixtures/contract_fixture.dart';
import '../ui/content/demo_content.dart';
import 'world_interactions.dart';
import 'world_map.dart';

/// Playable B2/B3 geometry, not the final B4 map/art pass.
final class InteractionWorld {
  InteractionWorld(DemoContent content) {
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
        4,
        5,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.mara'),
      ),
      target(
        'npc.orrin',
        town,
        2,
        7,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.orrin'),
      ),
      target(
        'npc.sable',
        route,
        7,
        8,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.sable'),
      ),
      target(
        'chest.causeway_supplies',
        route,
        9,
        2,
        WorldTargetKind.chest,
        'Supply chest',
      ),
      target(
        'exit.harbor_to_causeway',
        town,
        16,
        6,
        WorldTargetKind.exit,
        'Saltglass Causeway',
      ),
      target(
        'exit.causeway_to_harbor',
        route,
        3,
        12,
        WorldTargetKind.exit,
        'Bellwether Harbor',
      ),
      target(
        'exit.causeway_to_cistern',
        route,
        20,
        6,
        WorldTargetKind.exit,
        'Tide Cistern',
      ),
      target(
        'exit.cistern_to_causeway',
        dungeon,
        1,
        6,
        WorldTargetKind.exit,
        'Saltglass Causeway',
      ),
    ]);
    maps = Map.unmodifiable({
      town: _map(
        town,
        18,
        12,
        {'entry': (4, 6), 'from_causeway': (14, 6)},
        {(10, 3), (11, 3), (10, 4), (11, 4), (10, 8), (11, 8)},
      ),
      route: _map(
        route,
        22,
        14,
        {'entry': (3, 10), 'from_harbor': (3, 10), 'from_cistern': (18, 6)},
        {
          for (var x = 10; x <= 13; x++)
            for (var y = 5; y <= 8; y++) (x, y),
        },
      ),
      dungeon: _map(
        dungeon,
        18,
        14,
        {'entry': (3, 6), 'from_causeway': (3, 6)},
        {
          for (var y = 1; y < 13; y++)
            if (y != 6 && y != 7) (8, y),
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
    );
  }
}
