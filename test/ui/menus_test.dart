import 'dart:async';
import 'dart:io';

import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/ui/demo/main.dart';
import 'package:app_4/ui/dialogue_panel.dart';
import 'package:app_4/ui/game_theme.dart';
import 'package:app_4/ui/party_menu.dart';
import 'package:app_4/ui/title_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class TestHost extends ChangeNotifier implements PartyMenuHost {
  TestHost(this.state);
  bool get observed => hasListeners;
  @override
  GameState state;
  final commands = <MenuCommand>[];
  Future<CommandResult> Function(MenuCommand)? handler;
  @override
  Future<CommandResult> submit(MenuCommand command) async {
    commands.add(command);
    return handler == null
        ? CommandRejected(
            code: 'rule',
            message: 'Not allowed for this companion.',
          )
        : handler!(command);
  }

  void publish(GameState value) {
    state = value;
    notifyListeners();
  }
}

void main() {
  final content = DemoContent.decode(
    File('assets/data/lantern_wake.json').readAsStringSync(),
  );
  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    Size size = const Size(1280, 720),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: lanternTheme(), home: child));
    await tester.pumpAndSettle();
  }

  testWidgets('all four members show authoritative stats, equipment and jobs', (
    tester,
  ) async {
    final host = TestHost(previewState(content));
    await pump(tester, PartyMenu(host: host, content: content, onBack: () {}));
    for (final name in ['Ada', 'Ren', 'Iona', 'Tavi']) {
      expect(find.text(name), findsOneWidget);
    }
    expect(find.text('HP 84 / 100'), findsOneWidget);
    expect(find.text('MP 0 / 0'), findsNWidgets(2));
    expect(find.text('Warrior · Level 3'), findsOneWidget);
    expect(find.text('Weapon: Harbor Blade'), findsOneWidget);
    final initial = host.state;
    host.publish(
      GameState(
        position: initial.position,
        party: initial.party,
        inventory: initial.inventory,
        gold: 999,
        quests: initial.quests,
      ),
    );
    await tester.pump();
    expect(find.text('999 gold'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    expect(host.observed, isFalse);
    host.dispose();
  });
  testWidgets(
    'inventory sends shared command and displays rejection without changing state',
    (tester) async {
      final host = TestHost(previewState(content));
      final before = host.state;
      await pump(
        tester,
        PartyMenu(
          host: host,
          content: content,
          initialPage: PartyPage.inventory,
          onBack: () {},
        ),
      );
      await tester.tap(find.text('Iona'));
      await tester.pump();
      await tester.tap(find.text('Use on Iona').first);
      await tester.pumpAndSettle();
      final command = host.commands.single as UseItem;
      expect(command.memberId, 'hero.iona');
      expect(command.itemId, 'item.salves');
      expect(find.text('Not allowed for this companion.'), findsOneWidget);
      expect(identical(host.state, before), isTrue);
    },
  );
  testWidgets('equipment and jobs dispatch exact IDs including null unequip', (
    tester,
  ) async {
    final host = TestHost(previewState(content));
    await pump(
      tester,
      PartyMenu(
        host: host,
        content: content,
        initialPage: PartyPage.equipment,
        onBack: () {},
      ),
    );
    await tester.tap(find.text('Equip Shell Staff'));
    await tester.pumpAndSettle();
    final equip = host.commands.last as EquipItem;
    expect(equip.itemId, 'item.shell_staff');
    expect(equip.slotId, 'weapon');
    expect(equip.memberId, 'hero.ada');
    await tester.tap(find.text('Unequip').first);
    await tester.pumpAndSettle();
    expect((host.commands.last as EquipItem).itemId, isNull);
    await tester.tap(find.text('Jobs'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose White Mage'));
    await tester.tap(find.text('Choose White Mage'));
    await tester.pumpAndSettle();
    expect((host.commands.last as ChangeJob).jobId, 'job.white_mage');
  });
  testWidgets(
    'pending commands block repeat dispatch and back; accepted state comes from host',
    (tester) async {
      final host = TestHost(previewState(content));
      final completer = Completer<CommandResult>();
      host.handler = (_) => completer.future;
      var back = 0;
      await pump(
        tester,
        PartyMenu(
          host: host,
          content: content,
          initialPage: PartyPage.inventory,
          onBack: () => back++,
        ),
      );
      await tester.tap(find.text('Use on Ada').first);
      await tester.pump();
      await tester.tap(find.text('Use on Ada').first);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(host.commands.length, 1);
      expect(back, 0);
      final state = host.state;
      host.publish(
        GameState(
          position: state.position,
          party: state.party,
          inventory: Inventory({}),
          gold: state.gold,
          quests: state.quests,
        ),
      );
      completer.complete(CommandAccepted(host.state));
      await tester.pumpAndSettle();
      expect(find.text('Your bag is empty.'), findsOneWidget);
      expect(find.text('Party updated.'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(back, 1);
    },
  );
  testWidgets('host replacement detaches listener and ignores stale result', (
    tester,
  ) async {
    final first = TestHost(previewState(content));
    final second = TestHost(previewState(content));
    final pending = Completer<CommandResult>();
    first.handler = (_) => pending.future;
    await pump(
      tester,
      PartyMenu(
        host: first,
        content: content,
        initialPage: PartyPage.inventory,
        onBack: () {},
      ),
    );
    await tester.tap(find.text('Use on Ada').first);
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        theme: lanternTheme(),
        home: PartyMenu(
          host: second,
          content: content,
          initialPage: PartyPage.inventory,
          onBack: () {},
        ),
      ),
    );
    pending.complete(CommandRejected(code: 'old', message: 'Stale error'));
    await tester.pumpAndSettle();
    expect(first.observed, isFalse);
    expect(second.observed, isTrue);
    expect(find.text('Stale error'), findsNothing);
  });
  testWidgets('host exceptions are visible and restore controls', (
    tester,
  ) async {
    final host = TestHost(previewState(content));
    host.handler = (_) async => throw StateError('offline');
    await pump(
      tester,
      PartyMenu(
        host: host,
        content: content,
        initialPage: PartyPage.inventory,
        onBack: () {},
      ),
    );
    await tester.tap(find.text('Use on Ada').first);
    await tester.pumpAndSettle();
    expect(
      find.text('The action could not be completed. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Use on Ada').first,
          )
          .onPressed,
      isNotNull,
    );
  });
  for (final availability in <LoadResult?>[
    null,
    SaveMissing(),
    SaveUnreadable(SaveReadFailure.corrupt),
    SaveUnreadable(SaveReadFailure.unsupportedVersion),
    SaveUnreadable(SaveReadFailure.unavailable),
  ]) {
    testWidgets(
      'Continue disabled for ${availability.runtimeType} ${availability is SaveUnreadable ? availability.reason : ''}',
      (tester) async {
        await pump(
          tester,
          TitleScreen(
            availability: availability,
            hasActiveProgress: false,
            onNewGame: () async {},
            onContinue: () async {},
          ),
        );
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Continue'),
              )
              .onPressed,
          isNull,
        );
      },
    );
  }
  testWidgets(
    'Continue invokes host; New Game requires confirmation and cancel preserves progress',
    (tester) async {
      var started = 0;
      var continued = 0;
      await pump(
        tester,
        TitleScreen(
          availability: SaveLoaded(
            SaveData(
              contentVersion: content.version,
              state: previewState(content),
            ),
          ),
          hasActiveProgress: true,
          onNewGame: () async => started++,
          onContinue: () async => continued++,
        ),
      );
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(continued, 1);
      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep progress'));
      await tester.pumpAndSettle();
      expect(started, 0);
      await tester.tap(find.text('New Game'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start new game'));
      await tester.pumpAndSettle();
      expect(started, 1);
    },
  );
  testWidgets('title async failure is recoverable', (tester) async {
    await pump(
      tester,
      TitleScreen(
        availability: SaveMissing(),
        hasActiveProgress: false,
        onNewGame: () async => throw StateError('offline'),
        onContinue: () async {},
      ),
    );
    await tester.tap(find.text('New Game'));
    await tester.pumpAndSettle();
    expect(
      find.text('Unable to open the journey. Please try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'New Game'))
          .onPressed,
      isNotNull,
    );
  });
  testWidgets('dialogue keyboard advances, completes once and restores focus', (
    tester,
  ) async {
    final results = <DialogueDismissal>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: FilledButton(
            focusNode: focus,
            autofocus: true,
            onPressed: () async {
              results.add(
                await showGameDialogue(
                  context,
                  DialogueRequest(
                    id: 'dialogue.test',
                    speaker: 'Mara',
                    lines: ['First line', 'Last line'],
                  ),
                ),
              );
            },
            child: const Text('Talk'),
          ),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('First line'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('Last line'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(results, [DialogueDismissal.completed]);
    expect(focus.hasFocus, isTrue);
    await tester.tap(find.text('Talk'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(results, [DialogueDismissal.completed, DialogueDismissal.cancelled]);
  });
  for (final size in [
    const Size(1280, 720),
    const Size(480, 640),
    const Size(360, 640),
  ]) {
    testWidgets('all screens fit $size', (tester) async {
      await pump(
        tester,
        TitleScreen(
          availability: SaveMissing(),
          hasActiveProgress: false,
          onNewGame: () async {},
          onContinue: () async {},
        ),
        size: size,
      );
      expect(tester.takeException(), isNull);
      for (final page in PartyPage.values) {
        await tester.pumpWidget(const SizedBox());
        await pump(
          tester,
          PartyMenu(
            host: TestHost(previewState(content)),
            content: content,
            initialPage: page,
            onBack: () {},
          ),
          size: size,
        );
        expect(tester.takeException(), isNull, reason: '$page at $size');
      }
    });
  }
}
