import 'dart:convert';

import '../../core/contracts.dart';

/// D-owned authoring schema. Shared adapters below use the existing A1 DTOs.
/// Narrative metadata is not a replacement for C's rules or B's map format.
final class ContentEntry {
  ContentEntry._(Map<String, Object?> fields)
    : fields = Map.unmodifiable(fields);
  final Map<String, Object?> fields;
  String get id => text('id');
  String get name => fields['name'] as String? ?? id;
  String get description => fields['description'] as String? ?? '';
  String text(String key) => fields[key]! as String;
  String? optionalText(String key) => fields[key] as String?;
  List<String> strings(String key) => (fields[key]! as List).cast<String>();
  int number(String key) => fields[key]! as int;
}

final class DemoContent {
  DemoContent._(
    this.version,
    this.title,
    this.premise,
    this.sections,
    this.flags,
    this.questId,
    this.questName,
    this.steps,
  );

  final String version;
  final String title;
  final String premise;
  final Map<String, List<ContentEntry>> sections;
  final Set<String> flags;
  final String questId;
  final String questName;
  final List<ContentEntry> steps;

  List<ContentEntry> entries(String section) => sections[section]!;
  ContentEntry find(String section, String id) =>
      entries(section).firstWhere((entry) => entry.id == id);
  String label(String section, String id) {
    for (final entry in entries(section)) {
      if (entry.id == id) return entry.name;
    }
    return id;
  }

  Map<String, JobDefinition> get sharedJobs => Map.unmodifiable({
    for (final job in entries('jobs'))
      job.id: JobDefinition(
        id: job.id,
        abilityIds: job.strings('abilityIds').toSet(),
      ),
  });
  Map<String, ItemDefinition> get sharedItems => Map.unmodifiable({
    for (final item in entries('items')) item.id: ItemDefinition(id: item.id),
  });

  factory DemoContent.decode(String source) {
    final root = _object(jsonDecode(source), 'content');
    _keys(root, {
      'schemaVersion',
      'contentVersion',
      'title',
      'premise',
      ..._schemas.keys,
      'flags',
      'quest',
    }, 'content');
    if (root['schemaVersion'] != 1) {
      throw const FormatException('Unsupported content schemaVersion');
    }
    final version = _text(root['contentVersion'], 'contentVersion');
    final title = _text(root['title'], 'title');
    final premise = _text(root['premise'], 'premise');
    final sections = <String, List<ContentEntry>>{};
    final ids = <String>{};
    for (final schema in _schemas.entries) {
      final rows = _list(root[schema.key], schema.key);
      if (rows.isEmpty) throw FormatException('${schema.key} cannot be empty');
      sections[schema.key] = List.unmodifiable(
        rows.map((value) {
          final row = _object(value, schema.key);
          _keys(row, schema.value.keys.toSet(), schema.key);
          final checked = <String, Object?>{};
          for (final field in schema.value.entries) {
            final v = row[field.key];
            final path = '${schema.key}.${field.key}';
            checked[field.key] = switch (field.value) {
              'text' => _text(v, path),
              'optional' => v == null ? null : _text(v, path),
              'list' => List<String>.unmodifiable(
                _list(v, path).map((e) => _text(e, path)),
              ),
              'positive' =>
                v is int && v > 0
                    ? v
                    : throw FormatException('$path must be a positive integer'),
              _ => throw StateError('Unknown schema field'),
            };
          }
          final id = checked['id']! as String;
          _id(id);
          if (!ids.add(id)) throw FormatException('Duplicate ID: $id');
          return ContentEntry._(checked);
        }),
      );
    }
    final flagList = _list(
      root['flags'],
      'flags',
    ).map((e) => _text(e, 'flag')).toList();
    for (final flag in flagList) {
      _id(flag);
      if (!ids.add(flag)) throw FormatException('Duplicate ID: $flag');
    }
    final quest = _object(root['quest'], 'quest');
    _keys(quest, {'id', 'name', 'steps'}, 'quest');
    final questId = _text(quest['id'], 'quest.id');
    _id(questId);
    if (!ids.add(questId)) throw FormatException('Duplicate ID: $questId');
    final steps = <ContentEntry>[];
    for (final value in _list(quest['steps'], 'quest.steps')) {
      final row = _object(value, 'step');
      _keys(row, {
        'id',
        'mapId',
        'dialogueId',
        'requiresFlags',
        'setsFlag',
        'enemyId',
      }, 'step');
      final checked = <String, Object?>{};
      for (final key in ['id', 'mapId', 'dialogueId']) {
        checked[key] = _text(row[key], 'step.$key');
      }
      for (final key in ['setsFlag', 'enemyId']) {
        checked[key] = row[key] == null ? null : _text(row[key], 'step.$key');
      }
      checked['requiresFlags'] = List<String>.unmodifiable(
        _list(
          row['requiresFlags'],
          'requiresFlags',
        ).map((e) => _text(e, 'flag')),
      );
      final id = checked['id']! as String;
      _id(id);
      if (!ids.add(id)) throw FormatException('Duplicate ID: $id');
      steps.add(ContentEntry._(checked));
    }
    final content = DemoContent._(
      version,
      title,
      premise,
      Map.unmodifiable(sections),
      Set.unmodifiable(flagList),
      questId,
      _text(quest['name'], 'quest.name'),
      List.unmodifiable(steps),
    );
    content._validate();
    return content;
  }

