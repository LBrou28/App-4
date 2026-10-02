import 'package:flutter/foundation.dart';

import '../core/contracts.dart';
import '../battle/battle_session.dart';
import '../core/fixtures/contract_fixture.dart';
import 'world_operations.dart';

/// Loaded world plus B's full-footprint validation. No combat/content rules.
final class WorldSession {
  WorldSession({
    required this.map,
    required this.initialState,
    required this.isClear,
    WorldOperations? operations,
    this.contentVersion,
    this.validateSavedState,
  }) : operations = operations ?? WorldOperations();
  final WorldOperations operations;
  final MapDefinition map;
  final GameState initialState;
  final bool Function(WorldPosition) isClear;
  final String? contentVersion;
  final bool Function(GameState)? validateSavedState;
}

typedef WorldLoader = Future<WorldSession> Function();
typedef BattleFactory = BattleSession Function(BattleInput input);

/// Authoritative A coordinator. Only registered C battle adapters may launch.
class AppController extends ChangeNotifier
    implements WorldInteractionHost, ValueListenable<bool> {
  AppController({
    required this.loadWorld,
    Map<String, BattleFactory> battles = const {},
    this.saves,
  }) : _battles = Map.unmodifiable(battles);
  final SaveRepository? saves;
  final Map<String, BattleFactory> _battles;
  BattleSession? _battle;
  BattleSession? get activeBattle => _battle;
  int _encounterSequence = 0;
  @override
  bool get value => _paused;
  final WorldLoader loadWorld;
  GameState _state = createContractFixture();
  WorldSession? _session;
  WorldArea? _area;
  ActiveDialogue? _dialogue;
  WorldQuestStep? _postBattleDialogue;
  int _dialogueSequence = 0;
  bool _checking = false;
  bool _saving = false;
  ActiveDialogue? get activeDialogue => _dialogue;
  AppMode _mode = AppMode.title;
  int _revision = 0;
  int _loadGeneration = 0;
  bool _paused = false;
  bool _remoteReadOnly = false;
  bool _musicEnabled = true;
  bool _effectsEnabled = true;
  bool _disposed = false;
  bool _notifying = false;
  String? _error;

  @override
  GameState get state => _state;
  @override
  int get revision => _revision;
  AppMode get mode => _mode;
  bool get paused => _paused;

  /// A Lantern Link guest renders the host's authoritative state but cannot
  /// mutate the local exploration session.
  bool get remoteReadOnly => _remoteReadOnly;
  bool get musicEnabled => _musicEnabled;
  bool get effectsEnabled => _effectsEnabled;
  String? get error => _error;
  MapDefinition? get map => _area?.map;
  @override
  bool get movementEnabled =>
      !_disposed &&
      _mode == AppMode.exploration &&
      !_paused &&
      !_remoteReadOnly;
  bool get _canWrite => !_disposed && !_notifying && !_checking && !_saving;

  Future<LoadResult> readSave() async =>
      await saves?.load() ?? SaveUnreadable(SaveReadFailure.unavailable);

  /// Saves one coherent snapshot while world writes are gated. Saving itself
  /// never changes the state or revision.
  Future<WriteResult> saveCurrent() async {
    final repository = saves;
    final version = _session?.contentVersion;
    if (!_canWrite ||
        _mode != AppMode.exploration ||
        !_paused ||
        _remoteReadOnly ||
        repository == null ||
        version == null) {
      return SaveWriteFailed('Saving is unavailable right now.');
    }
    _saving = true;
    try {
      return await repository.save(
        SaveData(contentVersion: version, state: _state),
      );
    } finally {
      _saving = false;
    }
  }

  /// Restores only a compatible state on a currently valid world. A rejected
  /// save leaves the active state, revision and mode unchanged.
  Future<LoadResult> continueGame() async {
    if (!_canWrite || _mode != AppMode.title || saves == null) {
      return SaveUnreadable(SaveReadFailure.unavailable);
    }
    _saving = true;
    try {
      final loadedSave = await saves!.load();
      if (loadedSave is! SaveLoaded || _disposed) return loadedSave;
      final loadedWorld = await loadWorld();
      if (_disposed) return SaveUnreadable(SaveReadFailure.unavailable);
      if (loadedSave.data.contentVersion != loadedWorld.contentVersion) {
        return SaveUnreadable(SaveReadFailure.unsupportedVersion);
      }
      final restored = loadedSave.data.state;
      final area =
          loadedWorld.operations.areas[restored.position.mapId] ??
          (restored.position.mapId == loadedWorld.map.id
              ? WorldArea(map: loadedWorld.map, isClear: loadedWorld.isClear)
              : null);
      if (area == null ||
          !_check(() => area.permits(restored.position, restored.quests)) ||
          restored.party.length != loadedWorld.initialState.party.length ||
          !restored.party.asMap().entries.every(
            (entry) =>
                entry.value.id == loadedWorld.initialState.party[entry.key].id,
          ) ||
          loadedWorld.validateSavedState?.call(restored) == false) {
        return SaveUnreadable(SaveReadFailure.corrupt);
      }
      _session = loadedWorld;
      _area = area;
      _state = restored;
      _dialogue = null;
      _postBattleDialogue = null;
      _battle = null;
      _remoteReadOnly = false;
      _paused = false;
      _error = null;
      _mode = AppMode.exploration;
      _publish();
      return loadedSave;
    } catch (_) {
      return SaveUnreadable(SaveReadFailure.corrupt);
    } finally {
      _saving = false;
    }
  }

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
    _postBattleDialogue = null;
    _battle = null;
    _remoteReadOnly = false;
    _mode = AppMode.loading;
    _paused = false;
    _error = null;
    _publish();
    try {
      final loaded = await loadWorld();
      if (_disposed || generation != _loadGeneration) return;
      if (loaded.initialState.position.mapId != loaded.map.id ||
          !_check(
            () =>
                (loaded.operations.areas[loaded.map.id] ??
                        WorldArea(map: loaded.map, isClear: loaded.isClear))
                    .permits(
                      loaded.initialState.position,
                      loaded.initialState.quests,
                    ),
          )) {
        throw StateError('Invalid world spawn');
      }
      _session = loaded;
      _area =
          loaded.operations.areas[loaded.map.id] ??
          WorldArea(map: loaded.map, isClear: loaded.isClear);
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

  /// Applies a validated exploration snapshot received from the Lantern Link
  /// server. This intentionally reuses the normal world loader and its
  /// geometry/content checks rather than trusting network data at the UI edge.
  ///
  /// Once applied, the controller is read-only until a local session starts.
  Future<bool> applyRemoteExplorationState(
    GameState remote, {
    bool readOnly = true,
  }) async {
    if (!_canWrite || _mode == AppMode.loading) return false;
    final generation = ++_loadGeneration;
    try {
      // Movement snapshots arrive frequently. Once a guest has a validated
      // world session, reuse it instead of reloading artwork/map data for
      // every authoritative position update.
      final loaded = _session ?? await loadWorld();
      if (_disposed || generation != _loadGeneration) return false;
      final area = remote.position.mapId == loaded.map.id
          ? WorldArea(map: loaded.map, isClear: loaded.isClear)
          : loaded.operations.areas[remote.position.mapId];
      if (area == null ||
          !_check(() => area.isClear(remote.position)) ||
          remote.party.length != loaded.initialState.party.length ||
          !remote.party.asMap().entries.every(
            (entry) =>
                entry.value.id == loaded.initialState.party[entry.key].id,
          ) ||
          loaded.validateSavedState?.call(remote) == false) {
        return false;
      }
      _session = loaded;
      _area = area;
      _state = remote;
      _dialogue = null;
      _postBattleDialogue = null;
      _battle = null;
      _paused = false;
      _remoteReadOnly = readOnly;
      _error = null;
      _mode = AppMode.exploration;
      _publish();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Releases the local placeholder encounter after Lantern Link has accepted
  /// the same request. The server is then the sole battle authority.
  bool handoffBattleToLanternLink() {
    if (!_canWrite || _mode != AppMode.battle || _battle == null) return false;
    _battle = null;
    _postBattleDialogue = null;
    _mode = AppMode.exploration;
    _publish();
    return true;
  }

  bool setPaused(bool value) {
    if (!_canWrite ||
        _remoteReadOnly ||
        (_mode != AppMode.exploration &&
            _mode != AppMode.dialogue &&
            _mode != AppMode.battle) ||
        value == _paused) {
      return false;
    }
    _paused = value;
    _publish();
    return true;
  }

  /// Presentation settings deliberately live outside the save state. They must
  /// remain usable while the game simulation is paused.
  bool setMusicEnabled(bool value) {
    if (!_canWrite || value == _musicEnabled) return false;
    _musicEnabled = value;
    _publish();
    return true;
  }

  bool setEffectsEnabled(bool value) {
    if (!_canWrite || value == _effectsEnabled) return false;
    _effectsEnabled = value;
    _publish();
    return true;
  }

  void returnToTitle() {
    if (!_canWrite || _mode == AppMode.title) return;
    ++_loadGeneration; // Cancel pending completions without resetting revision.
    _dialogue = null;
    _postBattleDialogue = null;
    _battle = null;
    _remoteReadOnly = false;
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
        !_check(() => _area!.permits(position, state.quests))) {
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

  WorldQuestStep? _availableQuestStep(String interactionId) {
    for (final step in _session!.operations.questSteps.values) {
      if (step.interactionId != interactionId ||
          !_reachable(step.site) ||
          !state.quests.flags.containsAll(step.requiresFlags) ||
          (step.setsFlag != null &&
              state.quests.flags.contains(step.setsFlag))) {
        continue;
      }
      return step;
    }
    return null;
  }

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
    final destination =
        _session!.operations.areas[exit.destinationMapId] ??
        (exit.destinationMapId == _session!.map.id
            ? WorldArea(map: _session!.map, isClear: _session!.isClear)
            : null);
    final spawn = destination?.map.spawns[exit.spawnId];
    if (destination == null ||
        spawn == null ||
        !_check(() => destination.permits(spawn, state.quests))) {
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
    final questStep = _availableQuestStep(interactionId);
    if (questStep != null) {
      if (questStep.encounterId != null) {
        return _launchEncounter(
          EncounterRequest(definitionId: questStep.encounterId!),
          postBattleDialogue: questStep,
        );
      }
      _dialogue = ActiveDialogue(
        token: ++_dialogueSequence,
        dialogue: questStep.dialogue,
        setsQuestFlag: questStep.setsFlag,
      );
      _mode = AppMode.dialogue;
      _publish();
      return true;
    }
    final dialogue = _session!.operations.dialogues[interactionId];
    if (dialogue == null || !_reachable(dialogue.site)) return false;
    _dialogue = ActiveDialogue(token: ++_dialogueSequence, dialogue: dialogue);
    _mode = AppMode.dialogue;
    _publish();
    return true;
  }

  /// A's presentation adapter owns completion. Cancellation and completion both
  /// release the gate. Quest flags are granted only by successful completion.
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

  /// Completion can grant the one authored flag attached to the active quest
  /// dialogue. A stale route or cancellation cannot write it.
  bool completeDialogue(int token, {required int expectedRevision}) {
    if (!_canWrite ||
        expectedRevision != revision ||
        _mode != AppMode.dialogue ||
        _dialogue?.token != token) {
      return false;
    }
    final flag = _dialogue!.setsQuestFlag;
    if (flag != null && state.quests.flags.contains(flag)) return false;
    if (flag != null) {
      _state = _copyState(
        quests: QuestFlags(
          flags: {...state.quests.flags, flag},
          openedChestIds: state.quests.openedChestIds,
        ),
      );
    }
    _dialogue = null;
    _mode = AppMode.exploration;
    _publish();
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

  /// Only explicitly registered C factories can launch. Rejection is a no-op.
  @override
  bool requestEncounter(
    EncounterRequest request, {
    required int expectedRevision,
  }) {
    if (!_canInteract(expectedRevision) || !state.party.any((m) => m.hp > 0)) {
      return false;
    }
    return _launchEncounter(request);
  }

  bool _launchEncounter(
    EncounterRequest request, {
    WorldQuestStep? postBattleDialogue,
  }) {
    if (!state.party.any((m) => m.hp > 0)) return false;
    final factory = _battles[request.definitionId];
    if (factory == null) return false;
    final sequence = _encounterSequence + 1;
    final input = BattleInput(
      encounterId: 'encounter.$sequence',
      baseRevision: revision + 1,
      request: request,
      state: state,
      seed: sequence,
    );
    BattleSession? session;
    final valid = _check(() {
      session = factory(input);
      return identical(session!.input, input) && session!.result == null;
    });
    if (!valid) return false;
    _encounterSequence = sequence;
    _battle = session;
    _postBattleDialogue = postBattleDialogue;
    _mode = AppMode.battle;
    _publish();
    return true;
  }

  /// C2's no-cost/no-reward result is produced by the exact active session.
  /// Correlation uses the launch revision, not gate revisions changed by pause.
  bool acceptBattleResult(BattleResult result) {
    final session = _battle;
    if (!_canWrite ||
        _paused ||
        _mode != AppMode.battle ||
        session == null ||
        !identical(result, session.result) ||
        result.encounterId != session.input.encounterId ||
        result.baseRevision != session.input.baseRevision) {
      return false;
    }
    final next = GameState(
      position: session.input.state.position,
      party: result.party,
      inventory: result.inventory,
      gold: result.gold,
      quests: session.input.state.quests,
    );
    if (!result.party.asMap().entries.every(
          (entry) => entry.value.id == session.input.state.party[entry.key].id,
        ) ||
        !_check(() => _session?.validateSavedState?.call(next) ?? true)) {
      return false;
    }
    _state = next;
    final followup = result.outcome == BattleOutcome.victory
        ? _postBattleDialogue
        : null;
    _battle =
        null; // Clear before publication: duplicate callbacks cannot commit.
    _postBattleDialogue = null;
    if (followup != null) {
      _dialogue = ActiveDialogue(
        token: ++_dialogueSequence,
        dialogue: followup.dialogue,
        setsQuestFlag: followup.setsFlag,
      );
      _mode = AppMode.dialogue;
    } else {
      _mode = result.outcome == BattleOutcome.defeat
          ? AppMode.gameOver
          : AppMode.exploration;
    }
    _publish();
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    ++_loadGeneration;
    super.dispose();
  }
}
