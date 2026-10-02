import 'dart:math' as math;
import 'dart:ui';

/// Artwork coordinates for the isolated Drowned Cistern collision review.
/// This is not production quest state. Activation only opens the center sluice.
class CisternGeometry {
  CisternGeometry({this.sluiceOpen = false});
  final bool sluiceOpen;
  static const size = Size(1254, 1254);
  static const spawn = Offset(108, 1220);
  static const valveApproach = Offset(265, 198);
  static const footRadius = 6.0;
  static const openArtRegion = Rect.fromLTWH(578, 385, 98, 197);

  static Path polygon(List<double> xy) => Path()
    ..addPolygon([
      for (var i = 0; i < xy.length; i += 2) Offset(xy[i], xy[i + 1]),
    ], true);
  static Path rectangle(double x, double y, double w, double h) =>
      Path()..addRect(Rect.fromLTWH(x, y, w, h));

  bool get canOpen => !sluiceOpen;
  bool canOperateValve(Offset feet) =>
      canOpen && isClear(feet) && (feet - valveApproach).distance <= 40;

  // The polygons include the moss/grass on solid ground, not just path centers.
  // dart format off
  late final lanes = <Path>[
    // Southwest entrance, steps, and the cleared lower-left yellow connection.
    polygon([33,1254, 176,1254, 205,1221, 223,1189, 237,1167,
      268,1149, 296,1146, 297,1118, 259,1109, 220,1122,
      200,1142, 176,1166, 148,1187, 113,1200, 86,1218]),
    polygon([207,1112, 205,1058, 199,1038, 199,982, 207,953,
      209,914, 232,913, 232,925, 277,925, 277,930, 319,930,
      322,956, 330,975, 359,998, 402,1009, 487,1009,
      487,1049, 461,1063, 413,1069, 388,1078, 343,1085,
      305,1091, 303,1111]),
    polygon([484,1027, 486,997, 513,992, 550,981, 567,956,
      585,936, 650,936, 670,951, 679,966, 686,988, 663,1003,
      650,1018, 610,1038, 568,1050, 537,1063, 510,1069, 484,1069]),
    rectangle(215,1090,78,47),
    // Clear, widened lower entrance connection and central stone landing.
    rectangle(270,1011,310,53),
    polygon([490,731, 596,731, 596,874, 534,874, 527,864, 527,794, 508,782, 490,782]),
    rectangle(590,875,62,75),
    rectangle(587,699,73,185),
    // Main junction, west bridge and upper vestibule.
    polygon([589,874, 534,874, 527,861, 527,794, 508,782,
      490,782, 490,731, 505,731, 552,731, 575,731,
      587,739, 655,736, 673,735, 691,743, 729,748, 755,745,
      784,739, 819,745, 834,754, 868,761, 903,754, 932,756,
      943,744, 956,724, 983,732, 994,754, 979,770, 956,784,
      934,784, 904,782, 878,782, 851,782, 836,782, 809,782,
      783,782, 749,782, 715,782, 684,788, 665,817, 665,852, 654,874]),
    rectangle(350,734,245,43),
    rectangle(672,745,160,37),
    // Final review: smooth the eastern ground junction without exposing water.
    polygon([830,744, 870,744, 897,735, 914,716, 925,693,
      944,675, 967,681, 997,720, 993,754, 978,774, 956,784,
      935,784, 912,782, 878,782, 851,782, 830,782]),
    rectangle(590,608,66,100),
    polygon([508,554, 536,531, 562,545, 586,552, 608,569,
      650,569, 673,556, 699,548, 719,526, 735,524, 733,549,
      705,581, 686,594, 654,611, 594,611, 575,600, 552,600,
      530,586, 517,573]),
    rectangle(601,526,53,57),
    // Western courts and stairs: required detour to the northwest valve.
    polygon([235,179, 260,173, 288,172, 301,164, 314,158,
      323,164, 324,187, 323,217, 295,226, 295,250, 244,250,
      228,243, 208,244, 198,234, 194,213, 220,192]),
    rectangle(244,210,47,35),
    // Wider valve steps and the continuous western stair flight.
    rectangle(211,189,110,31),
    rectangle(214,210,98,112),
    rectangle(229,317,82,95),
    rectangle(228,408,98,103),
    rectangle(233,498,88,82),
    rectangle(306,567,282,43),
    rectangle(278,570,58,49), // No wall sliver on the cleared connection.
    rectangle(577,580,40,34),
    polygon([234,241, 290,241, 289,343, 295,354, 310,363,
      322,369, 319,396, 307,425, 310,435, 331,441, 339,472,
      343,488, 342,518, 308,518, 308,550, 279,554, 279,570,
      236,570, 236,550, 207,552, 179,556, 149,550, 143,532,
      142,496, 156,478, 191,473, 198,461, 218,451, 228,434,
      231,392, 246,383, 247,273]),
    rectangle(244,498,64,52),
    polygon([137,546, 179,546, 195,560, 218,560, 231,548,
      298,548, 298,580, 300,608, 322,627, 345,640, 360,657,
      354,679, 357,700, 365,720, 389,735, 427,734, 427,760,
      399,762, 376,759, 345,759, 326,746, 309,738, 271,723,
      220,722, 198,715, 152,710, 129,699, 131,660, 130,620, 137,592]),
    rectangle(146,526,61,28),
    // Eastern loop, chest landing, steps and the second yellow-cleared corner.
    polygon([990,189, 1015,184, 1049,187, 1069,195, 1086,193,
      1104,184, 1121,180, 1155,180, 1156,203, 1143,218,
      1125,231, 1105,231, 1098,260, 1066,275, 1040,277,
      1026,293, 1010,293, 1004,337, 1027,349, 1045,359,
      1074,350, 1112,358, 1144,360, 1144,383, 1132,407,
      1125,440, 1107,451, 1061,454, 1044,471, 1033,483,
      1025,503, 1020,535, 1015,576, 989,594, 961,595,
      947,578, 948,549, 947,518, 941,491, 935,482, 964,470,
      975,450, 983,429, 969,417, 956,409, 943,405, 940,383,
      954,363, 965,347, 962,327, 964,276, 974,266, 974,254,
      960,250, 942,250, 936,233, 949,223, 970,221]),
    rectangle(969,275,48,114),
    rectangle(967,519,55,91),
    polygon([962,602, 1018,602, 1019,625, 1044,640, 1048,663,
      1030,680, 1010,691, 997,712, 989,737, 971,755, 944,760,
      913,753, 907,734, 914,704, 926,686, 932,661, 931,643, 947,622]),
    polygon([907,757, 947,735, 960,746, 973,762, 982,785,
      1006,806, 1021,830, 1049,852, 1053,875, 1068,893,
      1074,918, 1111,931, 1133,944, 1140,965, 1130,988,
      1101,1009, 1068,1004, 1041,988, 1037,962, 1027,932,
      1010,918, 1007,896, 990,880, 979,861, 970,826,
      950,811, 945,784, 921,781]),
    // Boss room is ground; its central access remains closed until activation.
    polygon([485,169, 516,154, 548,158, 582,149, 599,152,
      599,129, 643,129, 661,151, 688,159, 710,156, 742,164,
      764,182, 786,218, 770,249, 750,261, 747,278, 724,297,
      714,316, 680,333, 657,336, 657,349, 590,349, 589,336,
      553,328, 535,321, 528,309, 510,300, 498,280, 490,254,
      480,237, 477,209]),
    rectangle(590,345,65,60),
    if (sluiceOpen) rectangle(597,392,61,177),
  ];

