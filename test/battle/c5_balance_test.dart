import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/battle/lantern_balance.dart';
import 'package:app_4/core/contracts.dart' as shared;
import 'package:app_4/progression.dart';
import 'package:flutter_test/flutter_test.dart';

const _heroIds = ['hero.ada', 'hero.ren', 'hero.iona', 'hero.tavi'];

shared.GameState freshParty(List<String> jobs) {
  final progression = LanternJobRules();
  return shared.GameState(
    position: shared.WorldPosition(mapId: 'map.bellwether', x: 1.5, y: 1.5),
    party: [
      for (var index = 0; index < jobs.length; index++)
        _freshMember(_heroIds[index], jobs[index], progression),
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

shared.PartyMember _freshMember(
  String id,
  String jobId,
  LanternJobRules progression,
) {
  final placeholder = shared.PartyMember(
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
  final profile = progression.profileFor(placeholder);
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

shared.BattleInput inputFor(shared.GameState state, String definitionId) =>
    shared.BattleInput(
      encounterId: 'run.$definitionId',
      baseRevision: 1,
      request: shared.EncounterRequest(definitionId: definitionId),
      state: state,
      seed: 23,
    );

shared.GameState stateFromResult(
  shared.GameState previous,
  shared.BattleResult result,
) => shared.GameState(
  position: previous.position,
  party: result.party,
  inventory: result.inventory,
  gold: result.gold,
  quests: previous.quests,
);

List<HeroCommand> sensibleCommands(BattleSession session) {
  final living = session.snapshot.combatants
      .where(
        (combatant) => combatant.side == BattleSide.heroes && combatant.isAlive,
      )
      .toList();
  final enemy = session.snapshot.combatants.firstWhere(
    (combatant) => combatant.side == BattleSide.enemies && combatant.isAlive,
  );
  final lowest = living.reduce(
    (current, next) => current.hp <= next.hp ? current : next,
  );
  return [
    for (final hero in living)
      if (hero.spellIds.contains('spell.mend') &&
          hero.mp >= session.rules.spells['spell.mend']!.mpCost &&
          lowest.hp * 2 <= lowest.maxHp)
        HeroCommand.spell(hero.id, 'spell.mend', lowest.id)
      else if (hero.spellIds.contains('spell.ember') &&
          hero.mp >= session.rules.spells['spell.ember']!.mpCost)
        HeroCommand.spell(hero.id, 'spell.ember', enemy.id)
      else
        HeroCommand.attack(hero.id, enemy.id),
  ];
}

({shared.BattleResult result, List<BattleEvent> events}) play(
  LanternBalance balance,
  shared.GameState state,
  String encounterId,
) {
  final session = balance.createSession(inputFor(state, encounterId));
  final events = <BattleEvent>[];
  for (var round = 0; session.result == null && round < 20; round++) {
    final resolved = session.resolve(
      session.snapshot.round,
      sensibleCommands(session),
    );
    events.addAll(resolved.events);
  }
  return (result: session.result!, events: events);
}

void main() {
  const route = [
    'enemy.brine_mite',
    'enemy.wick_moth',
    'enemy.silt_guard',
    'enemy.hollow_bell',
  ];

  test('C5 encounter table defines three regular enemies and a boss', () {
    expect(LanternBalance.encounters.keys, route);
    expect(LanternBalance.encounters['enemy.hollow_bell']!.isBoss, isTrue);
    expect(
      LanternBalance.encounters['enemy.hollow_bell']!.pattern
          .map((move) => move.kind),
      [EnemyMoveKind.spell, EnemyMoveKind.defend],
    );
    expect(
      LanternBalance.encounters.values
          .where((encounter) => !encounter.isBoss)
          .length,
      3,
    );
  });

  for (final jobs in [
    const ['job.warrior', 'job.monk', 'job.white_mage', 'job.black_mage'],
    const [
      'job.warrior',
      'job.warrior',
      'job.white_mage',
      'job.black_mage',
    ],
  ]) {
    test('fresh ${jobs.join(', ')} party clears the tuned route', () {
      final balance = LanternBalance();
      var state = freshParty(jobs);
      for (final encounterId in route) {
        final battle = play(balance, state, encounterId);
        expect(battle.result.outcome, shared.BattleOutcome.victory);
        state = stateFromResult(state, battle.result);
      }
      expect(state.gold, 88);
      for (final member in state.party) {
        expect(member.experience, 186);
        expect(member.jobProgress[member.jobId], 186);
        expect(member.level, 2);
      }
    });
  }

  test('the boss needs physical damage and magic across several rounds', () {
    final balance = LanternBalance();
    final battle = play(
      balance,
      freshParty([
        'job.warrior',
        'job.monk',
        'job.white_mage',
        'job.black_mage',
      ]),
      'enemy.hollow_bell',
    );
    expect(battle.result.outcome, shared.BattleOutcome.victory);
    expect(
      battle.events.where((event) => event.actorId == 'enemy.hollow_bell'),
      containsAll([
        isA<BattleEvent>().having(
          (event) => event.kind,
          'Rill',
          BattleEventKind.spell,
        ),
        isA<BattleEvent>().having(
          (event) => event.kind,
          'Defend',
          BattleEventKind.defend,
        ),
      ]),
    );
    expect(
      battle.events.where((event) => event.actorId == 'hero.tavi').any(
        (event) => event.kind == BattleEventKind.spell,
      ),
      isTrue,
    );
    expect(
      battle.events.where((event) => event.actorId == 'hero.ada').any(
        (event) => event.kind == BattleEventKind.attack,
      ),
      isTrue,
    );
    expect(
      battle.events.where((event) => event.actorId == 'enemy.hollow_bell').length,
      greaterThanOrEqualTo(4),
    );
  });

  test('only a victory grants rewards, and the result cannot grant twice', () {
    final balance = LanternBalance();
    final session = balance.createSession(
      inputFor(
        freshParty([
          'job.warrior',
          'job.monk',
          'job.white_mage',
          'job.black_mage',
        ]),
        'enemy.brine_mite',
      ),
    );
    while (session.result == null) {
      session.resolve(session.snapshot.round, sensibleCommands(session));
    }
    final won = session.result!;
    expect(won.gold, 8);
    expect(won.party.map((member) => member.experience), everyElement(24));
    expect(identical(session.result, won), isTrue);
    expect(
      () => session.resolve(session.snapshot.round, sensibleCommands(session)),
      throwsStateError,
    );

    final defeatedState = freshParty([
      'job.warrior',
      'job.monk',
      'job.white_mage',
      'job.black_mage',
    ]);
    final defeated = balance.createSession(
      inputFor(
        shared.GameState(
          position: defeatedState.position,
          party: [
            for (final member in defeatedState.party)
              shared.PartyMember(
                id: member.id,
                jobId: member.jobId,
                hp: 0,
                maxHp: member.maxHp,
                mp: member.mp,
                maxMp: member.maxMp,
                level: member.level,
                experience: member.experience,
                jobProgress: member.jobProgress,
                equipment: member.equipment,
              ),
          ],
          inventory: defeatedState.inventory,
          gold: defeatedState.gold,
          quests: defeatedState.quests,
        ),
        'enemy.brine_mite',
      ),
    ).result!;
    expect(defeated.outcome, shared.BattleOutcome.defeat);
    expect(defeated.gold, 0);
    expect(defeated.party.map((member) => member.experience), everyElement(0));
  });
}
