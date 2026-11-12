import 'package:app_4/battle/battle.dart' hide BattleOutcome;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/multiplayer/lantern_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LanternLinkRoom room() => LanternLinkRoom(
    name: 'bellwether',
    initialState: createContractFixture(),
    createBattle: (input) => BattleSession(
      input: input,
      heroStats: {
        for (final member in input.state.party)
          member.id: const CombatStats(attack: 20, defense: 2, speed: 5),
      },
      enemies: [
        Combatant(
          id: 'enemy.test',
          side: BattleSide.enemies,
          hp: 1,
          maxHp: 1,
          attack: 0,
          defense: 0,
          speed: 1,
        ),
      ],
    ),
  );

  void readyTwoPlayerRoom(LanternLinkRoom value) {
    value.join('host');
    value.join('guest');
    value.configure('host', LanternLinkMode.twoPlayers);
    value.assign('host', {
      'host': ['fixture.hero.0', 'fixture.hero.1'],
      'guest': ['fixture.hero.2', 'fixture.hero.3'],
    });
  }

  test('lobby assigns every hero exactly once and preserves a host', () {
    final value = room();
    value.join('host');
    value.join('guest');
    expect(
      () => value.configure('guest', LanternLinkMode.twoPlayers),
      throwsStateError,
    );
    value.configure('host', LanternLinkMode.twoPlayers);
    expect(
      () => value.assign('host', {
        'host': ['fixture.hero.0', 'fixture.hero.1'],
        'guest': ['fixture.hero.2', 'fixture.hero.2'],
      }),
      throwsArgumentError,
    );
    readyTwoPlayerRoom(value);
    expect(value.snapshot.assignments['guest'], [
      'fixture.hero.2',
      'fixture.hero.3',
    ]);
  });

  test('only assigned players lock commands and the server resolves once', () {
    final value = room();
    readyTwoPlayerRoom(value);
    value.beginBattle('host', definitionId: 'enemy.test', seed: 1);
    expect(
      () => value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.attack('fixture.hero.0', 'enemy.test'),
      ),
      throwsStateError,
    );
    for (final hero in ['fixture.hero.0', 'fixture.hero.1']) {
      value.submitCommand(
        'host',
        round: 1,
        command: HeroCommand.attack(hero, 'enemy.test'),
      );
    }
    value.submitCommand(
      'guest',
      round: 1,
      command: const HeroCommand.attack('fixture.hero.2', 'enemy.test'),
    );
    final event = value.submitCommand(
      'guest',
      round: 1,
      command: const HeroCommand.attack('fixture.hero.3', 'enemy.test'),
    );
    expect(event.kind, 'battleFinished');
    expect(value.snapshot.phase, LanternLinkPhase.exploration);
    expect(value.snapshot.battle, isNull);
    expect(
      () => value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.attack('fixture.hero.3', 'enemy.test'),
      ),
      throwsStateError,
    );
  });

  test(
    'host dialogue is included in the authoritative exploration snapshot',
    () {
      final value = room();
      readyTwoPlayerRoom(value);
      final event = value.publishExploration(
        'host',
        value.snapshot.state,
        expectedRevision: value.snapshot.revision,
        dialogue: LanternLinkDialogue(
          id: 'dialogue.keeper',
          speaker: 'Keeper Mara',
          lines: ['The bell is awake.'],
        ),
      );
      expect(event.snapshot.dialogue?.speaker, 'Keeper Mara');
      expect(event.snapshot.dialogue?.lines, ['The bell is awake.']);
    },
  );

  test('disconnect pauses play until the assigned player reconnects', () {
    final value = room();
    readyTwoPlayerRoom(value);
    value.beginBattle('host', definitionId: 'enemy.test', seed: 1);
    value.leave('guest');
    expect(value.snapshot.phase, LanternLinkPhase.paused);
    expect(
      () => value.submitCommand(
        'host',
        round: 1,
        command: const HeroCommand.attack('fixture.hero.0', 'enemy.test'),
      ),
      throwsStateError,
    );
    value.join('guest');
    expect(value.snapshot.phase, LanternLinkPhase.battle);
  });

  test(
    'invalid command is rejected before locking so round remains recoverable',
    () {
      final base = createContractFixture();
      final state = GameState(
        position: base.position,
        party: base.party,
        inventory: Inventory({'item.salves': 1}),
        gold: base.gold,
        quests: base.quests,
      );
      final value = LanternLinkRoom(
        name: 'bellwether',
        initialState: state,
        createBattle: (input) => BattleSession(
          input: input,
          rules: CombatRules(
            spells: [
              CombatEffect(
                id: 'spell.expensive',
                name: 'Expensive',
                kind: EffectKind.damage,
                power: 5,
                mpCost: 99,
              ),
            ],
            items: [
              CombatEffect(
                id: 'item.salves',
                name: 'Harbor Salve',
                kind: EffectKind.heal,
                power: 10,
              ),
            ],
          ),
          heroStats: {
            for (final member in input.state.party)
              member.id: const CombatStats(attack: 20, defense: 2, speed: 5),
          },
          heroSpells: {
            for (final member in input.state.party)
              member.id: {'spell.expensive'},
          },
          enemies: [
            Combatant(
              id: 'enemy.test',
              side: BattleSide.enemies,
              hp: 100,
              maxHp: 100,
              attack: 1,
              defense: 0,
              speed: 1,
            ),
          ],
        ),
      );
      readyTwoPlayerRoom(value);
      value.beginBattle('host', definitionId: 'enemy.test', seed: 1);
      final revBefore = value.snapshot.revision;

      expect(
        () => value.submitCommand(
          'host',
          round: 1,
          command: const HeroCommand.attack('fixture.hero.0', 'enemy.missing'),
        ),
        throwsArgumentError,
      );
      expect(
        () => value.submitCommand(
          'host',
          round: 1,
          command: const HeroCommand.spell(
            'fixture.hero.0',
            'spell.expensive',
            'enemy.test',
          ),
        ),
        throwsArgumentError,
      );
      expect(value.snapshot.revision, revBefore);

      value.submitCommand(
        'host',
        round: 1,
        command: const HeroCommand.attack('fixture.hero.0', 'enemy.test'),
      );
      value.submitCommand(
        'host',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.1'),
      );
      value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.2'),
      );
      final resolved = value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.3'),
      );
      expect(resolved.kind, 'roundResolved');
      expect(resolved.snapshot.battle!.round, 2);
    },
  );

  test(
    'shared item reservation rejects over-committed item commands atomically',
    () {
      final base = createContractFixture();
      final state = GameState(
        position: base.position,
        party: base.party,
        inventory: Inventory({'item.salves': 1}),
        gold: base.gold,
        quests: base.quests,
      );
      final value = LanternLinkRoom(
        name: 'bellwether',
        initialState: state,
        createBattle: (input) => BattleSession(
          input: input,
          rules: CombatRules(
            items: [
              CombatEffect(
                id: 'item.salves',
                name: 'Harbor Salve',
                kind: EffectKind.heal,
                power: 10,
              ),
            ],
          ),
          heroStats: {
            for (final member in input.state.party)
              member.id: const CombatStats(attack: 1, defense: 2, speed: 5),
          },
          enemies: [
            Combatant(
              id: 'enemy.test',
              side: BattleSide.enemies,
              hp: 100,
              maxHp: 100,
              attack: 1,
              defense: 0,
              speed: 1,
            ),
          ],
        ),
      );
      readyTwoPlayerRoom(value);
      value.beginBattle('host', definitionId: 'enemy.test', seed: 1);

      value.submitCommand(
        'host',
        round: 1,
        command: const HeroCommand.item(
          'fixture.hero.0',
          'item.salves',
          'fixture.hero.0',
        ),
      );
      final revAfterFirst = value.snapshot.revision;
      expect(
        () => value.submitCommand(
          'guest',
          round: 1,
          command: const HeroCommand.item(
            'fixture.hero.2',
            'item.salves',
            'fixture.hero.2',
          ),
        ),
        throwsArgumentError,
      );
      expect(value.snapshot.revision, revAfterFirst);

      value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.2'),
      );
      value.submitCommand(
        'host',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.1'),
      );
      expect(
        () => value.submitCommand(
          'guest',
          round: 1,
          command: const HeroCommand.item(
            'fixture.hero.3',
            'item.salves',
            'fixture.hero.3',
          ),
        ),
        throwsArgumentError,
      );
      final resolved = value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.3'),
      );
      expect(resolved.kind, 'roundResolved');
      expect(resolved.snapshot.battle!.round, 2);
      expect(resolved.snapshot.battle!.inventory['item.salves'], 0);
    },
  );

  test(
    'failed flee advances round, clears locks, and publishes damage',
    () async {
      final value = LanternLinkRoom(
        name: 'bellwether',
        initialState: createContractFixture(),
        createBattle: (input) => BattleSession(
          input: input,
          rules: CombatRules(
            flee: FleeRules(
              basePercent: 0,
              speedWeight: 0,
              minimumPercent: 0,
              maximumPercent: 0,
            ),
          ),
          heroStats: {
            for (final member in input.state.party)
              member.id: const CombatStats(attack: 4, defense: 0, speed: 5),
          },
          enemies: [
            Combatant(
              id: 'enemy.test',
              side: BattleSide.enemies,
              hp: 20,
              maxHp: 20,
              attack: 3,
              defense: 0,
              speed: 1,
            ),
          ],
        ),
      );
      readyTwoPlayerRoom(value);
      value.beginBattle('host', definitionId: 'enemy.test', seed: 1);
      value.submitCommand(
        'host',
        round: 1,
        command: const HeroCommand.defend('fixture.hero.0'),
      );
      final revBeforeFlee = value.snapshot.revision;

      final event = await value.flee('guest', round: 1);
      expect(event.kind, 'fleeFailed');
      expect(event.snapshot.phase, LanternLinkPhase.battle);
      expect(event.snapshot.revision, revBeforeFlee + 1);
      expect(event.snapshot.battle!.round, 2);
      expect(event.snapshot.outcome, isNull);
      expect(
        event.snapshot.battle!.combatants
            .firstWhere((c) => c.id == 'fixture.hero.0')
            .hp,
        lessThan(10),
      );
      // Prior round's locked command was cleared so hero.0 can act in round 2.
      final lockRound2 = value.submitCommand(
        'host',
        round: 2,
        command: const HeroCommand.defend('fixture.hero.0'),
      );
      expect(lockRound2.kind, 'commandLocked');
    },
  );

  test(
    'lethal failed flee transitions to gameOver with defeat metadata',
    () async {
      final base = createContractFixture();
      final fragile = GameState(
        position: base.position,
        party: [
          base.party.first,
          for (final m in base.party.skip(1))
            PartyMember(
              id: m.id,
              jobId: m.jobId,
              hp: 0,
              maxHp: m.maxHp,
              mp: m.mp,
              maxMp: m.maxMp,
              level: m.level,
              experience: m.experience,
              jobProgress: m.jobProgress,
              equipment: m.equipment,
            ),
        ],
        inventory: base.inventory,
        gold: base.gold,
        quests: base.quests,
      );
      final value = LanternLinkRoom(
        name: 'bellwether',
        initialState: fragile,
        createBattle: (input) => BattleSession(
          input: input,
          rules: CombatRules(
            flee: FleeRules(
              basePercent: 0,
              speedWeight: 0,
              minimumPercent: 0,
              maximumPercent: 0,
            ),
          ),
          heroStats: {
            for (final member in input.state.party)
              member.id: const CombatStats(attack: 1, defense: 0, speed: 5),
          },
          enemies: [
            Combatant(
              id: 'enemy.lethal',
              side: BattleSide.enemies,
              hp: 50,
              maxHp: 50,
              attack: 25,
              defense: 0,
              speed: 20,
            ),
          ],
        ),
      );
      readyTwoPlayerRoom(value);
      value.beginBattle('host', definitionId: 'enemy.lethal', seed: 1);

      final event = await value.flee('guest', round: 1);
      expect(event.kind, 'battleFinished');
      expect(event.snapshot.phase, LanternLinkPhase.gameOver);
      expect(event.snapshot.battle, isNull);
      expect(event.snapshot.encounterId, 'lantern-link-1');
      expect(event.snapshot.encounterDefinitionId, 'enemy.lethal');
      expect(event.snapshot.outcome, BattleOutcome.defeat);
      expect(event.snapshot.state.party.every((m) => m.hp == 0), isTrue);
    },
  );

  test('gameOver resists disconnect auto-resume, persists metadata, and supports host-only restart', () {
    final base = createContractFixture();
    final fragile = GameState(
      position: base.position,
      party: [
        base.party.first,
        for (final m in base.party.skip(1))
          PartyMember(
            id: m.id,
            jobId: m.jobId,
            hp: 0,
            maxHp: m.maxHp,
            mp: m.mp,
            maxMp: m.maxMp,
            level: m.level,
            experience: m.experience,
            jobProgress: m.jobProgress,
            equipment: m.equipment,
          ),
      ],
      inventory: base.inventory,
      gold: base.gold,
      quests: base.quests,
    );
    final value = LanternLinkRoom(
      name: 'bellwether',
      initialState: fragile,
      createBattle: (input) => BattleSession(
        input: input,
        heroStats: {
          for (final member in input.state.party)
            member.id: const CombatStats(attack: 1, defense: 0, speed: 1),
        },
        enemies: [
          Combatant(
            id: 'enemy.lethal',
            side: BattleSide.enemies,
            hp: 50,
            maxHp: 50,
            attack: 25,
            defense: 0,
            speed: 20,
          ),
        ],
      ),
    );
    readyTwoPlayerRoom(value);
    expect(() => value.restart('host'), throwsStateError);

    value.beginBattle('host', definitionId: 'enemy.lethal', seed: 1);
    expect(value.snapshot.encounterId, 'lantern-link-1');
    expect(value.snapshot.encounterDefinitionId, 'enemy.lethal');
    expect(value.snapshot.outcome, isNull);

    final finished = value.submitCommand(
      'host',
      round: 1,
      command: const HeroCommand.defend('fixture.hero.0'),
    );
    expect(finished.kind, 'battleFinished');
    expect(finished.snapshot.phase, LanternLinkPhase.gameOver);
    expect(finished.snapshot.outcome, BattleOutcome.defeat);
    expect(finished.snapshot.encounterId, 'lantern-link-1');
    expect(finished.snapshot.encounterDefinitionId, 'enemy.lethal');

    value.leave('guest');
    expect(value.snapshot.phase, LanternLinkPhase.gameOver);
    expect(() => value.restart('host'), throwsStateError);

    value.join('guest');
    expect(value.snapshot.phase, LanternLinkPhase.gameOver);
    expect(() => value.restart('guest'), throwsStateError);

    final restarted = value.restart('host');
    expect(restarted.kind, 'restarted');
    expect(restarted.snapshot.phase, LanternLinkPhase.exploration);
    expect(restarted.snapshot.dialogue, isNull);
    expect(restarted.snapshot.battle, isNull);
    expect(restarted.snapshot.encounterId, isNull);
    expect(restarted.snapshot.encounterDefinitionId, isNull);
    expect(restarted.snapshot.outcome, isNull);
    expect(restarted.snapshot.state.party.first.hp, 10);

    final nextBattle = value.beginBattle(
      'host',
      definitionId: 'enemy.lethal',
      seed: 2,
    );
    expect(nextBattle.snapshot.encounterId, 'lantern-link-2');
    expect(nextBattle.snapshot.outcome, isNull);
  });

  test(
    'victory persists encounter metadata until next battle resets outcome',
    () {
      final value = room();
      readyTwoPlayerRoom(value);
      value.beginBattle('host', definitionId: 'enemy.test', seed: 1);
      expect(value.snapshot.encounterId, 'lantern-link-1');
      expect(value.snapshot.encounterDefinitionId, 'enemy.test');
      expect(value.snapshot.outcome, isNull);

      for (final hero in ['fixture.hero.0', 'fixture.hero.1']) {
        value.submitCommand(
          'host',
          round: 1,
          command: HeroCommand.attack(hero, 'enemy.test'),
        );
      }
      value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.attack('fixture.hero.2', 'enemy.test'),
      );
      final won = value.submitCommand(
        'guest',
        round: 1,
        command: const HeroCommand.attack('fixture.hero.3', 'enemy.test'),
      );
      expect(won.snapshot.phase, LanternLinkPhase.exploration);
      expect(won.snapshot.outcome, BattleOutcome.victory);
      expect(won.snapshot.encounterId, 'lantern-link-1');
      expect(won.snapshot.encounterDefinitionId, 'enemy.test');

      final explored = value.publishExploration(
        'host',
        value.snapshot.state,
        expectedRevision: value.snapshot.revision,
      );
      expect(explored.snapshot.outcome, BattleOutcome.victory);
      expect(explored.snapshot.encounterId, 'lantern-link-1');

      final second = value.beginBattle(
        'host',
        definitionId: 'enemy.next',
        seed: 2,
      );
      expect(second.snapshot.encounterId, 'lantern-link-2');
      expect(second.snapshot.encounterDefinitionId, 'enemy.next');
      expect(second.snapshot.outcome, isNull);
    },
  );
}
