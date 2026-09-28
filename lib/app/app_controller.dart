import 'package:flutter/foundation.dart';

import '../core/contracts.dart';
import '../core/fixtures/contract_fixture.dart';

/// Loaded world plus B's full-footprint validation. No combat/content rules.
final class WorldSession {
  WorldSession({
    required this.map,
    required this.initialState,
    required this.isClear,
  });
  final MapDefinition map;
  final GameState initialState;
  final bool Function(WorldPosition) isClear;
}

typedef WorldLoader = Future<WorldSession> Function();

/// A2 exploration slice. Battle acceptance stays disabled until its contract is agreed.
class AppController extends ChangeNotifier implements WorldHost {
  AppController({required this.loadWorld});
  final WorldLoader loadWorld;
  GameState _state = createContractFixture();
  WorldSession? _session;
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
  MapDefinition? get map => _session?.map;
  @override
  bool get movementEnabled =>
      !_disposed && _mode == AppMode.exploration && !_paused;
  bool get _canWrite => !_disposed && !_notifying;

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
    _mode = AppMode.loading;
    _paused = false;
    _error = null;
    _publish();
    try {
      final loaded = await loadWorld();
      if (_disposed || generation != _loadGeneration) return;
      if (loaded.initialState.position.mapId != loaded.map.id ||
          !loaded.isClear(loaded.initialState.position)) {
        throw StateError('Invalid world spawn');
      }
      _session = loaded;
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
    if (!_canWrite || _mode != AppMode.exploration || value == _paused) {
      return false;
    }
    _paused = value;
    _publish();
    return true;
  }

  void returnToTitle() {
    if (!_canWrite || _mode == AppMode.title) return;
    ++_loadGeneration; // Cancel pending completions without resetting revision.
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
        position.mapId != _session?.map.id ||
        !_session!.isClear(position)) {
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
