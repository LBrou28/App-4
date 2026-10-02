import 'dart:ui';

import '../app/content_operations.dart';
import '../app/world_operations.dart';
import '../core/contracts.dart';
import '../ui/content/demo_content.dart';
import 'harbor_geometry.dart';
import 'causeway_geometry.dart';
import 'cistern_geometry.dart';
import 'world_map.dart';
import 'world_interactions.dart';

/// Art coordinates, collision and markers share one 8px tile-space transform.
/// The grid is catalog/save metadata; movement uses the reviewed polygons.
class ArtworkScene {
  const ArtworkScene(this.id, this.asset, this.size);
  final String id;
  final String asset;
  final Size size;
  static const pixelsPerTile = 8.0;
  static const zoom = 1.5;
  static const displayTile = pixelsPerTile * zoom;
  Offset pixels(WorldPosition p) => Offset(p.x, p.y) * pixelsPerTile;
  WorldPosition position(Offset pixels) => WorldPosition(
    mapId: id,
    x: pixels.dx / pixelsPerTile,
    y: pixels.dy / pixelsPerTile,
  );
  Size get displaySize => size * zoom;
}

class ArtworkWorld {
  ArtworkWorld(this.content) {
    WorldTarget target(
      String id,
      String map,
      double px,
      double py,
      WorldTargetKind kind,
      String label, {
      double reach = 36,
    }) => WorldTarget(
      id: id,
      mapId: map,
      x: (px / 8).floor(),
      y: (py / 8).floor(),
      kind: kind,
      label: label,
      reachRadius: reach / 8,
    );
    targets = WorldInteractions([
      target(
        'npc.mara',
        town,
        640,
        462,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.mara'),
      ),
      target(
        'npc.orrin',
        town,
        302,
        532,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.orrin'),
      ),
      target(
        'npc.sable',
        route,
        350,
        748,
        WorldTargetKind.npc,
        content.label('npcs', 'npc.sable'),
      ),
      target(
        'chest.causeway_supplies',
        route,
        440,
        688,
        WorldTargetKind.chest,
        'Supply chest',
        reach: 56,
      ),
      target(
        'quest.cistern.threshold',
        dungeon,
        625,
        579,
        WorldTargetKind.quest,
        'Beacon chamber approach',
      ),
      target(
        'quest.cistern.valve',
        dungeon,
        265,
        154,
        WorldTargetKind.quest,
        'Turn northwest valve',
        reach: 56,
      ),
      target(
        'quest.cistern.bell',
        dungeon,
        625,
        238,
        WorldTargetKind.quest,
        'The Hollow Bell',
        reach: 40,
      ),
      target(
        'exit.harbor_to_causeway',
        town,
        596,
        20,
        WorldTargetKind.exit,
        'Saltglass Causeway',
        reach: 12,
      ),
      target(
        'exit.causeway_to_harbor',
        route,
        612,
        1236,
        WorldTargetKind.exit,
        'Bellwether Harbor',
        reach: 12,
      ),
      target(
        'exit.causeway_to_cistern',
        route,
        1196,
        20,
        WorldTargetKind.exit,
        'Tide Cistern',
        reach: 12,
      ),
      target(
        'exit.cistern_to_causeway',
        dungeon,
        80,
        1236,
        WorldTargetKind.exit,
        'Saltglass Causeway',
        reach: 12,
      ),
    ]);
    WorldLandmark landmark(
      String id,
      String map,
      double px,
      double py,
      String label,
      WorldLandmarkKind kind,
    ) => WorldLandmark(
      id: id,
      mapId: map,
      x: (px / 8).floor(),
      y: (py / 8).floor(),
      label: label,
      kind: kind,
    );
    landmarks = List.unmodifiable([
      landmark(
        'landmark.bellwether.rest_house',
        town,
        305,
        577,
        'Rest house',
        WorldLandmarkKind.rest,
      ),
      landmark(
        'landmark.bellwether.lantern',
        town,
        650,
        512,
        'Harbor lantern shrine',
        WorldLandmarkKind.lantern,
      ),
      landmark(
        'landmark.bellwether.dock',
        town,
        647,
        824,
        'Southern dock',
        WorldLandmarkKind.dock,
      ),
      landmark(
        'landmark.saltglass.supplies',
        route,
        481,
        711,
        'Supply campsite',
        WorldLandmarkKind.supplies,
      ),
      landmark(
        'landmark.saltglass.shelter',
        route,
        292,
        737,
        'Camp shelter',
        WorldLandmarkKind.shelter,
      ),
      landmark(
        'landmark.cistern.rest',
        dungeon,
        180,
        675,
        'Rest alcove',
        WorldLandmarkKind.rest,
      ),
      landmark(
        'landmark.cistern.threshold',
        dungeon,
        622,
        602,
        'Beacon approach',
        WorldLandmarkKind.threshold,
      ),
      landmark(
        'landmark.cistern.bell',
        dungeon,
        623,
        121,
        'Beacon lantern',
        WorldLandmarkKind.lantern,
      ),
    ]);
    maps = Map.unmodifiable({
      for (final scene in scenes.values)
        scene.id: _map(scene, switch (scene.id) {
          town => {
            'entry': HarborGeometry.spawn,
            'from_causeway': const Offset(695, 165),
          },
          route => {
            'entry': CausewayGeometry.spawn,
            'from_harbor': CausewayGeometry.spawn,
            'from_cistern': const Offset(1188, 76),
          },
          _ => {
            'entry': CisternGeometry.spawn,
            'from_causeway': CisternGeometry.spawn,
          },
        }),
    });
    names = Map.unmodifiable({
      for (final id in scenes.keys) id: content.find('maps', id).name,
    });
    final byId = {for (final target in targets.targets) target.id: target};
    InteractionSite site(String id) => InteractionSite(
      mapId: byId[id]!.mapId,
      canActivate: byId[id]!.reachable,
    );
    QuestPlacement placement(String id) =>
        QuestPlacement(interactionId: id, site: site(id));
    final authored = contentOperations(
      content: content,
      sites: {
        for (final t in targets.targets)
          if (t.kind == WorldTargetKind.npc || t.kind == WorldTargetKind.chest)
            t.id: site(t.id),
      },
      questPlacements: {
        'step.accept': placement('npc.mara'),
        'step.prepare': placement('npc.sable'),
        'step.enter': placement('quest.cistern.threshold'),
        'step.valve': placement('quest.cistern.valve'),
        'step.bell': placement('quest.cistern.bell'),
        'step.return': placement('npc.mara'),
      },
      areas: [
        for (final map in maps.values)
          WorldArea(
            map: map,
            isClear: (p) => isClear(p, const {}),
            isClearWithQuests: (p, quests) => isClear(p, quests.flags),
          ),
      ],
      exits: [
        MapExit(
          id: 'exit.harbor_to_causeway',
          site: site('exit.harbor_to_causeway'),
          destinationMapId: route,
          spawnId: 'from_harbor',
        ),
        MapExit(
          id: 'exit.causeway_to_harbor',
          site: site('exit.causeway_to_harbor'),
          destinationMapId: town,
          spawnId: 'from_causeway',
        ),
        MapExit(
          id: 'exit.causeway_to_cistern',
          site: site('exit.causeway_to_cistern'),
          destinationMapId: dungeon,
          spawnId: 'from_causeway',
        ),
        MapExit(
          id: 'exit.cistern_to_causeway',
          site: site('exit.cistern_to_causeway'),
          destinationMapId: route,
          spawnId: 'from_cistern',
        ),
      ],
    );
    // The boss remains unavailable until the same durable flag opens its route.
    operations = WorldOperations(
      areas: authored.areas.values.toList(),
      exits: authored.exits.values.toList(),
      dialogues: authored.dialogues.values.toList(),
      chests: authored.chests.values.toList(),
      itemIds: content.sharedItems.keys.toSet(),
      questSteps: [
        for (final step in authored.questSteps.values)
          if (step.id != 'step.bell')
            step
          else
            WorldQuestStep(
              id: step.id,
              interactionId: step.interactionId,
              site: step.site,
              dialogue: step.dialogue,
              requiresFlags: {...step.requiresFlags, sluiceFlag},
              setsFlag: step.setsFlag,
              encounterId: step.encounterId,
            ),
      ],
    );
  }
  static const town = 'map.bellwether',
      route = 'map.salt_path',
      dungeon = 'map.tide_cistern';
  static const sluiceFlag = 'quest.cistern.sluice_open';
  static const scenes = <String, ArtworkScene>{
    town: ArtworkScene(
      town,
      'assets/maps/bellwether_harbor_paths_v3.png',
      HarborGeometry.size,
    ),
    route: ArtworkScene(
      route,
      'assets/maps/saltglass_causeway_green_removed.png',
      CausewayGeometry.size,
    ),
    dungeon: ArtworkScene(
      dungeon,
      'assets/maps/drowned_cistern_paths_v2.png',
      CisternGeometry.size,
    ),
  };
  final DemoContent content;
  final _harbor = HarborGeometry();
  final _causeway = CausewayGeometry();
  final _closed = CisternGeometry();
  final _open = CisternGeometry(sluiceOpen: true);
  late final WorldInteractions targets;
  late final List<WorldLandmark> landmarks;
  late final Map<String, MapDefinition> maps;
  late final Map<String, String> names;
  late final WorldOperations operations;

