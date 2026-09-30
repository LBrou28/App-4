import '../core/contracts.dart';

/// B supplies geometry, full-footprint collision and reach predicates.
/// Predicates must be synchronous, pure reads of the supplied position.
final class WorldArea {
  const WorldArea({required this.map, required this.isClear});
  final MapDefinition map;
  final bool Function(WorldPosition) isClear;
}

final class InteractionSite {
  InteractionSite({required this.mapId, required this.canActivate}) {
    requireId(mapId, 'interaction map');
  }
  final String mapId;
  final bool Function(WorldPosition) canActivate;
}

final class MapExit {
  MapExit({
    required this.id,
    required this.site,
    required this.destinationMapId,
    required this.spawnId,
  }) {
    requireId(id, 'exit');
    requireId(destinationMapId, 'destination map');
    requireId(spawnId, 'spawn');
  }
  final String id;
  final InteractionSite site;
  final String destinationMapId;
  final String spawnId;
}

final class WorldDialogue {
  WorldDialogue({
    required this.id,
    required this.site,
    required this.speaker,
    required List<String> lines,
  }) : lines = List.unmodifiable(lines) {
    requireId(id, 'dialogue interaction');
    if (speaker.trim().isEmpty ||
        lines.isEmpty ||
        lines.any((line) => line.trim().isEmpty)) {
      throw ArgumentError('Dialogue needs a speaker and nonempty lines');
    }
  }
  final String id;
  final InteractionSite site;
  final String speaker;
  final List<String> lines;
}

/// A content-authored quest moment attached to one of B's interaction sites.
/// Completing its dialogue can grant one durable quest flag; cancelling it
/// never changes game state. An encounter-backed step presents its dialogue
/// only after the matching battle is won.
final class WorldQuestStep {
  WorldQuestStep({
    required this.id,
    required this.interactionId,
    required this.site,
    required this.dialogue,
    Set<String> requiresFlags = const {},
    this.setsFlag,
    this.encounterId,
  }) : requiresFlags = Set.unmodifiable(requiresFlags) {
    requireId(id, 'quest step');
    requireId(interactionId, 'quest interaction');
    for (final flag in requiresFlags) {
      requireId(flag, 'required quest flag');
    }
    final grantedFlag = setsFlag;
    if (grantedFlag != null) requireId(grantedFlag, 'set quest flag');
    final battle = encounterId;
    if (battle != null) requireId(battle, 'quest encounter');
  }

  final String id;
  final String interactionId;
  final InteractionSite site;
  final WorldDialogue dialogue;
  final Set<String> requiresFlags;
  final String? setsFlag;
  final String? encounterId;
}

final class WorldChest {
  WorldChest({
    required this.id,
    required this.site,
    required this.itemId,
    required this.quantity,
  }) {
    requireId(id, 'chest');
    requireId(itemId, 'chest item');
    if (quantity <= 0) throw ArgumentError('Chest quantity must be positive');
  }
  final String id;
  final InteractionSite site;
  final String itemId;
  final int quantity;
}

/// Immutable registration, assembled by A from B geometry and D content.
/// No default reach rule: absent placements remain unavailable.
final class WorldOperations {
  WorldOperations({
    List<WorldArea> areas = const [],
    List<MapExit> exits = const [],
    List<WorldDialogue> dialogues = const [],
    List<WorldQuestStep> questSteps = const [],
    List<WorldChest> chests = const [],
    Set<String> itemIds = const {},
  }) : areas = _index(areas, (v) => v.map.id),
       exits = _index(exits, (v) => v.id),
       dialogues = _index(dialogues, (v) => v.id),
       questSteps = _index(questSteps, (v) => v.id),
       chests = _index(chests, (v) => v.id) {
    for (final chest in chests) {
      if (!itemIds.contains(chest.itemId)) {
        throw ArgumentError('Unknown chest item: ${chest.itemId}');
      }
    }
  }
  final Map<String, WorldArea> areas;
  final Map<String, MapExit> exits;
  final Map<String, WorldDialogue> dialogues;
  final Map<String, WorldQuestStep> questSteps;
  final Map<String, WorldChest> chests;
}

Map<String, T> _index<T>(List<T> values, String Function(T) key) {
  final result = <String, T>{};
  for (final value in values) {
    if (result.containsKey(key(value))) {
      throw ArgumentError('Duplicate registration: ${key(value)}');
    }
    result[key(value)] = value;
  }
  return Map.unmodifiable(result);
}

final class ActiveDialogue {
  const ActiveDialogue({
    required this.token,
    required this.dialogue,
    this.setsQuestFlag,
  });
  final int token;
  final WorldDialogue dialogue;
  final String? setsQuestFlag;
}
