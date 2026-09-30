import 'package:flutter/material.dart';

import '../../core/contracts.dart' as shared;
import '../../ui/game_theme.dart';
import '../battle.dart';
import '../battle_session.dart';
import '../ui/battle_screen.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: lanternTheme(),
    home: const C3Demo(),
  ),
);

/// C3 practice fixture. HP/stats and inventory are not campaign starting data.
BattleSession createC3DemoSession({bool boss = false}) {
  const ids = ['hero.ada', 'hero.ren', 'hero.iona', 'hero.tavi'];
  const jobs = ['job.warrior', 'job.monk', 'job.white_mage', 'job.black_mage'];
  final state = shared.GameState(
    position: shared.WorldPosition(mapId: 'map.bellwether', x: 1.5, y: 1.5),
    party: [
      for (var i = 0; i < 4; i++)
        shared.PartyMember(
          id: ids[i],
          jobId: jobs[i],
          hp: i == 1
              ? 0
              : i == 0
              ? 12
              : 30,
          maxHp: 30,
          mp: 6,
          maxMp: 6,
          level: 1,
          experience: 0,
          jobProgress: {jobs[i]: 0},
          equipment: {},
        ),
    ],
    inventory: shared.Inventory({
      'item.salves': 2,
      'item.ether': 1,
      'item.revival': 1,
    }),
    gold: 0,
    quests: shared.QuestFlags(flags: {}, openedChestIds: {}),
  );
  final enemyId = boss ? 'enemy.hollow_bell' : 'enemy.wick_moth';
  return BattleSession(
    input: shared.BattleInput(
      encounterId: 'c3.practice',
      baseRevision: 1,
      request: shared.EncounterRequest(definitionId: 'c3.practice'),
      state: state,
      seed: 17,
    ),
    rules: lanternCombatRules(),
    heroStats: {
      for (final id in ids)
        id: const CombatStats(attack: 7, defense: 2, speed: 10),
    },
    heroSpells: const {
      'hero.iona': {'spell.mend'},
      'hero.tavi': {'spell.ember', 'spell.rill'},
    },
    enemies: [
      Combatant(
        id: enemyId,
        side: BattleSide.enemies,
        hp: boss ? 100 : 60,
        maxHp: boss ? 100 : 60,
        attack: 6,
        defense: 3,
        speed: 5,
        mp: 6,
        maxMp: 6,
        spellIds: {boss ? 'spell.rill' : 'spell.ember'},
        pattern: lanternEnemyPatterns[enemyId]!,
        isBoss: boss,
      ),
    ],
  );
}

class C3Demo extends StatefulWidget {
  const C3Demo({super.key});
  @override
  State<C3Demo> createState() => _C3DemoState();
}

class _C3DemoState extends State<C3Demo> {
  BattleSession? _session;
  shared.BattleResult? _result;
  @override
  Widget build(BuildContext context) => _session != null && _result == null
      ? BattleScreen(
          session: _session!,
          title: 'C3 combat practice',
          names: const {
            'hero.ada': 'Ada',
            'hero.ren': 'Ren',
            'hero.iona': 'Iona',
            'hero.tavi': 'Tavi',
            'enemy.wick_moth': 'Wick Moth',
            'enemy.hollow_bell': 'The Hollow Bell',
          },
          onCompleted: (result) => setState(() => _result = result),
        )
      : Scaffold(
          body: Center(
            child: SizedBox(
              width: 380,
              child: MenuPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _result == null
                          ? 'C3 combat practice'
                          : 'Result: ${_result!.outcome.name}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Practice magic, recovery items and escape. Ren starts knocked out so you can try a Wake Seed. No campaign progress is saved.',
                    ),
                    if (_result != null)
                      Text(
                        'Items remaining: ${_result!.inventory.quantities.values.fold(0, (a, b) => a + b)}',
                      ),
                    const SizedBox(height: 16),
                    for (final boss in [false, true])
                      FilledButton(
                        onPressed: () => setState(() {
                          _session = createC3DemoSession(boss: boss);
                          _result = null;
                        }),
                        child: Text(
                          boss ? 'Boss practice' : 'Regular practice',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
}
