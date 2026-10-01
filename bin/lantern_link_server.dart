import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:app_4/app/integration_preview.dart'
    show createLanternInitialState;
import 'package:app_4/battle/battle.dart';
import 'package:app_4/battle/lantern_balance.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/multiplayer/lantern_link.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/interaction_world.dart';

/// Start with: dart run bin/lantern_link_server.dart --room bellwether
///
/// The service intentionally binds all interfaces for a local network demo.
/// Only run it on a trusted LAN; it is a classroom game server, not an
/// internet-facing authenticated service.
Future<void> main(List<String> args) async {
  final roomName = _argument(args, '--room') ?? 'bellwether';
  final port = int.tryParse(_argument(args, '--port') ?? '') ?? 8088;
  final content = DemoContent.decode(
    await File('assets/data/lantern_wake.json').readAsString(),
  );
  final world = InteractionWorld(content);
  final state = createLanternInitialState(
    content,
    world.maps['map.bellwether']!.spawns['entry']!,
    progression: LanternBalance().progression,
  );
  final server = LanternLinkServer(
    LanternLinkRoom(
      name: roomName,
      initialState: state,
      createBattle: LanternBalance().createSession,
    ),
  );
  final bound = await server.start(port: port);
  stdout.writeln(
    'Lantern Link room "$roomName" listening at ws://${bound.address.address}:${bound.port}/lantern-link',
  );
}

String? _argument(List<String> args, String name) {
  final index = args.indexOf(name);
  return index >= 0 && index + 1 < args.length ? args[index + 1] : null;
}

/// Thin WebSocket transport. All authorization and round-state validation live
/// in [LanternLinkRoom], so the exact same rules are covered by VM tests.
final class LanternLinkServer {
  LanternLinkServer(this.room);
  final LanternLinkRoom room;
  final Map<WebSocket, String> _players = {};
  HttpServer? _server;

  Future<HttpServer> start({int port = 8088}) async {
    final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server = server;
    unawaited(server.forEach(_handleRequest));
    return server;
  }

  Future<void> close() => _server?.close(force: true) ?? Future.value();

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path != '/lantern-link' ||
        !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.notFound
        ..write('Use WebSocket endpoint /lantern-link')
        ..close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen(
      (dynamic raw) => _handleMessage(socket, raw),
      onDone: () => _disconnect(socket),
      onError: (_) => _disconnect(socket),
      cancelOnError: true,
    );
  }

  Future<void> _handleMessage(WebSocket socket, dynamic raw) async {
    try {
      final message = jsonDecode(raw as String);
      if (message is! Map) throw ArgumentError('Expected a JSON object');
      final json = Map<String, dynamic>.from(message);
      final type = json['type'] as String?;
      LanternLinkEvent event;
      if (type == 'hello') {
        final playerId = json['playerId'] as String?;
        if (playerId == null) throw ArgumentError('playerId is required');
        final previous = _players.entries
            .where((entry) => entry.value == playerId)
            .toList();
        for (final entry in previous) {
          entry.key.close(
            WebSocketStatus.normalClosure,
            'Reconnected elsewhere',
          );
          _players.remove(entry.key);
        }
        event = room.join(playerId);
        _players[socket] = playerId;
      } else {
        final playerId = _players[socket];
        if (playerId == null) throw StateError('Send hello first');
        event = await _dispatch(playerId, type, json);
      }
      _broadcast(event);
    } catch (error) {
      _send(socket, {'type': 'error', 'message': error.toString()});
    }
  }

  Future<LanternLinkEvent> _dispatch(
    String playerId,
    String? type,
    Map<String, dynamic> json,
  ) async {
    switch (type) {
      case 'configure':
        return room.configure(
          playerId,
          json['mode'] == 'four'
              ? LanternLinkMode.fourPlayers
              : LanternLinkMode.twoPlayers,
        );
      case 'assign':
        final raw = Map<String, dynamic>.from(json['assignments'] as Map);
        return room.assign(playerId, {
          for (final entry in raw.entries)
            entry.key: List<String>.from(entry.value as List),
        });
      case 'exploration':
        return room.publishExploration(
          playerId,
          _state(Map<String, dynamic>.from(json['state'] as Map)),
          expectedRevision: json['revision'] as int,
        );
      case 'battleStart':
        return room.beginBattle(
          playerId,
          definitionId: json['definitionId'] as String,
          seed: json['seed'] as int,
        );
      case 'command':
        return room.submitCommand(
          playerId,
          round: json['round'] as int,
          command: _command(Map<String, dynamic>.from(json['command'] as Map)),
        );
      case 'flee':
        return room.flee(playerId, round: json['round'] as int);
      default:
        throw ArgumentError('Unknown message type: $type');
    }
  }

  void _disconnect(WebSocket socket) {
    final playerId = _players.remove(socket);
    if (playerId != null) _broadcast(room.leave(playerId));
  }

  void _broadcast(LanternLinkEvent event) {
    final payload = {'type': event.kind, 'snapshot': _snapshot(event.snapshot)};
    for (final socket in _players.keys.toList()) {
      _send(socket, payload);
    }
  }

  void _send(WebSocket socket, Map<String, Object?> message) {
    if (socket.readyState == WebSocket.open) socket.add(jsonEncode(message));
  }
}

