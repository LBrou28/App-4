import 'dart:io';

import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final world = InteractionWorld(
    DemoContent.decode(File('assets/data/lantern_wake.json').readAsStringSync()),
  );

  Set<(int, int)> reachableTiles(String mapId) {
    final map = world.maps[mapId]!;
    final collision = WorldCollision(map);
    final pending = [
      (map.spawns['entry']!.x.floor(), map.spawns['entry']!.y.floor()),
    ];
    final reached = <(int, int)>{};
    while (pending.isNotEmpty) {
      final tile = pending.removeLast();
      if (reached.contains(tile) ||
          !collision.isClear(
            WorldPosition(mapId: mapId, x: tile.$1 + .5, y: tile.$2 + .5),
          )) {
        continue;
      }
      reached.add(tile);
      for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        pending.add((tile.$1 + dx, tile.$2 + dy));
      }
    }
    return reached;
  }

  test('tutorial-island landmarks are named, clear, and reachable', () {
    final expectedLabels = {
      'map.bellwether': {'Rest house', 'Harbor lantern', 'Eastern dock'},
      'map.salt_path': {'Supply spur', 'Sheltered bench'},
      'map.tide_cistern': {'Rest alcove', 'Marked threshold', 'Bell chamber'},
    };

    for (final entry in expectedLabels.entries) {
      final reached = reachableTiles(entry.key);
      final mapLandmarks = world.landmarks
          .where((landmark) => landmark.mapId == entry.key)
          .toList();
      expect(mapLandmarks.map((landmark) => landmark.label).toSet(), entry.value);
      for (final landmark in mapLandmarks) {
        expect(reached, contains((landmark.x, landmark.y)), reason: landmark.id);
      }
    }
  });

  test('the authored maps preserve the return path between each tutorial area', () {
    final exits = {
      for (final target in world.targets.targets.where(
        (target) => target.id.startsWith('exit.'),
      ))
        target.id: target,
    };

    expect(exits['exit.harbor_to_causeway']!.mapId, 'map.bellwether');
    expect(exits['exit.causeway_to_harbor']!.mapId, 'map.salt_path');
    expect(exits['exit.causeway_to_cistern']!.mapId, 'map.salt_path');
    expect(exits['exit.cistern_to_causeway']!.mapId, 'map.tide_cistern');
    for (final exit in exits.values) {
      expect(
        reachableTiles(exit.mapId),
        contains((exit.x, exit.y)),
        reason: exit.id,
      );
    }
  });
}
