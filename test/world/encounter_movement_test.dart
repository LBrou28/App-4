import 'package:app_4/core/contracts.dart';
import 'package:app_4/world/demo/demo_host.dart';
import 'package:app_4/world/world_controller.dart';
import 'package:app_4/world/world_encounters.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

class Rolls implements EncounterRandom {
  Rolls(this.hit);
  final bool hit;
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    return hit ? 0 : max - 1;
  }
}

class RejectedHost extends DemoWorldHost {
  RejectedHost(super.map);
  @override
  bool updatePosition(
    WorldPosition position, {
    required int expectedRevision,
  }) => false;
}

void main() {
  final map = parseWorldMap('route', [
    '####################',
    '#S.................#',
    '####################',
  ]);
  EncounterStepper policy(Rolls rolls) => EncounterStepper(
    zones: [
      EncounterZone(
        mapId: map.id,
        left: 1,
        top: 1,
        width: 18,
        height: 1,
        definitionId: 'patrol',
        rollDenominator: 2,
        rollThreshold: 1,
      ),
    ],
    random: rolls,
  );

  test('30/60/120 FPS count the same three distance steps', () {
    for (final fps in [30, 60, 120]) {
      final host = DemoWorldHost(map);
      final rolls = Rolls(false);
      final controller = WorldController(
        host: host,
        collision: WorldCollision(map),
        encounters: policy(rolls),
      );
      controller.press('right', WalkDirection.right);
      for (var i = 0; i < fps; i++) {
        controller.advance(1 / fps);
      }
      expect(rolls.calls, 3);
      host.dispose();
    }
  });

  test('idle, wall pushing, and rejected movement produce no rolls', () {
    for (final host in [DemoWorldHost(map), RejectedHost(map)]) {
      final rolls = Rolls(true);
      final controller = WorldController(
        host: host,
        collision: WorldCollision(map),
        encounters: policy(rolls),
      );
      for (var i = 0; i < 100; i++) {
        controller.advance(.1);
      }
      controller.press('left', WalkDirection.left);
      for (var i = 0; i < 100; i++) {
        controller.advance(.1);
      }
      expect(rolls.calls, 0);
      host.dispose();
    }
  });

  test('fresh post-movement revision, single request, return location and cooldown', () {
    final host = DemoWorldHost(map, encounterIds: {'patrol'});
    final rolls = Rolls(true);
    final stepper = policy(rolls);
    final controller = WorldController(
      host: host,
      collision: WorldCollision(map),
      encounters: stepper,
    );
    host.addListener(controller.synchronize);
    controller.press('right', WalkDirection.right);
    for (var i = 0; i < 4; i++) {
      controller.advance(.1);
    }
    expect(host.encounterCount, 1);
    expect(host.revision, 5);
    final captured = host.state.position;
    for (var i = 0; i < 30; i++) {
      controller.advance(.1);
    }
    expect(host.state.position, same(captured));
    expect(
      host.requestEncounter(
        EncounterRequest(definitionId: 'patrol'),
        expectedRevision: host.revision,
      ),
      isFalse,
    );
    host.finishEncounter();
    expect(controller.advance(.1), isFalse);
    expect(host.state.position, same(captured));
    controller.press('right', WalkDirection.right);
    for (var i = 0; i < 10; i++) {
      controller.advance(.1);
    }
    expect(stepper.remainingCooldown, 0);
    expect(host.encounterCount, 1);
    for (var i = 0; i < 4; i++) {
      controller.advance(.1);
    }
    expect(host.encounterCount, 2);
    host.dispose();
  });
}
