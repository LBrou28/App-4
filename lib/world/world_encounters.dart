import '../core/contracts.dart';

/// A deterministic source lets encounter behavior be tested without relying on
/// wall-clock randomness. Implementations must return a value in [0, max).
abstract interface class EncounterRandom {
  int nextInt(int max);
}

/// A rectangular, tile-aligned area that can produce a named encounter.
final class EncounterZone {
  EncounterZone({
    required this.mapId,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.definitionId,
    required this.rollDenominator,
    required this.rollThreshold,
    this.alternativeDefinitionIds = const [],
  }) {
    requireId(mapId, 'encounter map id');
    requireId(definitionId, 'encounter definition id');
    for (final id in alternativeDefinitionIds) {
      requireId(id, 'alternative encounter definition id');
    }
    if (left < 0 || top < 0 || width <= 0 || height <= 0) {
      throw ArgumentError('Encounter zone bounds must be positive');
    }
    if (rollDenominator <= 0 ||
        rollThreshold <= 0 ||
        rollThreshold > rollDenominator) {
      throw ArgumentError('Encounter chance must be within its denominator');
    }
  }

  final String mapId;
  final int left;
  final int top;
  final int width;
  final int height;
  final String definitionId;
  final List<String> alternativeDefinitionIds;
  final int rollDenominator;
  final int rollThreshold;

  bool contains(WorldPosition position) =>
      position.mapId == mapId &&
      position.x.floor() >= left &&
      position.x.floor() < left + width &&
      position.y.floor() >= top &&
      position.y.floor() < top + height;
}

/// B3 encounter policy. Call [recordAcceptedStep] only after the host accepts a
/// movement transaction. An accepted encounter makes the host gate exploration;
/// that gate prevents further calls from creating a second active encounter.
class EncounterStepper {
  EncounterStepper({
    required List<EncounterZone> zones,
    required this.random,
    this.cooldownSteps = 3,
    this.initialCooldownSteps = 0,
    this.stepDistance = 1,
    this.canEncounter,
  }) : _zones = List.unmodifiable(zones) {
    if (cooldownSteps < 0 || initialCooldownSteps < 0) {
      throw ArgumentError("Encounter cooldown cannot be negative");
    }
    if (!stepDistance.isFinite || stepDistance <= 0) {
      throw ArgumentError.value(stepDistance, "stepDistance");
    }
    _remainingCooldown = initialCooldownSteps;
  }

  final List<EncounterZone> _zones;
  final EncounterRandom random;
  final int cooldownSteps;
  final int initialCooldownSteps;

  /// Committed world-space travel between checks, independent of frame rate.
  final double stepDistance;
  final bool Function(WorldPosition)? canEncounter;
  String? _mapId;
  int _remainingCooldown = 0;

  int get remainingCooldown => _remainingCooldown;

  /// Called on controller attachment as well as checks, so even an immediate
  /// exit/re-entry grants grace without discarding a longer post-battle cooldown.
  void enterMap(String mapId) {
    if (_mapId == mapId) return;
    _mapId = mapId;
    if (_remainingCooldown < initialCooldownSteps) {
      _remainingCooldown = initialCooldownSteps;
    }
  }

  /// Returns true only when the host accepted one new encounter request.
  bool recordAcceptedStep(WorldHost host) {
    if (!host.movementEnabled) return false;
    final position = host.state.position;
    enterMap(position.mapId);
    if (canEncounter?.call(position) == false) return false;
    final zone = _zones.where((zone) => zone.contains(position)).firstOrNull;
    if (zone == null) return false;
    if (_remainingCooldown > 0) {
      _remainingCooldown--;
      return false;
    }
    if (random.nextInt(zone.rollDenominator) >= zone.rollThreshold) {
      return false;
    }
    final definitions = [zone.definitionId, ...zone.alternativeDefinitionIds];
    final definition = definitions.length == 1
        ? definitions.single
        : definitions[random.nextInt(definitions.length)];
    final accepted = host.requestEncounter(
      EncounterRequest(definitionId: definition),
      expectedRevision: host.revision,
    );
    if (accepted) _remainingCooldown = cooldownSteps;
    return accepted;
  }

  /// Use after an accepted map transition or a New Game/load that replaces the
  /// current exploration context. No encounter rolls occur while standing still.
  void resetCooldown() {
    _mapId = null;
    _remainingCooldown = initialCooldownSteps;
  }
}
