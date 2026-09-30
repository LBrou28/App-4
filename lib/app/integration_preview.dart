import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../battle/battle.dart' as combat;
import '../battle/combat_rules.dart';
import '../battle/battle_session.dart';
import '../battle/demo/main.dart' show createBattleDemoSession;
import '../core/contracts.dart';
import '../ui/content/demo_content.dart';
import '../world/interaction_world.dart';
import '../world/world_view.dart';
import '../save/local_save_repository.dart';
import 'game_app.dart';

/// Reuses Joseph's training roster/stats, not a new production balance source.
/// The actual party HP comes from A's current snapshot. No rewards are granted.
BattleSession createTrainingBattle(BattleInput input) {
  final template = createBattleDemoSession();
  return BattleSession(
    input: input,
    heroStats: {
      for (final actor in template.snapshot.combatants)
        if (actor.side == combat.BattleSide.heroes)
          actor.id: CombatStats(
            attack: actor.attack,
            defense: actor.defense,
            speed: actor.speed,
          ),
    },
    enemies: template.snapshot.combatants
        .where((actor) => actor.side == combat.BattleSide.enemies)
        .toList(),
    fleePolicy: template.fleePolicy,
  );
}

/// Builds the campaign encounter adapter from the approved C3/D4 content IDs.
///
/// The preview still starts with A's fixture party, so members whose job is
/// not yet a content job are assigned the matching authored job by party
/// position. Once C4 replaces the fixture party, its job IDs are used
/// directly. C5 can tune the provisional numbers without changing this
/// registration contract.
BattleSession createLanternProductionBattle(
  BattleInput input,
  DemoContent content,
) {
  final heroes = content.entries('heroes');
  final jobs = content.sharedJobs;
  final heroSpells = <String, Set<String>>{};
  final heroStats = <String, CombatStats>{};
  for (var i = 0; i < input.state.party.length; i++) {
    final member = input.state.party[i];
    final authoredJobId = jobs.containsKey(member.jobId)
        ? member.jobId
        : heroes[i % heroes.length].text('jobId');
    heroSpells[member.id] = jobs[authoredJobId]!.abilityIds;
    heroStats[member.id] = const CombatStats(attack: 7, defense: 2, speed: 10);
  }

  final map = content.find('maps', input.state.position.mapId);
  final definition = input.request.definitionId;
  final enemyId = definition.endsWith('.boss')
      ? 'enemy.hollow_bell'
      : map.strings('enemyIds').firstOrNull ?? 'enemy.wick_moth';
  final enemy = content.find('enemies', enemyId);
  final boss = enemy.text('kind') == 'boss';
  final stats = switch (enemyId) {
    'enemy.brine_mite' => (hp: 32, attack: 6, defense: 2, speed: 5, mp: 0),
    'enemy.wick_moth' => (hp: 45, attack: 5, defense: 2, speed: 7, mp: 6),
    'enemy.silt_guard' => (hp: 70, attack: 8, defense: 6, speed: 3, mp: 0),
    'enemy.hollow_bell' => (hp: 100, attack: 10, defense: 5, speed: 4, mp: 6),
    _ => throw StateError('No C3 stats registered for $enemyId'),
  };
  return BattleSession(
    input: input,
    rules: lanternCombatRules(),
    heroStats: heroStats,
    heroSpells: heroSpells,
    enemies: [
      combat.Combatant(
        // Keep the authored definition ID for pattern lookup, but give this
        // encounter instance its own ID for result correlation.
        id: '${enemy.id}@${input.encounterId}',
        side: combat.BattleSide.enemies,
        hp: stats.hp,
        maxHp: stats.hp,
        attack: stats.attack,
        defense: stats.defense,
        speed: stats.speed,
        mp: stats.mp,
        maxMp: stats.mp,
        spellIds: enemy.strings('spellIds').toSet(),
        pattern: lanternEnemyPatterns[enemy.id]!,
        isBoss: boss,
      ),
    ],
  );
}

/// Connected B/A/C/D preview using the registered C3 encounter adapter.
Widget buildIntegrationPreview({SaveRepository? saves}) {
  late InteractionWorld world;
  late DemoContent content;
  return GameApp(
    title: 'App-4 • Integration preview',
    introduction: 'Explore three connected areas. Face an NPC or chest and press E or Interact.\n\nLantern encounters use the registered C3 rules and authored spell/enemy IDs. Pause while exploring to save your journey.',
    saves: saves ?? LocalSaveRepository(),
    battles: {
      'fixture.battle': (input) =>
          createLanternProductionBattle(input, content),
      'fixture.battle.boss': (input) =>
          createLanternProductionBattle(input, content),
    },
    trainingEncounterId: 'fixture.battle',
    battleTitle: 'Lantern encounter',
    battleNames: const {
      'fixture.hero.0': 'Ash',
      'fixture.hero.1': 'Mira',
      'fixture.hero.2': 'Rowan',
      'fixture.hero.3': 'Wren',
      'enemy.brine_mite': 'Brine Mite',
      'enemy.wick_moth': 'Wick Moth',
      'enemy.silt_guard': 'Silt Guard',
      'enemy.hollow_bell': 'The Hollow Bell',
    },
    loadWorld: () async {
      content = DemoContent.decode(
        await rootBundle.loadString('assets/data/lantern_wake.json'),
      );
      world = InteractionWorld(content);
      return world.session();
    },
    buildWorld: (map) =>
        (context, host, changes) => WorldView(
          map: map,
          host: host,
          changes: changes,
          interactions: world.targets,
          landmarks: world.landmarks,
          mapName: world.names[map.id],
        ),
  );
}
