import 'package:app_4/core/contracts.dart';
import 'package:app_4/world/world_encounters.dart';
import 'package:flutter_test/flutter_test.dart';

class SequenceRandom implements EncounterRandom {
  SequenceRandom(this.values);
  final List<int> values;
  var calls = 0;

  @override
  int nextInt(int max) {
    final value = values[calls++];
    if (value < 0 || value >= max) throw StateError('Bad test value');
    return value;
  }
}

class EncounterHost implements WorldHost {
  EncounterHost(this._state);
  GameState _state;
  int _revision = 0;
  bool _enabled = true;
  final requests = <EncounterRequest>[];

  @override
  GameState get state => _state;
  @override
  int get revision => _revision;
  @override
  bool get movementEnabled => _enabled;

  @override
  bool requestEncounter(EncounterRequest request, {required int expectedRevision}) {
    if (!_enabled || expectedRevision != _revision) return false;
    requests.add(request);
    _enabled = false;
    _revision++;
    return true;
  }

  @override
  bool updatePosition(WorldPosition position, {required int expectedRevision}) {
    if (!_enabled || expectedRevision != _revision) return false;
    _state = GameState(
      position: position,
      party: _state.party,
      inventory: _state.inventory,
      gold: _state.gold,
      quests: _state.quests,
    );
    _revision++;
    return true;
  }

  void returnToExploration() {
    _enabled = true;
    _revision++;
  }
}

GameState stateAt(String mapId, double x, double y) => GameState(
  position: WorldPosition(mapId: mapId, x: x, y: y),
  party: List.generate(4, (index) => PartyMember(
    id: 'hero.$index', jobId: 'job.$index', hp: 1, maxHp: 1, mp: 0, maxMp: 0,
    level: 1, experience: 0, jobProgress: const {}, equipment: const {},
  )),
  inventory: Inventory(const {}), gold: 0,
  quests: QuestFlags(flags: const {}, openedChestIds: const {}),
);

void main() {
  final zone = EncounterZone(
    mapId: 'route', left: 1, top: 1, width: 3, height: 2,
    definitionId: 'enemy.goblin', rollDenominator: 4, rollThreshold: 1,
  );

  test('only accepted movement steps in a zone can request an encounter', () {
    final host = EncounterHost(stateAt('town', 1.5, 1.5));
    final random = SequenceRandom([0]);
    final stepper = EncounterStepper(zones: [zone], random: random);
    expect(stepper.recordAcceptedStep(host), isFalse);
    expect(random.calls, 0);
    expect(host.updatePosition(WorldPosition(mapId: 'route', x: 1.5, y: 1.5), expectedRevision: 0), isTrue);
    expect(stepper.recordAcceptedStep(host), isTrue);
    expect(host.requests.single.definitionId, 'enemy.goblin');
    expect(host.movementEnabled, isFalse);
    expect(stepper.recordAcceptedStep(host), isFalse);
    expect(host.requests, hasLength(1));
  });

  test('cooldown consumes moved zone steps and does not roll', () {
    final host = EncounterHost(stateAt('route', 1.5, 1.5));
    final random = SequenceRandom([0, 0]);
    final stepper = EncounterStepper(zones: [zone], random: random, cooldownSteps: 2);
    expect(stepper.recordAcceptedStep(host), isTrue);
    host.returnToExploration();
    expect(stepper.recordAcceptedStep(host), isFalse);
    expect(stepper.remainingCooldown, 1);
    expect(stepper.recordAcceptedStep(host), isFalse);
    expect(stepper.remainingCooldown, 0);
    expect(stepper.recordAcceptedStep(host), isTrue);
    expect(random.calls, 2);
  });

  test('invalid zone chance is rejected early', () {
    expect(() => EncounterZone(mapId: 'x', left: 0, top: 0, width: 1, height: 1, definitionId: 'e', rollDenominator: 3, rollThreshold: 4), throwsArgumentError);
  });
}
