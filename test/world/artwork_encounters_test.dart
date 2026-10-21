import 'dart:io';

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/integration_preview.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/battle/battle_session.dart';
import 'package:app_4/battle/lantern_balance.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/world/artwork_encounters.dart';
import 'package:app_4/world/artwork_world.dart';
import 'package:app_4/world/interaction_world.dart';
import 'package:app_4/world/world_controller.dart';
import 'package:app_4/world/world_encounters.dart';
import 'package:app_4/world/world_map.dart';
import 'package:flutter_test/flutter_test.dart';

class HitRandom implements EncounterRandom {
  HitRandom({this.enemy = 0, this.hit = true});
  final int enemy;
  final bool hit;
  int rolls = 0;
  @override
  int nextInt(int max) {
    if (max == 5) {
      rolls++;
      return hit ? 0 : 4;
    }
    return enemy % max;
  }
}

class MemorySave implements SaveRepository {
  SaveData? data;
  @override
  Future<LoadResult> load() async =>
      data == null ? SaveMissing() : SaveLoaded(data!);
  @override
  Future<WriteResult> save(SaveData value) async {
    data = value;
    return SaveWritten();
  }
}

void win(BattleSession session) {
  for (var i = 0; i < 500 && session.result == null; i++) {
    final enemy = session.snapshot.combatants.firstWhere(
      (e) => e.side == combat.BattleSide.enemies && e.isAlive,
    );
    session.resolve(session.snapshot.round, [
      for (final hero in session.snapshot.combatants)
        if (hero.side == combat.BattleSide.heroes && hero.isAlive)
          combat.HeroCommand.attack(hero.id, enemy.id),
    ]);
  }
  expect(session.result!.outcome, BattleOutcome.victory);
}

