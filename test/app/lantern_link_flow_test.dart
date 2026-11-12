import 'dart:async';

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/game_app.dart';
import 'package:app_4/app/world_operations.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/battle/ui/battle_screen.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/multiplayer/lantern_link.dart';
import 'package:app_4/multiplayer/lantern_link_client.dart';
import 'package:app_4/ui/lantern_link_dialog.dart';
import 'package:app_4/world/prototype_map.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../bin/lantern_link_server.dart';

Future<void> until(LanternLinkClient client, bool Function() predicate) async {
  if (predicate()) return;
  final done = Completer<void>();
  void changed() {
    if (predicate() && !done.isCompleted) done.complete();
  }

  client.addListener(changed);
  try {
    await done.future.timeout(const Duration(seconds: 5));
  } finally {
    client.removeListener(changed);
  }
}

void main() {
  for (final defeat in [false, true]) {
    testWidgets(
      'production shell applies shared ${defeat ? 'defeat and restart' : 'training victory'} without a local battle',
      (tester) async {
        final map = createPrototypeMap();
        final initial = createContractFixture(position: map.spawns['entry']!);
        BattleSession create(BattleInput input) => BattleSession(
          input: input,
          heroStats: {
            for (final m in input.state.party)
              m.id: const CombatStats(attack: 20, defense: 0, speed: 5),
          },
          enemies: [
            combat.Combatant(
              id: 'enemy',
              side: combat.BattleSide.enemies,
              hp: defeat ? 1000 : 1,
              maxHp: defeat ? 1000 : 1,
              attack: defeat ? 1000 : 0,
              defense: 0,
              speed: 0,
            ),
          ],
        );
        final room = LanternLinkRoom(
          name: 'shell-test',
          initialState: initial,
          createBattle: create,
        );
        final server = LanternLinkServer(room);
        final bound = await tester.runAsync(() => server.start(port: 0));
        final endpoint = 'ws://127.0.0.1:${bound!.port}/lantern-link';
        final peer = LanternLinkClient();
        WorldHost? worldHost;
        await tester.pumpWidget(
          GameApp(
            loadWorld: () async => WorldSession(
              map: map,
              initialState: initial,
              isClear: WorldCollision(map).isClear,
              operations: WorldOperations(
                questSteps: [
                  WorldQuestStep(
                    id: 'step.bell',
                    interactionId: 'bell',
                    site: InteractionSite(
                      mapId: map.id,
                      canActivate: (_) => true,
                    ),
                    dialogue: WorldDialogue(
                      id: 'dialogue.bell',
                      speaker: 'Keeper',
                      site: InteractionSite(
                        mapId: map.id,
                        canActivate: (_) => true,
                      ),
                      lines: ['The lantern is recovered.'],
                    ),
                    encounterId: 'enemy.hollow_bell',
                    setsFlag: 'quest.bell_awake',
                  ),
                ],
              ),
            ),
            buildWorld: (_) => (_, host, _) {
              worldHost = host;
              return TextButton(
                onPressed: () => (host as WorldInteractionHost).openDialogue(
                  'bell',
                  expectedRevision: host.revision,
                ),
                child: const Text('Ring bell'),
              );
            },
            battles: {'fixture.battle': create, 'enemy.hollow_bell': create},
            trainingEncounterId: 'fixture.battle',
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Lantern Link multiplayer'));
        await tester.pumpAndSettle();
        final client = tester
            .widget<LanternLinkDialog>(find.byType(LanternLinkDialog))
            .client;
        await tester.runAsync(() async {
          await client.connect(endpoint: endpoint, playerId: 'host');
          await until(client, () => client.snapshot != null);
          await peer.connect(endpoint: endpoint, playerId: 'guest');
          await until(client, () => client.snapshot!.players.length == 2);
          await client.assignEvenly(playerCount: 2);
          await until(peer, () => peer.snapshot?.phase == 'exploration');
        });
        await tester.pumpAndSettle();
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        await tester.runAsync(() => tester.tap(find.text('New Game')));
        await tester.pumpAndSettle();
        if (!defeat) {
          await tester.runAsync(() async {
            final controller = worldHost! as AppController;
            for (final x in [3.5, 4.5]) {
              expect(
                controller.updatePosition(
                  WorldPosition(mapId: map.id, x: x, y: 2.5),
                  expectedRevision: controller.revision,
                ),
                isTrue,
              );
            }
            expect(controller.setPaused(true), isTrue);
            await until(
              client,
              () => client.snapshot!.gameState.position.x == 4.5,
            );
          });
          await tester.pumpAndSettle();
          expect(find.text('Paused'), findsOneWidget);
          expect(worldHost!.state.position.x, 4.5);
          await tester.runAsync(
            () => tester.tap(find.text('Continue exploring')),
          );
          await tester.pumpAndSettle();
        }
        await tester.runAsync(() async {
          await tester.tap(find.text('Training battle'));
          await until(client, () => client.snapshot?.phase == 'battle');
        });
        await tester.pumpAndSettle();
        expect(find.byType(BattleScreen), findsNothing);
        expect(find.text('Training battle'), findsNothing);
        expect(worldHost!.movementEnabled, isFalse);
        expect(find.text('End session'), findsOneWidget);
        Future<void> finishBattle() async {
          for (
            var round = 0;
            client.snapshot?.phase == 'battle' && round < 10;
            round++
          ) {
            final oldRound = client.snapshot!.battle!['round'];
            final living = (client.snapshot!.battle!['combatants'] as List)
                .cast<Map>()
                .where((a) => a['side'] == 'heroes' && (a['hp'] as int) > 0);
            for (final actor in living) {
              final id = actor['id'] as String;
              final owner = client.snapshot!.assignments['host']!.contains(id)
                  ? client
                  : peer;
              await owner.attack(id, 'enemy');
            }
            await until(
              client,
              () =>
                  client.snapshot?.phase != 'battle' ||
                  client.snapshot!.battle!['round'] != oldRound,
            );
            await until(
              peer,
              () => peer.snapshot?.revision == client.snapshot?.revision,
            );
          }
        }

        await tester.runAsync(finishBattle);
        await tester.pumpAndSettle();
        if (defeat) {
          expect(find.text('Party defeated'), findsOneWidget);
          expect(worldHost!.state.party.every((m) => m.hp == 0), isTrue);
          await tester.runAsync(() async {
            await tester.tap(find.text('New Game'));
            await until(client, () => client.snapshot?.phase == 'exploration');
          });
          await tester.pumpAndSettle();
          expect(worldHost!.state.party.every((m) => m.hp > 0), isTrue);
        }
        expect(worldHost!.movementEnabled, isTrue);
        if (!defeat) {
          await tester.runAsync(() async {
            await tester.tap(find.text('Ring bell'));
            await until(client, () => client.snapshot?.phase == 'battle');
            await finishBattle();
            await until(
              client,
              () => client.snapshot!.gameState.quests.flags.contains(
                'quest.bell_awake',
              ),
            );
          });
          await tester.pumpAndSettle();
          expect(find.text('The lantern is recovered.'), findsOneWidget);
          expect(worldHost!.state.quests.flags, contains('quest.bell_awake'));
        }
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async {
          peer.dispose();
          await server.close();
        });
      },
    );
  }

  testWidgets(
    'guest leave returns to title and host migration restores control',
    (tester) async {
      final map = createPrototypeMap();
      final initial = createContractFixture(position: map.spawns['entry']!);
      final server = LanternLinkServer(
        LanternLinkRoom(
          name: 'migration',
          initialState: initial,
          createBattle: (_) => throw StateError('No combat in lifecycle test'),
        ),
      );
      final bound = await tester.runAsync(() => server.start(port: 0));
      final endpoint = 'ws://127.0.0.1:${bound!.port}/lantern-link';
      final originalHost = LanternLinkClient();
      await tester.runAsync(() async {
        await originalHost.connect(endpoint: endpoint, playerId: 'host');
        await until(originalHost, () => originalHost.snapshot != null);
      });
      WorldHost? worldHost;
      await tester.pumpWidget(
        GameApp(
          loadWorld: () async => WorldSession(
            map: map,
            initialState: initial,
            isClear: WorldCollision(map).isClear,
          ),
          buildWorld: (_) => (_, host, _) {
            worldHost = host;
            return const Text('Remote exploration');
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Lantern Link multiplayer'));
      await tester.pumpAndSettle();
      final guest = tester
          .widget<LanternLinkDialog>(find.byType(LanternLinkDialog))
          .client;
      await tester.runAsync(() async {
        await guest.connect(endpoint: endpoint, playerId: 'guest');
        await until(
          originalHost,
          () => originalHost.snapshot!.players.length == 2,
        );
        await originalHost.assignEvenly(playerCount: 2);
        await until(guest, () => guest.snapshot?.phase == 'exploration');
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave room'));
      await tester.pumpAndSettle();
      expect(find.text('New Game'), findsOneWidget);
      await tester.tap(find.byTooltip('Lantern Link multiplayer'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await guest.connect(endpoint: endpoint, playerId: 'guest');
        await until(guest, () => guest.snapshot?.phase == 'exploration');
      });
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(worldHost!.movementEnabled, isFalse);
      await tester.runAsync(() async {
        originalHost.disconnect();
        await until(
          guest,
          () => guest.isHost && guest.snapshot?.phase == 'paused',
        );
      });
      await tester.pumpAndSettle();
      expect(worldHost!.movementEnabled, isFalse);
      await tester.runAsync(() async {
        await originalHost.connect(endpoint: endpoint, playerId: 'host');
        await until(guest, () => guest.snapshot?.phase == 'exploration');
      });
      await tester.pumpAndSettle();
      expect(worldHost!.movementEnabled, isTrue);
      expect(originalHost.isHost, isFalse);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        originalHost.dispose();
        await server.close();
      });
    },
  );
}