  void _validate() {
    void ref(String section, String id, String owner) {
      if (!entries(section).any((e) => e.id == id)) {
        throw FormatException('$owner references unknown $section ID: $id');
      }
    }

    void refs(ContentEntry e, String field, String section) {
      final values = e.strings(field);
      if (values.toSet().length != values.length) {
        throw FormatException('${e.id} has duplicate $field');
      }
      for (final id in values) {
        ref(section, id, e.id);
      }
    }

    void choice(ContentEntry e, String field, Set<String> choices) {
      if (!choices.contains(e.text(field))) {
        throw FormatException('${e.id}: invalid $field');
      }
    }

    if (entries('heroes').length != 4 || entries('jobs').length != 4) {
      throw const FormatException('Four heroes and four jobs are required');
    }
    for (final e in entries('heroes')) {
      ref('jobs', e.text('jobId'), e.id);
    }
    for (final e in entries('jobs')) {
      refs(e, 'abilityIds', 'spells');
      refs(e, 'equipmentIds', 'items');
      for (final id in e.strings('equipmentIds')) {
        if (find('items', id).text('kind') == 'consumable') {
          throw FormatException('${e.id}: consumable in equipment list');
        }
      }
    }
    for (final e in entries('items')) {
      choice(e, 'kind', {'consumable', 'weapon', 'armor'});
      final expected = switch (e.text('kind')) {
        'weapon' => 'weapon',
        'armor' => 'body',
        _ => null,
      };
      if (e.optionalText('slotId') != expected) {
        throw FormatException('${e.id}: wrong equipment slot');
      }
    }
    for (final e in entries('spells')) {
      choice(e, 'target', {'ally', 'enemy'});
      choice(e, 'element', {'restoration', 'fire', 'water'});
    }
    for (final e in entries('enemies')) {
      choice(e, 'kind', {'regular', 'boss'});
      refs(e, 'spellIds', 'spells');
    }
    if (entries('enemies').where((e) => e.text('kind') == 'regular').length !=
            3 ||
        entries('enemies').where((e) => e.text('kind') == 'boss').length != 1) {
      throw const FormatException(
        'Three regular enemies and one boss required',
      );
    }
    for (final e in entries('maps')) {
      refs(e, 'exitIds', 'maps');
      refs(e, 'enemyIds', 'enemies');
      refs(e, 'dialogueIds', 'dialogues');
      for (final id in e.strings('exitIds')) {
        if (!find('maps', id).strings('exitIds').contains(e.id)) {
          throw FormatException('${e.id}: exit $id has no return route');
        }
      }
    }
    for (final e in entries('npcs')) {
      ref('maps', e.text('mapId'), e.id);
      ref('dialogues', e.text('dialogueId'), e.id);
      if (!find(
        'maps',
        e.text('mapId'),
      ).strings('dialogueIds').contains(e.text('dialogueId'))) {
        throw FormatException('${e.id}: dialogue missing from map');
      }
    }
    final speakers = {
      ...entries('heroes').map((e) => e.id),
      ...entries('npcs').map((e) => e.id),
    };
    for (final e in entries('dialogues')) {
      if (!speakers.contains(e.text('speakerId')) ||
          e.strings('lines').isEmpty) {
        throw FormatException('${e.id}: invalid speaker or empty dialogue');
      }
    }
    for (final e in entries('chests')) {
      ref('maps', e.text('mapId'), e.id);
      ref('items', e.text('itemId'), e.id);
    }
    for (final e in entries('restPoints')) {
      ref('maps', e.text('mapId'), e.id);
    }
    if (steps.isEmpty) throw const FormatException('Quest has no steps');
    final produced = <String>{};
    String? previousMap;
    for (final e in steps) {
      final mapId = e.text('mapId');
      ref('maps', mapId, e.id);
      ref('dialogues', e.text('dialogueId'), e.id);
      final map = find('maps', mapId);
      if (!map.strings('dialogueIds').contains(e.text('dialogueId'))) {
        throw FormatException('${e.id}: dialogue is not on this map');
      }
      // Later steps may return through multiple previously visited maps.
      if (previousMap != null && !_reachable(previousMap, mapId)) {
        throw FormatException('${e.id}: unreachable map');
      }
      previousMap = mapId;
      for (final flag in e.strings('requiresFlags')) {
        if (!flags.contains(flag) || !produced.contains(flag)) {
          throw FormatException(
            '${e.id}: flag $flag is unknown or not yet produced',
          );
        }
      }
      final set = e.optionalText('setsFlag');
      if (set != null && (!flags.contains(set) || !produced.add(set))) {
        throw FormatException('${e.id}: unknown or repeated flag $set');
      }
      final enemy = e.optionalText('enemyId');
      if (enemy != null) {
        ref('enemies', enemy, e.id);
        if (!map.strings('enemyIds').contains(enemy)) {
          throw FormatException('${e.id}: enemy is not on this map');
        }
      }
    }
    if (!produced.containsAll(flags)) {
      throw const FormatException('Unreachable quest flags');
    }
  }

