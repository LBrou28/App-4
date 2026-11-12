import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../bin/lantern_link_server.dart';

import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart' show GameState, PartyMember;
import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/multiplayer/lantern_link.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/world_spawn.dart';
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

  Future<Map<String, dynamic>> nextMessage(
    StreamIterator<dynamic> iterator,
  ) async {
    expect(
      await iterator.moveNext().timeout(const Duration(seconds: 3)),
      isTrue,
    );
    return Map<String, dynamic>.from(
      jsonDecode(iterator.current as String) as Map,
    );
  }

  test('rejects repeated hello identity switch and preserves same-ID reconnect', () async {
    final service = LanternLinkServer(room());
    final bound = await service.start(port: 0);
    final url =
        'ws://${InternetAddress.loopbackIPv4.address}:${bound.port}/lantern-link';

    final host = await WebSocket.connect(url);
    final hostMessages = StreamIterator<dynamic>(host);
    host.add(jsonEncode({'type': 'hello', 'playerId': 'host', 'requestId': 1}));
    final hostJoined = await nextMessage(hostMessages);
    expect(hostJoined['requestId'], 1);
    expect(hostJoined['requesterId'], 'host');

    final guest = await WebSocket.connect(url);
    final guestMessages = StreamIterator<dynamic>(guest);
    guest.add(
      jsonEncode({'type': 'hello', 'playerId': 'guest', 'requestId': 2}),
    );
    final hostSawGuest = await nextMessage(hostMessages);
    final guestJoined = await nextMessage(guestMessages);
    expect(hostSawGuest['requestId'], 2);
    expect(guestJoined['requesterId'], 'guest');

    // Attempting to switch identity on an already-identified socket fails
    // without disturbing guest or modifying room membership.
    host.add(
      jsonEncode({'type': 'hello', 'playerId': 'guest', 'requestId': 41}),
    );
    final switchError = await nextMessage(hostMessages);
    expect(switchError['type'], 'error');
    expect(switchError['requestId'], 41);
    expect(switchError['requestType'], 'hello');
    expect(service.room.snapshot.players, ['host', 'guest']);

    // Repeating hello with the same playerId on the same socket does not close
    // the socket.
    host.add(
      jsonEncode({'type': 'hello', 'playerId': 'host', 'requestId': 42}),
    );
    final sameSocketReconnect = await nextMessage(hostMessages);
    final guestSawSame = await nextMessage(guestMessages);
    expect(sameSocketReconnect['type'], 'reconnected');
    expect(sameSocketReconnect['requestId'], 42);
    expect(sameSocketReconnect['requesterId'], 'host');
    expect(guestSawSame['type'], 'reconnected');

    // Reconnecting from a new socket with the same playerId closes the old
    // socket without pausing the room.
    final replacement = await WebSocket.connect(url);
    final replacementMessages = StreamIterator<dynamic>(replacement);
    replacement.add(
      jsonEncode({'type': 'hello', 'playerId': 'host', 'requestId': 43}),
    );
    final replacementAck = await nextMessage(replacementMessages);
    final guestSawReplace = await nextMessage(guestMessages);
    expect(replacementAck['type'], 'reconnected');
    expect(replacementAck['requestId'], 43);
    expect(replacementAck['requesterId'], 'host');
    expect(guestSawReplace['type'], 'reconnected');
    expect(
      await hostMessages.moveNext().timeout(const Duration(seconds: 3)),
      isFalse,
    );
    expect(service.room.snapshot.players, ['host', 'guest']);

    await hostMessages.cancel();
    await guestMessages.cancel();
    await replacementMessages.cancel();
    await guest.close();
    await replacement.close();
    await service.close();
  });

  test('correlates requestId/requesterId, encounter metadata, gameOver, and restart', () async {
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
    final lethalRoom = LanternLinkRoom(
      name: 'test-room',
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
    final service = LanternLinkServer(lethalRoom);
    final bound = await service.start(port: 0);
    final url =
        'ws://${InternetAddress.loopbackIPv4.address}:${bound.port}/lantern-link';

    final host = await WebSocket.connect(url);
    final guest = await WebSocket.connect(url);
    final hostMessages = StreamIterator<dynamic>(host);
    final guestMessages = StreamIterator<dynamic>(guest);

    host.add(jsonEncode({'type': 'hello', 'playerId': 'host', 'requestId': 1}));
    await nextMessage(hostMessages);
    guest.add(
      jsonEncode({'type': 'hello', 'playerId': 'guest', 'requestId': 2}),
    );
    await nextMessage(hostMessages);
    await nextMessage(guestMessages);

    // Unauthorized request returns an error only to the requester with requestId.
    guest.add(jsonEncode({'type': 'configure', 'mode': 'two', 'requestId': 3}));
    final unauthorized = await nextMessage(guestMessages);
    expect(unauthorized['type'], 'error');
    expect(unauthorized['requestId'], 3);
    expect(unauthorized['requestType'], 'configure');

    host.add(jsonEncode({'type': 'configure', 'mode': 'two', 'requestId': 4}));
    final hostConfigured = await nextMessage(hostMessages);
    final guestConfigured = await nextMessage(guestMessages);
    expect(hostConfigured['type'], 'configured');
    expect(hostConfigured['requestId'], 4);
    expect(guestConfigured['requesterId'], 'host');

    host.add(
      jsonEncode({
        'type': 'assign',
        'requestId': 5,
        'assignments': {
          'host': ['fixture.hero.0', 'fixture.hero.1'],
          'guest': ['fixture.hero.2', 'fixture.hero.3'],
        },
      }),
    );
    await nextMessage(hostMessages);
    await nextMessage(guestMessages);

    host.add(
      jsonEncode({
        'type': 'battleStart',
        'definitionId': 'enemy.lethal',
        'seed': 1,
        'requestId': 6,
      }),
    );
    final hostStarted = await nextMessage(hostMessages);
    final guestStarted = await nextMessage(guestMessages);
    expect(hostStarted['requestId'], 6);
    expect(hostStarted['requesterId'], 'host');
    expect(hostStarted['snapshot']['encounterId'], 'lantern-link-1');
    expect(hostStarted['snapshot']['encounterDefinitionId'], 'enemy.lethal');
    expect(hostStarted['snapshot']['outcome'], isNull);
    expect(guestStarted['snapshot']['phase'], 'battle');

    host.add(
      jsonEncode({
        'type': 'command',
        'round': 1,
        'requestId': 7,
        'command': {'actorId': 'fixture.hero.0', 'action': 'defend'},
      }),
    );
    final hostDefeat = await nextMessage(hostMessages);
    final guestDefeat = await nextMessage(guestMessages);
    expect(hostDefeat['type'], 'battleFinished');
    expect(hostDefeat['requestId'], 7);
    expect(hostDefeat['requesterId'], 'host');
    expect(hostDefeat['snapshot']['phase'], 'gameOver');
    expect(hostDefeat['snapshot']['outcome'], 'defeat');
    expect(guestDefeat['snapshot']['encounterId'], 'lantern-link-1');

    guest.add(jsonEncode({'type': 'restart', 'requestId': 8}));
    final guestRestartErr = await nextMessage(guestMessages);
    expect(guestRestartErr['type'], 'error');
    expect(guestRestartErr['requestId'], 8);
    expect(guestRestartErr['requestType'], 'restart');

    host.add(jsonEncode({'type': 'restart', 'requestId': 9}));
    final hostRestarted = await nextMessage(hostMessages);
    final guestRestarted = await nextMessage(guestMessages);
    expect(hostRestarted['type'], 'restarted');
    expect(hostRestarted['requestId'], 9);
    expect(hostRestarted['requesterId'], 'host');
    expect(hostRestarted['snapshot']['phase'], 'exploration');
    expect(hostRestarted['snapshot']['encounterId'], isNull);
    expect(hostRestarted['snapshot']['encounterDefinitionId'], isNull);
    expect(hostRestarted['snapshot']['outcome'], isNull);
    expect(guestRestarted['snapshot']['state']['party'][0]['hp'], 10);

    await hostMessages.cancel();
    await guestMessages.cancel();
    await host.close();
    await guest.close();
    await service.close();
  });

  test('canonical server spawn uses harborEntryPosition', () {
    final content = DemoContent.decode(
      File('assets/data/lantern_wake.json').readAsStringSync(),
    );
    final created = createLanternLinkRoom(
      roomName: 'bellwether',
      content: content,
    );
    final expected = harborEntryPosition();
    expect(created.snapshot.state.position.mapId, expected.mapId);
    expect(created.snapshot.state.position.x, expected.x);
    expect(created.snapshot.state.position.y, expected.y);
  });
}
