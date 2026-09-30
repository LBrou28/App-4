/// Deterministic battle rules and resource accounting. See C3_HANDOFF.md.
library;

import 'dart:math';

import 'combat_rules.dart';
export 'combat_rules.dart';

enum BattleSide { heroes, enemies }

enum BattleAction { attack, defend, spell, item }

enum BattleOutcome { ongoing, victory, defeat, fled }

enum BattleEventKind {
  attack,
  defend,
  spell,
  item,
  skippedKnockout,
  skippedTarget,
  fled,
  fleeFailed,
}

final class Combatant {
  Combatant({
    required this.id,
    required this.side,
    required this.hp,
    required this.maxHp,
    required this.attack,
    required this.defense,
    required this.speed,
    this.mp = 0,
    this.maxMp = 0,
    Set<String> spellIds = const {},
    List<EnemyMove> pattern = const [],
    this.isBoss = false,
  }) : spellIds = Set.unmodifiable(spellIds),
       pattern = List.unmodifiable(pattern) {
    if (id.isEmpty ||
        id.trim() != id ||
        maxHp <= 0 ||
        hp < 0 ||
        hp > maxHp ||
        attack < 0 ||
        defense < 0 ||
        speed < 0 ||
        mp < 0 ||
        maxMp < mp) {
      throw ArgumentError('Invalid combatant');
    }
  }
  final String id;
  final BattleSide side;
  final int hp, maxHp, attack, defense, speed, mp, maxMp;
  final Set<String> spellIds;
  final List<EnemyMove> pattern;
  final bool isBoss;
  bool get isAlive => hp > 0;
  Combatant _with({int? hp, int? mp}) => Combatant(
    id: id,
    side: side,
    hp: (hp ?? this.hp).clamp(0, maxHp),
    maxHp: maxHp,
    attack: attack,
    defense: defense,
    speed: speed,
    mp: (mp ?? this.mp).clamp(0, maxMp),
    maxMp: maxMp,
    spellIds: spellIds,
    pattern: pattern,
    isBoss: isBoss,
  );
}

final class HeroCommand {
  const HeroCommand.attack(this.actorId, String target)
    : action = BattleAction.attack,
      targetId = target,
      effectId = null;
  const HeroCommand.defend(this.actorId)
    : action = BattleAction.defend,
      targetId = null,
      effectId = null;
  const HeroCommand.spell(this.actorId, this.effectId, this.targetId)
    : action = BattleAction.spell;
  const HeroCommand.item(this.actorId, this.effectId, this.targetId)
    : action = BattleAction.item;
  final String actorId;
  final BattleAction action;
  final String? targetId, effectId;
}

final class BattleSnapshot {
  BattleSnapshot._(
    this.round,
    List<Combatant> combatants,
    this.outcome,
    Map<String, int> inventory,
  ) : combatants = List.unmodifiable(combatants),
      inventory = Map.unmodifiable(inventory);
  final int round;
  final List<Combatant> combatants;
  final BattleOutcome outcome;
  final Map<String, int> inventory;
}

final class BattleEvent {
  const BattleEvent({
    required this.kind,
    required this.actorId,
    this.targetId,
    this.damage = 0,
    this.restored = 0,
    this.effectId,
  });
  final BattleEventKind kind;
  final String actorId;
  final String? targetId, effectId;
  final int damage, restored;
}

final class RoundResult {
  RoundResult._(this.resolvedRound, this.snapshot, List<BattleEvent> events)
    : events = List.unmodifiable(events);
  final int resolvedRound;
  final BattleSnapshot snapshot;
  final List<BattleEvent> events;
}

/// One engine per encounter. Rejected submissions change neither state nor RNG.
final class BattleEngine {
  BattleEngine({
    required List<Combatant> combatants,
    required this._random,
    CombatRules? rules,
    Map<String, int> inventory = const {},
  }) : rules = rules ?? CombatRules() {
    final roster = List<Combatant>.of(combatants);
    if (roster.where((c) => c.side == BattleSide.heroes).length != 4 ||
        !roster.any((c) => c.side == BattleSide.enemies) ||
        roster.map((c) => c.id).toSet().length != roster.length ||
        inventory.entries.any((e) => e.key.trim().isEmpty || e.value < 0)) {
      throw ArgumentError('Invalid roster or inventory');
    }
    for (final c in roster) {
      if (c.spellIds.any((id) => !this.rules.spells.containsKey(id)) ||
          c.pattern.any(
            (m) =>
                m.kind == EnemyMoveKind.spell &&
                (!c.spellIds.contains(m.spellId) ||
                    !this.rules.spells.containsKey(m.spellId)),
          )) {
        throw ArgumentError('Unknown or unlearned spell in roster');
      }
    }
    _snapshot = BattleSnapshot._(1, roster, _outcome(roster), inventory);
  }
  final Random _random;
  final CombatRules rules;
  late BattleSnapshot _snapshot;
  BattleSnapshot get snapshot => _snapshot;
  bool get canFlee =>
      rules.flee != null &&
      !snapshot.combatants.any(
        (c) => c.side == BattleSide.enemies && c.isBoss,
      ) &&
      snapshot.outcome == BattleOutcome.ongoing;

