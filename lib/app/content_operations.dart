import '../ui/content/demo_content.dart';
import '../core/contracts.dart';
import 'world_operations.dart';

/// B binds each authored quest step to a reachable interaction target.
final class QuestPlacement {
  QuestPlacement({required this.interactionId, required this.site}) {
    requireId(interactionId, 'quest interaction');
  }

  final String interactionId;
  final InteractionSite site;
}

/// Maps D's authored rows to A operations only where B has supplied placement.
/// Keys in sites are NPC or chest IDs, not dialogue IDs. A dialogue may be reused.
WorldOperations contentOperations({
  required DemoContent content,
  required Map<String, InteractionSite> sites,
  Map<String, QuestPlacement> questPlacements = const {},
  List<WorldArea> areas = const [],
  List<MapExit> exits = const [],
}) {
  final dialogues = <WorldDialogue>[];
  final questSteps = <WorldQuestStep>[];
  final chests = <WorldChest>[];
  final unused = sites.keys.toSet();
  for (final npc in content.entries('npcs')) {
    final site = sites[npc.id];
    if (site == null) continue;
    if (site.mapId != npc.text('mapId')) {
      throw ArgumentError(
        'NPC placement map disagrees with content: ${npc.id}',
      );
    }
    final row = content.find('dialogues', npc.text('dialogueId'));
    dialogues.add(
      WorldDialogue(
        id: npc.id,
        site: site,
        speaker: content.label('npcs', row.text('speakerId')),
        lines: row.strings('lines'),
      ),
    );
    unused.remove(npc.id);
  }
  for (final chest in content.entries('chests')) {
    final site = sites[chest.id];
    if (site == null) continue;
    if (site.mapId != chest.text('mapId')) {
      throw ArgumentError(
        'Chest placement map disagrees with content: ${chest.id}',
      );
    }
    chests.add(
      WorldChest(
        id: chest.id,
        site: site,
        itemId: chest.text('itemId'),
        quantity: chest.number('quantity'),
      ),
    );
    unused.remove(chest.id);
  }
  final unusedQuestSteps = questPlacements.keys.toSet();
  for (final step in content.steps) {
    final placement = questPlacements[step.id];
    if (placement == null) continue;
    if (placement.site.mapId != step.text('mapId')) {
      throw ArgumentError(
        'Quest placement map disagrees with content: ${step.id}',
      );
    }
    final row = content.find('dialogues', step.text('dialogueId'));
    questSteps.add(
      WorldQuestStep(
        id: step.id,
        interactionId: placement.interactionId,
        site: placement.site,
        dialogue: WorldDialogue(
          id: row.id,
          site: placement.site,
          speaker: content.label('npcs', row.text('speakerId')),
          lines: row.strings('lines'),
        ),
        requiresFlags: step.strings('requiresFlags').toSet(),
        setsFlag: step.optionalText('setsFlag'),
        encounterId: step.optionalText('enemyId'),
      ),
    );
    unusedQuestSteps.remove(step.id);
  }
  if (unused.isNotEmpty) throw ArgumentError('Unknown placements: $unused');
  if (unusedQuestSteps.isNotEmpty) {
    throw ArgumentError('Unknown quest placements: $unusedQuestSteps');
  }
  return WorldOperations(
    areas: areas,
    exits: exits,
    dialogues: dialogues,
    questSteps: questSteps,
    chests: chests,
    itemIds: content.sharedItems.keys.toSet(),
  );
}
