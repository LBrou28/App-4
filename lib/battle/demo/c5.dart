import 'package:flutter/material.dart';

import '../../core/contracts.dart' as shared;
import '../../progression.dart';
import '../../ui/game_theme.dart';
import '../battle_session.dart';
import '../lantern_balance.dart';
import '../ui/battle_screen.dart';

void main() => runApp(
  MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: lanternTheme(),
    home: const C5Demo(),
  ),
);

/// A review fixture using C4's actual level-one job resources.
BattleSession createC5DemoSession(String definitionId) {
  final balance = LanternBalance();
  final state = _freshState(balance.progression);
  return balance.createSession(
    shared.BattleInput(
      encounterId: 'c5.review.$definitionId',
      baseRevision: 1,
      request: shared.EncounterRequest(definitionId: definitionId),
      state: state,
      seed: 23,
    ),
  );
}

shared.GameState _freshState(LanternJobRules progression) {
  const ids = ['hero.ada', 'hero.ren', 'hero.iona', 'hero.tavi'];
  const jobs = [
    'job.warrior',
    'job.monk',
    'job.white_mage',
    'job.black_mage',
  ];
  return shared.GameState(
    position: shared.WorldPosition(mapId: 'map.bellwether', x: 1.5, y: 1.5),
    party: [
      for (var index = 0; index < ids.length; index++)
        _member(ids[index], jobs[index], progression),
    ],
    inventory: shared.Inventory({
      'item.salves': 2,
      'item.ether': 1,
      'item.revival': 1,
    }),
    gold: 0,
    quests: shared.QuestFlags(flags: {}, openedChestIds: {}),
  );
}

shared.PartyMember _member(
  String id,
  String jobId,
  LanternJobRules progression,
) {
  final levelOne = shared.PartyMember(
    id: id,
    jobId: jobId,
    hp: 1,
    maxHp: 1,
    mp: 0,
    maxMp: 0,
    level: 1,
    experience: 0,
    jobProgress: {jobId: 0},
    equipment: {},
  );
  final profile = progression.profileFor(levelOne);
  return shared.PartyMember(
    id: id,
    jobId: jobId,
    hp: profile.maxHp,
    maxHp: profile.maxHp,
    mp: profile.maxMp,
    maxMp: profile.maxMp,
    level: 1,
    experience: 0,
    jobProgress: {jobId: 0},
    equipment: {},
  );
}

class C5Demo extends StatefulWidget {
  const C5Demo({super.key});

  @override
  State<C5Demo> createState() => _C5DemoState();
}

class _C5DemoState extends State<C5Demo> {
  BattleSession? _session;
  shared.BattleResult? _result;

  @override
  Widget build(BuildContext context) => _session != null && _result == null
      ? BattleScreen(
          session: _session!,
          title: 'C5 balance review',
          names: const {
            'hero.ada': 'Ada',
            'hero.ren': 'Ren',
            'hero.iona': 'Iona',
            'hero.tavi': 'Tavi',
            'enemy.brine_mite': 'Brine Mite',
            'enemy.wick_moth': 'Wick Moth',
            'enemy.silt_guard': 'Silt Guard',
            'enemy.hollow_bell': 'The Hollow Bell',
          },
          onCompleted: (result) => setState(() => _result = result),
        )
      : Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              child: MenuPanel(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _result == null ? 'C5 balance review' : 'Battle result',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'A fresh Warrior, Monk, White Mage and Black Mage party. '
                      'Choose an encounter to review its rewards and behavior.',
                    ),
                    if (_result != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        '${_result!.outcome.name}: ${_result!.gold} gold; '
                        '${_result!.party.first.experience} XP per hero',
                      ),
                    ],
                    const SizedBox(height: 16),
                    for (final encounter in LanternBalance.encounters.values)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: FilledButton(
                          onPressed: () => setState(() {
                            _session = createC5DemoSession(encounter.id);
                            _result = null;
                          }),
                          child: Text(
                            '${encounter.isBoss ? 'Boss: ' : ''}'
                            '${encounter.id.replaceFirst('enemy.', '').replaceAll('_', ' ')} '
                            '(${encounter.rewards.experience} XP, ${encounter.rewards.gold} gold)',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
}
