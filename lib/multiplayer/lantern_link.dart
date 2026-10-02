import '../battle/battle.dart' hide BattleOutcome;
import '../battle/battle_session.dart';
import '../core/contracts.dart';

/// The server owns one room. The Flutter client only renders [snapshot] and
/// submits requests; it never resolves a combat round locally.
enum LanternLinkMode { twoPlayers, fourPlayers }

enum LanternLinkPhase { lobby, exploration, battle, paused }

typedef BattleSessionFactory = BattleSession Function(BattleInput input);

final class LanternLinkSnapshot {
  LanternLinkSnapshot({
    required this.room,
    required this.phase,
    required this.revision,
    required this.hostId,
    required List<String> players,
    required Map<String, List<String>> assignments,
    required this.state,
    this.dialogue,
    this.battle,
  }) : players = List<String>.unmodifiable(players),
       assignments = Map<String, List<String>>.unmodifiable({
         for (final entry in assignments.entries)
           entry.key: List<String>.unmodifiable(entry.value),
       });

  final String room;
  final LanternLinkPhase phase;
  final int revision;
  final String? hostId;
  final List<String> players;
  final Map<String, List<String>> assignments;
  final GameState state;
  final LanternLinkDialogue? dialogue;
  final BattleSnapshot? battle;
}

/// A host-authored dialogue payload. The room relays this presentation data but
/// never resolves completion, quest flags, or rewards.
final class LanternLinkDialogue {
  LanternLinkDialogue({
    required this.id,
    required this.speaker,
    required List<String> lines,
  }) : lines = List.unmodifiable(lines) {
    requireId(id, 'dialogue id');
    if (speaker.trim().isEmpty ||
        lines.isEmpty ||
        lines.any((line) => line.trim().isEmpty)) {
      throw ArgumentError('Dialogue needs a speaker and nonempty lines');
    }
  }

  final String id;
  final String speaker;
  final List<String> lines;
}

/// A successful server action. Network adapters broadcast this snapshot to all
/// connected clients, including the sender.
final class LanternLinkEvent {
  const LanternLinkEvent(this.kind, this.snapshot);
  final String kind;
  final LanternLinkSnapshot snapshot;
}

/// Authoritative local-network room. It deliberately has no sockets or Flutter
/// imports so its state machine can be tested on the Dart VM.
final class LanternLinkRoom {
  LanternLinkRoom({
    required this.name,
    required GameState initialState,
    required this.createBattle,
  }) : _state = initialState {
    requireId(name, 'room name');
  }

  final String name;
  final BattleSessionFactory createBattle;
  final List<String> _players = [];
  final Map<String, List<String>> _assignments = {};
  GameState _state;
  LanternLinkMode? _mode;
  LanternLinkPhase _phase = LanternLinkPhase.lobby;
  BattleSession? _session;
  final Map<String, HeroCommand> _lockedCommands = {};
  int _revision = 0;
  int _encounterSequence = 0;
  String? _hostId;
  LanternLinkDialogue? _dialogue;

  LanternLinkSnapshot get snapshot => LanternLinkSnapshot(
    room: name,
    phase: _phase,
    revision: _revision,
    hostId: _hostId,
    players: _players,
    assignments: _assignments,
    state: _state,
    dialogue: _dialogue,
    battle: _session?.snapshot,
  );

  LanternLinkEvent join(String playerId) {
    requireId(playerId, 'player ID');
    if (_players.contains(playerId)) return _event('reconnected');
    final capacity = _mode == LanternLinkMode.twoPlayers ? 2 : 4;
    if (_players.length >= capacity) throw StateError('Room is full');
    _players.add(playerId);
    _hostId ??= playerId;
    if (_phase == LanternLinkPhase.paused && _allAssignedPlayersPresent) {
      _phase = _session == null
          ? LanternLinkPhase.exploration
          : LanternLinkPhase.battle;
    }
    return _commit('joined');
  }

  LanternLinkEvent leave(String playerId) {
    if (!_players.remove(playerId)) return _event('left');
    if (playerId == _hostId) _hostId = _players.isEmpty ? null : _players.first;
    // Keep assignments for a reconnect, but stop a round immediately. This is
    // the explicit safe fallback promised by T3.
    if (_phase == LanternLinkPhase.battle ||
        _phase == LanternLinkPhase.exploration) {
      _phase = LanternLinkPhase.paused;
    }
    return _commit('playerDisconnected');
  }

  LanternLinkEvent configure(String playerId, LanternLinkMode mode) {
    _requireHost(playerId);
    if (_phase != LanternLinkPhase.lobby) throw StateError('Lobby is closed');
    if (_players.length > _capacity(mode)) {
      throw StateError('Too many connected players for this mode');
    }
    _mode = mode;
    _assignments.clear();
    return _commit('configured');
  }

  LanternLinkEvent assign(
    String playerId,
    Map<String, List<String>> assignments,
  ) {
    _requireHost(playerId);
    if (_phase != LanternLinkPhase.lobby || _mode == null) {
      throw StateError('Configure the lobby before assigning heroes');
    }
    _validateAssignments(assignments);
    _assignments
      ..clear()
      ..addAll({
        for (final entry in assignments.entries)
          entry.key: List.of(entry.value),
      });
    _phase = LanternLinkPhase.exploration;
    return _commit('ready');
  }

