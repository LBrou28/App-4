import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/battle/demo/main.dart';
import 'package:app_4/battle/ui/battle_controller.dart';
import 'package:app_4/battle/ui/battle_screen.dart';
import 'package:app_4/core/contracts.dart' as shared;
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/ui/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

BattleSession session({
  int enemyHp = 20,
  int enemyAttack = 3,
  int enemySpeed = 0,
  FleePolicy? fleePolicy,
}) {
  final state = createContractFixture();
  return BattleSession(
    input: shared.BattleInput(
      encounterId: 'test.encounter',
      baseRevision: 42,
      request: shared.EncounterRequest(definitionId: 'test.enemies'),
      state: state,
      seed: 4,
    ),
    heroStats: {
      for (final m in state.party)
        m.id: const CombatStats(attack: 8, defense: 0, speed: 5),
    },
    enemies: [
      Combatant(
        id: 'enemy',
        side: BattleSide.enemies,
        hp: enemyHp,
        maxHp: enemyHp,
        attack: enemyAttack,
        defense: 0,
        speed: enemySpeed,
      ),
    ],
    fleePolicy: fleePolicy,
  );
}

void chooseAttacks(BattleController controller) {
  while (controller.active != null) {
    controller.attack();
    controller.target('enemy');
  }
}

void main() {
  test(
    'selection cancels, backtracks and edits without touching combat state',
    () {
      final c = BattleController(session());
      addTearDown(c.dispose);
      c.attack();
      c.target('missing');
      expect(c.targeting, isTrue);
      expect(c.commands, isEmpty);
      c.back();
      expect(c.targeting, isFalse);
      c.defend();
      c.defend();
      c.back();
      expect(c.commands, hasLength(1));
      c.edit('fixture.hero.0');
      expect(c.commands, isEmpty);
      expect(c.snapshot.round, 1);
    },
  );

  test('adapter preserves correlation and all non-HP party fields', () async {
    final s = session(enemyHp: 1);
    final c = BattleController(s, eventDelay: Duration.zero);
    addTearDown(c.dispose);
    chooseAttacks(c);
    await c.submit();
    final result = c.takeResult()!;
    expect(result.outcome, shared.BattleOutcome.victory);
    expect(result.encounterId, s.input.encounterId);
    expect(result.baseRevision, 42);
    expect(result.inventory, same(s.input.state.inventory));
    expect(result.gold, s.input.state.gold);
    for (var i = 0; i < 4; i++) {
      final before = s.input.state.party[i];
      final after = result.party[i];
      expect(
        [
          after.id,
          after.jobId,
          after.hp,
          after.maxHp,
          after.mp,
          after.maxMp,
          after.level,
          after.experience,
        ],
        [
          before.id,
          before.jobId,
          before.hp,
          before.maxHp,
          before.mp,
          before.maxMp,
          before.level,
          before.experience,
        ],
      );
      expect(after.equipment, before.equipment);
      expect(after.jobProgress, before.jobProgress);
    }
    expect(c.takeResult(), isNull);
    expect(() => s.resolve(1, []), throwsStateError);
  });

  test(
    'defeat returns updated HP and never changes the input snapshot',
    () async {
      final s = session(enemyHp: 1000, enemyAttack: 100, enemySpeed: 10);
      final c = BattleController(s, eventDelay: Duration.zero);
      addTearDown(c.dispose);
      for (var i = 0; i < 4; i++) {
        chooseAttacks(c);
        await c.submit();
      }
      expect(c.result!.outcome, shared.BattleOutcome.defeat);
      expect(c.result!.party.every((p) => p.hp == 0), isTrue);
      expect(s.input.state.party.every((p) => p.hp == 10), isTrue);
    },
  );

  test(
    'flee locks input, failed attempt retains choices, success returns fled',
    () async {
      var pending = Completer<bool>();
      var calls = 0;
      final c = BattleController(
        session(
          fleePolicy: (_) {
            calls++;
            return pending.future;
          },
        ),
      );
      addTearDown(c.dispose);
      c.defend();
      final first = c.flee();
      await c.flee();
      c.defend();
      await c.submit();
      c.back();
      expect(calls, 1);
      expect(c.commands, hasLength(1));
      pending.complete(false);
      await first;
      expect(c.busy, isFalse);
      expect(c.result, isNull);
      pending = Completer<bool>();
      final second = c.flee();
      pending.complete(true);
      await second;
      expect(c.result!.outcome, shared.BattleOutcome.fled);
      expect(c.result!.party.first.hp, 10);
      expect(c.takeResult(), isNotNull);
      expect(c.takeResult(), isNull);
    },
  );

  test(
    'flee errors unlock input and disposal suppresses pending notifications',
    () async {
      final pending = Completer<bool>();
      final c = BattleController(session(fleePolicy: (_) => pending.future));
      final task = c.flee();
      c.dispose();
      pending.completeError(StateError('cancelled'));
      await task;
      expect(c.takeResult(), isNull);
      final retry = BattleController(
        session(fleePolicy: (_) async => throw StateError('offline')),
      );
      addTearDown(retry.dispose);
      await retry.flee();
      expect(retry.busy, isFalse);
      expect(retry.canChoose, isTrue);
    },
  );

  Future<void> mount(
    WidgetTester tester,
    BattleSession s, {
    ValueChanged<shared.BattleResult>? onCompleted,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: lanternTheme(),
        home: BattleScreen(session: s, onCompleted: onCompleted ?? (_) {}),
      ),
    );
  }

  Future<void> tapKey(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(ValueKey(key)));
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  Future<void> chooseRound(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tapKey(tester, 'attack');
      await tapKey(tester, 'target-enemy');
    }
  }

  testWidgets('commands, cancel/back/edit and duplicate submit lock work', (
    tester,
  ) async {
    final s = session(enemyHp: 100);
    await mount(tester, s);
    expect(find.text('MP 3 / 3'), findsNWidgets(4));
    await tapKey(tester, 'attack');
    expect(find.text('Cancel target'), findsOneWidget);
    await tapKey(tester, 'back');
    await tapKey(tester, 'defend');
    await tapKey(tester, 'edit-fixture.hero.0');
    await chooseRound(tester);
    final submit = tester
        .widget<FilledButton>(find.byKey(const ValueKey('submit-round')))
        .onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('submit-round')))
          .onPressed,
      isNull,
    );
    expect(
      tester.widget<TextButton>(find.byKey(const ValueKey('back'))).onPressed,
      isNull,
    );
    await tester.pumpAndSettle();
    expect(s.snapshot.round, 2);
    expect(find.textContaining('damage'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('victory Continue emits exactly one BattleResult', (
    tester,
  ) async {
    final results = <shared.BattleResult>[];
    await mount(tester, session(enemyHp: 1), onCompleted: results.add);
    await chooseRound(tester);
    await tapKey(tester, 'submit-round');
    await tester.pumpAndSettle();
    expect(find.text('Victory'), findsOneWidget);
    expect(find.text('Defeated'), findsOneWidget);
    final done = tester
        .widget<FilledButton>(find.byKey(const ValueKey('return-result')))
        .onPressed!;
    done();
    done();
    expect(results, hasLength(1));
    expect(results.single.outcome, shared.BattleOutcome.victory);
  });

  testWidgets('defeat shows knocked-out heroes and returns through callback', (
    tester,
  ) async {
    final s = session(enemyHp: 1000, enemyAttack: 100, enemySpeed: 10);
    while (s.result == null) {
      s.resolve(s.snapshot.round, [
        for (final c in s.snapshot.combatants)
          if (c.side == BattleSide.heroes && c.isAlive)
            HeroCommand.attack(c.id, 'enemy'),
      ]);
    }
    final results = <shared.BattleResult>[];
    await mount(tester, s, onCompleted: results.add);
    expect(find.text('Defeat'), findsOneWidget);
    expect(find.text('Knocked out'), findsNWidgets(4));
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const ValueKey('target-enemy')))
          .onPressed,
      isNull,
    );
    await tapKey(tester, 'return-result');
    expect(results.single.outcome, shared.BattleOutcome.defeat);
  });

  testWidgets('flee completion returns via shared result callback', (
    tester,
  ) async {
    final results = <shared.BattleResult>[];
    await mount(
      tester,
      session(fleePolicy: (_) async => true),
      onCompleted: results.add,
    );
    await tapKey(tester, 'flee');
    await tester.pumpAndSettle();
    expect(find.text('Escaped'), findsOneWidget);
    await tapKey(tester, 'return-result');
    expect(results.single.outcome, shared.BattleOutcome.fled);
  });

  testWidgets('replacement during playback cannot deliver an old result', (
    tester,
  ) async {
    final results = <shared.BattleResult>[];
    await mount(tester, session(enemyHp: 1), onCompleted: results.add);
    await chooseRound(tester);
    await tapKey(tester, 'submit-round');
    await tester.pumpWidget(
      MaterialApp(
        theme: lanternTheme(),
        home: BattleScreen(session: session(), onCompleted: results.add),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('0 / 4 commands selected'), findsOneWidget);
    expect(results, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('1280x720 and narrow layouts fit; optional real-font evidence', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (const bool.fromEnvironment('C2_CAPTURE')) {
      await tester.runAsync(() async {
        for (final entry in {
          'Roboto': const String.fromEnvironment('C2_TEXT_FONT'),
          'MaterialIcons': const String.fromEnvironment('C2_ICON_FONT'),
        }.entries) {
          await (FontLoader(entry.key)..addFont(
                Future.value(
                  (await File(entry.value).readAsBytes()).buffer.asByteData(),
                ),
              ))
              .load();
        }
      });
    }
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: lanternTheme(),
          home: const BattleDemo(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    if (const bool.fromEnvironment('C2_CAPTURE')) {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('lib/battle/evidence/c2-battle.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    tester.view.physicalSize = const Size(480, 640);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tapKey(tester, 'defend');
    expect(find.text('1 / 4 commands selected'), findsOneWidget);
  });
}
