import 'dart:math';

import 'package:app_4/battle/battle.dart';
import 'package:flutter_test/flutter_test.dart';

// Fixed variance for exact arithmetic; seeded Random is exercised separately.
class FixedRandom implements Random {
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    return 1;
  }

  @override
  bool nextBool() => throw UnimplementedError();
  @override
  double nextDouble() => throw UnimplementedError();
}

Combatant hero(int i, {int hp = 30, int speed = 10, int attack = 8}) =>
    Combatant(
      id: 'hero.$i',
      side: BattleSide.heroes,
      hp: hp,
      maxHp: 30,
      attack: attack,
      defense: 2,
      speed: speed,
    );
Combatant enemy(
  int i, {
  int hp = 100,
  int speed = 5,
  int attack = 9,
  int defense = 3,
}) => Combatant(
  id: 'enemy.$i',
  side: BattleSide.enemies,
  hp: hp,
  maxHp: 100,
  attack: attack,
  defense: defense,
  speed: speed,
);
List<HeroCommand> attacks(BattleEngine engine, {String target = 'enemy.0'}) =>
    engine.snapshot.combatants
        .where((c) => c.side == BattleSide.heroes && c.isAlive)
        .map((c) => HeroCommand.attack(c.id, target))
        .toList();
BattleEngine fixture({Random? random}) => BattleEngine(
  combatants: [...List.generate(4, hero), enemy(0), enemy(1)],
  random: random ?? FixedRandom(),
);