  bool _reachable(String start, String goal) {
    final pending = [start];
    final seen = <String>{};
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (id == goal) return true;
      if (seen.add(id)) pending.addAll(find('maps', id).strings('exitIds'));
    }
    return false;
  }
}

Map<String, Object?> _object(Object? value, String path) {
  if (value is! Map<String, dynamic>) {
    throw FormatException('$path must be an object');
  }
  return value.cast<String, Object?>();
}

List<dynamic> _list(Object? value, String path) {
  if (value is! List) throw FormatException('$path must be a list');
  return value;
}

String _text(Object? value, String path) {
  if (value is! String || value.trim().isEmpty || value != value.trim()) {
    throw FormatException('$path must be nonempty, trimmed text');
  }
  return value;
}

void _keys(Map<String, Object?> value, Set<String> keys, String path) {
  if (value.keys.toSet().difference(keys).isNotEmpty ||
      keys.difference(value.keys.toSet()).isNotEmpty) {
    throw FormatException('$path: unexpected or missing fields');
  }
}

void _id(String id) {
  if (!RegExp(r'^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*)+$').hasMatch(id)) {
    throw FormatException('Invalid stable ID: $id');
  }
}

const _named = {'id': 'text', 'name': 'text', 'description': 'text'};
const _schemas = {
  'heroes': {..._named, 'jobId': 'text'},
  'jobs': {..._named, 'abilityIds': 'list', 'equipmentIds': 'list'},
  'items': {..._named, 'kind': 'text', 'slotId': 'optional'},
  'spells': {..._named, 'target': 'text', 'element': 'text'},
  'enemies': {..._named, 'kind': 'text', 'spellIds': 'list', 'tactic': 'text'},
  'maps': {
    ..._named,
    'exitIds': 'list',
    'enemyIds': 'list',
    'dialogueIds': 'list',
  },
  'npcs': {..._named, 'mapId': 'text', 'dialogueId': 'text'},
  'dialogues': {'id': 'text', 'speakerId': 'text', 'lines': 'list'},
  'chests': {
    'id': 'text',
    'mapId': 'text',
    'itemId': 'text',
    'quantity': 'positive',
  },
  'restPoints': {..._named, 'mapId': 'text'},
};
