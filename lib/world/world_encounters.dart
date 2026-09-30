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
  }) {
    requireId(mapId, 'encounter map id');
    requireId(definitionId, 'encounter definition id');
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
  }) : _zones = List.unmodifiable(zones) {
    if (cooldownSteps < 0) throw ArgumentError.value(cooldownSteps);
  }

  final List<EncounterZone> _zones;
  final EncounterRandom random;
  final int cooldownSteps;
  int _remainingCooldown = 0;

  int get remainingCooldown => _remainingCooldown;

  /// Returns true only when the host accepted one new encounter request.
  bool recordAcceptedStep(WorldHost host) {
    if (!host.movementEnabled) return false;
    final position = host.state.position;
    final zone = _zones.where((zone) => zone.contains(position)).firstOrNull;
    if (zone == null) return false;
    if (_remainingCooldown > 0) {
      _remainingCooldown--;
      return false;
    }
    if (random.nextInt(zone.rollDenominator) >= zone.rollThreshold) {
      return false;
    }
    final accepted = host.requestEncounter(
      EncounterRequest(definitionId: zone.definitionId),
      expectedRevision: host.revision,
    );
    if (accepted) _remainingCooldown = cooldownSteps;
    return accepted;
  }

  /// Use after an accepted map transition or a New Game/load that replaces the
  /// current exploration context. No encounter rolls occur while standing still.
  void resetCooldown() => _remainingCooldown = 0;
}
