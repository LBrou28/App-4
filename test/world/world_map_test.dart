import 'package:app_4/core/contracts.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final map = createPrototypeMap();
  final collision = WorldCollision(map);
  WorldPosition at(double x, double y) =>
      WorldPosition(mapId: map.id, x: x, y: y);

  test('prototype preserves the planned geometry and tile-center spawn', () {
    expect(map.width, 16);
    expect(map.height, 12);
    expect(map.blocked.where((blocked) => !blocked), hasLength(130));
    expect(map.spawns['entry']!.x, 2.5);
    expect(map.spawns['entry']!.y, 2.5);
  });

  test('map input rejects malformed geometry and ambiguous spawns', () {
    for (final rows in <List<String>>[
      [],
      [''],
      ['S.', '.'],
      ['SS'],
      ['..'],
      ['SX'],
    ]) {
      expect(() => parseWorldMap('bad', rows), throwsFormatException);
    }
  });

  test(
    'full footprint rejects wall overlap even when center tile is clear',
    () {
      expect(collision.isClear(at(6.9, 4.5)), isFalse);
      expect(collision.isClear(at(6.72, 4.5)), isTrue);
      expect(collision.isClear(at(.1, .1)), isFalse);
      expect(
        collision.isClear(WorldPosition(mapId: 'other', x: 2.5, y: 2.5)),
        isFalse,
      );
      expect(
        () => WorldCollision(
          MapDefinition(
            id: 'bad',
            width: 2,
            height: 1,
            blocked: [false, true],
            spawns: {'entry': WorldPosition(mapId: 'bad', x: .9, y: .5)},
          ),
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'moves in all four directions and stops precisely at perimeter walls',
    () {
      final p = at(2.5, 2.5);
      expect(collision.move(p, WalkDirection.up, .5).y, 2);
      expect(collision.move(p, WalkDirection.down, .5).y, 3);
      expect(collision.move(p, WalkDirection.left, .5).x, 2);
      expect(collision.move(p, WalkDirection.right, .5).x, 3);
      expect(collision.move(p, WalkDirection.left, 100).x, closeTo(1.28, 1e-9));
      expect(collision.move(p, WalkDirection.up, 100).y, closeTo(1.28, 1e-9));
      expect(
        collision.move(p, WalkDirection.right, 100).x,
        closeTo(14.72, 1e-9),
      );
      expect(
        collision.move(p, WalkDirection.down, 100).y,
        closeTo(10.72, 1e-9),
      );
    },
  );

  test('sweeps cannot tunnel through interior walls or clip corners', () {
    expect(
      collision.move(at(5, 4.5), WalkDirection.right, 100).x,
      closeTo(6.72, 1e-9),
    );
    expect(
      collision.move(at(9, 4.5), WalkDirection.left, 100).x,
      closeTo(8.28, 1e-9),
    );
    expect(
      collision.move(at(6.8, 2.5), WalkDirection.down, 10).y,
      closeTo(2.72, 1e-9),
    );
    expect(
      collision.move(at(8.5, 9), WalkDirection.up, 10).y,
      closeTo(8.28, 1e-9),
    );
    expect(
      () => collision.move(at(7.5, 4), WalkDirection.left, 1),
      throwsStateError,
    );
  });

  test('open map boundaries still constrain the entire footprint', () {
    final open = parseWorldMap('open', ['S...', '....']);
    final physics = WorldCollision(open);
    final p = open.spawns['entry']!;
    expect(physics.move(p, WalkDirection.left, 10).x, closeTo(.28, 1e-9));
    expect(physics.move(p, WalkDirection.down, 10).y, closeTo(1.72, 1e-9));
    expect(physics.move(p, WalkDirection.right, 10).x, closeTo(3.72, 1e-9));
  });
}
