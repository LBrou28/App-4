import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../battle/battle.dart' as combat;
import '../battle/battle_session.dart';
import '../battle/demo/main.dart' show createBattleDemoSession;
import '../core/contracts.dart';
import '../ui/content/demo_content.dart';
import '../world/interaction_world.dart';
import '../world/world_view.dart';
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

/// Connected B/A/C/D preview. Authored encounter tables are still a C/B handoff.
Widget buildIntegrationPreview() {
  late InteractionWorld world;
  return GameApp(
    title: 'App-4 • Integration preview',
    introduction: 'Explore three connected areas. Face an NPC or chest and press E or Interact.\n\nTraining battle uses temporary combat stats, grants no rewards and always allows escape. Progress is not saved.',
    battles: {'fixture.battle': createTrainingBattle},
    trainingEncounterId: 'fixture.battle',
    battleTitle: 'Training encounter',
    battleNames: const {
      'fixture.hero.0': 'Ash',
      'fixture.hero.1': 'Mira',
      'fixture.hero.2': 'Rowan',
      'fixture.hero.3': 'Wren',
      'fixture.enemy.0': 'Bramble crawler',
      'fixture.enemy.1': 'Moss beetle',
    },
    loadWorld: () async {
      world = InteractionWorld(
        DemoContent.decode(
          await rootBundle.loadString('assets/data/lantern_wake.json'),
        ),
      );
      return world.session();
    },
    buildWorld: (map) =>
        (context, host, changes) => WorldView(
          map: map,
          host: host,
          changes: changes,
          interactions: world.targets,
          mapName: world.names[map.id],
        ),
  );
}