void main() {
  test('four heroes complete a battle without UI', () {
    final engine = fixture(random: Random(42));
    var rounds = 0;
    while (engine.snapshot.outcome == BattleOutcome.ongoing && rounds < 100) {
      engine.resolveRound(
        expectedRound: engine.snapshot.round,
        commands: attacks(engine),
      );
      rounds++;
    }
    expect(engine.snapshot.outcome, isNot(BattleOutcome.ongoing));
    expect(rounds, greaterThan(1));
    expect(
      engine.snapshot.combatants.every((c) => c.hp >= 0 && c.hp <= c.maxHp),
      isTrue,
    );
  });

  test(
    'speed descending, heroes first on ties, roster order within a side',
    () {
      final engine = BattleEngine(
        combatants: [
          enemy(0, speed: 10),
          hero(2, speed: 11),
          hero(0),
          enemy(1, speed: 10),
          hero(3),
          hero(1),
        ],
        random: FixedRandom(),
      );
      final result = engine.resolveRound(
        expectedRound: 1,
        commands: attacks(engine),
      );
      expect(result.events.map((e) => e.actorId), [
        'hero.2',
        'hero.0',
        'hero.3',
        'hero.1',
        'enemy.0',
        'enemy.1',
      ]);
      expect(result.snapshot.round, 2);
    },
  );

  test('damage subtracts defense and overkill clamps HP and event damage', () {
    final engine = BattleEngine(
      combatants: [...List.generate(4, hero), enemy(0, hp: 3)],
      random: FixedRandom(),
    );
    final result = engine.resolveRound(
      expectedRound: 1,
      commands: attacks(engine),
    );
    expect(result.events, hasLength(1));
    expect(result.events.single.damage, 3);
    expect(result.snapshot.combatants.last.hp, 0);
    expect(result.snapshot.outcome, BattleOutcome.victory);
  });

  test('normal damage and minimum one damage', () {
    final engine = fixture();
    final result = engine.resolveRound(
      expectedRound: 1,
      commands: attacks(engine),
    );
    expect(result.events.first.damage, 5);
    final armored = BattleEngine(
      combatants: [...List.generate(4, hero), enemy(0, defense: 999)],
      random: FixedRandom(),
    );
    final minimum = armored.resolveRound(
      expectedRound: 1,
      commands: attacks(armored),
    );
    expect(minimum.events.first.damage, 1);
  });

  test('Defend protects against faster enemies, rounds up and expires', () {
    final engine = BattleEngine(
      combatants: [...List.generate(4, hero), enemy(0, speed: 20)],
      random: FixedRandom(),
    );
    final first = engine.resolveRound(
      expectedRound: 1,
      commands: [
        const HeroCommand.defend('hero.0'),
        for (var i = 1; i < 4; i++) HeroCommand.attack('hero.$i', 'enemy.0'),
      ],
    );
    expect(first.events.first.actorId, 'enemy.0');
    expect(first.events.first.damage, 4); // ceil((9 - 2) / 2)
    expect(first.snapshot.combatants.first.hp, 26);
    final second = engine.resolveRound(
      expectedRound: 2,
      commands: attacks(engine),
    );
    expect(second.events.first.damage, 7);
    expect(second.snapshot.combatants.first.hp, 19);
  });

  test('hero knocked out before its turn skips its selected action', () {
    final engine = BattleEngine(
      combatants: [
        hero(0, hp: 1),
        hero(1),
        hero(2),
        hero(3),
        enemy(0, speed: 20),
      ],
      random: FixedRandom(),
    );
    final result = engine.resolveRound(
      expectedRound: 1,
      commands: attacks(engine),
    );
    expect(result.events[1].kind, BattleEventKind.skippedKnockout);
    expect(result.events[1].actorId, 'hero.0');
    final next = engine.resolveRound(
      expectedRound: 2,
      commands: attacks(engine),
    );
    expect(next.events.any((e) => e.actorId == 'hero.0'), isFalse);
    expect(next.events.first.targetId, 'hero.1');
  });

  test('KO enemy skips and subsequent attacks retarget first living enemy', () {
    final engine = BattleEngine(
      combatants: [...List.generate(4, hero), enemy(0, hp: 1), enemy(1)],
      random: FixedRandom(),
    );
    final result = engine.resolveRound(
      expectedRound: 1,
      commands: attacks(engine),
    );
    expect(result.events[1].targetId, 'enemy.1');
    expect(result.events[4].kind, BattleEventKind.skippedKnockout);
    expect(result.events[4].actorId, 'enemy.0');
    final next = engine.resolveRound(
      expectedRound: 2,
      commands: attacks(engine),
    );
    expect(next.events.first.targetId, 'enemy.1');
  });

  test('defeat immediately ends resolution and rejects later commands', () {
    final engine = BattleEngine(
      combatants: [
        hero(0, hp: 1),
        hero(1, hp: 0),
        hero(2, hp: 0),
        hero(3, hp: 0),
        enemy(0, speed: 20),
        enemy(1),
      ],
      random: FixedRandom(),
    );
    final result = engine.resolveRound(
      expectedRound: 1,
      commands: attacks(engine),
    );
    expect(result.snapshot.outcome, BattleOutcome.defeat);
    expect(result.events, hasLength(1));
    expect(
      () => engine.resolveRound(expectedRound: 1, commands: []),
      throwsStateError,
    );
  });

  test(
    'already terminal input rejects resolution without consuming randomness',
    () {
      for (final defeated in [true, false]) {
        final random = FixedRandom();
        final engine = BattleEngine(
          combatants: [
            for (var i = 0; i < 4; i++) hero(i, hp: defeated ? 0 : 30),
            enemy(0, hp: defeated ? 100 : 0),
          ],
          random: random,
        );
        expect(
          engine.snapshot.outcome,
          defeated ? BattleOutcome.defeat : BattleOutcome.victory,
        );
        expect(
          () => engine.resolveRound(expectedRound: 1, commands: []),
          throwsStateError,
        );
        expect(random.calls, 0);
      }
    },
  );

  test('same seed and commands produce identical full battle transcripts', () {
    List<Object> play(int seed) {
      final engine = fixture(random: Random(seed));
      final transcript = <Object>[];
      while (engine.snapshot.outcome == BattleOutcome.ongoing) {
        final result = engine.resolveRound(
          expectedRound: engine.snapshot.round,
          commands: attacks(engine),
        );
        transcript.add([
          result.resolvedRound,
          result.snapshot.outcome,
          result.snapshot.combatants.map((c) => c.hp).toList(),
          result.events
              .map((e) => [e.kind, e.actorId, e.targetId, e.damage])
              .toList(),
        ]);
      }
      return transcript;
    }

    expect(play(123), equals(play(123)));
    expect(play(123), isNot(equals(play(456))));
  });

  test('stale round cannot resolve twice or consume randomness', () {
    final random = FixedRandom();
    final engine = fixture(random: random);
    final commands = attacks(engine);
    engine.resolveRound(expectedRound: 1, commands: commands);
    final saved = engine.snapshot;
    final calls = random.calls;
    expect(
      () => engine.resolveRound(expectedRound: 1, commands: commands),
      throwsStateError,
    );
    expect(identical(engine.snapshot, saved), isTrue);
    expect(random.calls, calls);
  });

  test('invalid commands are rejected atomically before RNG consumption', () {
    final random = FixedRandom();
    final engine = fixture(random: random);
    final valid = attacks(engine);
    final invalid = <List<HeroCommand>>[
      valid.take(3).toList(),
      [...valid, valid.first],
      [const HeroCommand.attack('unknown', 'enemy.0'), ...valid.skip(1)],
      [const HeroCommand.attack('enemy.0', 'hero.0'), ...valid.skip(1)],
      [const HeroCommand.attack('hero.0', 'unknown'), ...valid.skip(1)],
      [const HeroCommand.attack('hero.0', 'hero.1'), ...valid.skip(1)],
    ];
    final before = engine.snapshot;
    for (final commands in invalid) {
      expect(
        () => engine.resolveRound(expectedRound: 1, commands: commands),
        throwsArgumentError,
      );
      expect(identical(before, engine.snapshot), isTrue);
      expect(random.calls, 0);
    }
    expect(
      engine.resolveRound(expectedRound: 1, commands: valid).resolvedRound,
      1,
    );
  });

  test('knocked out hero cannot submit a command', () {
    final engine = BattleEngine(
      combatants: [hero(0, hp: 0), hero(1), hero(2), hero(3), enemy(0)],
      random: FixedRandom(),
    );
    expect(
      () => engine.resolveRound(
        expectedRound: 1,
        commands: [const HeroCommand.defend('hero.0'), ...attacks(engine)],
      ),
      throwsArgumentError,
    );
  });

  test('snapshots copy roster and preserve previous rounds immutably', () {
    final roster = [...List.generate(4, hero), enemy(0)];
    final engine = BattleEngine(combatants: roster, random: FixedRandom());
    final before = engine.snapshot;
    roster.clear();
    expect(before.combatants, hasLength(5));
    expect(() => before.combatants.clear(), throwsUnsupportedError);
    final result = engine.resolveRound(
      expectedRound: 1,
      commands: attacks(engine),
    );
    expect(before.combatants.last.hp, 100);
    expect(result.snapshot.combatants.last.hp, 80);
    expect(() => result.events.clear(), throwsUnsupportedError);
  });

  test('reject malformed stats, duplicate IDs and wrong roster sizes', () {
    expect(() => hero(0, hp: -1), throwsArgumentError);
    expect(() => hero(0, hp: 31), throwsArgumentError);
    expect(() => hero(0, speed: -1), throwsArgumentError);
    expect(() => hero(0, attack: -1), throwsArgumentError);
    expect(() => enemy(0, defense: -1), throwsArgumentError);
    for (final roster in [
      <Combatant>[],
      [hero(0), enemy(0)],
      [...List.generate(4, hero)],
      [hero(0), hero(0), hero(2), hero(3), enemy(0)],
    ]) {
      expect(
        () => BattleEngine(combatants: roster, random: FixedRandom()),
        throwsArgumentError,
      );
    }
  });
}
