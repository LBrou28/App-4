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
  bool _disposed = false;
  int _nextRequestId = 0;
  int _connectionEpoch = 0;
  final Map<int, Completer<LanternLinkClientSnapshot>> _pendingRequests = {};

  bool _sendingState = false;
  Future<void>? _inFlightExplorationFuture;
  GameState? _queuedExploration;
  LanternLinkDialogue? _queuedDialogue;
  Completer<void>? _queuedExplorationCompleter;

  Future<void>? _inFlightStart;
  bool _startingEncounter = false;
  bool _battleStartSent = false;

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
    if (_disposed) {
      throw StateError('LanternLinkClient was disposed');
    }
    final uri = Uri.parse(endpoint.trim());
    if (!uri.hasScheme || !['ws', 'wss'].contains(uri.scheme)) {
      throw ArgumentError('Enter a ws:// or wss:// server address');
    }
    final trimmedPlayerId = playerId.trim();
    if (trimmedPlayerId.isEmpty) {
      throw ArgumentError('Enter a player name');
    }
    disconnect();
    final epoch = _connectionEpoch;
    _connecting = true;
    _error = null;
    _notify();
    WebSocketChannel? channel;
    try {
      channel = WebSocketChannel.connect(uri);
      _channel = channel;
      _playerId = trimmedPlayerId;
      final activeChannel = channel;
      _messages = activeChannel.stream.listen(
        (dynamic raw) => _receive(activeChannel, raw),
        onError: (Object error) =>
            _handleChannelFailure(activeChannel, error.toString()),
        onDone: () => _handleChannelFailure(
          activeChannel,
          'Disconnected from Lantern Link',
        ),
      );
      unawaited(
        activeChannel.ready.then(
          (_) {},
          onError: (Object error) =>
              _handleChannelFailure(activeChannel, error.toString()),
        ),
      );
      await _sendRequest({'type': 'hello', 'playerId': _playerId});
    } catch (error) {
      if (_connectionEpoch == epoch) {
        if (_channel == channel && channel != null) {
          _teardownConnection(
            clearError: false,
            notify: true,
            failureMessage: error.toString(),
          );
        } else {
          _error = error.toString();
        }
      }
      rethrow;
    } finally {
      if (!_disposed && _connectionEpoch == epoch) {
        _connecting = false;
        _notify();
      }
    }
  }

  Future<void> configurePlayers(int count) =>
      _sendRequest({'type': 'configure', 'mode': count == 4 ? 'four' : 'two'})
          .then((_) {});

  /// Host convenience action: configures the requested mode, awaits server
  /// acknowledgement, then distributes the four authored heroes in the stable
  /// player order sent by the server.
  Future<void> assignEvenly({int? playerCount}) async {
    final epoch = _connectionEpoch;
    final initial = _snapshot;
    if (initial == null) {
      final error = StateError('Connect to a Lantern Link server first.');
      _error = error.message;
      _notify();
      throw error;
    }
    final targetCount = playerCount ?? initial.players.length;
    if ((targetCount != 2 && targetCount != 4) ||
        initial.players.length != targetCount ||
        initial.heroIds.length != 4) {
      final message =
          'Need exactly ${playerCount ?? '2 or 4'} connected players before assigning heroes.';
      _error = message;
      _notify();
      throw StateError(message);
    }
    await configurePlayers(targetCount);
    if (epoch != _connectionEpoch) throw StateError('Connection changed');
    final value = _snapshot;
    if (value == null ||
        value.players.length != targetCount ||
        value.heroIds.length != 4) {
      final message =
          'Need exactly $targetCount connected players before assigning heroes.';
      _error = message;
      _notify();
      throw StateError(message);
    }
    final players = value.players;
    final heroes = value.heroIds;
    final each = heroes.length ~/ players.length;
    await _sendRequest({
      'type': 'assign',
      'assignments': {
        for (var index = 0; index < players.length; index++)
          players[index]: heroes.sublist(index * each, (index + 1) * each),
      },
    });
  }

  Future<void> startEncounter({
    String definitionId = 'enemy.brine_mite',
    int? seed,
    GameState? state,
  }) async {
    final epoch = _connectionEpoch;
    while (_inFlightStart != null) {
      try {
        await _inFlightStart;
      } catch (_) {}
    }
    if (epoch != _connectionEpoch) throw StateError('Connection changed');
    if (_disposed) {
      throw StateError('LanternLinkClient was disposed');
    }
    final value = _snapshot;
    if (_channel == null) {
      final error = StateError('Connect to a Lantern Link server first.');
      _error = error.message;
      _notify();
      throw error;
    }
    if (!isHost || value?.phase != 'exploration') {
      final error = StateError('Lobby is not ready for a battle');
      _error = error.message;
      _notify();
      throw error;
    }
    final startFuture = _runStartEncounter(
      definitionId: definitionId,
      seed: seed,
      state: state,
    );
    _inFlightStart = startFuture;
    try {
      await startFuture;
    } finally {
      if (identical(_inFlightStart, startFuture)) {
        _inFlightStart = null;
      }
    }
  }

  Future<void> _runStartEncounter({
    required String definitionId,
    required int? seed,
    required GameState? state,
  }) async {
    final epoch = _connectionEpoch;
    _startingEncounter = true;
    try {
      if (state != null) {
        if (_inFlightExplorationFuture != null || _queuedExploration != null) {
          _queuedExploration = state;
          _queuedDialogue = null;
        } else {
          await _sendExploration(state);
        }
      }
      while (_inFlightExplorationFuture != null || _queuedExploration != null) {
        final inFlight = _inFlightExplorationFuture;
        if (inFlight != null) {
          await inFlight;
        }
        if (_queuedExploration != null && _inFlightExplorationFuture == null) {
          _pumpExploration();
        }
      }
      if (epoch != _connectionEpoch ||
          _disposed ||
          _channel == null ||
          !isHost ||
          _snapshot?.phase != 'exploration') {
        throw StateError('Lobby is not ready for a battle');
      }
      _battleStartSent = true;
      await _sendRequest({
        'type': 'battleStart',
        'definitionId': definitionId,
        'seed': seed ?? DateTime.now().microsecondsSinceEpoch,
      });
      if (epoch == _connectionEpoch) _clearQueuedExploration();
    } finally {
      if (epoch == _connectionEpoch) {
        _battleStartSent = false;
        _startingEncounter = false;
        if (!_disposed &&
            _channel != null &&
            isHost &&
            _snapshot?.phase == 'exploration' &&
            _queuedExploration != null &&
            _inFlightExplorationFuture == null) {
          _pumpExploration();
        }
      }
    }
  }

  Future<void> restart() async {
    final epoch = _connectionEpoch;
    await _sendRequest({'type': 'restart'});
    if (epoch == _connectionEpoch) _clearQueuedExploration();
  }

  Future<void> attack(String actorId, String targetId) =>
      _command({'actorId': actorId, 'action': 'attack', 'targetId': targetId});

  Future<void> defend(String actorId) =>
      _command({'actorId': actorId, 'action': 'defend'});

  Future<void> publishExploration(
    GameState state, {
    LanternLinkDialogue? dialogue,
  }) {
    final value = _snapshot;
    if (_disposed || !isHost || value?.phase != 'exploration') {
      return Future<void>.value();
    }
    if (_sendingState || _startingEncounter) {
      _queuedExploration = state;
      _queuedDialogue = dialogue;
      return (_queuedExplorationCompleter ??= Completer<void>()).future;
    }
    return _sendExploration(state, dialogue: dialogue);
  }

  Future<void> _sendExploration(
    GameState state, {
    LanternLinkDialogue? dialogue,
  }) {
    final value = _snapshot;
    if (_channel == null) {
      return Future<void>.error(
        StateError('Connect to a Lantern Link server first.'),
      );
    }
    if (_disposed || !isHost || value?.phase != 'exploration') {
      return Future<void>.value();
    }
    final sentRevision = value!.revision;
    final epoch = _connectionEpoch;
    _sendingState = true;
    late final Future<void> future;
    future =
        _sendRequest({
          'type': 'exploration',
          'revision': sentRevision,
          'state': _stateJson(state),
          if (dialogue != null)
            'dialogue': {
              'id': dialogue.id,
              'speaker': dialogue.speaker,
              'lines': dialogue.lines,
            },
        }).then(
          (_) {
            if (epoch != _connectionEpoch) return;
            _sendingState = false;
            if (identical(_inFlightExplorationFuture, future)) {
              _inFlightExplorationFuture = null;
            }
            if (!_battleStartSent) {
              _pumpExploration();
            }
          },
          onError: (Object error, StackTrace stack) {
            if (epoch != _connectionEpoch) {
              Error.throwWithStackTrace(error, stack);
            }
            _sendingState = false;
            if (identical(_inFlightExplorationFuture, future)) {
              _inFlightExplorationFuture = null;
            }
            if (_startingEncounter) {
              _clearQueuedExplorationWithError(error, stack);
            } else if (!_battleStartSent &&
                !_disposed &&
                _channel != null &&
                isHost &&
                _snapshot?.phase == 'exploration' &&
                _snapshot!.revision != sentRevision) {
              _pumpExploration();
            } else {
              _clearQueuedExplorationWithError(error, stack);
            }
            Error.throwWithStackTrace(error, stack);
          },
        );
    _inFlightExplorationFuture = future;
    return future;
  }

  void _pumpExploration() {
    if (_sendingState || _battleStartSent) return;
    final queued = _queuedExploration;
    if (queued == null) return;
    final queuedDialogue = _queuedDialogue;
    final queuedCompleter = _queuedExplorationCompleter;
    _queuedExploration = null;
    _queuedDialogue = null;
    _queuedExplorationCompleter = null;
    if (_disposed ||
        _channel == null ||
        !isHost ||
        _snapshot?.phase != 'exploration') {
      if (queuedCompleter != null && !queuedCompleter.isCompleted) {
        queuedCompleter.complete();
      }
      return;
    }
    final future = _sendExploration(queued, dialogue: queuedDialogue);
    if (queuedCompleter != null) {
      future.then(
        (_) {
          if (!queuedCompleter.isCompleted) queuedCompleter.complete();
        },
        onError: (Object error, StackTrace stack) {
          if (!queuedCompleter.isCompleted) {
            queuedCompleter.completeError(error, stack);
          }
        },
      );
    }
  }

  void _clearQueuedExploration() {
    _queuedExploration = null;
    _queuedDialogue = null;
    final queuedCompleter = _queuedExplorationCompleter;
    _queuedExplorationCompleter = null;
    if (queuedCompleter != null && !queuedCompleter.isCompleted) {
      queuedCompleter.complete();
    }
  }

  void _clearQueuedExplorationWithError(Object error, StackTrace stack) {
    _queuedExploration = null;
    _queuedDialogue = null;
    final queuedCompleter = _queuedExplorationCompleter;
    _queuedExplorationCompleter = null;
    if (queuedCompleter != null && !queuedCompleter.isCompleted) {
      queuedCompleter.completeError(error, stack);
    }
  }

  Future<void> _command(Map<String, Object?> command) {
    final value = _snapshot;
    if (value?.battle == null) return Future<void>.value();
    return _sendRequest({
      'type': 'command',
      'round': value!.battle!['round'],
      'command': command,
    }).then((_) {});
  }

  void _receive(WebSocketChannel channel, dynamic raw) {
    if (_disposed || _channel != channel) return;
    try {
      final message = Map<String, dynamic>.from(
        jsonDecode(raw as String) as Map,
      );
      if (message['type'] == 'error') {
        final errorMessage =
            message['message'] as String? ??
            'Lantern Link rejected that request.';
        _error = errorMessage;
        final requestId = message['requestId'];
        final requesterId = message['requesterId'] as String?;
        if (requestId is int &&
            (requesterId == null || requesterId == _playerId)) {
          final pending = _pendingRequests.remove(requestId);
          if (pending != null && !pending.isCompleted) {
            pending.completeError(StateError(errorMessage));
          }
        }
      } else if (message['snapshot'] is Map) {
        final nextSnapshot = LanternLinkClientSnapshot.fromJson(
          Map<String, dynamic>.from(message['snapshot'] as Map),
        );
        _snapshot = nextSnapshot;
        _error = null;
        final requestId = message['requestId'];
        final requesterId = message['requesterId'] as String?;
        if (requestId is int && requesterId == _playerId) {
          final pending = _pendingRequests.remove(requestId);
          if (pending != null && !pending.isCompleted) {
            pending.complete(nextSnapshot);
          }
        }
      }
    } catch (_) {
      _error = 'Received an unreadable server message.';
    }
    _notify();
  }

  Future<LanternLinkClientSnapshot> _sendRequest(Map<String, Object?> message) {
    if (_disposed) {
      return Future<LanternLinkClientSnapshot>.error(
        StateError('LanternLinkClient was disposed'),
      );
    }
    final channel = _channel;
    if (channel == null) {
      final error = StateError('Connect to a Lantern Link server first.');
      _error = error.message;
      _notify();
      return Future<LanternLinkClientSnapshot>.error(error);
    }
    final requestId = ++_nextRequestId;
    final completer = Completer<LanternLinkClientSnapshot>();
    _pendingRequests[requestId] = completer;
    try {
      channel.sink.add(jsonEncode({...message, 'requestId': requestId}));
    } catch (error) {
      _handleChannelFailure(channel, error.toString());
    }
    return completer.future;
  }

  void _handleChannelFailure(WebSocketChannel channel, String message) {
    if (_disposed || _channel != channel) return;
    _teardownConnection(
      clearError: false,
      notify: true,
      failureMessage: message,
    );
  }

  void _teardownConnection({
    required bool clearError,
    required bool notify,
    String failureMessage = 'Disconnected from Lantern Link',
  }) {
    _connectionEpoch++;
    final messages = _messages;
    final channel = _channel;
    _messages = null;
    _channel = null;
    _snapshot = null;
    _playerId = null;
    _connecting = false;
    _sendingState = false;
    _inFlightExplorationFuture = null;
    _startingEncounter = false;
    _battleStartSent = false;
    _inFlightStart = null;
    _error = clearError ? null : failureMessage;

    final failure = StateError(failureMessage);
    _clearQueuedExplorationWithError(failure, StackTrace.current);
    for (final request in _pendingRequests.values) {
      if (!request.isCompleted) request.completeError(failure);
    }
    _pendingRequests.clear();

    if (messages != null) unawaited(messages.cancel());
    if (channel != null) unawaited(channel.sink.close());
    if (notify) _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void disconnect() {
    final hadConnection =
        _channel != null ||
        _messages != null ||
        _snapshot != null ||
        _connecting ||
        _pendingRequests.isNotEmpty ||
        _queuedExploration != null;
    _teardownConnection(
      clearError: true,
      notify: hadConnection && !_disposed,
      failureMessage: 'Disconnected from Lantern Link',
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _teardownConnection(
      clearError: true,
      notify: false,
      failureMessage: 'LanternLinkClient was disposed',
    );
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
    this.encounterId,
    this.encounterDefinitionId,
    this.outcome,
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
        encounterId: json['encounterId'] as String?,
        encounterDefinitionId: json['encounterDefinitionId'] as String?,
        outcome: json['outcome'] as String?,
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
  final String? encounterId;
  final String? encounterDefinitionId;
  final String? outcome;

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
