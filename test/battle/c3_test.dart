import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart' as shared;
import 'package:app_4/battle/demo/c3.dart';
import 'package:app_4/battle/ui/battle_controller.dart';
import 'package:app_4/battle/ui/battle_screen.dart';
import 'package:app_4/ui/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Rolls implements Random {
  Rolls(this.roll);
  final int roll;
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    return roll % max;
  }

  @override
  bool nextBool() => throw UnimplementedError();
  @override
  double nextDouble() => throw UnimplementedError();
}

Combatant hero(int n, {int hp = 20, int mp = 6, int speed = 10}) => Combatant(
  id: 'h$n',
  side: BattleSide.heroes,
  hp: hp,
  maxHp: 30,
  mp: mp,
  maxMp: 6,
  attack: 8,
  defense: 2,
  speed: speed,
  spellIds: {'spell.mend', 'spell.ember', 'spell.rill'},
);
Combatant enemy({
  int hp = 100,
  int speed = 0,
  int attack = 1,
  int mp = 0,
  bool boss = false,
  List<EnemyMove> pattern = const [EnemyMove.defend()],
}) => Combatant(
  id: 'e',
  side: BattleSide.enemies,
  hp: hp,
  maxHp: 100,
  mp: mp,
  maxMp: 6,
  attack: attack,
  defense: 3,
  speed: speed,
  isBoss: boss,
  spellIds: {'spell.ember'},
  pattern: pattern,
);
BattleEngine engine({
  List<Combatant>? heroes,
  Combatant? foe,
  Rolls? random,
  CombatRules? rules,
  Map<String, int> items = const {
    'item.salves': 1,
    'item.revival': 2,
    'item.ether': 1,
  },
}) => BattleEngine(
  combatants: [...heroes ?? List.generate(4, hero), foe ?? enemy()],
  random: random ?? Rolls(1),
  rules: rules ?? lanternCombatRules(),
  inventory: items,
);
List<HeroCommand> commands(BattleEngine e, List<HeroCommand> chosen) => [
  for (final h in e.snapshot.combatants.where(
    (c) => c.side == BattleSide.heroes && c.isAlive,
  ))
    chosen.where((c) => c.actorId == h.id).firstOrNull ??
        HeroCommand.defend(h.id),
];
RoundResult run(BattleEngine e, List<HeroCommand> chosen) => e.resolveRound(
  expectedRound: e.snapshot.round,
  commands: commands(e, chosen),
);
Combatant actor(BattleEngine e, String id) =>
    e.snapshot.combatants.firstWhere((c) => c.id == id);