  CombatEffect? effect(HeroCommand command) => switch (command.action) {
    BattleAction.spell => rules.spells[command.effectId],
    BattleAction.item => rules.items[command.effectId],
    _ => null,
  };
  static bool validEffectTarget(
    CombatEffect effect,
    Combatant actor,
    Combatant target,
  ) => effect.kind == EffectKind.damage
      ? target.side != actor.side && target.isAlive
      : target.side == actor.side &&
            (effect.kind == EffectKind.revive
                ? !target.isAlive
                : target.isAlive);

  void _checkRound(int round) {
    if (snapshot.outcome != BattleOutcome.ongoing) {
      throw StateError('Battle has ended');
    }
    if (round != snapshot.round) throw StateError('Stale round');
  }

  RoundResult resolveRound({
    required int expectedRound,
    required List<HeroCommand> commands,
  }) {
    _checkRound(expectedRound);
    final byId = {for (final c in snapshot.combatants) c.id: c};
    final selected = <String, HeroCommand>{};
    final reserved = <String, int>{};
    for (final command in commands) {
      final actor = byId[command.actorId];
      final target = byId[command.targetId];
      if (actor == null ||
          actor.side != BattleSide.heroes ||
          !actor.isAlive ||
          selected.containsKey(actor.id)) {
        throw ArgumentError('Command actor must be a distinct living hero');
      }
      if (command.action == BattleAction.attack &&
          target?.side != BattleSide.enemies) {
        throw ArgumentError('Attack target must be a known enemy');
      }
      if (command.action == BattleAction.spell ||
          command.action == BattleAction.item) {
        final e = effect(command);
        if (e == null ||
            target == null ||
            !validEffectTarget(e, actor, target)) {
          throw ArgumentError('Invalid effect or target');
        }
        if (command.action == BattleAction.spell &&
            (!actor.spellIds.contains(e.id) || actor.mp < e.mpCost)) {
          throw ArgumentError('Unlearned spell or insufficient MP');
        }
        if (command.action == BattleAction.item) {
          reserved[e.id] = (reserved[e.id] ?? 0) + 1;
          if (reserved[e.id]! > (snapshot.inventory[e.id] ?? 0)) {
            throw ArgumentError('Insufficient items for selected commands');
          }
        }
      }
      selected[actor.id] = command;
    }
    if (selected.length !=
        snapshot.combatants
            .where((c) => c.side == BattleSide.heroes && c.isAlive)
            .length) {
      throw ArgumentError('Select one command for every living hero');
    }
    return _resolve(selected);
  }

  /// One party-wide attempt; failure forfeits hero actions for this round.
  RoundResult attemptFlee({required int expectedRound}) {
    _checkRound(expectedRound);
    if (!canFlee) throw StateError('Escape unavailable');
    final rule = rules.flee!;
    int fastest(BattleSide side) => snapshot.combatants
        .where((c) => c.side == side && c.isAlive)
        .map((c) => c.speed)
        .reduce(max);
    final chance =
        (rule.basePercent +
                rule.speedWeight *
                    (fastest(BattleSide.heroes) - fastest(BattleSide.enemies)))
            .clamp(rule.minimumPercent, rule.maximumPercent);
    final escaped = _random.nextInt(100) < chance;
    final event = BattleEvent(
      kind: escaped ? BattleEventKind.fled : BattleEventKind.fleeFailed,
      actorId: 'party',
    );
    if (!escaped) {
      return _resolve({}, enemiesOnly: true, initialEvents: [event]);
    }
    _snapshot = BattleSnapshot._(
      snapshot.round,
      snapshot.combatants,
      BattleOutcome.fled,
      snapshot.inventory,
    );
    return RoundResult._(snapshot.round, snapshot, [event]);
  }

