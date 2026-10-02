import 'dart:ui';

/// All coordinates are in the original 1402 × 1122 artwork. Rendering and
/// movement use this same coordinate space, avoiding coarse tile rounding.
class HarborGeometry {
  static const size = Size(1402, 1122);
  static const spawn = Offset(11.5 * 1402 / 25, 12.5 * 1122 / 20);
  static const footRadius = 6.0;

  static Path polygon(List<Offset> points) => Path()..addPolygon(points, true);
  static Path rectangle(double x, double y, double w, double h) =>
      Path()..addRect(Rect.fromLTWH(x, y, w, h));

  /// Connected paved/wooden lanes, plus the two open dirt paths. Edges follow
  /// the actual shoreline/retaining walls rather than painted red strokes.
  final lanes = <Path>[
    polygon(const [
      Offset(548, 0),
      Offset(641, 0),
      Offset(648, 33),
      Offset(674, 55),
      Offset(695, 78),
      Offset(713, 102),
      Offset(723, 130),
      Offset(727, 160),
      Offset(720, 195),
      Offset(711, 230),
      Offset(716, 266),
      Offset(716, 375),
      Offset(632, 375),
      Offset(632, 272),
      Offset(618, 272),
      Offset(625, 243),
      Offset(638, 215),
      Offset(643, 181),
      Offset(639, 143),
      Offset(628, 108),
      Offset(607, 79),
      Offset(578, 56),
      Offset(556, 28),
    ]),
    rectangle(268, 111, 66, 450),
    polygon(const [
      Offset(497, 366),
      Offset(618, 366),
      Offset(618, 329),
      Offset(811, 329),
      Offset(811, 383),
      Offset(1097, 383),
      Offset(1097, 529),
      Offset(1162, 529),
      Offset(1162, 613),
      Offset(963, 613),
      Offset(963, 698),
      Offset(416, 698),
      Offset(416, 604),
      Offset(267, 604),
      Offset(267, 546),
      Offset(348, 546),
      Offset(348, 522),
      Offset(497, 522),
    ]),
    // West pier includes its elbow back to the plaza.
    polygon(const [
      Offset(346, 603),
      Offset(413, 603),
      Offset(413, 697),
      Offset(348, 697),
      Offset(348, 842),
      Offset(270, 842),
      Offset(270, 698),
      Offset(244, 698),
      Offset(244, 648),
      Offset(346, 648),
    ]),
    rectangle(603, 686, 87, 264),
    polygon(const [
      Offset(880, 684),
      Offset(949, 684),
      Offset(949, 759),
      Offset(1044, 759),
      Offset(1044, 844),
      Offset(881, 844),
    ]),
    // Right side stairs/path connecting the harbor gate and shrine.
    polygon(const [
      Offset(1100, 169),
      Offset(1184, 169),
      Offset(1184, 235),
      Offset(1206, 255),
      Offset(1222, 272),
      Offset(1236, 290),
      Offset(1248, 309),
      Offset(1256, 330),
      Offset(1256, 353),
      Offset(1248, 374),
      Offset(1234, 394),
      Offset(1218, 417),
      Offset(1200, 444),
      Offset(1218, 480),
      Offset(1230, 498),
      Offset(1248, 498),
      Offset(1248, 595),
      Offset(1150, 595),
      Offset(1150, 480),
      Offset(1145, 450),
      Offset(1131, 430),
      Offset(1110, 409),
      Offset(1095, 385),
      Offset(1095, 307),
      Offset(1103, 259),
      Offset(1100, 235),
    ]),
    rectangle(1072, 129, 143, 48),
    // Courtyard and the connector beside the upper-right house.
    rectangle(821, 320, 267, 93),
    rectangle(745, 360, 343, 23),
    polygon(const [
      Offset(1015, 235),
      Offset(1090, 225),
      Offset(1148, 235),
      Offset(1155, 264),
      Offset(1080, 285),
      Offset(1080, 389),
      Offset(1015, 389),
    ]),
    rectangle(1190, 506, 212, 72),
    rectangle(1185, 580, 57, 136),
  ];

