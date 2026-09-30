import '../ui/content/demo_content.dart';
import 'world_operations.dart';

/// Maps D's authored rows to A operations only where B has supplied placement.
/// Keys in sites are NPC or chest IDs, not dialogue IDs. A dialogue may be reused.
WorldOperations contentOperations({
  required DemoContent content,
  required Map<String, InteractionSite> sites,
  List<WorldArea> areas = const [],
  List<MapExit> exits = const [],
}) {
  final dialogues = <WorldDialogue>[];
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
  if (unused.isNotEmpty) throw ArgumentError('Unknown placements: $unused');
  return WorldOperations(
    areas: areas,
    exits: exits,
    dialogues: dialogues,
    chests: chests,
    itemIds: content.sharedItems.keys.toSet(),
  );
}
