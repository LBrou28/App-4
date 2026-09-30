import 'dart:ui';

import 'package:app_4/core/contracts.dart';
import 'package:app_4/world/demo/demo_host.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_camera.dart';
import 'package:app_4/world/world_controller.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

class RejectingHost extends DemoWorldHost {
  RejectingHost(super.map);
  @override
  bool updatePosition(
    WorldPosition position, {
    required int expectedRevision,
  }) => false;
}

void main() {
  final map = createPrototypeMap();
  late DemoWorldHost host;
  late WorldController controller;
  setUp(() {
    host = DemoWorldHost(map);
    controller = WorldController(host: host, collision: WorldCollision(map));
    host.addListener(controller.synchronize);
  });
  tearDown(() => host.dispose());

  test('equal time at 30/60/120 FPS covers equal distance', () {
    for (final fps in [30, 60, 120]) {
      host.reset();
      controller.clearInput();
      controller.press('right', WalkDirection.right);
      for (var i = 0; i < fps; i++) {
        controller.advance(1 / fps);
      }
      expect(host.state.position.x, closeTo(5.5, 1e-9));
      expect(host.state.position.y, 2.5);
    }
  });

  test('latest direction wins; releasing one source preserves other input', () {
    controller.press('arrow', WalkDirection.right);
    controller.press('touch', WalkDirection.down);
    controller.advance(.1);
    expect(host.state.position.x, 2.5);
    expect(host.state.position.y, closeTo(2.8, 1e-9));
    controller.release('touch');
    controller.advance(.1);
    expect(host.state.position.x, closeTo(2.8, 1e-9));
    controller.release('arrow');
    expect(controller.advance(.1), isFalse);
  });

  test(
    'every movement gate clears held input and resume does not replay it',
    () {
      for (final gate in DemoGate.values.where(
        (gate) => gate != DemoGate.exploration,
      )) {
        controller.press('key', WalkDirection.right);
        host.setGate(gate);
        final p = host.state.position;
        expect(controller.advance(.1), isFalse);
        controller.press('key', WalkDirection.right);
        host.setGate(DemoGate.exploration);
        expect(controller.advance(.1), isFalse);
        expect(host.state.position, same(p));
      }
    },
  );

  test('stall time is discarded and input reset prevents catch-up', () {
    controller.press('key', WalkDirection.right);
    controller.advance(10);
    expect(host.state.position.x, closeTo(2.8, 1e-9));
    controller.clearInput();
    expect(controller.advance(10), isFalse);
    expect(controller.advance(double.nan), isFalse);
  });

  test('rejected movement never creates optimistic world state', () {
    final rejected = RejectingHost(map);
    final control = WorldController(
      host: rejected,
      collision: WorldCollision(map),
    );
    control.press('key', WalkDirection.right);
    expect(control.advance(.1), isFalse);
    expect(rejected.state.position.x, 2.5);
    expect(rejected.revision, 0);
    rejected.dispose();
  });

  test('test host publishes coherent state synchronously and rejects stale/reentrant writes', () {
    var notifications = 0;
    host.addListener(() {
      notifications++;
      expect(host.revision, 1);
      expect(host.state.position.x, 3);
      expect(
        host.updatePosition(
          map.spawns['entry']!,
          expectedRevision: host.revision,
        ),
        isFalse,
      );
    });
    final next = WorldPosition(mapId: map.id, x: 3, y: 2.5);
    expect(host.updatePosition(next, expectedRevision: 0), isTrue);
    expect(notifications, 1);
    expect(host.updatePosition(next, expectedRevision: 0), isFalse);
    expect(notifications, 1);
  });

  test(
    'reset and gate transitions retain a monotonically increasing revision',
    () {
      host.setGate(DemoGate.loading);
      expect(host.revision, 1);
      host.reset();
      expect(host.revision, 2);
      expect(
        host.updatePosition(map.spawns['entry']!, expectedRevision: 0),
        isFalse,
      );
      expect(
        host.requestEncounter(
          EncounterRequest(definitionId: 'unknown'),
          expectedRevision: 2,
        ),
        isFalse,
      );
      expect(host.revision, 2);
    },
  );

  test(
    'camera clamps all corners and centers a map smaller than its viewport',
    () {
      for (final player in [Offset.zero, const Offset(1000, 800)]) {
        final camera = worldCameraOffset(
          viewport: const Size(500, 400),
          mapSize: const Size(1000, 800),
          player: player,
        );
        expect(camera.dx, inInclusiveRange(-500, 0));
        expect(camera.dy, inInclusiveRange(-400, 0));
      }
      expect(
        worldCameraOffset(
          viewport: const Size(1200, 900),
          mapSize: const Size(768, 576),
          player: const Offset(100, 100),
        ),
        const Offset(216, 162),
      );
    },
  );
}
