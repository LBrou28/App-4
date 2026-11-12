import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../bin/lantern_link_server.dart';

import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/core/contracts.dart';
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
  test(
    'client parses encounter metadata, outcome, and gameOver phase',
    () async {
      final relay = await _RelayServer.start();
      final client = LanternLinkClient();
      addTearDown(() async {
        client.dispose();
        await relay.close();
      });

      final connectFuture = client.connect(
        endpoint: relay.endpoint,
        playerId: 'host',
      );
      final hello = await relay.nextMessage();
      relay.sendSnapshot(
        hello.socket,
        kind: 'joined',
        requestId: hello.message['requestId'] as int,
        requesterId: 'host',
        phase: 'gameOver',
        revision: 9,
        encounterId: 'lantern-link-4',
        encounterDefinitionId: 'enemy.brine_mite',
        outcome: 'defeat',
      );
      await connectFuture;

      expect(client.snapshot?.phase, 'gameOver');
      expect(client.snapshot?.encounterId, 'lantern-link-4');
      expect(client.snapshot?.encounterDefinitionId, 'enemy.brine_mite');
      expect(client.snapshot?.outcome, 'defeat');

      final restartFuture = client.restart();
      final restartMsg = await relay.nextMessage();
      expect(restartMsg.message['type'], 'restart');
      relay.sendSnapshot(
        restartMsg.socket,
        kind: 'restarted',
        requestId: restartMsg.message['requestId'] as int,
        requesterId: 'host',
        phase: 'exploration',
        revision: 10,
      );
      await restartFuture;

      expect(client.snapshot?.phase, 'exploration');
      expect(client.snapshot?.encounterId, isNull);
      expect(client.snapshot?.encounterDefinitionId, isNull);
      expect(client.snapshot?.outcome, isNull);
    },
  );

  test(
    'request correlation ignores colliding requestIds from other players',
    () async {
      final relay = await _RelayServer.start();
      final client = LanternLinkClient();
      addTearDown(() async {
        client.dispose();
        await relay.close();
      });

      final connectFuture = client.connect(
        endpoint: relay.endpoint,
        playerId: 'host',
      );
      final hello = await relay.nextMessage();
      relay.sendSnapshot(
        hello.socket,
        kind: 'joined',
        requestId: hello.message['requestId'] as int,
        requesterId: 'host',
        phase: 'lobby',
        revision: 1,
        players: const ['host'],
      );
      await connectFuture;

      var configuredDone = false;
      final configureFuture = client.configurePlayers(2).then((_) {
        configuredDone = true;
      });
      final configureMsg = await relay.nextMessage();
      final hostRequestId = configureMsg.message['requestId'] as int;

      // Broadcast from guest using the same numeric requestId must not resolve host's Future.
      relay.sendSnapshot(
        configureMsg.socket,
        kind: 'joined',
        requestId: hostRequestId,
        requesterId: 'guest',
        phase: 'lobby',
        revision: 2,
        players: const ['host', 'guest'],
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(configuredDone, isFalse);

      relay.sendSnapshot(
        configureMsg.socket,
        kind: 'configured',
        requestId: hostRequestId,
        requesterId: 'host',
        phase: 'lobby',
        revision: 3,
        players: const ['host', 'guest'],
      );
      await configureFuture;
      expect(configuredDone, isTrue);
    },
  );

  test(
    'assignEvenly configures selected mode and awaits ack before assigning',
    () async {
      final relay = await _RelayServer.start();
      final client = LanternLinkClient();
      addTearDown(() async {
        client.dispose();
        await relay.close();
      });

      final connectFuture = client.connect(
        endpoint: relay.endpoint,
        playerId: 'host',
      );
      final hello = await relay.nextMessage();
      relay.sendSnapshot(
        hello.socket,
        kind: 'joined',
        requestId: hello.message['requestId'] as int,
        requesterId: 'host',
        phase: 'lobby',
        revision: 1,
        players: const ['host', 'guest'],
      );
      await connectFuture;

      final assignFuture = client.assignEvenly(playerCount: 2);
      final configureMsg = await relay.nextMessage();
      expect(configureMsg.message['type'], 'configure');
      expect(configureMsg.message['mode'], 'two');

      // Ensure assign is not sent before configure is acknowledged.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(relay.pendingCount, 0);

      relay.sendSnapshot(
        configureMsg.socket,
        kind: 'configured',
        requestId: configureMsg.message['requestId'] as int,
        requesterId: 'host',
        phase: 'lobby',
        revision: 2,
        players: const ['host', 'guest'],
      );

      final assignMsg = await relay.nextMessage();
      expect(assignMsg.message['type'], 'assign');
      relay.sendSnapshot(
        assignMsg.socket,
        kind: 'ready',
        requestId: assignMsg.message['requestId'] as int,
        requesterId: 'host',
        phase: 'exploration',
        revision: 3,
        players: const ['host', 'guest'],
        assignments: const {
          'host': ['fixture.hero.0', 'fixture.hero.1'],
          'guest': ['fixture.hero.2', 'fixture.hero.3'],
        },
      );
      await assignFuture;
      expect(client.snapshot?.phase, 'exploration');
    },
  );

  test('startEncounter drains queued latest exploration/dialogue before battleStart', () async {
    final relay = await _RelayServer.start();
    final client = LanternLinkClient();
    addTearDown(() async {
      client.dispose();
      await relay.close();
    });

    final connectFuture = client.connect(
      endpoint: relay.endpoint,
      playerId: 'host',
    );
    final hello = await relay.nextMessage();
    relay.sendSnapshot(
      hello.socket,
      kind: 'ready',
      requestId: hello.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 3,
      players: const ['host', 'guest'],
    );
    await connectFuture;

    final state1 = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 1.0, y: 1.0),
    );
    final state2 = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 2.0, y: 1.0),
    );
    final state3 = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 2.5, y: 1.5),
    );
    final d2 = LanternLinkDialogue(
      id: 'd.two',
      speaker: 'Keeper',
      lines: ['Two'],
    );
    final d3 = LanternLinkDialogue(
      id: 'd.three',
      speaker: 'Keeper',
      lines: ['Three'],
    );

    final pub1 = client.publishExploration(state1);
    final pub2 = client.publishExploration(state2, dialogue: d2);
    final pub3 = client.publishExploration(state3, dialogue: d3);
    final startFuture = client.startEncounter(
      definitionId: 'enemy.brine_mite',
      seed: 42,
    );

    final msg1 = await relay.nextMessage();
    expect(msg1.message['type'], 'exploration');
    expect(msg1.message['state']['position']['x'], 1.0);

    // Unrelated broadcast while exploration is in flight must not flush queue early.
    relay.sendSnapshot(
      msg1.socket,
      kind: 'reconnected',
      requestId: 99,
      requesterId: 'guest',
      phase: 'exploration',
      revision: 3,
      players: const ['host', 'guest'],
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(relay.pendingCount, 0);

    relay.sendSnapshot(
      msg1.socket,
      kind: 'exploration',
      requestId: msg1.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 4,
      players: const ['host', 'guest'],
      state: state1,
    );
    await pub1;

    // Latest queued state3 and dialogue d3 must be sent next; state2/d2 coalesced.
    final msg2 = await relay.nextMessage();
    expect(msg2.message['type'], 'exploration');
    expect(msg2.message['revision'], 4);
    expect(msg2.message['state']['position']['x'], 2.5);
    expect(msg2.message['dialogue']['id'], 'd.three');

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(relay.pendingCount, 0);

    relay.sendSnapshot(
      msg2.socket,
      kind: 'exploration',
      requestId: msg2.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 5,
      players: const ['host', 'guest'],
      state: state3,
      dialogue: d3,
    );
    await Future.wait([pub2, pub3]);

    final battleStartMsg = await relay.nextMessage();
    expect(battleStartMsg.message['type'], 'battleStart');
    expect(battleStartMsg.message['definitionId'], 'enemy.brine_mite');
    expect(battleStartMsg.message['seed'], 42);

    // Updates arriving while battleStart is in flight must not race on the wire.
    final duringBattleStart = client.publishExploration(state1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(relay.pendingCount, 0);

    relay.sendSnapshot(
      battleStartMsg.socket,
      kind: 'battleStarted',
      requestId: battleStartMsg.message['requestId'] as int,
      requesterId: 'host',
      phase: 'battle',
      revision: 6,
      players: const ['host', 'guest'],
      state: state3,
      encounterId: 'lantern-link-1',
      encounterDefinitionId: 'enemy.brine_mite',
    );
    await Future.wait([startFuture, duringBattleStart]);
    expect(client.snapshot?.phase, 'battle');
    expect(relay.pendingCount, 0);
  });

  test('startEncounter publishes passed state and aborts without battleStart on rejected publication', () async {
    final relay = await _RelayServer.start();
    final client = LanternLinkClient();
    addTearDown(() async {
      client.dispose();
      await relay.close();
    });

    final connectFuture = client.connect(
      endpoint: relay.endpoint,
      playerId: 'host',
    );
    final hello = await relay.nextMessage();
    relay.sendSnapshot(
      hello.socket,
      kind: 'ready',
      requestId: hello.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 3,
      players: const ['host', 'guest'],
    );
    await connectFuture;

    final rejectedState = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 2.0, y: 2.0),
    );
    final failedStart = client.startEncounter(
      definitionId: 'enemy.brine_mite',
      seed: 7,
      state: rejectedState,
    );
    final expMsg = await relay.nextMessage();
    expect(expMsg.message['type'], 'exploration');
    expect(expMsg.message['state']['position']['x'], 2.0);

    relay.sendError(
      expMsg.socket,
      'Stale or unavailable exploration update',
      requestId: expMsg.message['requestId'] as int,
    );
    await expectLater(failedStart, throwsStateError);
    expect(client.error, 'Stale or unavailable exploration update');

    // battleStart must never have been sent.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(relay.pendingCount, 0);

    // Client recovers cleanly for a subsequent startEncounter.
    final retryState = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 2.5, y: 2.0),
    );
    final retryStart = client.startEncounter(
      definitionId: 'enemy.brine_mite',
      seed: 8,
      state: retryState,
    );
    final retryExp = await relay.nextMessage();
    expect(retryExp.message['type'], 'exploration');
    relay.sendSnapshot(
      retryExp.socket,
      kind: 'exploration',
      requestId: retryExp.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 4,
      players: const ['host', 'guest'],
      state: retryState,
    );
    final battleStart = await relay.nextMessage();
    expect(battleStart.message['type'], 'battleStart');
    relay.sendSnapshot(
      battleStart.socket,
      kind: 'battleStarted',
      requestId: battleStart.message['requestId'] as int,
      requesterId: 'host',
      phase: 'battle',
      revision: 5,
      players: const ['host', 'guest'],
      state: retryState,
    );
    await retryStart;
    expect(client.snapshot?.phase, 'battle');
  });

  test('disconnect clears queued exploration, notifies on active loss, and isolates obsolete socket callbacks', () async {
    final relay = await _RelayServer.start();
    final client = LanternLinkClient();
    addTearDown(() async {
      client.dispose();
      await relay.close();
    });

    var notifications = 0;
    client.addListener(() => notifications++);

    // Disconnecting while already disconnected must not spuriously notify.
    client.disconnect();
    expect(notifications, 0);

    final connect1 = client.connect(endpoint: relay.endpoint, playerId: 'host');
    final hello1 = await relay.nextMessage();
    relay.sendSnapshot(
      hello1.socket,
      kind: 'ready',
      requestId: hello1.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 3,
      players: const ['host', 'guest'],
    );
    await connect1;
    final oldSocket = hello1.socket;

    final s1 = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 1.1, y: 1.1),
    );
    final s2 = createContractFixture(
      position: WorldPosition(mapId: 'fixture.room', x: 2.2, y: 2.2),
    );
    final d2 = LanternLinkDialogue(
      id: 'd.stale',
      speaker: 'Keeper',
      lines: ['Stale'],
    );
    final pub1 = client.publishExploration(s1).catchError((_) {});
    final pub2 = client.publishExploration(s2, dialogue: d2).catchError((_) {});
    await relay.nextMessage();

    final beforeDisconnect = notifications;
    client.disconnect();
    await Future.wait([pub1, pub2]);
    expect(notifications, greaterThan(beforeDisconnect));
    expect(client.connected, isFalse);
    expect(client.snapshot, isNull);

    // Reconnect on a new socket; old queued exploration must not leak.
    final connect2 = client.connect(endpoint: relay.endpoint, playerId: 'host');
    final hello2 = await relay.nextMessage();
    expect(hello2.message['type'], 'hello');
    relay.sendSnapshot(
      hello2.socket,
      kind: 'ready',
      requestId: hello2.message['requestId'] as int,
      requesterId: 'host',
      phase: 'exploration',
      revision: 1,
      players: const ['host', 'guest'],
    );
    await connect2;

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(relay.pendingCount, 0);

    // Obsolete socket messages/errors/close must not corrupt the active reconnect.
    relay.sendError(oldSocket, 'Obsolete socket error');
    await oldSocket.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(client.connected, isTrue);
    expect(client.error, isNull);
    expect(client.snapshot?.revision, 1);

    // Real transport close on active socket must clear snapshot and notify.
    final beforeDrop = notifications;
    await hello2.socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notifications, greaterThan(beforeDrop));
    expect(client.connected, isFalse);
    expect(client.snapshot, isNull);
    expect(client.error, 'Disconnected from Lantern Link');
  });

  test('dispose does not notify listeners during or after disposal', () async {
    final relay = await _RelayServer.start();
    final client = LanternLinkClient();
    addTearDown(relay.close);

    final connectFuture = client.connect(
      endpoint: relay.endpoint,
      playerId: 'host',
    );
    final hello = await relay.nextMessage();
    relay.sendSnapshot(
      hello.socket,
      kind: 'joined',
      requestId: hello.message['requestId'] as int,
      requesterId: 'host',
      phase: 'lobby',
      revision: 1,
      players: const ['host'],
    );
    await connectFuture;

    var notificationsAfterConnect = 0;
    client.addListener(() => notificationsAfterConnect++);
    client.dispose();
    await hello.socket.close();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(notificationsAfterConnect, 0);
  });

  test(
    'rejected battleStart flushes queued exploration and allows retry',
    () async {
      final relay = await _RelayServer.start();
      final client = LanternLinkClient();
      addTearDown(() async {
        client.dispose();
        await relay.close();
      });

      final connectFuture = client.connect(
        endpoint: relay.endpoint,
        playerId: 'host',
      );
      final hello = await relay.nextMessage();
      relay.sendSnapshot(
        hello.socket,
        kind: 'ready',
        requestId: hello.message['requestId'] as int,
        requesterId: 'host',
        phase: 'exploration',
        revision: 3,
        players: const ['host', 'guest'],
      );
      await connectFuture;

      final state1 = createContractFixture(
        position: WorldPosition(mapId: 'fixture.room', x: 1.5, y: 1.0),
      );
      final state2 = createContractFixture(
        position: WorldPosition(mapId: 'fixture.room', x: 2.0, y: 1.0),
      );

      final failedStart = client.startEncounter(
        definitionId: 'enemy.brine_mite',
        seed: 11,
        state: state1,
      );
      final exp1 = await relay.nextMessage();
      expect(exp1.message['type'], 'exploration');
      relay.sendSnapshot(
        exp1.socket,
        kind: 'exploration',
        requestId: exp1.message['requestId'] as int,
        requesterId: 'host',
        phase: 'exploration',
        revision: 4,
        players: const ['host', 'guest'],
        state: state1,
      );

      final battleStart1 = await relay.nextMessage();
      expect(battleStart1.message['type'], 'battleStart');

      // Queue a newer exploration update while battleStart is in flight.
      final queuedPub = client.publishExploration(state2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(relay.pendingCount, 0);

      relay.sendError(
        battleStart1.socket,
        'Encounter unavailable',
        requestId: battleStart1.message['requestId'] as int,
      );
      await expectLater(failedStart, throwsStateError);

      // Queued exploration flushes now that start failed and phase is still exploration.
      final exp2 = await relay.nextMessage();
      expect(exp2.message['type'], 'exploration');
      expect(exp2.message['state']['position']['x'], 2.0);
      relay.sendSnapshot(
        exp2.socket,
        kind: 'exploration',
        requestId: exp2.message['requestId'] as int,
        requesterId: 'host',
        phase: 'exploration',
        revision: 5,
        players: const ['host', 'guest'],
        state: state2,
      );
      await queuedPub;

      final retryStart = client.startEncounter(
        definitionId: 'enemy.brine_mite',
        seed: 12,
      );
      final battleStart2 = await relay.nextMessage();
      expect(battleStart2.message['type'], 'battleStart');
      relay.sendSnapshot(
        battleStart2.socket,
        kind: 'battleStarted',
        requestId: battleStart2.message['requestId'] as int,
        requesterId: 'host',
        phase: 'battle',
        revision: 6,
        players: const ['host', 'guest'],
        state: state2,
      );
      await retryStart;
      expect(client.snapshot?.phase, 'battle');
    },
  );
  test('superseded hello cannot change the new connection status', () async {
    final relay = await _RelayServer.start();
    final client = LanternLinkClient();
    addTearDown(() async {
      client.dispose();
      await relay.close();
    });
    final first = client.connect(endpoint: relay.endpoint, playerId: 'host');
    final firstRejected = expectLater(first, throwsStateError);
    await relay.nextMessage();
    final second = client.connect(endpoint: relay.endpoint, playerId: 'host');
    await firstRejected;
    final hello = await relay.nextMessage();
    expect(client.connecting, isTrue);
    expect(client.error, isNull);
    relay.sendSnapshot(
      hello.socket,
      kind: 'joined',
      requestId: hello.message['requestId'] as int,
      requesterId: 'host',
      phase: 'lobby',
      revision: 1,
    );
    await second;
    expect(client.connected, isTrue);
    client.disconnect();
    expect(client.error, isNull);
    expect(client.snapshot, isNull);
  });
}