  /// Individual solid objects. Each entry is deliberately kept small so the
  /// adjacent paving and stair treads stay available to the player.
  final objects = <Path>[
    // The entire upper-left pocket and its side piers are closed, as marked
    // in the latest review. The lower quay remains available below it.
    rectangle(0, 0, 584, 390),
    polygon(const [
      Offset(350, 56),
      Offset(513, 56),
      Offset(568, 121),
      Offset(568, 217),
      Offset(481, 217),
      Offset(481, 196),
      Offset(350, 196),
    ]),
    polygon(const [
      Offset(765, 113),
      Offset(929, 113),
      Offset(998, 214),
      Offset(998, 320),
      Offset(934, 320),
      Offset(934, 285),
      Offset(778, 285),
      Offset(778, 204),
      Offset(765, 204),
    ]),
    rectangle(99, 397, 177, 159),
    polygon(const [
      Offset(826, 386),
      Offset(1014, 386),
      Offset(1014, 470),
      Offset(988, 470),
      Offset(988, 565),
      Offset(835, 565),
      Offset(835, 470),
      Offset(826, 470),
    ]),
    // Walls and the inaccessible rocky pockets behind them.
    rectangle(228, 0, 110, 101),
    rectangle(345, 225, 167, 65),
    rectangle(512, 223, 72, 167),
    rectangle(340, 292, 151, 247),
    rectangle(590, 270, 41, 114),
    rectangle(717, 270, 22, 114),
    rectangle(736, 332, 85, 25),
    polygon(const [
      Offset(1062, 284),
      Offset(1110, 284),
      Offset(1110, 371),
      Offset(1086, 371),
      Offset(1086, 332),
      Offset(1062, 332),
    ]),
    rectangle(1013, 423, 82, 24),
    rectangle(1074, 443, 23, 93),
    rectangle(1090, 531, 75, 24),
    rectangle(1154, 549, 21, 66),
    // Crates/barrels covered in red; green-marked props are omitted.
    rectangle(488, 173, 80, 44),
    rectangle(340, 429, 44, 90),
    rectangle(510, 397, 76, 81),
    rectangle(421, 615, 84, 69),
    rectangle(992, 521, 69, 46),
    // Monument itself is solid; its staircase is walkable.
    rectangle(628, 482, 42, 73),
    rectangle(584, 515, 24, 95),
    rectangle(688, 516, 24, 94),
    rectangle(339, 596, 25, 36),
    rectangle(590, 680, 15, 42),
    rectangle(690, 683, 17, 46),
    // Shrine posts remain solid while its front terrace and stairs are open.
    rectangle(1062, 113, 22, 55),
    rectangle(1188, 112, 23, 56),
    rectangle(1092, 12, 103, 117),
  ];

  late final Path walkable = lanes.fold<Path>(
    Path(),
    (path, lane) => Path.combine(PathOperation.union, path, lane),
  );
  late final Path solidObjects = objects.fold<Path>(
    Path(),
    (path, object) => Path.combine(PathOperation.union, path, object),
  );
  late final Path blocked = Path.combine(
    PathOperation.union,
    Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      walkable,
    ),
    solidObjects,
  );

  bool isClear(Offset feet) {
    // Nine probes check the foot-sized footprint, including diagonal corners.
    for (final dx in [-footRadius, 0.0, footRadius]) {
      for (final dy in [-footRadius, 0.0, footRadius]) {
        final sample = feet + Offset(dx, dy);
        if (!walkable.contains(sample) || solidObjects.contains(sample)) {
          return false;
        }
      }
    }
    return true;
  }

  Offset move(Offset start, Offset delta) {
    var result = start;
    final steps = (delta.distance / 2).ceil().clamp(1, 1000);
    final step = delta / steps.toDouble();
    // Small swept steps prevent passing through narrow walls, while splitting
    // axes permits sliding along an edge when diagonal input is held.
    for (var i = 0; i < steps; i++) {
      final horizontal = result + Offset(step.dx, 0);
      if (isClear(horizontal)) result = horizontal;
      final vertical = result + Offset(0, step.dy);
      if (isClear(vertical)) result = vertical;
    }
    return result;
  }
}
