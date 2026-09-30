import 'models.dart';

/// Structural references only. This deliberately contains no combat formulas,
/// actual game content, map loading or equipment restrictions.
final class ContentCatalog {
  ContentCatalog({
    required Map<String, MapDefinition> maps,
    required Map<String, JobDefinition> jobs,
    required Map<String, ItemDefinition> items,
  }) : maps = Map.unmodifiable(maps),
       jobs = Map.unmodifiable(jobs),
       items = Map.unmodifiable(items) {
    for (final entry in maps.entries) {
      if (entry.key != entry.value.id) {
        throw ArgumentError('Map key/ID mismatch');
      }
    }
    for (final entry in jobs.entries) {
      if (entry.key != entry.value.id) {
        throw ArgumentError('Job key/ID mismatch');
      }
    }
    for (final entry in items.entries) {
      if (entry.key != entry.value.id) {
        throw ArgumentError('Item key/ID mismatch');
      }
    }
  }

  final Map<String, MapDefinition> maps;
  final Map<String, JobDefinition> jobs;
  final Map<String, ItemDefinition> items;

  /// All errors returned together so an author can repair a fixture in one pass.
  /// Quest/chest/ability validation needs D/B's agreed content registries.
  List<String> validate(GameState state) {
    final errors = <String>[];
    final map = maps[state.position.mapId];
    if (map == null) {
      errors.add('Unknown map: ${state.position.mapId}');
    } else if (state.position.x >= map.width ||
        state.position.y >= map.height) {
      errors.add('Position outside map: ${map.id}');
    } else if (map.blocked[state.position.y.floor() * map.width +
        state.position.x.floor()]) {
      errors.add('Position on blocked tile: ${map.id}');
    }
    for (final member in state.party) {
      for (final jobId in {member.jobId, ...member.jobProgress.keys}) {
        if (!jobs.containsKey(jobId)) errors.add('Unknown job: $jobId');
      }
      for (final itemId in member.equipment.values) {
        if (!items.containsKey(itemId)) {
          errors.add('Unknown equipped item: $itemId');
        }
      }
    }
    for (final itemId in state.inventory.quantities.keys) {
      if (!items.containsKey(itemId)) {
        errors.add('Unknown inventory item: $itemId');
      }
    }
    return List.unmodifiable(errors);
  }
}
