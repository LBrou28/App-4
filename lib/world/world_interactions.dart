import '../core/contracts.dart';
import 'world_map.dart';

enum WorldTargetKind { npc, chest, quest, exit }

/// A named point of interest shown on B's authored maps. Landmarks are visual
/// only: story progression and effects remain owned by their respective A/C/D
/// operations.
enum WorldLandmarkKind {
  rest,
  lantern,
  dock,
  supplies,
  shelter,
  threshold,
  bell,
}

final class WorldLandmark {
  WorldLandmark({
    required this.id,
    required this.mapId,
    required this.x,
    required this.y,
    required this.label,
    required this.kind,
  }) {
    requireId(id, 'world landmark');
    requireId(mapId, 'landmark map');
    if (x < 0 || y < 0 || label.trim().isEmpty) {
      throw ArgumentError('Invalid landmark placement: $id');
    }
  }

  final String id;
  final String mapId;
  final int x;
  final int y;
  final String label;
  final WorldLandmarkKind kind;
}

/// B's placement and reach rule. A owns the registered operation and its effects.
final class WorldTarget {
  WorldTarget({
    required this.id,
    required this.mapId,
    required this.x,
    required this.y,
    required this.label,
    required this.kind,
  }) {
    requireId(id, 'world target');
    requireId(mapId, 'target map');
    if (x < 0 || y < 0 || label.trim().isEmpty) {
      throw ArgumentError('Invalid target placement: $id');
    }
  }

  final String id;
  final String mapId;
  final int x;
  final int y;
  final String label;
  final WorldTargetKind kind;

  /// Adjacent cardinal tiles cannot reach through an intervening wall. NPCs and
  /// chests occupy blocked tiles; exits occupy a clear tile under the player.
  bool reachable(WorldPosition p) =>
      p.mapId == mapId &&
      (kind == WorldTargetKind.exit
          ? p.x.floor() == x && p.y.floor() == y
          : (p.x.floor() - x).abs() + (p.y.floor() - y).abs() == 1);

  bool inFront(WorldPosition p, WalkDirection facing) {
    if (!reachable(p) || kind == WorldTargetKind.exit) return false;
    final (dx, dy) = switch (facing) {
      WalkDirection.up => (0, -1),
      WalkDirection.down => (0, 1),
      WalkDirection.left => (-1, 0),
      WalkDirection.right => (1, 0),
    };
    return p.x.floor() + dx == x && p.y.floor() + dy == y;
  }
}

final class WorldInteractions {
  WorldInteractions(List<WorldTarget> targets)
    : targets = List.unmodifiable(targets) {
    if (targets.map((t) => t.id).toSet().length != targets.length) {
      throw ArgumentError('Duplicate world target IDs');
    }
    if (targets.map((t) => '${t.mapId}:${t.x}:${t.y}').toSet().length !=
        targets.length) {
      throw ArgumentError('Overlapping world targets');
    }
  }
  final List<WorldTarget> targets;

  WorldTarget? inFront(WorldPosition p, WalkDirection facing) =>
      targets.where((t) => t.inFront(p, facing)).firstOrNull;

  bool exitAfterMovement(WorldHost host) {
    if (host is! WorldInteractionHost || !host.movementEnabled) return false;
    final exit = targets
        .where(
          (t) =>
              t.kind == WorldTargetKind.exit &&
              t.reachable(host.state.position),
        )
        .firstOrNull;
    return exit != null &&
        host.useMapExit(exit.id, expectedRevision: host.revision);
  }
}
