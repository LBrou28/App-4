import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/world/demo/causeway_geometry.dart';

void main() {
  late CausewayGeometry map;
  setUp(() => map = CausewayGeometry());

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

  final mainTrail = <Offset>[
    CausewayGeometry.spawn,
    const Offset(617, 1120),
    const Offset(617, 1080),
    const Offset(638, 1018),
    const Offset(679, 951),
    const Offset(705, 911),
    const Offset(697, 877),
    const Offset(650, 812),
    const Offset(582, 753),
    const Offset(529, 696),
    const Offset(489, 631),
    const Offset(477, 588),
    const Offset(477, 550),
    const Offset(477, 521),
    const Offset(477, 500),
    const Offset(456, 481),
    const Offset(435, 477),
    const Offset(447, 436),
    const Offset(496, 410),
    const Offset(553, 403),
    const Offset(650, 402),
    const Offset(740, 402),
    const Offset(784, 402),
    const Offset(845, 369),
    const Offset(900, 341),
    const Offset(960, 306),
    const Offset(1018, 258),
    const Offset(1045, 204),
    const Offset(1050, 175),
    const Offset(1066, 148),
    const Offset(1106, 116),
    const Offset(1170, 87),
    const Offset(1210, 43),
    const Offset(1213, 12),
  ];

  test(
    'Harbor entrance, bridge and northeast exit form one traversable route',
    () {
      walk(mainTrail);
      walk(mainTrail.reversed.toList());
    },
  );

  test('Camp chest can be approached without walking through its props', () {
    walk([
      const Offset(529, 696),
      const Offset(493, 720),
      const Offset(455, 736),
      const Offset(441, 733),
    ]);
    expect(map.isClear(const Offset(440, 690)), isFalse);
    expect(map.isClear(const Offset(374, 707)), isFalse);
    expect(map.isClear(const Offset(278, 686)), isFalse);
  });

  test('Northwest steps and right overlook remain accessible', () {
    walk([
      const Offset(496, 410),
      const Offset(459, 396),
      const Offset(419, 372),
      const Offset(377, 347),
      const Offset(343, 315),
      const Offset(336, 276),
      const Offset(333, 247),
      const Offset(333, 228),
      const Offset(293, 224),
      const Offset(250, 202),
      const Offset(236, 178),
    ]);
    walk([
      const Offset(845, 369),
      const Offset(887, 405),
      const Offset(910, 439),
      const Offset(910, 475),
      const Offset(937, 514),
      const Offset(987, 553),
      const Offset(993, 590),
      const Offset(993, 610),
    ]);
  });

  test('Red terrain, parapets and retained posts block movement', () {
    for (final feet in [
      const Offset(650, 360),
      const Offset(650, 447),
      const Offset(535, 425),
      const Offset(235, 130),
      const Offset(370, 480),
      const Offset(450, 950),
      const Offset(880, 600),
      const Offset(1000, 675),
      const Offset(990, 650),
      const Offset(200, 450),
      const Offset(200, 1050),
    ]) {
      expect(map.isClear(feet), isFalse, reason: '$feet should be solid');
    }
    final stopped = map.move(const Offset(650, 402), const Offset(0, 160));
    expect(stopped.dy, lessThan(424));
    expect(map.isClear(stopped), isTrue);
  });

  test('Grass beside the trail is accessible on each land shelf', () {
    for (final feet in [
      const Offset(514, 1175),
      const Offset(735, 1180),
      const Offset(511, 1050),
      const Offset(736, 962),
      const Offset(610, 890),
      const Offset(742, 845),
      const Offset(530, 745),
      const Offset(390, 651),
      const Offset(305, 739),
      const Offset(450, 641),
      const Offset(432, 414),
      const Offset(420, 340),
      const Offset(178, 205),
      const Offset(326, 169),
      const Offset(388, 162),
      const Offset(972, 348),
      const Offset(1120, 258),
      const Offset(1160, 242),
      const Offset(1000, 210),
      const Offset(1141, 105),
      const Offset(1008, 535),
      const Offset(956, 518),
    ]) {
      expect(map.isClear(feet), isTrue, reason: 'Grass at $feet');
    }
    walk([
      CausewayGeometry.spawn,
      const Offset(574, 1200),
      const Offset(525, 1200),
      const Offset(525, 1177),
      const Offset(511, 1177),
      const Offset(511, 1144),
      const Offset(511, 1100),
      const Offset(511, 1050),
    ]);
    walk([
      const Offset(377, 347),
      const Offset(411, 322),
      const Offset(441, 316),
    ]);
    walk([
      const Offset(900, 341),
      const Offset(952, 327),
      const Offset(1010, 328),
      const Offset(1065, 307),
    ]);
  });
}
