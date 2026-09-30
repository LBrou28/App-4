import 'package:flutter/foundation.dart';

import '../core/contracts.dart';
import '../core/fixtures/contract_fixture.dart';
import 'world_operations.dart';

/// Loaded world plus B's full-footprint validation. No combat/content rules.
final class WorldSession {
  WorldSession({
    required this.map,
    required this.initialState,
    required this.isClear,
    WorldOperations? operations,
  }) : operations = operations ?? WorldOperations();
  final WorldOperations operations;
  final MapDefinition map;
  final GameState initialState;
  final bool Function(WorldPosition) isClear;
}

typedef WorldLoader = Future<WorldSession> Function();

/// A2 exploration slice. Battle acceptance stays disabled until its contract is agreed.
class AppController extends ChangeNotifier implements WorldInteractionHost {
  AppController({required this.loadWorld});
  final WorldLoader loadWorld;
  GameState _state = createContractFixture();
  WorldSession? _session;
  WorldArea? _area;
  ActiveDialogue? _dialogue;
  int _dialogueSequence = 0;
  bool _checking = false;
  ActiveDialogue? get activeDialogue => _dialogue;
  AppMode _mode = AppMode.title;
  int _revision = 0;
  int _loadGeneration = 0;
  bool _paused = false;
  bool _disposed = false;
  bool _notifying = false;
  String? _error;

  @override
  GameState get state => _state;
  @override
  int get revision => _revision;
  AppMode get mode => _mode;
  bool get paused => _paused;
  String? get error => _error;
  MapDefinition? get map => _area?.map;
  @override
  bool get movementEnabled =>
      !_disposed && _mode == AppMode.exploration && !_paused;
  bool get _canWrite => !_disposed && !_notifying && !_checking;

  void _publish() {
    _revision++;
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
    }
  }

  Future<void> newGame() async {
    if (!_canWrite || _mode == AppMode.loading) return;
    final generation = ++_loadGeneration;
    _dialogue = null;
    _mode = AppMode.loading;
    _paused = false;
    _error = null;
    _publish();
    try {
      final loaded = await loadWorld();
      if (_disposed || generation != _loadGeneration) return;
      if (loaded.initialState.position.mapId != loaded.map.id ||
          !_check(() => loaded.isClear(loaded.initialState.position))) {
        throw StateError('Invalid world spawn');
      }
      _session = loaded;
      _area = WorldArea(map: loaded.map, isClear: loaded.isClear);
      _state = loaded.initialState;
      _mode = AppMode.exploration;
      _publish();
    } catch (_) {
      if (_disposed || generation != _loadGeneration) return;
      _mode = AppMode.error;
      _error = 'The practice world could not be loaded. Please try again.';
      _publish();
    }
  }

  bool setPaused(bool value) {
    if (!_canWrite ||
        (_mode != AppMode.exploration && _mode != AppMode.dialogue) ||
        value == _paused) {
      return false;
    }
    _paused = value;
    _publish();
    return true;
  }

  void returnToTitle() {
    if (!_canWrite || _mode == AppMode.title) return;
    ++_loadGeneration; // Cancel pending completions without resetting revision.
    _dialogue = null;
    _mode = AppMode.title;
    _paused = false;
    _error = null;
    _publish();
  }

  @override
  bool updatePosition(WorldPosition position, {required int expectedRevision}) {
    if (!_canWrite ||
        !movementEnabled ||
        expectedRevision != revision ||
        position.mapId != _area?.map.id ||
        !_check(() => _area!.isClear(position))) {
      return false;
    }
    _state = GameState(
      position: position,
      party: state.party,
      inventory: state.inventory,
      gold: state.gold,
      quests: state.quests,
    );
    _publish();
    return true;
  }

  // Fail closed for invalid B geometry callbacks; never allow nested writes.
  bool _check(bool Function() predicate) {
    _checking = true;
    try {
      return predicate();
    } catch (_) {
      return false;
    } finally {
      _checking = false;
    }
  }

  bool _canInteract(int expectedRevision) =>
      _canWrite && movementEnabled && expectedRevision == revision;

  bool _reachable(InteractionSite site) =>
      site.mapId == state.position.mapId &&
      _check(() => site.canActivate(state.position));

  GameState _copyState({
    WorldPosition? position,
    Inventory? inventory,
    QuestFlags? quests,
  }) => GameState(
    position: position ?? state.position,
    party: state.party,
    inventory: inventory ?? state.inventory,
    gold: state.gold,
    quests: quests ?? state.quests,
  );

  @override
  bool useMapExit(String exitId, {required int expectedRevision}) {
    if (!_canInteract(expectedRevision)) return false;
    final exit = _session!.operations.exits[exitId];
    if (exit == null || !_reachable(exit.site)) return false;
    final destination = exit.destinationMapId == _session!.map.id
        ? WorldArea(map: _session!.map, isClear: _session!.isClear)
        : _session!.operations.areas[exit.destinationMapId];
    final spawn = destination?.map.spawns[exit.spawnId];
    if (destination == null ||
        spawn == null ||
        !_check(() => destination.isClear(spawn))) {
      return false;
    }
    _state = _copyState(position: spawn);
    _area = destination;
    _publish();
    return true;
  }

  @override
  bool openDialogue(String interactionId, {required int expectedRevision}) {
    if (!_canInteract(expectedRevision)) return false;
    final dialogue = _session!.operations.dialogues[interactionId];
    if (dialogue == null || !_reachable(dialogue.site)) return false;
    _dialogue = ActiveDialogue(token: ++_dialogueSequence, dialogue: dialogue);
    _mode = AppMode.dialogue;
    _publish();
    return true;
  }

  /// A's presentation adapter owns completion. Cancellation and completion both
  /// release the gate; neither grants implicit quest flags or rewards.
  bool closeDialogue(int token, {required int expectedRevision}) {
    if (!_canWrite ||
        expectedRevision != revision ||
        _mode != AppMode.dialogue ||
        _dialogue?.token != token) {
      return false;
    }
    _dialogue = null;
    _mode = AppMode.exploration;
    _publish(); // Preserve lifecycle pause; dismissal must not auto-resume.
    return true;
  }

  @override
  bool openChest(String chestId, {required int expectedRevision}) {
    if (!_canInteract(expectedRevision)) return false;
    final chest = _session!.operations.chests[chestId];
    if (chest == null ||
        state.quests.openedChestIds.contains(chestId) ||
        !_reachable(chest.site)) {
      return false;
    }
    final quantities = {...state.inventory.quantities};
    quantities[chest.itemId] = (quantities[chest.itemId] ?? 0) + chest.quantity;
    _state = _copyState(
      inventory: Inventory(quantities),
      quests: QuestFlags(
        flags: state.quests.flags,
        openedChestIds: {...state.quests.openedChestIds, chestId},
      ),
    );
    _publish();
    return true;
  }

  /// No encounter definitions or battle adapter have been agreed for this slice.
  /// All requests reject without mutation, including fresh requests.
  @override
  bool requestEncounter(
    EncounterRequest request, {
    required int expectedRevision,
  }) => false;

  @override
  void dispose() {
    _disposed = true;
    ++_loadGeneration;
    super.dispose();
  }
}