  RoundResult _resolve(
    Map<String, HeroCommand> selected, {
    bool enemiesOnly = false,
    List<BattleEvent> initialEvents = const [],
  }) {
    final roster = snapshot.combatants;
    final enemyMoves = <String, EnemyMove>{
      for (final c in roster.where(
        (c) => c.side == BattleSide.enemies && c.isAlive,
      ))
        c.id: c.pattern.isEmpty
            ? const EnemyMove.attack()
            : c.pattern[(snapshot.round - 1) % c.pattern.length],
    };
    final defending = {
      ...selected.values
          .where((c) => c.action == BattleAction.defend)
          .map((c) => c.actorId),
      ...enemyMoves.entries
          .where((e) => e.value.kind == EnemyMoveKind.defend)
          .map((e) => e.key),
    };
    final order = [
      for (var i = 0; i < roster.length; i++)
        if (roster[i].isAlive &&
            (!enemiesOnly || roster[i].side == BattleSide.enemies))
          i,
    ];
    order.sort((a, b) {
      final speed = roster[b].speed.compareTo(roster[a].speed);
      if (speed != 0) return speed;
      final side = roster[a].side.index.compareTo(roster[b].side.index);
      return side != 0 ? side : a.compareTo(b);
    });
    final current = List<Combatant>.of(roster);
    final inventory = Map<String, int>.of(snapshot.inventory);
    final events = List<BattleEvent>.of(initialEvents);
    var outcome = BattleOutcome.ongoing;
    for (final index in order) {
      final actor = current[index];
      if (!actor.isAlive) {
        events.add(
          BattleEvent(kind: BattleEventKind.skippedKnockout, actorId: actor.id),
        );
        continue;
      }
      var command = selected[actor.id];
      if (actor.side == BattleSide.enemies) {
        final move = enemyMoves[actor.id]!;
        if (move.kind == EnemyMoveKind.defend) {
          command = HeroCommand.defend(actor.id);
        } else {
          final spell = rules.spells[move.spellId];
          final targets = current
              .where(
                (c) => spell != null && actor.mp >= spell.mpCost
                    ? validEffectTarget(spell, actor, c)
                    : c.side != actor.side && c.isAlive,
              )
              .toList();
          if (move.target == EnemyTarget.lowestHp) {
            // Stable roster order breaks equal-HP ties.
            targets.sort((a, b) {
              final hp = a.hp.compareTo(b.hp);
              return hp != 0
                  ? hp
                  : current.indexOf(a).compareTo(current.indexOf(b));
            });
          }
          command =
              spell != null && actor.mp >= spell.mpCost && targets.isNotEmpty
              ? HeroCommand.spell(actor.id, spell.id, targets.first.id)
              : HeroCommand.attack(
                  actor.id,
                  targets.isNotEmpty &&
                          (spell == null || actor.mp < spell.mpCost)
                      ? targets.first.id
                      : current
                            .firstWhere(
                              (c) => c.side != actor.side && c.isAlive,
                            )
                            .id,
                );
        }
      }
      if (command!.action == BattleAction.defend) {
        events.add(
          BattleEvent(kind: BattleEventKind.defend, actorId: actor.id),
        );
        continue;
      }
      final e = effect(command);
      var targetIndex = current.indexWhere((c) => c.id == command!.targetId);
      final damageAction =
          command.action == BattleAction.attack || e?.kind == EffectKind.damage;
      if (damageAction && (targetIndex < 0 || !current[targetIndex].isAlive)) {
        targetIndex = current.indexWhere(
          (c) => c.side != actor.side && c.isAlive,
        );
      }
      if (targetIndex < 0 ||
          (e != null && !validEffectTarget(e, actor, current[targetIndex]))) {
        events.add(
          BattleEvent(
            kind: BattleEventKind.skippedTarget,
            actorId: actor.id,
            effectId: command.effectId,
          ),
        );
        continue; // Target became invalid; no cost and no automatic ally retarget.
      }
      if (command.action == BattleAction.spell) {
        current[index] = actor._with(mp: actor.mp - e!.mpCost);
      }
      if (command.action == BattleAction.item) {
        inventory[e!.id] = inventory[e.id]! - 1;
      }
      // Read after paying MP so self-healing never refunds the spell cost.
      final target = current[targetIndex];
      var damage = 0;
      var restored = 0;
      if (damageAction) {
        damage =
            e?.power ??
            max(1, actor.attack - target.defense + _random.nextInt(3) - 1);
        if (defending.contains(target.id)) damage = (damage + 1) ~/ 2;
        current[targetIndex] = target._with(hp: target.hp - damage);
        damage = target.hp - current[targetIndex].hp;
      } else if (e!.kind == EffectKind.restoreMp) {
        current[targetIndex] = target._with(mp: target.mp + e.power);
        restored = current[targetIndex].mp - target.mp;
      } else {
        current[targetIndex] = target._with(hp: target.hp + e.power);
        restored = current[targetIndex].hp - target.hp;
      }
      events.add(
        BattleEvent(
          kind: switch (command.action) {
            BattleAction.spell => BattleEventKind.spell,
            BattleAction.item => BattleEventKind.item,
            _ => BattleEventKind.attack,
          },
          actorId: actor.id,
          targetId: target.id,
          damage: damage,
          restored: restored,
          effectId: e?.id,
        ),
      );
      outcome = _outcome(current);
      if (outcome != BattleOutcome.ongoing) break;
    }
    final round = snapshot.round;
    _snapshot = BattleSnapshot._(
      outcome == BattleOutcome.ongoing ? round + 1 : round,
      current,
      outcome,
      inventory,
    );
    return RoundResult._(round, snapshot, events);
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
