import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/world/demo/cistern_geometry.dart';

void main() {
  late CisternGeometry map;
  setUp(() => map = CisternGeometry());

  void walk(List<Offset> route) {
    var feet = route.first;
    expect(map.isClear(feet), isTrue, reason: 'Start $feet');
    for (final goal in route.skip(1)) {
      final next = map.move(feet, goal - feet);
      expect(
        (next - goal).distance,
        lessThan(.01),
        reason: 'Blocked walking $feet → $goal; stopped at $next',
      );
      feet = next;
    }
  }

  final entranceToJunction = <Offset>[
    CisternGeometry.spawn,
    const Offset(170, 1200),
    const Offset(215, 1160),
    const Offset(265, 1134),
    const Offset(267, 1100),
    const Offset(267, 1048),
    const Offset(330, 1048),
    const Offset(430, 1038),
    const Offset(500, 1035),
    const Offset(557, 1018),
    const Offset(622, 973),
    const Offset(622, 920),
    const Offset(622, 850),
    const Offset(622, 770),
  ];
  final junctionToValve = <Offset>[
    const Offset(622, 770),
    const Offset(565, 752),
    const Offset(505, 752),
    const Offset(505, 752),
    const Offset(465, 746),
    const Offset(414, 746),
    const Offset(369, 743),
    const Offset(335, 738),
    const Offset(315, 726),
    const Offset(279, 703),
    const Offset(277, 602),
    const Offset(269, 575),
    const Offset(269, 540),
    const Offset(269, 510),
    const Offset(280, 480),
    const Offset(264, 451),
    const Offset(269, 403),
    const Offset(269, 345),
    const Offset(269, 274),
    const Offset(269, 234),
    CisternGeometry.valveApproach,
  ];
  final junctionToChest = <Offset>[
    const Offset(622, 770),
    const Offset(708, 761),
    const Offset(777, 761),
    const Offset(847, 768),
    const Offset(925, 770),
    const Offset(974, 746),
    const Offset(975, 714),
    const Offset(981, 687),
    const Offset(990, 660),
    const Offset(989, 631),
    const Offset(991, 600),
    const Offset(991, 550),
    const Offset(991, 512),
    const Offset(991, 484),
    const Offset(1025, 467),
    const Offset(1055, 440),
    const Offset(1080, 445),
  ];

  test(
    'Entrance and lower-left yellow-cleared path join the main junction',
    () {
      walk(entranceToJunction);
      walk(entranceToJunction.reversed.toList());
    },
  );
  test('Northwest valve requires a connected western detour', () {
    walk(junctionToValve);
    walk(junctionToValve.reversed.toList());
    expect(map.canOperateValve(CisternGeometry.valveApproach), isTrue);
    expect(map.canOperateValve(CisternGeometry.spawn), isFalse);
    expect(map.canOperateValve(const Offset(265, 150)), isFalse);
  });
  test('Right yellow-cleared connection reaches the chest', () {
    walk(junctionToChest);
    walk(junctionToChest.reversed.toList());
    expect(map.isClear(const Offset(1080, 410)), isFalse);
  });
  test(
    'Sluice blocks the center until activated, then connects the chamber',
    () {
      final approach = <Offset>[
        const Offset(622, 770),
        const Offset(622, 670),
        const Offset(622, 606),
        const Offset(627, 580),
        const Offset(627, 563),
      ];
      walk(approach);
      expect(
        map.move(const Offset(627, 563), const Offset(0, -313)).dy,
        greaterThan(525),
      );
      expect(map.isClear(const Offset(627, 480)), isFalse);
      map = CisternGeometry(sluiceOpen: true);
      walk([
        ...approach,
        const Offset(627, 525),
        const Offset(627, 480),
        const Offset(627, 410),
        const Offset(627, 360),
        const Offset(625, 250),
        const Offset(625, 160),
      ]);
      expect(map.canOperateValve(CisternGeometry.valveApproach), isFalse);
    },
  );
  test('Opening the center does not open other sluices or water', () {
    for (final open in [false, true]) {
      map = CisternGeometry(sluiceOpen: open);
      for (final feet in [
        const Offset(850, 250),
        const Offset(399, 225),
        const Offset(1050, 548),
        const Offset(536, 1100),
        const Offset(505, 825),
        const Offset(465, 500),
        const Offset(714, 440),
        const Offset(200, 819),
        const Offset(400, 1120),
      ]) {
        expect(map.isClear(feet), isFalse, reason: 'Water $feet; open $open');
      }
    }
  });
  test(
    'Grass on courtyards is walkable; retained columns and props are solid',
    () {
      for (final feet in [
        const Offset(160, 600),
        const Offset(198, 685),
        const Offset(329, 1049),
        const Offset(565, 980),
        const Offset(941, 728),
      ]) {
        expect(map.isClear(feet), isTrue, reason: 'Ground $feet');
      }
      for (final feet in [
        const Offset(249, 656),
        const Offset(352, 685),
        const Offset(195, 1008),
        const Offset(298, 973),
        const Offset(620, 120),
      ]) {
        expect(map.isClear(feet), isFalse, reason: 'Retained prop $feet');
      }
    },
  );
  test(
    'Swept movement stops at cliff rims even with a large requested step',
    () {
      final start = const Offset(622, 770);
      final result = map.move(start, const Offset(0, -1200));
      expect(map.isClear(result), isTrue);
      expect(result.dy, greaterThan(525));
    },
  );

  test('Widened crossings allow parallel walking lines instead of a tight centerline', () {
    for (final y in [1020.0, 1035.0, 1050.0]) {
      walk([Offset(310, y), Offset(480, y), Offset(570, y)]);
    }
    for (final y in [750.0, 758.0, 767.0]) {
      walk([Offset(420, y), Offset(500, y), Offset(580, y), Offset(622, y)]);
    }
    for (final x in [245.0, 269.0, 295.0]) {
      walk([Offset(x, 265), Offset(x, 340), Offset(x, 400)]);
    }
    // The old pillar notch is now a broad, ordinary stone landing.
    walk([
      const Offset(535, 752),
      const Offset(535, 845),
      const Offset(622, 845),
    ]);
  });

  test('Opened sluice leaves room to walk on either side of its center', () {
    map = CisternGeometry(sluiceOpen: true);
    for (final x in [608.0, 627.0, 646.0]) {
      walk([Offset(x, 535), Offset(x, 480), Offset(x, 405)]);
    }
  });

  test('Three final review areas have clear ground and smooth crossings', () {
    walk([
      const Offset(286, 594),
      const Offset(302, 594),
      const Offset(325, 594),
    ]);
    for (final y in [750.0, 762.0]) {
      walk([Offset(360, y), Offset(415, y), Offset(500, y), Offset(580, y)]);
    }
    walk([
      const Offset(847, 760),
      const Offset(893, 760),
      const Offset(937, 750),
      const Offset(958, 715),
      const Offset(980, 685),
      const Offset(990, 650),
    ]);
    expect(map.isClear(const Offset(890, 685)), isFalse);
    expect(map.isClear(const Offset(800, 820)), isFalse);
  });
}
