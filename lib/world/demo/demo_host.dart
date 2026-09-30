import 'package:flutter/foundation.dart';

import '../../core/contracts.dart';
import '../../core/fixtures/contract_fixture.dart';
import '../world_map.dart';

enum DemoGate { exploration, pause, dialogue, battle, loading }

/// Test harness only, not A2. No combat, dialogue, persistence or rewards.
class DemoWorldHost extends ChangeNotifier implements WorldHost {
  DemoWorldHost(this.map)
    : _state = createContractFixture(position: map.spawns['entry']!),
      _collision = WorldCollision(map);

  final MapDefinition map;
  final WorldCollision _collision;
  GameState _state;
  int _revision = 0;
  DemoGate _gate = DemoGate.exploration;
  bool _disposed = false;
  bool _notifying = false;

  @override
  GameState get state => _state;
  @override
  int get revision => _revision;
  DemoGate get gate => _gate;
  bool get hasSubscribers => hasListeners;
  @override
  bool get movementEnabled => !_disposed && _gate == DemoGate.exploration;

  void _publish() {
    _revision++;
    _notifying = true;
    try {
      notifyListeners();
    } finally {
      _notifying = false;
    }
  }

  void setGate(DemoGate gate) {
    if (_disposed || _notifying || gate == _gate) return;
    _gate = gate;
    _publish();
  }

  void reset() {
    if (_disposed || _notifying) return;
    _state = createContractFixture(position: map.spawns['entry']!);
    _gate = DemoGate.exploration;
    _publish();
  }

  @override
  bool updatePosition(WorldPosition position, {required int expectedRevision}) {
    if (_disposed ||
        _notifying ||
        !movementEnabled ||
        expectedRevision != revision ||
        !_collision.isClear(position)) {
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

  // Encounter definitions are unavailable in B1. Reject without mutation.
  @override
  bool requestEncounter(
    EncounterRequest request, {
    required int expectedRevision,
  }) => false;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
