import 'package:flutter/material.dart';

import '../../core/contracts.dart' as shared;
import '../../core/fixtures/contract_fixture.dart';
import '../../ui/game_theme.dart';
import '../battle.dart';
import '../battle_session.dart';
import '../ui/battle_screen.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: lanternTheme(),
    home: const BattleDemo(),
  ),
);

/// Synthetic encounter. Guaranteed escape is a demo policy, not C3 balance.
BattleSession createBattleDemoSession() => BattleSession(
  input: shared.BattleInput(
    encounterId: 'fixture.encounter',
    baseRevision: 1,
    request: shared.EncounterRequest(definitionId: 'fixture.battle'),
    state: createContractFixture(),
    seed: 17,
  ),
  heroStats: {
    for (var i = 0; i < 4; i++)
      'fixture.hero.$i': CombatStats(attack: 5 + i, defense: 2, speed: 8 - i),
  },
  enemies: [
    for (var i = 0; i < 2; i++)
      Combatant(
        id: 'fixture.enemy.$i',
        side: BattleSide.enemies,
        hp: 24,
        maxHp: 24,
        attack: 5,
        defense: 2,
        speed: 5,
      ),
  ],
  fleePolicy: (_) async => true,
);

class BattleDemo extends StatefulWidget {
  const BattleDemo({super.key});
  @override
  State<BattleDemo> createState() => _BattleDemoState();
}

class _BattleDemoState extends State<BattleDemo> {
  BattleSession _session = createBattleDemoSession();
  shared.BattleResult? _result;
  @override
  Widget build(BuildContext context) => _result == null
      ? BattleScreen(
          session: _session,
          title: 'Training encounter',
          names: const {
            'fixture.hero.0': 'Ash',
            'fixture.hero.1': 'Mira',
            'fixture.hero.2': 'Rowan',
            'fixture.hero.3': 'Wren',
            'fixture.enemy.0': 'Bramble crawler',
            'fixture.enemy.1': 'Moss beetle',
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
                    const Icon(Icons.flag_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(switch (_result!.outcome) {
                      shared.BattleOutcome.victory => 'Victory',
                      shared.BattleOutcome.defeat => 'Defeat',
                      shared.BattleOutcome.fled => 'Escaped',
                    }, style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 12),
                    const Text(
                      'Training complete. No rewards are granted. Escape always succeeds in this practice encounter.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => setState(() {
                        _session = createBattleDemoSession();
                        _result = null;
                      }),
                      child: const Text('Play again'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
}