void main() {
  test('failed flee playback respects pause, drops selections, and rejects repeat taps', () async {
    final t = createC3DemoSession();
    final rules = CombatRules(
      spells: t.rules.spells.values.toList(),
      items: t.rules.items.values.toList(),
      flee: FleeRules(basePercent: 0, minimumPercent: 0, maximumPercent: 0),
    );
    final s = BattleSession(
      input: t.input,
      rules: rules,
      heroStats: {
        for (final m in t.input.state.party)
          m.id: const CombatStats(attack: 5, defense: 2, speed: 10),
      },
      enemies: t.snapshot.combatants
          .where((c) => c.side == BattleSide.enemies)
          .toList(),
    );
    final pause = ValueNotifier(false);
    final c = BattleController(
      s,
      eventDelay: Duration.zero,
      pauseSignal: pause,
    );
    addTearDown(c.dispose);
    addTearDown(pause.dispose);
    c.defend();
    final work = c.flee();
    pause.value = true;
    await c.flee();
    await Future<void>.delayed(Duration.zero);
    expect(c.busy, isTrue);
    expect(c.snapshot.round, 1);
    expect(s.snapshot.round, 2);
    expect(c.canChoose, isFalse);
    pause.value = false;
    await work;
    expect(c.snapshot.round, 2);
    expect(c.commands, isEmpty);
    expect(c.busy, isFalse);
    expect(s.snapshot.inventory, t.input.state.inventory.quantities);
  });
  testWidgets('C3 menus fit narrow viewport and boss escape is disabled', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: lanternTheme(),
        home: BattleScreen(
          session: createC3DemoSession(boss: true),
          onCompleted: (_) {},
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const ValueKey('items')));
    await tester.tap(find.byKey(const ValueKey('items')));
    await tester.pump();
    expect(
      tester.widget<TextButton>(find.byKey(const ValueKey('flee'))).onPressed,
      isNull,
    );
    expect(find.text('Boss encounter: escape is disabled.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('terminal result carries spent resources and preserves correlation and input', () {
    final template = createC3DemoSession();
    final s = BattleSession(
      input: template.input,
      rules: lanternCombatRules(),
      heroStats: {
        for (final m in template.input.state.party)
          m.id: const CombatStats(attack: 5, defense: 2, speed: 10),
      },
      heroSpells: const {
        'hero.iona': {'spell.mend'},
        'hero.tavi': {'spell.ember'},
      },
      enemies: [
        Combatant(
          id: 'e',
          side: BattleSide.enemies,
          hp: 10,
          maxHp: 10,
          attack: 1,
          defense: 0,
          speed: 0,
        ),
      ],
    );
    s.resolve(1, [
      const HeroCommand.item('hero.ada', 'item.salves', 'hero.ada'),
      const HeroCommand.spell('hero.iona', 'spell.mend', 'hero.ada'),
      const HeroCommand.spell('hero.tavi', 'spell.ember', 'e'),
    ]);
    final r = s.result!;
    expect(r.outcome, shared.BattleOutcome.victory);
    expect(r.encounterId, s.input.encounterId);
    expect(r.baseRevision, s.input.baseRevision);
    expect(r.inventory.quantities['item.salves'], 1);
    expect(r.party[2].mp, 4);
    expect(r.party[3].mp, 3);
    expect(s.input.state.party[3].mp, 6);
    expect(s.input.state.inventory.quantities['item.salves'], 2);
    expect(r.gold, s.input.state.gold);
  });
  test('boss cannot escape even with legacy training policy', () async {
    final template = createC3DemoSession(boss: true);
    final s = BattleSession(
      input: template.input,
      rules: lanternCombatRules(),
      heroStats: {
        for (final m in template.input.state.party)
          m.id: const CombatStats(attack: 5, defense: 2, speed: 10),
      },
      enemies: template.snapshot.combatants
          .where((c) => c.side == BattleSide.enemies)
          .toList(),
      fleePolicy: (_) async => true,
    );
    expect(await s.flee(), isFalse);
    expect(s.result, isNull);
    expect(s.snapshot.round, 1);
  });
  test(
    'unlearned spells reject and killing blow never spends later commands',
    () {
      final e = engine(foe: enemy(hp: 1));
      run(e, [
        const HeroCommand.spell('h0', 'spell.ember', 'e'),
        const HeroCommand.item('h1', 'item.salves', 'h1'),
      ]);
      expect(e.snapshot.outcome, BattleOutcome.victory);
      expect(e.snapshot.inventory['item.salves'], 1);
      final e2 = engine(
        heroes: [
          Combatant(
            id: 'h0',
            side: BattleSide.heroes,
            hp: 20,
            maxHp: 30,
            attack: 5,
            defense: 2,
            speed: 10,
            mp: 6,
            maxMp: 6,
          ),
          hero(1),
          hero(2),
          hero(3),
        ],
      );
      expect(
        () => run(e2, [const HeroCommand.spell('h0', 'spell.ember', 'e')]),
        throwsArgumentError,
      );
    },
  );

  test(
    'spell and item resources pay once, clamp healing and reject stale repeat',
    () {
      final e = engine();
      final before = e.snapshot;
      final input = commands(e, [
        const HeroCommand.spell('h0', 'spell.mend', 'h0'),
        const HeroCommand.item('h1', 'item.salves', 'h2'),
      ]);
      final result = e.resolveRound(expectedRound: 1, commands: input);
      expect(actor(e, 'h0').hp, 30);
      expect(actor(e, 'h0').mp, 4);
      expect(actor(e, 'h2').hp, 30);
      expect(e.snapshot.inventory['item.salves'], 0);
      expect(
        result.events.where((v) => v.restored > 0).map((v) => v.restored),
        [10, 10],
      );
      expect(before.combatants.first.mp, 6);
      expect(before.inventory['item.salves'], 1);
      expect(
        () => e.resolveRound(expectedRound: 1, commands: input),
        throwsStateError,
      );
      expect(actor(e, 'h0').mp, 4);
    },
  );
  test(
    'invalid targets and shared item oversubscription are atomic before RNG',
    () {
      final rng = Rolls(1);
      final e = engine(random: rng);
      for (final selected in [
        [const HeroCommand.spell('h0', 'spell.ember', 'h1')],
        [const HeroCommand.spell('h0', 'spell.mend', 'e')],
        [const HeroCommand.item('h0', 'item.revival', 'h1')],
        [const HeroCommand.item('h0', 'item.salves', 'missing')],
        [const HeroCommand.spell('h0', 'unknown', 'e')],
        [
          const HeroCommand.item('h0', 'item.salves', 'h0'),
          const HeroCommand.item('h1', 'item.salves', 'h1'),
        ],
      ]) {
        final before = e.snapshot;
        expect(() => run(e, selected), throwsArgumentError);
        expect(identical(e.snapshot, before), isTrue);
        expect(rng.calls, 0);
      }
    },
  );
  test('exhausted MP and items reject without advancing the round', () {
    final e = engine();
    run(e, [
      const HeroCommand.spell('h0', 'spell.ember', 'e'),
      const HeroCommand.item('h1', 'item.salves', 'h1'),
    ]);
    run(e, [const HeroCommand.spell('h0', 'spell.ember', 'e')]);
    expect(actor(e, 'h0').mp, 0);
    final before = e.snapshot;
    expect(
      () => run(e, [const HeroCommand.spell('h0', 'spell.ember', 'e')]),
      throwsArgumentError,
    );
    expect(
      () => run(e, [const HeroCommand.item('h1', 'item.salves', 'h1')]),
      throwsArgumentError,
    );
    expect(identical(before, e.snapshot), isTrue);
  });
  test('revival only accepts KO; duplicate revival skips with no second cost or new turn', () {
    final e = engine(heroes: [hero(0), hero(1), hero(2), hero(3, hp: 0)]);
    expect(
      () => run(e, [const HeroCommand.spell('h0', 'spell.mend', 'h3')]),
      throwsArgumentError,
    );
    final r = run(e, [
      const HeroCommand.item('h0', 'item.revival', 'h3'),
      const HeroCommand.item('h1', 'item.revival', 'h3'),
    ]);
    expect(actor(e, 'h3').hp, 10);
    expect(e.snapshot.inventory['item.revival'], 1);
    expect(
      r.events.where((v) => v.kind == BattleEventKind.skippedTarget).length,
      1,
    );
    expect(r.events.any((v) => v.actorId == 'h3'), isFalse);
  });
  test('knocked-out caster and ally target spend no resources', () {
    final e = engine(
      foe: enemy(speed: 99, attack: 99, pattern: [const EnemyMove.attack()]),
    );
    final r = run(e, [
      const HeroCommand.spell('h0', 'spell.ember', 'e'),
      const HeroCommand.item('h1', 'item.salves', 'h0'),
    ]);
    expect(actor(e, 'h0').hp, 0);
    expect(actor(e, 'h0').mp, 6);
    expect(e.snapshot.inventory['item.salves'], 1);
    expect(
      r.events.any((v) => v.kind == BattleEventKind.skippedTarget),
      isTrue,
    );
  });
  test('MP recovery clamps and cannot revive', () {
    final e = engine(
      heroes: [hero(0, mp: 4), hero(1), hero(2), hero(3, hp: 0)],
    );
    expect(
      () => run(e, [const HeroCommand.item('h0', 'item.ether', 'h3')]),
      throwsArgumentError,
    );
    final r = run(e, [const HeroCommand.item('h0', 'item.ether', 'h0')]);
    expect(actor(e, 'h0').mp, 6);
    expect(r.events.first.restored, 2);
  });
  test('enemy cycles spells and defense, picks lowest HP, falls back when MP is empty', () {
    final e = engine(
      heroes: [hero(0), hero(1, hp: 12), hero(2), hero(3)],
      foe: enemy(
        mp: 3,
        pattern: [
          const EnemyMove.spell('spell.ember', target: EnemyTarget.lowestHp),
          const EnemyMove.defend(),
        ],
      ),
    );
    final r = run(e, []);
    final spell = r.events.last;
    expect(spell.kind, BattleEventKind.spell);
    expect(spell.targetId, 'h1');
    expect(spell.damage, 5);
    expect(actor(e, 'e').mp, 0);
    expect(run(e, []).events.last.kind, BattleEventKind.defend);
    final fallback = run(e, []).events.last;
    expect(fallback.kind, BattleEventKind.attack);
    expect(fallback.targetId, 'h1');
  });
  test('flee threshold, failure turn cost, success and boss rejection', () {
    final fail = engine(
      random: Rolls(90),
      foe: enemy(pattern: [const EnemyMove.attack()]),
    );
    final r = fail.attemptFlee(expectedRound: 1);
    expect(r.events.first.kind, BattleEventKind.fleeFailed);
    expect(r.events.where((v) => v.actorId.startsWith('h')), isEmpty);
    expect(fail.snapshot.round, 2);
    expect(actor(fail, 'h0').hp, 19);
    final success = engine(random: Rolls(89));
    expect(
      success.attemptFlee(expectedRound: 1).snapshot.outcome,
      BattleOutcome.fled,
    );
    expect(() => success.attemptFlee(expectedRound: 1), throwsStateError);
    final rng = Rolls(0);
    final boss = engine(random: rng, foe: enemy(boss: true));
    expect(boss.canFlee, isFalse);
    expect(() => boss.attemptFlee(expectedRound: 1), throwsStateError);
    expect(rng.calls, 0);
    expect(boss.snapshot.round, 1);
  });
  test('failed flee can cause defeat and never spends selected items', () {
    final e = engine(
      random: Rolls(99),
      heroes: [hero(0, hp: 1), hero(1, hp: 0), hero(2, hp: 0), hero(3, hp: 0)],
      foe: enemy(attack: 99, pattern: [const EnemyMove.attack()]),
    );
    expect(
      e.attemptFlee(expectedRound: 1).snapshot.outcome,
      BattleOutcome.defeat,
    );
    expect(e.snapshot.inventory['item.salves'], 1);
  });
  test('same seed and commands preserve spell/AI/flee replay', () {
    BattleEngine seeded() => BattleEngine(
      combatants: [
        ...List.generate(4, hero),
        enemy(pattern: [const EnemyMove.attack()]),
      ],
      random: Random(32),
      rules: lanternCombatRules(),
    );
    final a = seeded(), b = seeded();
    for (var i = 0; i < 2; i++) {
      run(a, [const HeroCommand.spell('h0', 'spell.ember', 'e')]);
      run(b, [const HeroCommand.spell('h0', 'spell.ember', 'e')]);
    }
    a.attemptFlee(expectedRound: 3);
    b.attemptFlee(expectedRound: 3);
    expect(a.snapshot.outcome, b.snapshot.outcome);
    expect(
      a.snapshot.combatants.map((c) => [c.hp, c.mp]),
      b.snapshot.combatants.map((c) => [c.hp, c.mp]),
    );
  });
  test('C3 definitions agree with D4 IDs, targets and enemy spell lists', () {
    final content = jsonDecode(
      File('assets/data/lantern_wake.json').readAsStringSync(),
    ) as Map;
    final rules = lanternCombatRules();
    final spells = {
      for (final row in content['spells'] as List) row['id']: row,
    };
    final items = {for (final row in content['items'] as List) row['id']: row};
    for (final s in rules.spells.values) {
      expect(
        spells[s.id]['target'],
        s.kind == EffectKind.damage ? 'enemy' : 'ally',
      );
    }
    for (final i in rules.items.values) {
      expect(items[i.id]['kind'], 'consumable');
    }
    for (final row in content['enemies'] as List) {
      for (final move in lanternEnemyPatterns[row['id']]!) {
        if (move.spellId != null) {
          expect(row['spellIds'], contains(move.spellId));
        }
      }
    }
  });
  test('controller reserves last item and back releases reservation without consuming it', () {
    final s = createC3DemoSession();
    final c = BattleController(s);
    addTearDown(c.dispose);
    final revive = s.rules.items['item.revival']!;
    c.chooseEffect(revive, item: true);
    c.target('hero.ren');
    expect(c.availableItems(revive.id), 0);
    expect(c.canUse(revive, item: true), isFalse);
    expect(s.snapshot.inventory[revive.id], 1);
    c.back();
    expect(c.availableItems(revive.id), 1);
  });
  testWidgets(
    'magic, revival, MP display, result resources and duplicate submit',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = createC3DemoSession();
      await tester.pumpWidget(
        MaterialApp(
          theme: lanternTheme(),
          home: BattleScreen(
            session: s,
            onCompleted: (_) {},
            eventDelay: Duration.zero,
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('items')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('effect-item.revival')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('target-hero.ren')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('magic')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('effect-spell.mend')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('target-hero.ada')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('magic')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('effect-spell.ember')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('target-enemy.wick_moth')));
      await tester.pump();
      final submit = tester
          .widget<FilledButton>(find.byKey(const ValueKey('submit-round')))
          .onPressed!;
      submit();
      submit();
      await tester.pumpAndSettle();
      expect(s.snapshot.round, 2);
      expect(s.snapshot.inventory['item.revival'], 0);
      expect(find.text('MP 4 / 6'), findsOneWidget);
      expect(find.text('MP 3 / 6'), findsOneWidget);
      // The moth targets the newly revived lowest-HP ally later in this round.
      expect(s.snapshot.combatants.firstWhere((c) => c.id == 'hero.ren').hp, 0);

      expect(tester.takeException(), isNull);
    },
  );
}
