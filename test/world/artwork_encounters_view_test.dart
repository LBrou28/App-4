import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/integration_preview.dart';
import 'package:app_4/battle/ui/battle_screen.dart';
import 'package:app_4/battle/battle.dart' as combat;
import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/sprite_art.dart';
import 'package:app_4/world/artwork_world.dart';
import 'package:app_4/world/world_encounters.dart';
import 'package:app_4/world/world_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class HitRandom implements EncounterRandom {
  int calls = 0;
  @override
  int nextInt(int max) {
    calls++;
    return 0;
  }
}

class NoSave implements SaveRepository {
  @override
  Future<LoadResult> load() async => SaveMissing();
  @override
  Future<WriteResult> save(SaveData data) async => SaveWritten();
}

void main() {
  testWidgets(
    'main walking launches its production encounter and keeps the same cooldown after battle',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1280, 720);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final boundary = GlobalKey();
      final random = HitRandom();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: buildIntegrationPreview(
            saves: NoSave(),
            encounterRandom: random,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('New Game'));
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final view = tester.widget<WorldView>(find.byType(WorldView));
      final host = view.host as AppController;
      final art = view.artwork!;
      final policy = view.encounters!;
      expect(
        host.updatePosition(
          ArtworkWorld.scenes[ArtworkWorld.town]!.position(
            const ui.Offset(596, 20),
          ),
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      expect(
        host.useMapExit(
          'exit.harbor_to_causeway',
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      await tester.pump();
      final routeView = tester.widget<WorldView>(find.byType(WorldView));
      expect(routeView.encounters, same(policy));
      expect(host.activeBattle, isNull);
      // Start on a clear portion of the trail; subsequent movement uses the real
      // keyboard handler/ticker, rather than manually requesting a battle.
      expect(
        host.updatePosition(
          ArtworkWorld.scenes[ArtworkWorld.route]!.position(
            const ui.Offset(615, 1040),
          ),
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      for (var i = 0; i < 50 && host.activeBattle == null; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      expect(host.activeBattle!.input.request.definitionId, 'enemy.brine_mite');
      expect(host.activeBattle!.input.state.position.mapId, ArtworkWorld.route);
      await tester.pump();
      final battle = tester.widget<BattleScreen>(find.byType(BattleScreen));
      expect(battle.session, same(host.activeBattle));
      expect(
        tester.widget<EncounterArtwork>(find.byType(EncounterArtwork)).enemyId,
        'enemy.brine_mite',
      );
      expect(find.byType(ExplorationHeroSprite), findsNothing);
      if (const bool.fromEnvironment('ENCOUNTER_CAPTURE')) {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': const String.fromEnvironment('MAP_TEXT_FONT'),
            'MaterialIcons': const String.fromEnvironment('MAP_ICON_FONT'),
          }.entries) {
            if (entry.value.isEmpty) continue;
            await (FontLoader(entry.key)..addFont(
                  Future.value(
                    (await File(entry.value).readAsBytes()).buffer.asByteData(),
                  ),
                ))
                .load();
          }
        });
        await tester.pumpAndSettle();
        final painter =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await painter.toImage(pixelRatio: 1);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('docs/evidence/b3-walking-encounter.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
      final session = host.activeBattle!;
      for (var i = 0; i < 20 && session.result == null; i++) {
        session.resolve(session.snapshot.round, [
          for (final hero in session.snapshot.combatants)
            if (hero.side == combat.BattleSide.heroes && hero.isAlive)
              combat.HeroCommand.attack(hero.id, 'enemy.brine_mite'),
        ]);
      }
      battle.onCompleted(session.result!);
      await tester.pump();
      expect(
        tester.widget<WorldView>(find.byType(WorldView)).encounters,
        same(policy),
      );
      expect(policy.remainingCooldown, 6);
      final rolls = random.calls;
      await tester.pump(const Duration(seconds: 1));
      expect(host.activeBattle, isNull);
      expect(random.calls, rolls);
      expect(art.isClear(host.state.position, {}), isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'every campaign enemy selects one sprite; unknown IDs never display the concept sheet',
    (tester) async {
      for (final id in EncounterArtwork.regions.keys) {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 180,
                height: 156,
                child: EncounterArtwork(enemyId: id),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final image = tester.widget<Image>(find.byType(Image));
        expect(
          (image.image as AssetImage).assetName,
          id == 'enemy.hollow_bell'
              ? SpriteAssets.battleBoss
              : SpriteAssets.battleEnemies,
        );
        expect(image.filterQuality, FilterQuality.none);
        expect(find.byType(ClipRect), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(
        const MaterialApp(home: EncounterArtwork(enemyId: 'fixture.enemy.0')),
      );
      expect(find.byType(Image), findsNothing);
      expect(find.byIcon(Icons.pest_control), findsOneWidget);
    },
  );

  test(
    'sprite cutouts have transparent edges instead of a rectangular background',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      for (final asset in [
        SpriteAssets.battleEnemies,
        SpriteAssets.battleBoss,
      ]) {
        final data = await rootBundle.load(asset);
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
        final image = (await codec.getNextFrame()).image;
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        for (final pixel in [
          0,
          image.width - 1,
          (image.height - 1) * image.width,
          image.height * image.width - 1,
        ]) {
          expect(rgba[pixel * 4 + 3], 0, reason: asset);
        }
        image.dispose();
        codec.dispose();
      }
    },
  );
}
