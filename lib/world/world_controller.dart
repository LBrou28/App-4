import '../core/contracts.dart';
import 'world_map.dart';
import 'world_encounters.dart';
import 'world_interactions.dart';

/// Local input only; the host remains the sole owner of position/GameState.
class WorldController {
  WorldController({
    required this.host,
    required this.collision,
    this.encounters,
    this.interactions,
  });

  final WorldHost host;
  final WorldCollision collision;
  final EncounterStepper? encounters;
  final WorldInteractions? interactions;
  WalkDirection facing = WalkDirection.down;
  String? interactionMessage;

  WorldTarget? get interactionTarget =>
      interactions?.inFront(host.state.position, facing);

  bool interact() {
    final h = host;
    final target = interactionTarget;
    if (h is! WorldInteractionHost || !h.movementEnabled || target == null) {
      return false;
    }
    clearInput();
    if (target.kind == WorldTargetKind.chest &&
        h.state.quests.openedChestIds.contains(target.id)) {
      interactionMessage = 'This chest is empty.';
      return false;
    }
    final accepted = switch (target.kind) {
      WorldTargetKind.npc => h.openDialogue(
        target.id,
        expectedRevision: h.revision,
      ),
      WorldTargetKind.chest => h.openChest(
        target.id,
        expectedRevision: h.revision,
      ),
      WorldTargetKind.exit => false,
    };
    interactionMessage = accepted
        ? (target.kind == WorldTargetKind.chest
              ? 'Supplies added to your inventory.'
              : null)
        : 'Interaction unavailable.';
    synchronize();
    return accepted;
  }

  double _stepDistance = 0;
  final _held = <Object, WalkDirection>{};
  static const tilesPerSecond = 3.0;
  static const maximumFrameSeconds = .1;

  String? get positionError => collision.isClear(host.state.position)
      ? null
      : 'The current position does not fit this map. Reload a valid spawn.';

  WalkDirection? get direction => _held.isEmpty ? null : _held.values.last;

  // The most recently pressed direction wins: cardinal movement, no diagonal boost.
  // Sources keep WASD, arrows and simultaneous pointers independent.
  void press(Object source, WalkDirection direction) {
    if (host.movementEnabled && positionError == null) {
      facing = direction;
      interactionMessage = null;
      _held.remove(source);
      _held[source] = direction;
    }
  }

  void release(Object source) {
    _held.remove(source);
    if (direction != null) facing = direction!;
  }
  void clearInput() {
    _held.clear();
    _stepDistance = 0;
  }

  /// Safe to call from a synchronous host notification: no host writes here.
  void synchronize() {
    if (!host.movementEnabled || positionError != null) clearInput();
  }

  bool advance(double elapsedSeconds) {
    final state = host.state;
    final revision = host.revision;
    final enabled = host.movementEnabled;
    if (!enabled || !collision.isClear(state.position)) {
      clearInput();
      return false;
    }
    final active = direction;
    if (active == null || !elapsedSeconds.isFinite || elapsedSeconds <= 0) {
      return false;
    }
    facing = active;
    // Discard stall time rather than replaying a browser-tab backlog.
    final dt = elapsedSeconds.clamp(0.0, maximumFrameSeconds);
    final next = collision.move(state.position, active, tilesPerSecond * dt);
    if (next.x == state.position.x && next.y == state.position.y) return false;
    final accepted = host.updatePosition(next, expectedRevision: revision);
    if (accepted && interactions?.exitAfterMovement(host) == true) {
      clearInput();
      return true;
    }
    // Host notifications have finished. Count only committed physical travel,
    // never attempted distance, elapsed frames, or an external teleport.
    final committed = host.state.position;
    if (accepted &&
        host.movementEnabled &&
        committed.mapId == next.mapId &&
        committed.x == next.x &&
        committed.y == next.y &&
        encounters != null) {
      _stepDistance +=
          (committed.x - state.position.x).abs() +
          (committed.y - state.position.y).abs();
      while (_stepDistance >= 1 - 1e-9 && host.movementEnabled) {
        _stepDistance = (_stepDistance - 1).clamp(0.0, double.infinity);
        if (encounters!.recordAcceptedStep(host)) {
          clearInput();
          break;
        }
      }
    }
    // Always re-read after the transaction, including rejection. No optimistic state.
    synchronize();
    return accepted;
  }
}