void main() {
  late DemoContent content;
  late InteractionWorld world;
  late ArtworkWorld art;
  setUp(() {
    content = DemoContent.decode(
      File('assets/data/lantern_wake.json').readAsStringSync(),
    );
    world = InteractionWorld(content, useArtwork: true);
    art = world.artwork!;
  });

  WorldPosition at(String map, double x, double y) =>
      ArtworkWorld.scenes[map]!.position(Offset(x, y));

  Future<AppController> host(
    WorldPosition start, {
    MemorySave? saves,
    GameState? state,
  }) async {
    final balance = LanternBalance();
    final c = AppController(
      loadWorld: () async => world.session(
        restored: state ?? createLanternInitialState(content, start),
      ),
      saves: saves,
      battles: {
        for (final id in LanternBalance.encounters.keys)
          id: balance.createSession,
      },
    );
    addTearDown(c.dispose);
    await c.newGame();
    return c;
  }

  test(
    'harbor, camp, interactions, exits, spawns and boss chamber are safe',
    () async {
      final points = <WorldPosition>[
        at(ArtworkWorld.town, 650, 650),
        for (final map in art.maps.values) ...map.spawns.values,
        for (final target in art.targets.targets)
          WorldPosition(
            mapId: target.mapId,
            x: target.x + .5,
            y: target.y + .5,
          ),
        at(ArtworkWorld.route, 420, 740),
        at(ArtworkWorld.dungeon, 180, 675),
        at(ArtworkWorld.dungeon, 620, 310),
      ];
      final random = HitRandom();
      final policy = artworkEncounters(art, random: random);
      for (final point in points) {
        expect(
          policy.canEncounter!(point),
          isFalse,
          reason: '${point.mapId} ${point.x},${point.y}',
        );
      }
      final c = await host(art.maps[ArtworkWorld.town]!.spawns['entry']!);
      for (var i = 0; i < 100; i++) {
        expect(policy.recordAcceptedStep(c), isFalse);
      }
      expect(random.rolls, 0);
      expect(c.activeBattle, isNull);
    },
  );

  test(
    'walkable grass rolls authored causeway enemies; dungeon excludes boss',
    () async {
      // Both points are solid grass beside a path, covered by the reviewed geometry.
      for (final (map, pixel, enemy) in [
        (ArtworkWorld.route, const Offset(650, 1080), 'enemy.wick_moth'),
        (ArtworkWorld.dungeon, const Offset(300, 480), 'enemy.silt_guard'),
      ]) {
        final p = at(map, pixel.dx, pixel.dy);
        expect(art.isClear(p, {}), isTrue);
        final c = await host(p);
        final random = HitRandom(enemy: 1);
        final policy = artworkEncounters(art, random: random);
        for (var i = 0; i < 3; i++) {
          expect(policy.recordAcceptedStep(c), isFalse);
        }
        expect(policy.recordAcceptedStep(c), isTrue);
        expect(c.activeBattle!.input.request.definitionId, enemy);
        expect(c.activeBattle!.isBoss, isFalse);
        expect(policy.recordAcceptedStep(c), isFalse);
        expect(random.rolls, 1);
      }
    },
  );

  test(
    '64px spacing is frame independent; pause, idle and walls never roll',
    () async {
      for (final fps in [30, 60, 120]) {
        final c = await host(at(ArtworkWorld.route, 615, 1040));
        final random = HitRandom(hit: false);
        final policy = artworkEncounters(art, random: random);
        final movement = WorldController(
          host: c,
          collision: art.collision(ArtworkWorld.route),
          encounters: policy,
          speed: 14,
        );
        for (var i = 0; i < fps; i++) {
          movement.advance(1 / fps);
        }
        expect(random.rolls, 0);
        movement.press('up', WalkDirection.up);
        for (var i = 0; i < fps * 3; i++) {
          movement.advance(1 / fps);
        }
        expect(random.rolls, 2, reason: '$fps FPS');
        c.setPaused(true);
        for (var i = 0; i < fps * 5; i++) {
          movement.advance(1 / fps);
        }
        c.setPaused(false);
        expect(movement.advance(.1), isFalse);
        expect(random.rolls, 2);
        movement.press('left', WalkDirection.left);
        for (var i = 0; i < 50; i++) {
          movement.advance(.1);
        }
        final before = random.rolls;
        for (var i = 0; i < 100; i++) {
          movement.advance(.1);
        }
        expect(random.rolls, before);
      }
    },
  );

  test('victory pays once, enforces cooldown and retains rewards with load grace', () async {
    final saves = MemorySave();
    final c = await host(at(ArtworkWorld.route, 615, 1000), saves: saves);
    final random = HitRandom();
    final policy = artworkEncounters(art, random: random);
    for (var i = 0; i < 4; i++) {
      policy.recordAcceptedStep(c);
    }
    final captured = c.state.position;
    final session = c.activeBattle!;
    win(session);
    final result = session.result!;
    expect(c.acceptBattleResult(result), isTrue);
    expect(c.acceptBattleResult(result), isFalse);
    expect(c.state.position, captured);
    expect(c.state.gold, 8);
    expect(c.state.party.every((p) => p.experience == 24), isTrue);
    for (var i = 0; i < 6; i++) {
      expect(policy.recordAcceptedStep(c), isFalse);
    }
    expect(random.rolls, 1);
    c.setPaused(true);
    expect(await c.saveCurrent(), isA<SaveWritten>());
    c.returnToTitle();
    expect(await c.continueGame(), isA<SaveLoaded>());
    expect(c.state.position, captured);
    expect(c.state.gold, 8);
    expect(c.activeBattle, isNull);
    // Main creates a new policy in its loader; every Continue gets entry grace.
    final reloaded = artworkEncounters(art, random: random);
    for (var i = 0; i < 3; i++) {
      expect(reloaded.recordAcceptedStep(c), isFalse);
    }
    expect(random.rolls, 1);
    expect(reloaded.recordAcceptedStep(c), isTrue);
  });

  test(
    'production flee returns without rewards; defeat stays game-over and gated',
    () async {
      for (final defeat in [false, true]) {
        final c = await host(at(ArtworkWorld.dungeon, 300, 480));
        final policy = artworkEncounters(art, random: HitRandom());
        for (var i = 0; i < 4; i++) {
          policy.recordAcceptedStep(c);
        }
        final captured = c.state.position;
        final session = c.activeBattle!;
        if (defeat) {
          for (var i = 0; i < 500 && session.result == null; i++) {
            session.resolve(session.snapshot.round, [
              for (final hero in session.snapshot.combatants)
                if (hero.side == combat.BattleSide.heroes && hero.isAlive)
                  combat.HeroCommand.defend(hero.id),
            ]);
          }
          expect(session.result!.outcome, BattleOutcome.defeat);
        } else {
          for (var i = 0; i < 10 && session.result == null; i++) {
            await session.flee();
          }
          expect(session.result!.outcome, BattleOutcome.fled);
        }
        final result = session.result!;
        expect(c.acceptBattleResult(result), isTrue);
        expect(c.acceptBattleResult(result), isFalse);
        expect(c.state.position, captured);
        expect(c.state.gold, 0);
        expect(c.state.party.every((p) => p.experience == 0), isTrue);
        expect(c.mode, defeat ? AppMode.gameOver : AppMode.exploration);
        for (var i = 0; i < 6; i++) {
          expect(policy.recordAcceptedStep(c), isFalse);
        }
      }
    },
  );
  test('walking the northwest detour triggers fights; transitions take priority and grant grace', () async {
    final spawn = art.maps[ArtworkWorld.dungeon]!.spawns['entry']!;
    final start = WorldPosition(
      mapId: spawn.mapId,
      x: spawn.x.floor() + .5,
      y: spawn.y.floor() + .5,
    );
    final c = await host(start);
    final random = HitRandom();
    final policy = artworkEncounters(art, random: random);
    final collision = art.collision(ArtworkWorld.dungeon);
    final valve = art.targets.targets.singleWhere(
      (t) => t.id == 'quest.cistern.valve',
    );
    final pending = [(start.x.floor(), start.y.floor())];
    final previous = <(int, int), (int, int)?>{pending.single: null};
    (int, int)? goal;
    for (var i = 0; i < pending.length; i++) {
      final tile = pending[i];
      final p = WorldPosition(
        mapId: spawn.mapId,
        x: tile.$1 + .5,
        y: tile.$2 + .5,
      );
      if (valve.reachable(p)) {
        goal = tile;
        break;
      }
      for (final (dx, dy) in [(0, -1), (0, 1), (-1, 0), (1, 0)]) {
        final next = (tile.$1 + dx, tile.$2 + dy);
        if (previous.containsKey(next) ||
            !collision.isClear(
              WorldPosition(
                mapId: spawn.mapId,
                x: next.$1 + .5,
                y: next.$2 + .5,
              ),
            )) {
          continue;
        }
        previous[next] = tile;
        pending.add(next);
      }
    }
    expect(goal, isNotNull);
    final route = <(int, int)>[];
    for (var tile = goal!; previous[tile] != null; tile = previous[tile]!) {
      route.add(tile);
    }
    final movement = WorldController(
      host: c,
      collision: collision,
      encounters: policy,
      speed: 10,
    );
    c.addListener(movement.synchronize);
    var fights = 0;
    for (final tile in route.reversed) {
      final p = c.state.position;
      final dx = tile.$1 + .5 - p.x, dy = tile.$2 + .5 - p.y;
      final direction = dx.abs() > dy.abs()
          ? (dx > 0 ? WalkDirection.right : WalkDirection.left)
          : (dy > 0 ? WalkDirection.down : WalkDirection.up);
      movement.press('walk', direction);
      expect(movement.advance(.1), isTrue);
      if (c.activeBattle != null) {
        fights++;
        expect(c.activeBattle!.input.request.definitionId, 'enemy.silt_guard');
        win(c.activeBattle!);
        expect(c.acceptBattleResult(c.activeBattle!.result!), isTrue);
        expect(
          movement.advance(.1),
          isFalse,
          reason: 'Battle return cannot replay held walking',
        );
      }
    }
    expect(fights, greaterThan(0));
    expect(valve.reachable(c.state.position), isTrue);
    expect(c.state.quests.flags, isNot(contains('quest.lantern.bell_awake')));

    final routeHost = await host(at(ArtworkWorld.route, 612, 1220));
    final exitMovement = WorldController(
      host: routeHost,
      collision: art.collision(ArtworkWorld.route),
      interactions: art.targets,
      encounters: policy,
      speed: 14,
    );
    exitMovement.press('down', WalkDirection.down);
    expect(exitMovement.advance(.1), isTrue);
    expect(routeHost.state.position.mapId, ArtworkWorld.town);
    expect(routeHost.activeBattle, isNull);
    final before = random.rolls;
    policy.enterMap(ArtworkWorld.town);
    policy.enterMap(ArtworkWorld.route);
    expect(policy.remainingCooldown, greaterThanOrEqualTo(3));
    expect(random.rolls, before);
  });
}
