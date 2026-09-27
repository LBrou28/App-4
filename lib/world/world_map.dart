import 'dart:math' as math;

import '../core/contracts.dart';

enum WalkDirection { up, down, left, right }

/// B1 text map format: # wall, . floor, S the single entry tile.
/// Rendering/collision consume MapDefinition, never the source text.
MapDefinition parseWorldMap(String id, List<String> rows) {
  if (rows.isEmpty ||
      rows.first.isEmpty ||
      rows.any((row) => row.length != rows.first.length)) {
    throw FormatException('Map $id must be a nonempty rectangle');
  }
  WorldPosition? spawn;
  final blocked = <bool>[];
  for (var y = 0; y < rows.length; y++) {
    for (var x = 0; x < rows[y].length; x++) {
      final tile = rows[y][x];
      if (!['#', '.', 'S'].contains(tile)) {
        throw FormatException('Unknown tile $tile at ($x,$y) in $id');
      }
      if (tile == 'S') {
        if (spawn != null) throw FormatException('Multiple spawns in $id');
        spawn = WorldPosition(mapId: id, x: x + .5, y: y + .5);
      }
      blocked.add(tile == '#');
    }
  }
  if (spawn == null) throw FormatException('Missing spawn in $id');
  return MapDefinition(
    id: id,
    width: rows.first.length,
    height: rows.length,
    blocked: blocked,
    spawns: {'entry': spawn},
  );
}

/// Axis-aligned square footprint, 0.56 tiles wide. Tile edges may touch.
/// Cardinal sweeps visit every crossed tile, so even large steps cannot tunnel.
class WorldCollision {
  WorldCollision(this.map, {this.halfSize = .28}) {
    if (!halfSize.isFinite || halfSize <= 0 || halfSize >= .5) {
      throw ArgumentError.value(halfSize, 'halfSize');
    }
    for (final entry in map.spawns.entries) {
      if (!isClear(entry.value)) {
        throw ArgumentError('Spawn ${entry.key} has no footprint clearance');
      }
    }
  }

  final MapDefinition map;
  final double halfSize;
  static const _epsilon = 1e-9;

  bool isClear(WorldPosition p) {
    if (p.mapId != map.id ||
        p.x - halfSize < -_epsilon ||
        p.y - halfSize < -_epsilon ||
        p.x + halfSize > map.width + _epsilon ||
        p.y + halfSize > map.height + _epsilon) {
      return false;
    }
    for (
      var y = (p.y - halfSize + _epsilon).floor();
      y <= (p.y + halfSize - _epsilon).floor();
      y++
    ) {
      for (
        var x = (p.x - halfSize + _epsilon).floor();
        x <= (p.x + halfSize - _epsilon).floor();
        x++
      ) {
        if (x < 0 ||
            y < 0 ||
            x >= map.width ||
            y >= map.height ||
            map.blocked[y * map.width + x]) {
          return false;
        }
      }
    }
    return true;
  }

  WorldPosition move(
    WorldPosition p,
    WalkDirection direction,
    double distance,
  ) {
    if (!distance.isFinite || distance < 0) throw ArgumentError.value(distance);
    if (!isClear(p)) throw StateError('Invalid world position for ${map.id}');
    final horizontal =
        direction == WalkDirection.left || direction == WalkDirection.right;
    final positive =
        direction == WalkDirection.right || direction == WalkDirection.down;
    final axis = horizontal ? p.x : p.y;
    final cross = horizontal ? p.y : p.x;
    final extent = horizontal ? map.width : map.height;
    var target = (axis + (positive ? distance : -distance))
        .clamp(halfSize, extent - halfSize)
        .toDouble();
    final low = (math.min(axis, target) - halfSize + _epsilon).floor();
    final high = (math.max(axis, target) + halfSize - _epsilon).floor();
    for (var a = low; a <= high; a++) {
      for (
        var b = (cross - halfSize + _epsilon).floor();
        b <= (cross + halfSize - _epsilon).floor();
        b++
      ) {
        final x = horizontal ? a : b;
        final y = horizontal ? b : a;
        if (map.blocked[y * map.width + x]) {
          target = positive
              ? math.min(target, a - halfSize)
              : math.max(target, a + 1 + halfSize);
        }
      }
    }
    return WorldPosition(
      mapId: map.id,
      x: horizontal ? target : p.x,
      y: horizontal ? p.y : target,
    );
  }
}
