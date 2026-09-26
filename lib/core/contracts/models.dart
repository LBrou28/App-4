/// A1 review proposal. Do not treat these interfaces as agreed until the
/// B/C/D review checklist in docs/contracts.md is resolved.
library;

void requireId(String value, String field) {
  if (value.trim().isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'Expected a nonblank, trimmed ID');
  }
}

void requireNonNegative(int value, String field) {
  if (value < 0) throw ArgumentError.value(value, field, 'Must be nonnegative');
}

Map<String, int> checkedCounts(Map<String, int> values, String field) {
  for (final entry in values.entries) {
    requireId(entry.key, '$field key');
    requireNonNegative(entry.value, '$field.${entry.key}');
  }
  return Map.unmodifiable(values);
}

enum AppMode { title, loading, exploration, dialogue, battle, gameOver, error }

/// Tile-space center coordinates, with the top-left map corner at (0, 0).
/// Coordinate convention is a proposal requiring B's approval.
final class WorldPosition {
  WorldPosition({required this.mapId, required this.x, required this.y}) {
    requireId(mapId, 'mapId');
    if (!x.isFinite || !y.isFinite || x < 0 || y < 0) {
      throw ArgumentError('Position must be finite and nonnegative');
    }
  }

  final String mapId;
  final double x;
  final double y;
}

/// Shared map metadata only; B owns rendering and collision algorithms.
final class MapDefinition {
  MapDefinition({
    required this.id,
    required this.width,
    required this.height,
    required List<bool> blocked,
    required Map<String, WorldPosition> spawns,
  }) : blocked = List.unmodifiable(blocked),
       spawns = Map.unmodifiable(spawns) {
    requireId(id, 'map id');
    if (width <= 0 || height <= 0 || blocked.length != width * height) {
      throw ArgumentError(
        'Map dimensions must match a nonempty row-major grid',
      );
    }
    if (spawns.isEmpty) throw ArgumentError('At least one spawn is required');
    for (final entry in spawns.entries) {
      requireId(entry.key, 'spawn id');
      final p = entry.value;
      if (p.mapId != id || p.x >= width || p.y >= height) {
        throw ArgumentError('Spawn ${entry.key} is outside its map');
      }
      if (this.blocked[p.y.floor() * width + p.x.floor()]) {
        throw ArgumentError('Spawn ${entry.key} is on a blocked tile');
      }
    }
  }

  final String id;
  final int width;
  final int height;
  final List<bool> blocked;
  final Map<String, WorldPosition> spawns;
}

final class JobDefinition {
  JobDefinition({required this.id, required Set<String> abilityIds})
    : abilityIds = Set.unmodifiable(abilityIds) {
    requireId(id, 'job id');
    for (final id in abilityIds) {
      requireId(id, 'ability id');
    }
  }

  final String id;
  final Set<String> abilityIds;
}

/// Item rules, prices, effects and equipment restrictions remain C/D decisions.
final class ItemDefinition {
  ItemDefinition({required this.id}) {
    requireId(id, 'item id');
  }

  final String id;
}

final class PartyMember {
  PartyMember({
    required this.id,
    required this.jobId,
    required this.hp,
    required this.maxHp,
    required this.mp,
    required this.maxMp,
    required this.level,
    required this.experience,
    required Map<String, int> jobProgress,
    required Map<String, String> equipment,
  }) : jobProgress = checkedCounts(jobProgress, 'jobProgress'),
       equipment = Map.unmodifiable(equipment) {
    requireId(id, 'member id');
    requireId(jobId, 'job id');
    if (maxHp <= 0 ||
        hp < 0 ||
        hp > maxHp ||
        maxMp < 0 ||
        mp < 0 ||
        mp > maxMp) {
      throw ArgumentError('HP/MP must be within their maxima');
    }
    if (level < 1) throw ArgumentError('Level must be positive');
    requireNonNegative(experience, 'experience');
    for (final entry in equipment.entries) {
      requireId(entry.key, 'equipment slot');
      requireId(entry.value, 'equipped item');
    }
  }

  final String id;
  final String jobId;
  final int hp;
  final int maxHp;
  final int mp;
  final int maxMp;
  final int level;
  final int experience;
  final Map<String, int> jobProgress;
  final Map<String, String> equipment;
}

final class Inventory {
  Inventory(Map<String, int> quantities)
    : quantities = checkedCounts(quantities, 'inventory');

  /// Bag counts exclude equipped items. Requires C/D agreement.
  final Map<String, int> quantities;
}

final class QuestFlags {
  QuestFlags({required Set<String> flags, required Set<String> openedChestIds})
    : flags = Set.unmodifiable(flags),
      openedChestIds = Set.unmodifiable(openedChestIds) {
    for (final id in [...flags, ...openedChestIds]) {
      requireId(id, 'quest/chest id');
    }
  }

  final Set<String> flags;
  final Set<String> openedChestIds;
}

final class GameState {
  GameState({
    required this.position,
    required List<PartyMember> party,
    required this.inventory,
    required this.gold,
    required this.quests,
  }) : party = List.unmodifiable(party) {
    if (party.length != 4 || party.map((p) => p.id).toSet().length != 4) {
      throw ArgumentError('The demo requires four distinct party members');
    }
    requireNonNegative(gold, 'gold');
  }

  final WorldPosition position;
  final List<PartyMember> party;
  final Inventory inventory;
  final int gold;
  final QuestFlags quests;
}

/// Draft logical save envelope, not an implemented disk/browser storage format.
final class SaveData {
  SaveData({required this.contentVersion, required this.state}) {
    requireId(contentVersion, 'content version');
  }

  static const int proposedSchemaVersion = 1;
  final String contentVersion;
  final GameState state;
}