  bool _terrainClear(String id, Offset p, bool open) => switch (id) {
    town => _harbor.isClear(p),
    route => _causeway.isClear(p),
    dungeon => (open ? _open : _closed).isClear(p),
    _ => false,
  };
  bool isClear(WorldPosition p, Set<String> flags) {
    final scene = scenes[p.mapId];
    if (scene == null || !p.x.isFinite || !p.y.isFinite) return false;
    final feet = scene.pixels(p);
    if (!_terrainClear(p.mapId, feet, flags.contains(sluiceFlag))) return false;
    // Placeholder NPC/boss bodies occupy a small foot-sized spot, never a
    // whole coarse legacy tile. Static chests/valve already have art solids.
    for (final target in targets.targets.where(
      (t) =>
          t.mapId == p.mapId &&
          (t.kind == WorldTargetKind.npc || t.id == 'quest.cistern.bell'),
    )) {
      if ((feet - Offset((target.x + .5) * 8, (target.y + .5) * 8)).distance <
          14) {
        return false;
      }
    }
    return true;
  }

  WorldCollision collision(String id, {Set<String> Function()? flags}) =>
      WorldCollision(
        maps[id]!,
        clearance: (p) => isClear(p, flags?.call() ?? const {}),
        sweep: (p, direction, distance) {
          final travel = distance
              .clamp(0.0, maps[id]!.width + maps[id]!.height)
              .toDouble();
          final delta = switch (direction) {
            WalkDirection.up => Offset(0, -travel),
            WalkDirection.down => Offset(0, travel),
            WalkDirection.left => Offset(-travel, 0),
            WalkDirection.right => Offset(travel, 0),
          };
          var result = p;
          final steps = (travel * 8 / 2).ceil().clamp(1, 100000);
          for (var i = 0; i < steps; i++) {
            final next = WorldPosition(
              mapId: id,
              x: result.x + delta.dx / steps,
              y: result.y + delta.dy / steps,
            );
            if (!isClear(next, flags?.call() ?? const {})) break;
            result = next;
          }
          return result;
        },
      );

  MapDefinition _map(ArtworkScene scene, Map<String, Offset> spawns) {
    final width = (scene.size.width / 8).ceil(),
        height = (scene.size.height / 8).ceil();
    return MapDefinition(
      id: scene.id,
      width: width,
      height: height,
      blocked: [
        for (var y = 0; y < height; y++)
          for (var x = 0; x < width; x++)
            !isClear(WorldPosition(mapId: scene.id, x: x + .5, y: y + .5), {
              sluiceFlag,
            }),
      ],
      spawns: {for (final s in spawns.entries) s.key: scene.position(s.value)},
    );
  }
}
