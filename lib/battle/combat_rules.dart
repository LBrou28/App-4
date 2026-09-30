/// C-owned numerical rules; D owns names, narrative and stable content IDs.
enum EffectKind { damage, heal, revive, restoreMp }

final class CombatEffect {
  CombatEffect({
    required this.id,
    required this.name,
    required this.kind,
    required this.power,
    this.mpCost = 0,
  }) {
    if (id.trim().isEmpty ||
        id.trim() != id ||
        name.trim().isEmpty ||
        power <= 0 ||
        mpCost < 0) {
      throw ArgumentError('Invalid combat effect');
    }
  }
  final String id;
  final String name;
  final EffectKind kind;

  /// Flat HP/MP amount. Damage ignores physical defense, but respects Defend.
  final int power;
  final int mpCost;
}

enum EnemyMoveKind { attack, defend, spell }

enum EnemyTarget { firstLiving, lowestHp }

final class EnemyMove {
  const EnemyMove.attack({this.target = EnemyTarget.firstLiving})
    : kind = EnemyMoveKind.attack,
      spellId = null;
  const EnemyMove.defend()
    : kind = EnemyMoveKind.defend,
      spellId = null,
      target = EnemyTarget.firstLiving;
  const EnemyMove.spell(this.spellId, {this.target = EnemyTarget.firstLiving})
    : kind = EnemyMoveKind.spell;
  final EnemyMoveKind kind;
  final EnemyTarget target;
  final String? spellId;
}

final class FleeRules {
  FleeRules({
    this.basePercent = 50,
    this.speedWeight = 5,
    this.minimumPercent = 10,
    this.maximumPercent = 90,
  }) {
    if (minimumPercent < 0 ||
        maximumPercent > 100 ||
        minimumPercent > maximumPercent ||
        basePercent < 0 ||
        basePercent > 100 ||
        speedWeight < 0) {
      throw ArgumentError('Invalid flee rules');
    }
  }
  final int basePercent, speedWeight, minimumPercent, maximumPercent;
}

final class CombatRules {
  CombatRules({
    List<CombatEffect> spells = const [],
    List<CombatEffect> items = const [],
    this.flee,
  }) : spells = _index(spells),
       items = _index(items) {
    if (items.any((e) => e.mpCost != 0)) {
      throw ArgumentError('Items consume inventory, not MP');
    }
  }
  final Map<String, CombatEffect> spells, items;
  final FleeRules? flee;
  static Map<String, CombatEffect> _index(List<CombatEffect> values) {
    final result = {for (final e in values) e.id: e};
    if (result.length != values.length) {
      throw ArgumentError('Duplicate effect ID');
    }
    return Map.unmodifiable(result);
  }
}

/// Initial C3 tuning; C5 owns final encounter balance.
CombatRules lanternCombatRules() => CombatRules(
  spells: [
    CombatEffect(
      id: 'spell.mend',
      name: 'Mend',
      kind: EffectKind.heal,
      power: 12,
      mpCost: 2,
    ),
    CombatEffect(
      id: 'spell.ember',
      name: 'Ember',
      kind: EffectKind.damage,
      power: 10,
      mpCost: 3,
    ),
    CombatEffect(
      id: 'spell.rill',
      name: 'Rill',
      kind: EffectKind.damage,
      power: 10,
      mpCost: 3,
    ),
  ],
  items: [
    CombatEffect(
      id: 'item.salves',
      name: 'Harbor Salve',
      kind: EffectKind.heal,
      power: 20,
    ),
    CombatEffect(
      id: 'item.ether',
      name: 'Dew Phial',
      kind: EffectKind.restoreMp,
      power: 6,
    ),
    CombatEffect(
      id: 'item.revival',
      name: 'Wake Seed',
      kind: EffectKind.revive,
      power: 10,
    ),
  ],
  flee: FleeRules(),
);

const lanternEnemyPatterns = <String, List<EnemyMove>>{
  'enemy.brine_mite': [EnemyMove.attack()],
  'enemy.wick_moth': [
    EnemyMove.spell('spell.ember', target: EnemyTarget.lowestHp),
    EnemyMove.attack(),
  ],
  'enemy.silt_guard': [EnemyMove.defend(), EnemyMove.attack()],
  'enemy.hollow_bell': [
    EnemyMove.spell('spell.rill'),
    EnemyMove.attack(),
    EnemyMove.defend(),
  ],
};
