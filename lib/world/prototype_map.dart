import '../core/contracts.dart';
import 'world_map.dart';

/// B1 geometry only, separate from renderer and movement. Not D's game content.
const prototypeRows = [
  '################',
  '#..............#',
  '#.S............#',
  '#......#.......#',
  '#......#.......#',
  '#......#.......#',
  '#......#.......#',
  '#......####....#',
  '#..............#',
  '#..##..........#',
  '#..............#',
  '################',
];

MapDefinition createPrototypeMap() =>
    parseWorldMap('b1.practice', prototypeRows);
