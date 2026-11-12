import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_4/core/fixtures/contract_fixture.dart';
import 'package:app_4/multiplayer/lantern_link_client.dart';
import 'package:app_4/ui/lantern_link_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'default 2-player lobby action configures mode before assigning heroes',
    (tester) async {
      final server = (await tester.runAsync(_DialogTestServer.start))!;
      final client = LanternLinkClient();
      addTearDown(() async {
        await tester.runAsync(() async {
          client.dispose();
          await server.close();
        });
      });

      await tester.runAsync(() async {
        await HttpOverrides.runWithHttpOverrides(() async {
          final connectFuture = client.connect(
            endpoint: server.endpoint,
            playerId: 'host',
          );
          final hello = await server.nextMessage();
          expect(hello.message['type'], 'hello');
          server.sendSnapshot(
            hello.socket,
            kind: 'joined',
            requestId: hello.message['requestId'] as int,
            requesterId: 'host',
            phase: 'lobby',
            revision: 1,
            players: const ['host', 'guest'],
          );
          await connectFuture;
        }, _PassthroughHttpOverrides());
      });

      await tester.pumpWidget(
        MaterialApp(home: LanternLinkDialog(client: client)),
      );
      await tester.pump();

      final buttonFinder = find.widgetWithText(
        FilledButton,
        'Assign heroes and begin exploration',
      );
      expect(buttonFinder, findsOneWidget);
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNotNull);

      await tester.runAsync(() => tester.tap(buttonFinder));
      await tester.pump();

      // While awaiting server ack, button is disabled.
      expect(tester.widget<FilledButton>(buttonFinder).onPressed, isNull);

      await tester.runAsync(() async {
        final configureMsg = await server.nextMessage();
        expect(configureMsg.message['type'], 'configure');
        expect(configureMsg.message['mode'], 'two');
        // assign must not be sent before configure is acknowledged.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(server.pendingCount, 0);

        server.sendSnapshot(
          configureMsg.socket,
          kind: 'configured',
          requestId: configureMsg.message['requestId'] as int,
          requesterId: 'host',
          phase: 'lobby',
          revision: 2,
          players: const ['host', 'guest'],
        );

        final assignMsg = await server.nextMessage();
        expect(assignMsg.message['type'], 'assign');
        server.sendSnapshot(
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
        final ready = Completer<void>();
        void changed() {
          if (client.snapshot?.phase == 'exploration' && !ready.isCompleted) {
            ready.complete();
          }
        }

        client.addListener(changed);
        try {
          changed();
          await ready.future.timeout(const Duration(seconds: 3));
        } finally {
          client.removeListener(changed);
        }
      });

      await tester.pumpAndSettle();
      expect(find.textContaining('exploration'), findsOneWidget);
      expect(find.text('Start shared training battle'), findsOneWidget);
    },
  );

  testWidgets('dialog shows gameOver status and hides start battle button', (
    tester,
  ) async {
    final server = (await tester.runAsync(_DialogTestServer.start))!;
    final client = LanternLinkClient();
    addTearDown(() async {
      await tester.runAsync(() async {
        client.dispose();
        await server.close();
      });
    });

    await tester.runAsync(() async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final connectFuture = client.connect(
          endpoint: server.endpoint,
          playerId: 'host',
        );
        final hello = await server.nextMessage();
        server.sendSnapshot(
          hello.socket,
          kind: 'battleFinished',
          requestId: hello.message['requestId'] as int,
          requesterId: 'host',
          phase: 'gameOver',
          revision: 5,
          players: const ['host', 'guest'],
          assignments: const {
            'host': ['fixture.hero.0', 'fixture.hero.1'],
            'guest': ['fixture.hero.2', 'fixture.hero.3'],
          },
          encounterId: 'lantern-link-1',
          encounterDefinitionId: 'enemy.brine_mite',
          outcome: 'defeat',
        );
        await connectFuture;
      }, _PassthroughHttpOverrides());
    });

    await tester.pumpWidget(
      MaterialApp(home: LanternLinkDialog(client: client)),
    );
    await tester.pump();

    expect(find.textContaining('gameOver'), findsOneWidget);
    expect(find.text('Game over: the party was defeated.'), findsOneWidget);
    expect(find.text('Start shared training battle'), findsNothing);
  });
}

final class _PassthroughHttpOverrides extends HttpOverrides {}

final class _DialogTestServer {
  _DialogTestServer._(this._server);

  final HttpServer _server;
  final List<WebSocket> _sockets = [];
  final List<({WebSocket socket, Map<String, dynamic> message})> _queue = [];
  Completer<({WebSocket socket, Map<String, dynamic> message})>? _waiter;

  String get endpoint =>
      'ws://${InternetAddress.loopbackIPv4.address}:${_server.port}/lantern-link';

  int get pendingCount => _queue.length;

  static Future<_DialogTestServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final testServer = _DialogTestServer._(server);
    unawaited(server.forEach(testServer._handleRequest));
    return testServer;
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
    required int requestId,
    required String requesterId,
    required String phase,
    required int revision,
    required List<String> players,
    Map<String, List<String>> assignments = const {},
    String? encounterId,
    String? encounterDefinitionId,
    String? outcome,
  }) {
    final state = createContractFixture();
    socket.add(
      jsonEncode({
        'type': kind,
        'requestId': requestId,
        'requesterId': requesterId,
        'snapshot': {
          'room': 'dialog-test',
          'phase': phase,
          'revision': revision,
          'hostId': players.first,
          'players': players,
          'assignments': assignments,
          'state': {
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
          },
          'encounterId': ?encounterId,
          'encounterDefinitionId': ?encounterDefinitionId,
          'outcome': ?outcome,
        },
      }),
    );
  }

  Future<void> close() async {
    for (final socket in _sockets) {
      await socket.close();
    }
    await _server.close(force: true);
  }
}
