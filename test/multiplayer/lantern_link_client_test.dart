import 'dart:async';
import 'dart:io';

import '../../bin/lantern_link_server.dart';

import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/multiplayer/lantern_link.dart';
import 'package:app_4/multiplayer/lantern_link_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('browser-compatible client joins the WebSocket room and reads its snapshot', () async {
    final room = LanternLinkRoom(
      name: 'client-test',
      initialState: createContractFixture(),
      createBattle: (input) => BattleSession(
        input: input,
        heroStats: {
          for (final member in input.state.party)
            member.id: const CombatStats(attack: 4, defense: 2, speed: 5),
        },
        enemies: [
          Combatant(
            id: 'enemy.test',
            side: BattleSide.enemies,
            hp: 10,
            maxHp: 10,
            attack: 1,
            defense: 0,
            speed: 1,
          ),
        ],
      ),
    );
    final server = LanternLinkServer(room);
    final bound = await server.start(port: 0);
    final client = LanternLinkClient();
    final joined = Completer<void>();
    client.addListener(() {
      if (client.snapshot != null && !joined.isCompleted) joined.complete();
    });
    await client.connect(
      endpoint:
          'ws://${InternetAddress.loopbackIPv4.address}:${bound.port}/lantern-link',
      playerId: 'host',
    );
    await joined.future.timeout(const Duration(seconds: 3));
    expect(client.snapshot!.room, 'client-test');
    expect(client.isHost, isTrue);
    expect(client.snapshot!.gameState.position, isNotNull);
    expect(
      client.snapshot!.gameState.party.map((member) => member.id),
      orderedEquals(createContractFixture().party.map((member) => member.id)),
    );
    client.dispose();
    await server.close();
  });
}
