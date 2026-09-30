import '../core/contracts.dart' as shared;
import '../progression.dart';
import 'battle.dart';
import 'battle_session.dart';

/// C5's rewards are returned in C's one terminal battle snapshot.
final class BattleRewards {
  const BattleRewards({required this.experience, required this.gold});

  final int experience;
  final int gold;
}

/// One authored enemy entry with C-owned numbers and behaviour.
final class LanternEncounter {
  const LanternEncounter({
    required this.id,
    required this.hp,
    required this.attack,
    required this.defense,
    required this.speed,
    required this.mp,
    required this.spellIds,
    required this.pattern,
    required this.rewards,
    this.isBoss = false,
  });

  final String id;
  final int hp, attack, defense, speed, mp;
  final Set<String> spellIds;
  final List<EnemyMove> pattern;
  final BattleRewards rewards;
  final bool isBoss;

  Combatant spawn() => Combatant(
    id: id,
    side: BattleSide.enemies,
    hp: hp,
    maxHp: hp,
    attack: attack,
    defense: defense,
    speed: speed,
    mp: mp,
    maxMp: mp,
    spellIds: spellIds,
    pattern: pattern,
    isBoss: isBoss,
  );
}

/// C5's encounter numbers. D owns the names and stable IDs in its content file.
final class LanternBalance {
  LanternBalance({LanternJobRules? progression})
    : progression = progression ?? LanternJobRules();

  final LanternJobRules progression;

  static const encounters = <String, LanternEncounter>{
    'enemy.brine_mite': LanternEncounter(
      id: 'enemy.brine_mite',
      hp: 28,
      attack: 6,
      defense: 1,
      speed: 7,
      mp: 0,
      spellIds: {},
      pattern: [EnemyMove.attack()],
      rewards: BattleRewards(experience: 24, gold: 8),
    ),
    'enemy.wick_moth': LanternEncounter(
      id: 'enemy.wick_moth',
      hp: 40,
      attack: 5,
      defense: 2,
      speed: 10,
      mp: 6,
      spellIds: {'spell.ember'},
      pattern: [
        EnemyMove.spell('spell.ember', target: EnemyTarget.lowestHp),
        EnemyMove.attack(),
      ],
      rewards: BattleRewards(experience: 30, gold: 12),
    ),
    'enemy.silt_guard': LanternEncounter(
      id: 'enemy.silt_guard',
      hp: 54,
      attack: 8,
      defense: 6,
      speed: 4,
      mp: 0,
      spellIds: {},
      pattern: [EnemyMove.defend(), EnemyMove.attack()],
      rewards: BattleRewards(experience: 42, gold: 18),
    ),
    'enemy.hollow_bell': LanternEncounter(
      id: 'enemy.hollow_bell',
      hp: 108,
      attack: 0,
      defense: 5,
      speed: 8,
      mp: 12,
      spellIds: {'spell.rill'},
      pattern: [
        EnemyMove.spell('spell.rill', target: EnemyTarget.lowestHp),
        EnemyMove.defend(),
      ],
      rewards: BattleRewards(experience: 90, gold: 50),
      isBoss: true,
    ),
  };

  /// The encounter-specific values avoid changing C3's practice-rules tests.
  CombatRules get rules => CombatRules(
    spells: [
      CombatEffect(
        id: 'spell.mend',
        name: 'Mend',
        kind: EffectKind.heal,
        power: 14,
        mpCost: 2,
      ),
      CombatEffect(
        id: 'spell.ember',
        name: 'Ember',
        kind: EffectKind.damage,
        power: 11,
        mpCost: 3,
      ),
      CombatEffect(
        id: 'spell.rill',
        name: 'Rill',
        kind: EffectKind.damage,
        power: 8,
        mpCost: 3,
      ),
    ],
    items: [
      CombatEffect(
        id: 'item.salves',
        name: 'Harbor Salve',
        kind: EffectKind.heal,
        power: 18,
      ),
      CombatEffect(
        id: 'item.ether',
        name: 'Dew Phial',
        kind: EffectKind.restoreMp,
        power: 8,
      ),
      CombatEffect(
        id: 'item.revival',
        name: 'Wake Seed',
        kind: EffectKind.revive,
        power: 12,
      ),
    ],
    flee: FleeRules(),
  );

  BattleSession createSession(shared.BattleInput input) {
    final encounter = encounters[input.request.definitionId];
    if (encounter == null) {
      throw ArgumentError.value(input.request.definitionId, 'definitionId');
    }
    return BattleSession(
      input: input,
      rules: rules,
      heroStats: {
        for (final member in input.state.party)
          member.id: _stats(progression.profileFor(member)),
      },
      heroSpells: {
        for (final member in input.state.party)
          member.id: progression.profileFor(member).commandIds,
      },
      enemies: [encounter.spawn()],
      victoryRewardApplier: (state) => _applyRewards(state, encounter.rewards),
    );
  }

  shared.GameState _applyRewards(
    shared.GameState state,
    BattleRewards rewards,
  ) {
    final progressed = progression.grantExperience(
      state,
      amount: rewards.experience,
    );
    return shared.GameState(
      position: progressed.position,
      party: progressed.party,
      inventory: progressed.inventory,
      gold: progressed.gold + rewards.gold,
      quests: progressed.quests,
    );
  }

  static CombatStats _stats(JobProfile profile) => CombatStats(
    attack: profile.attack,
    defense: profile.defense,
    speed: profile.speed,
  );
}