  late final objects = <Path>[
    rectangle(240,119,50,70), // Valve body; front approach stays clear.
    rectangle(240,604,22,90), // Red-marked west post and column.
    polygon([525,502, 545,508, 568,554, 568,574, 543,580, 531,562]), // Fallen vestibule column.
    rectangle(342,649,34,69), // Column beside the wider western courtyard.
    rectangle(126,650,21,28), // Retained barrel.
    rectangle(569,609,20,133), rectangle(657,610,20,133),
    rectangle(944,275,25,107), rectangle(1016,260,30,116),
    rectangle(1065,386,45,48), // Chest is solid, with an accessible front.
    rectangle(187,986,18,49),
    rectangle(286,947,18,42), // Retained iron gate fence.
    rectangle(599,102,46,39), // Small lantern pedestal behind the boss.
    if (!sluiceOpen) rectangle(601,400,46,20),
  ];
  // dart format on

  late final walkable = lanes.fold<Path>(
    Path(),
    (a, b) => Path.combine(PathOperation.union, a, b),
  );
  late final solidObjects = objects.fold<Path>(
    Path(),
    (a, b) => Path.combine(PathOperation.union, a, b),
  );
  late final blocked = Path.combine(
    PathOperation.union,
    Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      walkable,
    ),
    solidObjects,
  );

  bool isClear(Offset feet) {
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
    final steps = math.max(1, (delta.distance / 2).ceil());
    final step = delta / steps.toDouble();
    for (var i = 0; i < steps; i++) {
      final horizontal = result + Offset(step.dx, 0);
      if (isClear(horizontal)) result = horizontal;
      final vertical = result + Offset(0, step.dy);
      if (isClear(vertical)) result = vertical;
    }
    return result;
  }
}