final class _RelayServer {
  _RelayServer._(this._server);

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  final StreamController<({WebSocket socket, Map<String, dynamic> message})>
  _incoming = StreamController.broadcast();
  final List<({WebSocket socket, Map<String, dynamic> message})> _queue = [];
  Completer<({WebSocket socket, Map<String, dynamic> message})>? _waiter;

  String get endpoint =>
      'ws://${InternetAddress.loopbackIPv4.address}:${_server.port}/lantern-link';

  int get pendingCount => _queue.length;

  static Future<_RelayServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final relay = _RelayServer._(server);
    unawaited(server.forEach(relay._handleRequest));
    return relay;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final socket = await WebSocketTransformer.upgrade(request);
    _sockets.add(socket);
    socket.listen((dynamic raw) {
      final decoded = Map<String, dynamic>.from(
        jsonDecode(raw as String) as Map,
      );
      final item = (socket: socket, message: decoded);
      final waiter = _waiter;
      if (waiter != null && !waiter.isCompleted) {
        _waiter = null;
        waiter.complete(item);
      } else {
        _queue.add(item);
      }
      _incoming.add(item);
    });
  }

  Future<({WebSocket socket, Map<String, dynamic> message})> nextMessage() {
    if (_queue.isNotEmpty) {
      return Future.value(_queue.removeAt(0));
    }
    final completer =
        Completer<({WebSocket socket, Map<String, dynamic> message})>();
    _waiter = completer;
    return completer.future.timeout(const Duration(seconds: 3));
  }

  void sendSnapshot(
    WebSocket socket, {
    required String kind,
    required String phase,
    required int revision,
    int? requestId,
    String? requesterId,
    List<String> players = const ['host'],
    Map<String, List<String>> assignments = const {},
    GameState? state,
    LanternLinkDialogue? dialogue,
    String? encounterId,
    String? encounterDefinitionId,
    String? outcome,
  }) {
    final value = state ?? createContractFixture();
    socket.add(
      jsonEncode({
        'type': kind,
        'requestId': ?requestId,
        'requesterId': ?requesterId,
        'snapshot': {
          'room': 'relay-test',
          'phase': phase,
          'revision': revision,
          'hostId': players.isEmpty ? null : players.first,
          'players': players,
          'assignments': assignments,
          'state': _encodeState(value),
          if (dialogue != null)
            'dialogue': {
              'id': dialogue.id,
              'speaker': dialogue.speaker,
              'lines': dialogue.lines,
            },
          'encounterId': ?encounterId,
          'encounterDefinitionId': ?encounterDefinitionId,
          'outcome': ?outcome,
        },
      }),
    );
  }

  void sendError(
    WebSocket socket,
    String message, {
    int? requestId,
    String? requesterId,
  }) {
    socket.add(
      jsonEncode({
        'type': 'error',
        'message': message,
        'requestId': ?requestId,
        'requesterId': ?requesterId,
      }),
    );
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _incoming.close();
    await _server.close(force: true);
  }
}

Map<String, Object?> _encodeState(GameState state) => {
  'position': {
    'mapId': state.position.mapId,
    'x': state.position.x,
    'y': state.position.y,
  },
  'party': [
    for (final m in state.party)
      {
        'id': m.id,
        'jobId': m.jobId,
        'hp': m.hp,
        'maxHp': m.maxHp,
        'mp': m.mp,
        'maxMp': m.maxMp,
        'level': m.level,
        'experience': m.experience,
        'jobProgress': m.jobProgress,
        'equipment': m.equipment,
      },
  ],
  'inventory': state.inventory.quantities,
  'gold': state.gold,
  'quests': {
    'flags': state.quests.flags.toList(),
    'openedChestIds': state.quests.openedChestIds.toList(),
  },
};
