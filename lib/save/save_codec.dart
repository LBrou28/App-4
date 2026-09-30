import 'dart:convert';

import '../core/contracts.dart';

/// Versioned, strict serialization of the shared state. Runtime revisions and
/// in-flight encounters are deliberately excluded.
final class SaveCodec {
  static String encode(SaveData data) => jsonEncode({
    'schemaVersion': SaveData.proposedSchemaVersion,
    'contentVersion': data.contentVersion,
    'state': {
      'position': {
        'mapId': data.state.position.mapId,
        'x': data.state.position.x,
        'y': data.state.position.y,
      },
      'party': [
        for (final m in data.state.party)
          {
            'id': m.id,
            'jobId': m.jobId,
            'hp': m.hp,
            'maxHp': m.maxHp,
            'mp': m.mp,
            'maxMp': m.maxMp,
            'level': m.level,
            'experience': m.experience,
            'jobProgress': m.jobProgress,
            'equipment': m.equipment,
          },
      ],
      'inventory': data.state.inventory.quantities,
      'gold': data.state.gold,
      'flags': data.state.quests.flags.toList()..sort(),
      'openedChestIds': data.state.quests.openedChestIds.toList()..sort(),
    },
  });

  static SaveData decode(String source) {
    final root = _object(jsonDecode(source), {
      'schemaVersion',
      'contentVersion',
      'state',
    });
    if (root['schemaVersion'] != SaveData.proposedSchemaVersion) {
      throw const UnsupportedSaveVersion();
    }
    final raw = _object(root['state'], {
      'position',
      'party',
      'inventory',
      'gold',
      'flags',
      'openedChestIds',
    });
    final pos = _object(raw['position'], {'mapId', 'x', 'y'});
    final party = _list(raw['party']).map((value) {
      final member = _object(value, {
        'id',
        'jobId',
        'hp',
        'maxHp',
        'mp',
        'maxMp',
        'level',
        'experience',
        'jobProgress',
        'equipment',
      });
      return PartyMember(
        id: _string(member['id']),
        jobId: _string(member['jobId']),
        hp: _int(member['hp']),
        maxHp: _int(member['maxHp']),
        mp: _int(member['mp']),
        maxMp: _int(member['maxMp']),
        level: _int(member['level']),
        experience: _int(member['experience']),
        jobProgress: _counts(member['jobProgress']),
        equipment: _strings(member['equipment']),
      );
    }).toList();
    return SaveData(
      contentVersion: _string(root['contentVersion']),
      state: GameState(
        position: WorldPosition(
          mapId: _string(pos['mapId']),
          x: _number(pos['x']),
          y: _number(pos['y']),
        ),
        party: party,
        inventory: Inventory(_counts(raw['inventory'])),
        gold: _int(raw['gold']),
        quests: QuestFlags(
          flags: _list(raw['flags']).map(_string).toSet(),
          openedChestIds: _list(raw['openedChestIds']).map(_string).toSet(),
        ),
      ),
    );
  }

  static Map<String, Object?> _object(Object? value, Set<String> keys) {
    if (value is! Map<String, dynamic> ||
        value.keys.toSet().difference(keys).isNotEmpty ||
        keys.difference(value.keys.toSet()).isNotEmpty) {
      throw const FormatException('Invalid save object');
    }
    return value.cast<String, Object?>();
  }

  static List<Object?> _list(Object? value) => value is List
      ? value.cast<Object?>()
      : throw const FormatException('Invalid save list');
  static String _string(Object? value) => value is String
      ? value
      : throw const FormatException('Invalid save text');
  static int _int(Object? value) => value is int
      ? value
      : throw const FormatException('Invalid save integer');
  static double _number(Object? value) => value is num
      ? value.toDouble()
      : throw const FormatException('Invalid save number');
  static Map<String, int> _counts(Object? value) => _map(value, _int);
  static Map<String, String> _strings(Object? value) => _map(value, _string);
  static Map<String, T> _map<T>(Object? value, T Function(Object?) read) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid save map');
    }
    return value.map((key, value) => MapEntry(key, read(value)));
  }
}

final class UnsupportedSaveVersion implements Exception {
  const UnsupportedSaveVersion();
}
