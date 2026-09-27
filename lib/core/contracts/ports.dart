import 'messages.dart';
import 'models.dart';

/// Combat/progression remains provisional; no rules implementation yet.
abstract interface class PartyRules {
  CommandResult apply(GameState current, MenuCommand command);
}

/// B1-v1 boundary approved by Jordan. See docs/contracts.md for atomicity,
/// monotonically increasing revisions and notification/lifecycle requirements.
/// Read state, revision and movementEnabled synchronously without an await.
abstract interface class WorldHost {
  GameState get state;
  int get revision;
  bool get movementEnabled;

  /// Synchronous and atomic: true publishes the position and a newer revision
  /// before returning; false leaves state, revision and movement gate unchanged.
  /// Reject stale revisions, disabled movement, wrong maps or invalid positions.
  /// B validates the full collision footprint before requesting this update.
  bool updatePosition(WorldPosition position, {required int expectedRevision});

  /// Uses the revision re-read AFTER accepted movement. True atomically captures
  /// that position, advances revision and disables movement/further encounters
  /// before notifying listeners or returning. False changes nothing.
  bool requestEncounter(
    EncounterRequest request, {
    required int expectedRevision,
  });
}

abstract interface class SaveRepository {
  Future<LoadResult> load();
  Future<WriteResult> save(SaveData data);
}

sealed class LoadResult {}

final class SaveLoaded extends LoadResult {
  SaveLoaded(this.data);
  final SaveData data;
}

final class SaveMissing extends LoadResult {}

final class SaveUnreadable extends LoadResult {
  SaveUnreadable(this.reason);
  final SaveReadFailure reason;
}

enum SaveReadFailure { corrupt, unsupportedVersion, unavailable }

sealed class WriteResult {}

final class SaveWritten extends WriteResult {}

final class SaveWriteFailed extends WriteResult {
  SaveWriteFailed(this.message);
  final String message;
}
