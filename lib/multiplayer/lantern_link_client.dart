import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/contracts.dart';
import 'lantern_link.dart';

/// Browser/desktop client for the T3 WebSocket protocol. It renders server
/// snapshots and never resolves lobby or combat state locally.
final class LanternLinkClient extends ChangeNotifier {
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _messages;
  LanternLinkClientSnapshot? _snapshot;
  String? _playerId;
  String? _error;
  bool _connecting = false;
  bool _sendingState = false;
  GameState? _queuedExploration;
  LanternLinkDialogue? _queuedDialogue;

  LanternLinkClientSnapshot? get snapshot => _snapshot;
  String? get playerId => _playerId;
  String? get error => _error;
  bool get connecting => _connecting;
  bool get connected => _channel != null && _snapshot != null;
  bool get isHost => _snapshot?.hostId == _playerId;

  Future<void> connect({
    required String endpoint,
    required String playerId,
  }) async {
    disconnect();
    final uri = Uri.parse(endpoint.trim());
    if (!uri.hasScheme || !['ws', 'wss'].contains(uri.scheme)) {
      throw ArgumentError('Enter a ws:// or wss:// server address');
    }
    if (playerId.trim().isEmpty) throw ArgumentError('Enter a player name');
    _connecting = true;
    _error = null;
    notifyListeners();
    try {
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _playerId = playerId.trim();
      _messages = channel.stream.listen(
        _receive,
        onError: (Object error) => _failed(error.toString()),
        onDone: () {
          if (_channel == channel) _failed('Disconnected from Lantern Link');
        },
      );
      _send({'type': 'hello', 'playerId': _playerId});
    } catch (error) {
      _failed(error.toString());
      rethrow;
    } finally {
      _connecting = false;
      notifyListeners();
    }
  }

  void configurePlayers(int count) =>
      _send({'type': 'configure', 'mode': count == 4 ? 'four' : 'two'});

  /// Host convenience action: distributes the four authored heroes in the
  /// stable player order sent by the server.
  void assignEvenly() {
    final value = _snapshot;
    if (value == null) return;
    final players = value.players;
    final heroes = value.heroIds;
    if ((players.length != 2 && players.length != 4) || heroes.length != 4) {
      _failed('Need exactly 2 or 4 connected players before assigning heroes.');
      return;
    }
    final each = heroes.length ~/ players.length;
    _send({
      'type': 'assign',
      'assignments': {
        for (var index = 0; index < players.length; index++)
          players[index]: heroes.sublist(index * each, (index + 1) * each),
      },
    });
  }

  void startEncounter({
    String definitionId = 'enemy.brine_mite',
    int? seed,
  }) => _send({
    'type': 'battleStart',
    'definitionId': definitionId,
    'seed': seed ?? DateTime.now().microsecondsSinceEpoch,
  });

  void attack(String actorId, String targetId) =>
      _command({'actorId': actorId, 'action': 'attack', 'targetId': targetId});

  void defend(String actorId) =>
      _command({'actorId': actorId, 'action': 'defend'});

  void publishExploration(GameState state, {LanternLinkDialogue? dialogue}) {
    final value = _snapshot;
    if (!isHost || value?.phase != 'exploration') return;
    if (_sendingState) {
      _queuedExploration = state;
      _queuedDialogue = dialogue;
      return;
    }
    _sendingState = true;
    _send({
      'type': 'exploration',
      'revision': value!.revision,
      'state': _stateJson(state),
      if (dialogue != null)
        'dialogue': {
          'id': dialogue.id,
          'speaker': dialogue.speaker,
          'lines': dialogue.lines,
        },
    });
  }

  void _command(Map<String, Object?> command) {
    final value = _snapshot;
    if (value?.battle == null) return;
    _send({
      'type': 'command',
      'round': value!.battle!['round'],
      'command': command,
    });
  }

  void _receive(dynamic raw) {
    try {
      final message = Map<String, dynamic>.from(
        jsonDecode(raw as String) as Map,
      );
      if (message['type'] == 'error') {
        _error =
            message['message'] as String? ??
            'Lantern Link rejected that request.';
      } else if (message['snapshot'] is Map) {
        _snapshot = LanternLinkClientSnapshot.fromJson(
          Map<String, dynamic>.from(message['snapshot'] as Map),
        );
        _error = null;
        _sendingState = false;
        final queued = _queuedExploration;
        final queuedDialogue = _queuedDialogue;
        _queuedExploration = null;
        _queuedDialogue = null;
        if (queued != null)
          publishExploration(queued, dialogue: queuedDialogue);
      }
    } catch (_) {
      _error = 'Received an unreadable server message.';
    }
    notifyListeners();
  }

