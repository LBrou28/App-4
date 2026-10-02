import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../battle/battle.dart' as combat;
import '../battle/battle_session.dart';
import '../battle/demo/main.dart' show createBattleDemoSession;
import '../battle/lantern_balance.dart';
import '../core/contracts.dart';
import '../progression.dart';
import '../ui/content/demo_content.dart';
import '../world/interaction_world.dart';
import '../world/world_view.dart';
import '../save/local_save_repository.dart';
import 'game_app.dart';

/// Reuses Joseph's training roster/stats, not a new production balance source.
/// The actual party HP comes from A's current snapshot. No rewards are granted.
BattleSession createTrainingBattle(BattleInput input) {
  final template = createBattleDemoSession();
  final heroes = template.snapshot.combatants
      .where((actor) => actor.side == combat.BattleSide.heroes)
      .toList();
  return BattleSession(
    input: input,
    heroStats: {
      for (var index = 0; index < input.state.party.length; index++)
        input.state.party[index].id: CombatStats(
          attack: heroes[index].attack,
          defense: heroes[index].defense,
          speed: heroes[index].speed,
        ),
    },
    enemies: template.snapshot.combatants
        .where((actor) => actor.side == combat.BattleSide.enemies)
        .toList(),
    fleePolicy: template.fleePolicy,
  );
}

/// Builds the persisted campaign state from D's authored hero/job IDs and C4's
/// production HP/MP rules. This is the identity baseline used to validate saves.
GameState createLanternInitialState(
  DemoContent content,
  WorldPosition position, {
  LanternJobRules? progression,
}) {
  final rules = progression ?? LanternJobRules();
  final heroes = content.entries('heroes');
  PartyMember member(ContentEntry hero) {
    final jobId = hero.text('jobId');
    final placeholder = PartyMember(
      id: hero.id,
      jobId: jobId,
      hp: 1,
      maxHp: 1,
      mp: 0,
      maxMp: 0,
      level: 1,
      experience: 0,
      jobProgress: {jobId: 0},
      equipment: {},
    );
    final profile = rules.profileFor(placeholder);
    return PartyMember(
      id: hero.id,
      jobId: jobId,
      hp: profile.maxHp,
      maxHp: profile.maxHp,
      mp: profile.maxMp,
      maxMp: profile.maxMp,
      level: 1,
      experience: 0,
      jobProgress: {jobId: 0},
      equipment: {},
    );
  }

  return GameState(
    position: position,
    party: heroes.map(member).toList(),
    inventory: Inventory({
      'item.salves': 2,
      'item.ether': 1,
      'item.revival': 1,
    }),
    gold: 0,
    quests: QuestFlags(flags: {}, openedChestIds: {}),
  );
}

/// Connected B/A/C/D preview using C4's party and C5's battle/reward rules.
Widget buildIntegrationPreview({SaveRepository? saves}) {
  late InteractionWorld world;
  final balance = LanternBalance();
  return GameApp(
    title: 'App-4 • Integration preview',
    introduction: 'Explore three connected areas. Face an NPC or chest and press E or Interact.\n\nLantern encounters use the registered C3 rules and authored spell/enemy IDs. Pause while exploring to save your journey.',
    saves: saves ?? LocalSaveRepository(),
    battles: {
      'fixture.battle': createTrainingBattle,
      for (final id in LanternBalance.encounters.keys)
        id: balance.createSession,
    },
    trainingEncounterId: 'fixture.battle',
    battleTitle: 'Lantern encounter',
    battleNames: const {
      'hero.ada': 'Ada',
      'hero.ren': 'Ren',
      'hero.iona': 'Iona',
      'hero.tavi': 'Tavi',
      'fixture.enemy.0': 'Bramble crawler',
      'fixture.enemy.1': 'Moss beetle',
      'enemy.brine_mite': 'Brine Mite',
      'enemy.wick_moth': 'Wick Moth',
      'enemy.silt_guard': 'Silt Guard',
      'enemy.hollow_bell': 'The Hollow Bell',
    },
    loadWorld: () async {
      final content = DemoContent.decode(
        await rootBundle.loadString('assets/data/lantern_wake.json'),
      );
      world = InteractionWorld(content, useArtwork: true);
      final entry = world.maps['map.bellwether']!.spawns['entry']!;
      return world.session(
        restored: createLanternInitialState(
          content,
          entry,
          progression: balance.progression,
        ),
      );
    },
    buildWorld: (map) =>
        (context, host, changes) => WorldView(
          map: map,
          host: host,
          changes: changes,
          interactions: world.targets,
          landmarks: world.landmarks,
          mapName: world.names[map.id],
          artwork: world.artwork,
        ),
  );
}
