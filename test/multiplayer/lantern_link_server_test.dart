import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../bin/lantern_link_server.dart';

import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/multiplayer/lantern_link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LanternLinkRoom room() => LanternLinkRoom(
    name: 'test-room',
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

  test('WebSocket clients can join a named local room and receive its snapshot', () async {
    final service = LanternLinkServer(room());
    final bound = await service.start(port: 0);
    final host = await WebSocket.connect(
      'ws://${InternetAddress.loopbackIPv4.address}:${bound.port}/lantern-link',
    );
    final hostMessages = StreamIterator<dynamic>(host);
    host.add(jsonEncode({'type': 'hello', 'playerId': 'host'}));
    expect(await hostMessages.moveNext(), isTrue);
    final first = Map<String, dynamic>.from(
      jsonDecode(hostMessages.current as String) as Map,
    );
    expect(first['type'], 'joined');
    expect(first['snapshot']['room'], 'test-room');

    final guest = await WebSocket.connect(
      'ws://${InternetAddress.loopbackIPv4.address}:${bound.port}/lantern-link',
    );
    final guestMessages = StreamIterator<dynamic>(guest);
    guest.add(jsonEncode({'type': 'hello', 'playerId': 'guest'}));
    expect(await guestMessages.moveNext(), isTrue);
    final second = Map<String, dynamic>.from(
      jsonDecode(guestMessages.current as String) as Map,
    );
    expect(second['snapshot']['players'], ['host', 'guest']);

    await hostMessages.cancel();
    await guestMessages.cancel();
    await host.close();
    await guest.close();
    await service.close();
  });
}
