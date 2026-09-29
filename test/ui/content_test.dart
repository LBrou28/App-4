import 'dart:convert';
import 'dart:io';

import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/ui/demo/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final source = File('assets/data/lantern_wake.json').readAsStringSync();
  Map<String, dynamic> data() => jsonDecode(source) as Map<String, dynamic>;
  test('complete quest content adapts to shared A1 job/item definitions', () {
    final content = DemoContent.decode(source);
    expect(content.entries('heroes').length, 4);
    expect(content.sharedJobs.length, 4);
    expect(content.entries('enemies').length, 4);
    final map = MapDefinition(
      id: 'map.bellwether',
      width: 3,
      height: 3,
      blocked: List.filled(9, false),
      spawns: {'entry': WorldPosition(mapId: 'map.bellwether', x: 1.5, y: 1.5)},
    );
    final catalog = ContentCatalog(
      maps: {map.id: map},
      jobs: content.sharedJobs,
      items: content.sharedItems,
    );
    expect(catalog.validate(previewState(content)), isEmpty);
    expect(
      content.steps.last.optionalText('setsFlag'),
      'quest.lantern.complete',
    );
    expect(() => content.entries('heroes').clear(), throwsUnsupportedError);
    expect(
      () =>
          content.find('jobs', 'job.white_mage').strings('abilityIds').clear(),
      throwsUnsupportedError,
    );
  });
  final mutations = <String, void Function(Map<String, dynamic>)>{
    'duplicate ID': (d) => d['heroes'][1]['id'] = d['heroes'][0]['id'],
    'missing field': (d) => d['jobs'][0].remove('abilityIds'),
    'unexpected field': (d) => d['spells'][0]['power'] = 10,
    'schema version': (d) => d['schemaVersion'] = 2,
    'untrimmed ID': (d) => d['heroes'][0]['id'] = ' hero.ada',
    'unknown job': (d) => d['heroes'][0]['jobId'] = 'job.missing',
    'unknown spell': (d) => d['jobs'][0]['abilityIds'] = ['spell.missing'],
    'unknown equipment': (d) => d['jobs'][0]['equipmentIds'] = ['item.missing'],
    'consumable equipment': (d) =>
        d['jobs'][0]['equipmentIds'] = ['item.salves'],
    'wrong slot': (d) => d['items'][0]['slotId'] = 'weapon',
    'bad target': (d) => d['spells'][0]['target'] = 'everyone',
    'unknown enemy spell': (d) =>
        d['enemies'][0]['spellIds'] = ['spell.missing'],
    'wrong boss count': (d) => d['enemies'][0]['kind'] = 'boss',
    'unknown map exit': (d) => d['maps'][0]['exitIds'] = ['map.missing'],
    'one way map exit': (d) => d['maps'][1]['exitIds'] = ['map.tide_cistern'],
    'unknown speaker': (d) => d['dialogues'][0]['speakerId'] = 'npc.missing',
    'empty dialogue': (d) => d['dialogues'][0]['lines'] = [],
    'empty line': (d) => d['dialogues'][0]['lines'] = [''],
    'invalid NPC map': (d) => d['npcs'][0]['mapId'] = 'map.missing',
    'invalid NPC dialogue': (d) => d['npcs'][0]['dialogueId'] = 'dialogue.jobs',
    'unknown chest reward': (d) => d['chests'][0]['itemId'] = 'item.missing',
    'negative reward': (d) => d['chests'][0]['quantity'] = -1,
    'fractional reward': (d) => d['chests'][0]['quantity'] = 1.5,
    'unknown rest map': (d) => d['restPoints'][0]['mapId'] = 'map.missing',
    'cyclic flags': (d) =>
        d['quest']['steps'][0]['requiresFlags'] = ['quest.lantern.complete'],
    'unknown set flag': (d) =>
        d['quest']['steps'][0]['setsFlag'] = 'quest.unknown',
    'wrong encounter location': (d) =>
        d['quest']['steps'][0]['enemyId'] = 'enemy.hollow_bell',
    'unknown quest dialogue': (d) =>
        d['quest']['steps'][0]['dialogueId'] = 'dialogue.missing',
    'empty quest': (d) => d['quest']['steps'] = [],
  };
  for (final mutation in mutations.entries) {
    test('rejects ${mutation.key}', () {
      final changed = data();
      mutation.value(changed);
      expect(
        () => DemoContent.decode(jsonEncode(changed)),
        throwsFormatException,
      );
    });
  }
}
