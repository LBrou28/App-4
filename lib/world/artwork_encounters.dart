import 'dart:math';
import 'dart:ui';

import '../core/contracts.dart';
import 'artwork_world.dart';
import 'world_encounters.dart';
import 'world_interactions.dart';

final class WalkingEncounterRandom implements EncounterRandom {
  WalkingEncounterRandom([Random? random]) : _random = random ?? Random();
  final Random _random;
  @override
  int nextInt(int max) => _random.nextInt(max);
}

/// Production walking policy: one check per 64 art pixels, a 192px entry/load
/// grace period, and at least 384px of danger-area travel after each fight.
/// Enemy IDs come from D's map content; C alone supplies combat and rewards.
EncounterStepper artworkEncounters(
  ArtworkWorld world, {
  EncounterRandom? random,
}) {
  final zones = <EncounterZone>[];
  for (final id in [ArtworkWorld.route, ArtworkWorld.dungeon]) {
    final enemies = world.content
        .find('maps', id)
        .strings('enemyIds')
        .where(
          (enemy) =>
              world.content.find('enemies', enemy).text('kind') == 'regular',
        )
        .toList();
    if (enemies.isEmpty) continue;
    final map = world.maps[id]!;
    zones.add(
      EncounterZone(
        mapId: id,
        left: 0,
        top: 0,
        width: map.width,
        height: map.height,
        definitionId: enemies.first,
        alternativeDefinitionIds: List.unmodifiable(enemies.skip(1)),
        rollDenominator: 5,
        rollThreshold: 1,
      ),
    );
  }
  bool safe(WorldPosition p) {
    final scene = ArtworkWorld.scenes[p.mapId];
    if (scene == null || p.mapId == ArtworkWorld.town) return true;
    final feet = scene.pixels(p);
    // The fixed boss owns the beacon chamber. Random battles never interrupt
    // its approach/lantern recovery, even after the sluice has opened.
    if (p.mapId == ArtworkWorld.dungeon &&
        const Rect.fromLTRB(465, 0, 790, 355).contains(feet)) {
      return true;
    }
    for (final spawn in world.maps[p.mapId]!.spawns.values) {
      if ((feet - scene.pixels(spawn)).distance <= 80) return true;
    }
    for (final target in world.targets.targets) {
      if (target.mapId != p.mapId) continue;
      final radius = max(64.0, (target.reachRadius ?? 0) * 8 + 24);
      if ((feet - Offset((target.x + .5) * 8, (target.y + .5) * 8)).distance <=
          radius) {
        return true;
      }
    }
    for (final landmark in world.landmarks) {
      if (landmark.mapId != p.mapId ||
          !{
            WorldLandmarkKind.rest,
            WorldLandmarkKind.shelter,
            WorldLandmarkKind.supplies,
          }.contains(landmark.kind)) {
        continue;
      }
      if ((feet - Offset((landmark.x + .5) * 8, (landmark.y + .5) * 8))
              .distance <=
          80) {
        return true;
      }
    }
    return false;
  }

  return EncounterStepper(
    zones: zones,
    random: random ?? WalkingEncounterRandom(),
    stepDistance: 64 / ArtworkScene.pixelsPerTile,
    initialCooldownSteps: 3,
    cooldownSteps: 6,
    canEncounter: (p) => !safe(p),
  );
}