  void _send(Map<String, Object?> message) {
    final channel = _channel;
    if (channel == null) {
      _failed('Connect to a Lantern Link server first.');
      return;
    }
    channel.sink.add(jsonEncode(message));
  }

  void _failed(String message) {
    _error = message;
    _sendingState = false;
    _queuedExploration = null;
    _queuedDialogue = null;
    notifyListeners();
  }

  void disconnect() {
    _messages?.cancel();
    _messages = null;
    _channel?.sink.close();
    _channel = null;
    _snapshot = null;
    _playerId = null;
    _sendingState = false;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}

final class LanternLinkClientSnapshot {
  LanternLinkClientSnapshot({
    required this.room,
    required this.phase,
    required this.revision,
    required this.hostId,
    required this.players,
    required this.assignments,
    required this.state,
    this.dialogue,
    this.battle,
  });

  factory LanternLinkClientSnapshot.fromJson(Map<String, dynamic> json) =>
      LanternLinkClientSnapshot(
        room: json['room'] as String,
        phase: json['phase'] as String,
        revision: json['revision'] as int,
        hostId: json['hostId'] as String?,
        players: List<String>.from(json['players'] as List),
        assignments: {
          for (final entry in Map<String, dynamic>.from(
            json['assignments'] as Map,
          ).entries)
            entry.key: List<String>.from(entry.value as List),
        },
        state: Map<String, dynamic>.from(json['state'] as Map),
        dialogue: json['dialogue'] == null
            ? null
            : LanternLinkDialogue(
                id: (json['dialogue'] as Map)['id'] as String,
                speaker: (json['dialogue'] as Map)['speaker'] as String,
                lines: List<String>.from(
                  (json['dialogue'] as Map)['lines'] as List,
                ),
              ),
        battle: json['battle'] == null
            ? null
            : Map<String, dynamic>.from(json['battle'] as Map),
      );

  final String room;
  final String phase;
  final int revision;
  final String? hostId;
  final List<String> players;
  final Map<String, List<String>> assignments;
  final Map<String, dynamic> state;
  final LanternLinkDialogue? dialogue;
  final Map<String, dynamic>? battle;

  /// Converts the server's authoritative exploration payload back into the
  /// shared immutable state model. UI code must never invent guest state.
  GameState get gameState => decodeLanternLinkState(state);

  List<String> get heroIds => [
    for (final value in state['party'] as List)
      Map<String, dynamic>.from(value as Map)['id'] as String,
  ];

  List<String> get ownedHeroes => assignments.entries
      .where((entry) => entry.key.isNotEmpty)
      .expand((entry) => entry.value)
      .toList();
}

GameState decodeLanternLinkState(Map<String, dynamic> json) {
  final position = Map<String, dynamic>.from(json['position'] as Map);
  final quests = Map<String, dynamic>.from(json['quests'] as Map);
  return GameState(
    position: WorldPosition(
      mapId: position['mapId'] as String,
      x: (position['x'] as num).toDouble(),
      y: (position['y'] as num).toDouble(),
    ),
    party: [
      for (final value in json['party'] as List)
        _memberFromJson(Map<String, dynamic>.from(value as Map)),
    ],
    inventory: Inventory(Map<String, int>.from(json['inventory'] as Map)),
    gold: json['gold'] as int,
    quests: QuestFlags(
      flags: Set<String>.from(quests['flags'] as List),
      openedChestIds: Set<String>.from(quests['openedChestIds'] as List),
    ),
  );
}

PartyMember _memberFromJson(Map<String, dynamic> json) => PartyMember(
  id: json['id'] as String,
  jobId: json['jobId'] as String,
  hp: json['hp'] as int,
  maxHp: json['maxHp'] as int,
  mp: json['mp'] as int,
  maxMp: json['maxMp'] as int,
  level: json['level'] as int,
  experience: json['experience'] as int,
  jobProgress: Map<String, int>.from(json['jobProgress'] as Map),
  equipment: Map<String, String>.from(json['equipment'] as Map),
);

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
