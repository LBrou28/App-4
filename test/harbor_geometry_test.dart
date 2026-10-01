import 'package:flutter_test/flutter_test.dart';
import 'package:app_4/world/demo/harbor_geometry.dart';

void main() {
  final geometry = HarborGeometry();
  test('the requested spawn and connected stair/dock paths have clearance', () {
    expect(geometry.isClear(HarborGeometry.spawn), isTrue);
    for (final feet in [
      const Offset(645, 670),
      const Offset(645, 800),
      const Offset(312, 770),
      const Offset(965, 810),
      const Offset(675, 320),
      const Offset(1210, 540),
      const Offset(665, 130),
      const Offset(645, 580),
      const Offset(860, 660),
      const Offset(1144, 151),
      const Offset(1052, 300),
    ]) {
      expect(geometry.isClear(feet), isTrue, reason: 'walkable at $feet');
    }
  });
  test('walking routes connect the spawn to docks, shrine and exits', () {
    final routes = <List<Offset>>[
      [
        const Offset(645, 660),
        const Offset(550, 660),
        const Offset(550, 580),
        const Offset(400, 580),
        const Offset(400, 670),
        const Offset(312, 670),
        const Offset(312, 810),
      ],
      [
        const Offset(645, 660),
        const Offset(730, 660),
        const Offset(730, 410),
        const Offset(675, 410),
        const Offset(675, 260),
        const Offset(680, 150),
        const Offset(655, 100),
        const Offset(630, 20),
      ],
      [
        const Offset(645, 660),
        const Offset(910, 660),
        const Offset(910, 790),
        const Offset(1000, 790),
      ],
      [
        const Offset(645, 660),
        const Offset(775, 660),
        const Offset(775, 372),
        const Offset(1052, 372),
        const Offset(1052, 355),
        const Offset(1052, 270),
        const Offset(1080, 250),
        const Offset(1144, 240),
        const Offset(1144, 151),
      ],
      [
        const Offset(645, 660),
        const Offset(775, 660),
        const Offset(775, 372),
        const Offset(1052, 372),
        const Offset(1052, 270),
        const Offset(1080, 250),
        const Offset(1144, 240),
        const Offset(1160, 265),
        const Offset(1230, 325),
        const Offset(1230, 355),
        const Offset(1198, 418),
        const Offset(1180, 445),
        const Offset(1180, 480),
        const Offset(1200, 480),
        const Offset(1200, 540),
        const Offset(1380, 540),
      ],
    ];
    for (final route in routes) {
      var feet = HarborGeometry.spawn;
      for (final target in route) {
        feet = geometry.move(feet, target - feet);
        expect(
          (feet - target).distance,
          lessThan(.01),
          reason: 'route must reach $target, reached $feet',
        );
      }
    }
  });
  test('houses, monument, shore and retained props stop the footprint', () {
    for (final feet in [
      const Offset(400, 140),
      const Offset(850, 200),
      const Offset(910, 480),
      const Offset(180, 460),
      const Offset(645, 540),
      const Offset(540, 440),
      const Offset(100, 900),
      const Offset(450, 660),
      const Offset(180, 135),
      const Offset(180, 310),
      const Offset(310, 210),
      const Offset(329, 260),
      const Offset(450, 210),
      const Offset(1080, 320),
      const Offset(1098, 355),
    ]) {
      expect(geometry.isClear(feet), isFalse, reason: 'blocked at $feet');
    }
  });
  test('large moves cannot cross the central monument or pier edge', () {
    final monument = geometry.move(
      const Offset(645, 600),
      const Offset(0, -200),
    );
    expect(monument.dy, greaterThanOrEqualTo(561));
    expect(geometry.isClear(monument), isTrue);
    final dock = geometry.move(const Offset(645, 800), const Offset(200, 0));
    expect(dock.dx, lessThanOrEqualTo(684));
    expect(geometry.isClear(dock), isTrue);
  });
}
