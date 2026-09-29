import 'package:shared_preferences/shared_preferences.dart';

import '../core/contracts.dart';
import 'save_codec.dart';

/// One local slot, shared by browser and desktop implementations of the plugin.
final class LocalSaveRepository implements SaveRepository {
  LocalSaveRepository({SharedPreferencesAsync? preferences})
    : _preferences = preferences ?? SharedPreferencesAsync();

  static const key = 'app_4.save.v1';
  final SharedPreferencesAsync _preferences;

  @override
  Future<LoadResult> load() async {
    try {
      final source = await _preferences.getString(key);
      if (source == null) return SaveMissing();
      try {
        return SaveLoaded(SaveCodec.decode(source));
      } on UnsupportedSaveVersion {
        return SaveUnreadable(SaveReadFailure.unsupportedVersion);
      } on Object {
        return SaveUnreadable(SaveReadFailure.corrupt);
      }
    } on Object {
      return SaveUnreadable(SaveReadFailure.unavailable);
    }
  }

  @override
  Future<WriteResult> save(SaveData data) async {
    try {
      await _preferences.setString(key, SaveCodec.encode(data));
      return SaveWritten();
    } on Object {
      return SaveWriteFailed('Save storage is unavailable.');
    }
  }
}