HeroCommand _command(Map<String, dynamic> json) {
  final actor = json['actorId'] as String;
  final target = json['targetId'] as String?;
  final effect = json['effectId'] as String?;
  return switch (json['action'] as String) {
    'attack' => HeroCommand.attack(actor, target!),
    'defend' => HeroCommand.defend(actor),
    'spell' => HeroCommand.spell(actor, effect!, target!),
    'item' => HeroCommand.item(actor, effect!, target!),
    _ => throw ArgumentError('Unknown battle action'),
  };
}

Map<String, Object?> _snapshot(LanternLinkSnapshot value) => {
  'room': value.room,
  'phase': value.phase.name,
  'revision': value.revision,
  'hostId': value.hostId,
  'players': value.players,
  'assignments': value.assignments,
  'state': _stateJson(value.state),
  if (value.battle != null)
    'battle': {
      'round': value.battle!.round,
      'outcome': value.battle!.outcome.name,
      'inventory': value.battle!.inventory,
      'combatants': [
        for (final c in value.battle!.combatants)
          {
            'id': c.id,
            'side': c.side.name,
            'hp': c.hp,
            'maxHp': c.maxHp,
            'mp': c.mp,
            'maxMp': c.maxMp,
          },
      ],
    },
};

Map<String, Object?> _stateJson(GameState state) => {
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

GameState _state(Map<String, dynamic> json) {
  final position = Map<String, dynamic>.from(json['position'] as Map);
  return GameState(
    position: WorldPosition(
      mapId: position['mapId'] as String,
      x: (position['x'] as num).toDouble(),
      y: (position['y'] as num).toDouble(),
    ),
    party: [
      for (final raw in json['party'] as List)
        () {
          final m = Map<String, dynamic>.from(raw as Map);
          return PartyMember(
            id: m['id'] as String,
            jobId: m['jobId'] as String,
            hp: m['hp'] as int,
            maxHp: m['maxHp'] as int,
            mp: m['mp'] as int,
            maxMp: m['maxMp'] as int,
            level: m['level'] as int,
            experience: m['experience'] as int,
            jobProgress: Map<String, int>.from(m['jobProgress'] as Map),
            equipment: Map<String, String>.from(m['equipment'] as Map),
          );
        }(),
    ],
    inventory: Inventory(Map<String, int>.from(json['inventory'] as Map)),
    gold: json['gold'] as int,
    quests: QuestFlags(
      flags: Set<String>.from(json['quests']['flags'] as List),
      openedChestIds: Set<String>.from(
        json['quests']['openedChestIds'] as List,
      ),
    ),
  );
}
