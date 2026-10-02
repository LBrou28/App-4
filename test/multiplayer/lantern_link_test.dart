import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
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
}
