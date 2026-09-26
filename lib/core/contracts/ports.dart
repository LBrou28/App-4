import 'messages.dart';
import 'models.dart';

/// All ports are review proposals; no app or persistence implementation yet.
abstract interface class PartyRules {
  CommandResult apply(GameState current, MenuCommand command);
}

abstract interface class WorldHost {
  GameState get state;
  int get revision;
  bool get movementEnabled;

  /// False means stale revision, wrong mode/map or rejected position.
  /// B validates collision before requesting this update.
  bool updatePosition(WorldPosition position, {required int expectedRevision});
  bool requestEncounter(EncounterRequest request);
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
