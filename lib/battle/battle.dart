/// C1 pure Dart battle rules. See README.md for proposed rules and integration.
library;

import 'dart:math';

enum BattleSide { heroes, enemies }

enum BattleAction { attack, defend }

enum BattleOutcome { ongoing, victory, defeat }

enum BattleEventKind { attack, defend, skippedKnockout }

/// Immutable battle-local data; this is not the application's GameState.
final class Combatant {
  Combatant({
    required this.id,
    required this.side,
    required this.hp,
    required this.maxHp,
    required this.attack,
    required this.defense,
    required this.speed,
  }) {
    if (id.isEmpty || id.trim() != id) {
      throw ArgumentError.value(id, 'id', 'Expected a nonblank trimmed ID');
    }
    if (maxHp <= 0 ||
        hp < 0 ||
        hp > maxHp ||
        attack < 0 ||
        defense < 0 ||
        speed < 0) {
      throw ArgumentError('Invalid HP or negative combat stat');
    }
  }

  final String id;
  final BattleSide side;
  final int hp;
  final int maxHp;
  final int attack;
  final int defense;
  final int speed;
  bool get isAlive => hp > 0;

  Combatant _withHp(int value) => Combatant(
    id: id,
    side: side,
    hp: value.clamp(0, maxHp),
    maxHp: maxHp,
    attack: attack,
    defense: defense,
    speed: speed,
  );
}

/// A command belongs to the engine/encounter on which it is submitted.
final class HeroCommand {
  const HeroCommand.attack(this.actorId, String target)
    : action = BattleAction.attack,
      targetId = target;
  const HeroCommand.defend(this.actorId)
    : action = BattleAction.defend,
      targetId = null;

  final String actorId;
  final BattleAction action;
  final String? targetId;
}

final class BattleSnapshot {
  BattleSnapshot._(this.round, List<Combatant> combatants, this.outcome)
    : combatants = List.unmodifiable(combatants);

  /// The next round accepting input. A terminal round keeps its number.
  final int round;
  final List<Combatant> combatants;
  final BattleOutcome outcome;
}

final class BattleEvent {
  const BattleEvent({
    required this.kind,
    required this.actorId,
    this.targetId,
    this.damage = 0,
  });

  final BattleEventKind kind;
  final String actorId;
  final String? targetId;

  /// Actual HP removed (after Defend and HP clamping).
  final int damage;
}

final class RoundResult {
  RoundResult._(this.resolvedRound, this.snapshot, List<BattleEvent> events)
    : events = List.unmodifiable(events);

  final int resolvedRound;
  final BattleSnapshot snapshot;
  final List<BattleEvent> events;
}

/// Synchronous round resolution. Invalid input changes neither state nor RNG.
/// Keep one engine per encounter; the caller owns pending UI selections.
final class BattleEngine {
  BattleEngine({required List<Combatant> combatants, required this._random}) {
    final roster = List<Combatant>.of(combatants);
    if (roster.where((c) => c.side == BattleSide.heroes).length != 4 ||
        !roster.any((c) => c.side == BattleSide.enemies) ||
        roster.map((c) => c.id).toSet().length != roster.length) {
      throw ArgumentError(
        'Need four heroes, at least one enemy and unique IDs',
      );
    }
    _snapshot = BattleSnapshot._(1, roster, _outcome(roster));
  }

  final Random _random;
  late BattleSnapshot _snapshot;
  BattleSnapshot get snapshot => _snapshot;

  RoundResult resolveRound({
    required int expectedRound,
    required List<HeroCommand> commands,
  }) {
    if (_snapshot.outcome != BattleOutcome.ongoing) {
      throw StateError('Battle has ended');
    }
    if (expectedRound != _snapshot.round) {
      throw StateError('Stale round: expected ${_snapshot.round}');
    }
    final roster = _snapshot.combatants;
    final byId = {for (final c in roster) c.id: c};
    final selected = <String, HeroCommand>{};
    for (final command in commands) {
      final actor = byId[command.actorId];
      if (actor == null ||
          actor.side != BattleSide.heroes ||
          !actor.isAlive ||
          selected.containsKey(command.actorId)) {
        throw ArgumentError('Command actor must be a distinct living hero');
      }
      if (command.action == BattleAction.attack &&
          byId[command.targetId]?.side != BattleSide.enemies) {
        throw ArgumentError('Attack target must be a known enemy');
      }
      selected[command.actorId] = command;
    }
    final livingHeroes = roster.where(
      (c) => c.side == BattleSide.heroes && c.isAlive,
    );
    if (selected.length != livingHeroes.length) {
      throw ArgumentError('Select one command for every living hero');
    }

    // Defend applies to the whole round, including attacks by faster enemies.
    final defending = selected.values
        .where((c) => c.action == BattleAction.defend)
        .map((c) => c.actorId)
        .toSet();
    final order = [
      for (var i = 0; i < roster.length; i++)
        if (roster[i].isAlive) i,
    ];
    order.sort((a, b) {
      final speed = roster[b].speed.compareTo(roster[a].speed);
      if (speed != 0) return speed;
      final side = roster[a].side.index.compareTo(roster[b].side.index);
      return side != 0 ? side : a.compareTo(b);
    });
    final current = List<Combatant>.of(roster);
    final events = <BattleEvent>[];
    var outcome = BattleOutcome.ongoing;
    for (final index in order) {
      final actor = current[index];
      if (!actor.isAlive) {
        events.add(
          BattleEvent(kind: BattleEventKind.skippedKnockout, actorId: actor.id),
        );
        continue;
      }
      final command = selected[actor.id];
      if (command?.action == BattleAction.defend) {
        events.add(
          BattleEvent(kind: BattleEventKind.defend, actorId: actor.id),
        );
        continue;
      }
      var targetIndex = command == null
          ? -1
          : current.indexWhere((c) => c.id == command.targetId && c.isAlive);
      // Dead targets retarget the first living opponent in supplied roster order.
      // C1 enemies always attack that first living hero (C3 adds richer AI).
      if (targetIndex < 0) {
        targetIndex = current.indexWhere(
          (c) => c.side != actor.side && c.isAlive,
        );
      }
      final target = current[targetIndex];
      var damage = max(
        1,
        actor.attack - target.defense + _random.nextInt(3) - 1,
      );
      if (defending.contains(target.id)) damage = (damage + 1) ~/ 2;
      final updated = target._withHp(target.hp - damage);
      current[targetIndex] = updated;
      events.add(
        BattleEvent(
          kind: BattleEventKind.attack,
          actorId: actor.id,
          targetId: target.id,
          damage: target.hp - updated.hp,
        ),
      );
      outcome = _outcome(current);
      if (outcome != BattleOutcome.ongoing) break;
    }
    final resolvedRound = _snapshot.round;
    _snapshot = BattleSnapshot._(
      outcome == BattleOutcome.ongoing ? resolvedRound + 1 : resolvedRound,
      current,
      outcome,
    );
    return RoundResult._(resolvedRound, _snapshot, events);
  }

  static BattleOutcome _outcome(List<Combatant> roster) {
    if (!roster.any((c) => c.side == BattleSide.heroes && c.isAlive)) {
      return BattleOutcome.defeat;
    }
    if (!roster.any((c) => c.side == BattleSide.enemies && c.isAlive)) {
      return BattleOutcome.victory;
    }
    return BattleOutcome.ongoing;
  }
}