  /// Only the elected host can publish an exploration snapshot. This keeps
  /// remote clients read-only during exploration while the host app remains the
  /// map/collision authority owned by B.
  LanternLinkEvent publishExploration(
    String playerId,
    GameState state, {
    required int expectedRevision,
    LanternLinkDialogue? dialogue,
  }) {
    _requireHost(playerId);
    if (_phase != LanternLinkPhase.exploration ||
        expectedRevision != _revision) {
      throw StateError('Stale or unavailable exploration update');
    }
    _state = state;
    _dialogue = dialogue;
    return _commit('exploration');
  }

  LanternLinkEvent beginBattle(
    String playerId, {
    required String definitionId,
    required int seed,
  }) {
    _requireHost(playerId);
    if (_phase != LanternLinkPhase.exploration || !_ready) {
      throw StateError('Lobby is not ready for a battle');
    }
    _session = createBattle(
      BattleInput(
        encounterId: 'lantern-link-${++_encounterSequence}',
        baseRevision: _revision,
        request: EncounterRequest(definitionId: definitionId),
        state: _state,
        seed: seed,
      ),
    );
    _lockedCommands.clear();
    _phase = LanternLinkPhase.battle;
    return _commit('battleStarted');
  }

  LanternLinkEvent submitCommand(
    String playerId, {
    required int round,
    required HeroCommand command,
  }) {
    final session = _session;
    if (_phase != LanternLinkPhase.battle ||
        session == null ||
        round != session.snapshot.round) {
      throw StateError('Stale or unavailable battle round');
    }
    if (!_players.contains(playerId) ||
        !(_assignments[playerId] ?? const []).contains(command.actorId)) {
      throw StateError('That player does not control ${command.actorId}');
    }
    final actor = session.snapshot.combatants
        .where((c) => c.id == command.actorId)
        .firstOrNull;
    if (actor == null || !actor.isAlive) throw StateError('Hero cannot act');
    if (_lockedCommands.containsKey(command.actorId)) {
      throw StateError('Hero command is already locked for this round');
    }
    _lockedCommands[command.actorId] = command;
    final livingHeroes = session.snapshot.combatants
        .where((c) => c.side == BattleSide.heroes && c.isAlive)
        .map((c) => c.id)
        .toSet();
    if (!_lockedCommands.keys.toSet().containsAll(livingHeroes)) {
      return _commit('commandLocked');
    }
    session.resolve(round, _lockedCommands.values.toList());
    _lockedCommands.clear();
    return _finishOrAdvance('roundResolved');
  }

  Future<LanternLinkEvent> flee(String playerId, {required int round}) async {
    final session = _session;
    if (_phase != LanternLinkPhase.battle ||
        session == null ||
        round != session.snapshot.round) {
      throw StateError('Stale or unavailable battle round');
    }
    if (!_players.contains(playerId) ||
        (_assignments[playerId] ?? const []).isEmpty) {
      throw StateError('Only an assigned player can flee');
    }
    if (!await session.flee()) {
      throw StateError('Escape was unavailable or failed');
    }
    _lockedCommands.clear();
    return _finishOrAdvance('fled');
  }

  LanternLinkEvent _finishOrAdvance(String event) {
    final session = _session!;
    final result = session.result;
    if (result == null) {
      return _commit(event);
    }
    _state = GameState(
      position: _state.position,
      party: result.party,
      inventory: result.inventory,
      gold: result.gold,
      quests: _state.quests,
    );
    _session = null;
    _phase = result.outcome == BattleOutcome.defeat
        ? LanternLinkPhase.paused
        : LanternLinkPhase.exploration;
    return _commit('battleFinished');
  }

  LanternLinkEvent _event(String kind) => LanternLinkEvent(kind, snapshot);
  LanternLinkEvent _commit(String kind) {
    _revision++;
    return _event(kind);
  }

  int _capacity(LanternLinkMode mode) =>
      mode == LanternLinkMode.twoPlayers ? 2 : 4;
  bool get _allAssignedPlayersPresent =>
      _assignments.keys.every(_players.contains);
  bool get _ready =>
      _mode != null &&
      _players.length == _capacity(_mode!) &&
      _assignments.length == _players.length &&
      _allAssignedPlayersPresent;

  void _requireHost(String playerId) {
    if (playerId != _hostId) throw StateError('Only the host can do that');
  }

  void _validateAssignments(Map<String, List<String>> assignments) {
    if (_mode == null || assignments.length != _capacity(_mode!)) {
      throw ArgumentError('Assignments must include every player');
    }
    if (!assignments.keys.toSet().containsAll(_players) ||
        assignments.keys.any((id) => !_players.contains(id))) {
      throw ArgumentError('Assignments must match connected players');
    }
    final heroes = _state.party.map((member) => member.id).toSet();
    final assigned = assignments.values.expand((ids) => ids).toList();
    final expectedEach = _mode == LanternLinkMode.twoPlayers ? 2 : 1;
    if (assignments.values.any((ids) => ids.length != expectedEach) ||
        assigned.length != heroes.length ||
        assigned.toSet().length != heroes.length ||
        !assigned.toSet().containsAll(heroes)) {
      throw ArgumentError('Each hero must have exactly one valid owner');
    }
  }
}
