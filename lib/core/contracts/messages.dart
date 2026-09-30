import 'models.dart';

/// A creates a unique encounter ID when accepting B's request; B supplies the
/// encounter definition ID. C returns the same ID and base revision.
final class EncounterRequest {
  EncounterRequest({required this.definitionId}) {
    requireId(definitionId, 'encounter definition');
  }

  final String definitionId;
}

final class BattleInput {
  BattleInput({
    required this.encounterId,
    required this.baseRevision,
    required this.request,
    required this.state,
    required this.seed,
  }) {
    requireId(encounterId, 'encounter id');
    requireNonNegative(baseRevision, 'base revision');
  }

  final String encounterId;
  final int baseRevision;
  final EncounterRequest request;
  final GameState state;
  final int seed;
}

enum BattleAction { attack, defend, ability, item, flee }

/// C validates actor/target eligibility and resource costs, not the DTO.
final class BattleCommand {
  BattleCommand({
    required this.actorId,
    required this.action,
    required List<String> targetIds,
    this.definitionId,
  }) : targetIds = List.unmodifiable(targetIds) {
    requireId(actorId, 'actor id');
    for (final id in targetIds) {
      requireId(id, 'target id');
    }
    final needsDefinition =
        action == BattleAction.ability || action == BattleAction.item;
    if (needsDefinition != (definitionId != null)) {
      throw ArgumentError('Only ability/item commands require a definition ID');
    }
    if (definitionId != null) requireId(definitionId!, 'action definition');
  }

  final String actorId;
  final BattleAction action;
  final List<String> targetIds;
  final String? definitionId;
}

enum BattleOutcome { victory, defeat, fled }

/// Proposed C -> A terminal snapshot. C owns progression calculations.
/// Final party/inventory/gold INCLUDE costs and earned rewards; A commits them
/// once, rather than calculating or adding rewards a second time.
final class BattleResult {
  BattleResult({
    required this.encounterId,
    required this.baseRevision,
    required this.outcome,
    required List<PartyMember> party,
    required this.inventory,
    required this.gold,
  }) : party = List.unmodifiable(party) {
    requireId(encounterId, 'encounter id');
    requireNonNegative(baseRevision, 'base revision');
    requireNonNegative(gold, 'gold');
    if (party.length != 4 || party.map((p) => p.id).toSet().length != 4) {
      throw ArgumentError('Result must contain four distinct members');
    }
  }

  final String encounterId;
  final int baseRevision;
  final BattleOutcome outcome;
  final List<PartyMember> party;
  final Inventory inventory;
  final int gold;
}

sealed class MenuCommand {}

final class UseItem extends MenuCommand {
  UseItem({required this.itemId, required this.memberId});
  final String itemId;
  final String memberId;
}

final class ChangeJob extends MenuCommand {
  ChangeJob({required this.memberId, required this.jobId});
  final String memberId;
  final String jobId;
}

final class EquipItem extends MenuCommand {
  EquipItem({required this.memberId, required this.slotId, this.itemId});
  final String memberId;
  final String slotId;

  /// Null requests unequip. Rules live with C, not the menu.
  final String? itemId;
}

/// A serializes state changes; C's rule service proposes the resulting state.
sealed class CommandResult {}

final class CommandAccepted extends CommandResult {
  CommandAccepted(this.state);
  final GameState state;
}

final class CommandRejected extends CommandResult {
  CommandRejected({required this.code, required this.message});
  final String code;
  final String message;
}
