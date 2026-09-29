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

/// C2 adapter for C1's Attack/Defend slice. No rewards or resource costs.
/// A receives the result and remains the owner of the application state.
final class BattleSession {
  BattleSession({
    required this.input,
    required Map<String, CombatStats> heroStats,
    required List<Combatant> enemies,
    this.fleePolicy,
  }) {
    if (enemies.any((e) => e.side != BattleSide.enemies)) {
      throw ArgumentError('Enemy roster contains a hero');
    }
    _engine = BattleEngine(
      combatants: [
        for (final member in input.state.party)
          _hero(member, heroStats[member.id]),
        ...enemies,
      ],
      random: Random(input.seed),
    );
    _captureOutcome();
  }

  final shared.BattleInput input;
  final FleePolicy? fleePolicy;
  late final BattleEngine _engine;
  shared.BattleResult? _result;
  bool _fleePending = false;
  BattleSnapshot get snapshot => _engine.snapshot;
  shared.BattleResult? get result => _result;

  static Combatant _hero(shared.PartyMember member, CombatStats? stats) {
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
    if (_result != null || _fleePending || fleePolicy == null) return false;
    _fleePending = true;
    try {
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
    } else if (snapshot.outcome == BattleOutcome.defeat) {
      _result = _makeResult(shared.BattleOutcome.defeat);
    }
  }

  shared.BattleResult _makeResult(shared.BattleOutcome outcome) {
    final hp = {for (final c in snapshot.combatants) c.id: c.hp};
    return shared.BattleResult(
      encounterId: input.encounterId,
      baseRevision: input.baseRevision,
      outcome: outcome,
      party: [
        for (final m in input.state.party)
          shared.PartyMember(
            id: m.id,
            jobId: m.jobId,
            hp: hp[m.id]!,
            maxHp: m.maxHp,
            mp: m.mp,
            maxMp: m.maxMp,
            level: m.level,
            experience: m.experience,
            jobProgress: m.jobProgress,
            equipment: m.equipment,
          ),
      ],
      inventory: input.state.inventory,
      gold: input.state.gold,
    );
  }
}
