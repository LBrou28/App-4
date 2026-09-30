import 'dart:math';

import '../core/contracts.dart' as shared;
import 'battle.dart';

/// C supplies combat stats; shared party data does not yet define their source.
final class CombatStats {
  const CombatStats({
    required this.attack,
    required this.defense,
    required this.speed,
  });
  final int attack;
  final int defense;
  final int speed;
}

typedef FleePolicy = Future<bool> Function(BattleSnapshot snapshot);

/// Adapts C battle HP/MP/inventory to the shared result. No rewards.
/// A receives the result and remains the owner of the application state.
final class BattleSession {
  BattleSession({
    required this.input,
    required Map<String, CombatStats> heroStats,
    required List<Combatant> enemies,
    this.fleePolicy,
    CombatRules? rules,
    Map<String, Set<String>> heroSpells = const {},
  }) {
    if (enemies.any((e) => e.side != BattleSide.enemies)) {
      throw ArgumentError('Enemy roster contains a hero');
    }
    _engine = BattleEngine(
      combatants: [
        for (final member in input.state.party)
          _hero(member, heroStats[member.id], heroSpells[member.id] ?? {}),
        ...enemies,
      ],
      random: Random(input.seed),
      rules: rules,
      inventory: input.state.inventory.quantities,
    );
    _captureOutcome();
  }

  final shared.BattleInput input;
  final FleePolicy? fleePolicy;
  late final BattleEngine _engine;
  shared.BattleResult? _result;
  bool _fleePending = false;
  CombatRules get rules => _engine.rules;
  bool get isBoss =>
      snapshot.combatants.any((c) => c.side == BattleSide.enemies && c.isBoss);
  bool get canFlee =>
      result == null && !isBoss && (fleePolicy != null || _engine.canFlee);
  RoundResult? lastFleeRound;
  BattleSnapshot get snapshot => _engine.snapshot;
  shared.BattleResult? get result => _result;

  static Combatant _hero(
    shared.PartyMember member,
    CombatStats? stats,
    Set<String> spells,
  ) {
    if (stats == null) {
      throw ArgumentError('Missing combat stats for ${member.id}');
    }
    return Combatant(
      id: member.id,
      side: BattleSide.heroes,
      hp: member.hp,
      maxHp: member.maxHp,
      attack: stats.attack,
      defense: stats.defense,
      speed: stats.speed,
      mp: member.mp,
      maxMp: member.maxMp,
      spellIds: spells,
    );
  }

  RoundResult resolve(int round, List<HeroCommand> commands) {
    if (_result != null || _fleePending) {
      throw StateError('Battle is unavailable');
    }
    final resolved = _engine.resolveRound(
      expectedRound: round,
      commands: commands,
    );
    _captureOutcome();
    return resolved;
  }

  Future<bool> flee() async {
    if (_fleePending || !canFlee) return false;
    _fleePending = true;
    try {
      lastFleeRound = null;
      if (fleePolicy == null) {
        lastFleeRound = _engine.attemptFlee(expectedRound: snapshot.round);
        _captureOutcome();
        return snapshot.outcome == BattleOutcome.fled;
      }
      if (!await fleePolicy!(snapshot)) return false;
      _result = _makeResult(shared.BattleOutcome.fled);
      return true;
    } finally {
      _fleePending = false;
    }
  }

  void _captureOutcome() {
    if (snapshot.outcome == BattleOutcome.victory) {
      _result = _makeResult(shared.BattleOutcome.victory);
    } else if (snapshot.outcome == BattleOutcome.fled) {
      _result = _makeResult(shared.BattleOutcome.fled);
    } else if (snapshot.outcome == BattleOutcome.defeat) {
      _result = _makeResult(shared.BattleOutcome.defeat);
    }
  }

  shared.BattleResult _makeResult(shared.BattleOutcome outcome) {
    final actors = {for (final c in snapshot.combatants) c.id: c};
    return shared.BattleResult(
      encounterId: input.encounterId,
      baseRevision: input.baseRevision,
      outcome: outcome,
      party: [
        for (final m in input.state.party)
          shared.PartyMember(
            id: m.id,
            jobId: m.jobId,
            hp: actors[m.id]!.hp,
            maxHp: m.maxHp,
            mp: actors[m.id]!.mp,
            maxMp: m.maxMp,
            level: m.level,
            experience: m.experience,
            jobProgress: m.jobProgress,
            equipment: m.equipment,
          ),
      ],
      inventory:
          snapshot.inventory.length ==
                  input.state.inventory.quantities.length &&
              snapshot.inventory.entries.every(
                (e) => input.state.inventory.quantities[e.key] == e.value,
              )
          ? input.state.inventory
          : shared.Inventory(snapshot.inventory),
      gold: input.state.gold,
    );
  }
}
