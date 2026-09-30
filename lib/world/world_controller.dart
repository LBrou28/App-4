import '../core/contracts.dart';
import 'world_map.dart';

/// Local input only; the host remains the sole owner of position/GameState.
class WorldController {
  WorldController({required this.host, required this.collision});

  final WorldHost host;
  final WorldCollision collision;
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
      _held.remove(source);
      _held[source] = direction;
    }
  }

  void release(Object source) => _held.remove(source);
  void clearInput() => _held.clear();

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
    // Discard stall time rather than replaying a browser-tab backlog.
    final dt = elapsedSeconds.clamp(0.0, maximumFrameSeconds);
    final next = collision.move(state.position, active, tilesPerSecond * dt);
    if (next.x == state.position.x && next.y == state.position.y) return false;
    final accepted = host.updatePosition(next, expectedRevision: revision);
    // Always re-read after the transaction, including rejection. No optimistic state.
    synchronize();
    return accepted;
  }
}
