import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/app/app_controller.dart';
import 'package:app_4/app/integration_preview.dart';
import 'package:app_4/core/contracts.dart';
import 'package:app_4/ui/sprite_art.dart';
import 'package:app_4/world/artwork_world.dart';
import 'package:app_4/world/world_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class NoSave implements SaveRepository {
  @override
  Future<LoadResult> load() async => SaveMissing();
  @override
  Future<WriteResult> save(SaveData data) async => SaveWritten();
}

void main() {
  testWidgets(
    'main renders three maps, markers, sprites and durable open overlay',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      if (const bool.fromEnvironment('MAP_CAPTURE')) {
        await tester.runAsync(() async {
          for (final entry in {
            'Roboto': const String.fromEnvironment('MAP_TEXT_FONT'),
            'MaterialIcons': const String.fromEnvironment('MAP_ICON_FONT'),
          }.entries) {
            await (FontLoader(entry.key)..addFont(
                  Future.value(
                    (await File(entry.value).readAsBytes()).buffer.asByteData(),
                  ),
                ))
                .load();
          }
        });
      }
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: buildIntegrationPreview(saves: NoSave()),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('New Game'));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      final host =
          tester.widget<WorldView>(find.byType(WorldView)).host
              as AppController;
      final art = tester.widget<WorldView>(find.byType(WorldView)).artwork!;
      WorldPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('world-canvas')),
                  )
                  .painter!
              as WorldPainter;
      Future<void> loaded(String map) async {
        for (var i = 0; i < 30 && painter().background == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 20)),
          );
          await tester.pump();
        }
        expect(painter().scene!.id, map);
        expect(painter().background, isNotNull);
        expect(
          painter().background!.width,
          ArtworkWorld.scenes[map]!.size.width.toInt(),
        );
        expect(painter().drawPlayerBody, isFalse);
        expect(painter().hideTownNpcs, isTrue);
        expect(find.byType(ExplorationHeroSprite), findsOneWidget);
        if (map == ArtworkWorld.town) {
          expect(find.byType(BellwetherTownspersonSprite), findsNWidgets(2));
        } else {
          expect(find.byType(BellwetherTownspersonSprite), findsNothing);
        }
        expect(find.byType(ExplorationPartyArtwork), findsNothing);
        expect(tester.takeException(), isNull);
      }

      Future<void> capture(String name) async {
        if (!const bool.fromEnvironment('MAP_CAPTURE')) return;
        await tester.pump();
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('docs/evidence').create(recursive: true);
          await File('docs/evidence/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      Future<void> exit(String id) async {
        final target = art.targets.targets.firstWhere((t) => t.id == id);
        expect(
          host.updatePosition(
            WorldPosition(
              mapId: target.mapId,
              x: target.x + .5,
              y: target.y + .5,
            ),
            expectedRevision: host.revision,
          ),
          isTrue,
        );
        expect(host.useMapExit(id, expectedRevision: host.revision), isTrue);
        await tester.pump();
        await loaded(host.map!.id);
      }

      await loaded(ArtworkWorld.town);
      expect(find.textContaining('Talk to Keeper Mara'), findsOneWidget);
      expect(find.byKey(const ValueKey('quest-marker-mara')), findsOneWidget);
      await capture('maps-main-harbor');
      await exit('exit.harbor_to_causeway');
      expect(find.textContaining('Before you go'), findsOneWidget);
      expect(find.byKey(const ValueKey('quest-marker-mara')), findsNothing);
      expect(
        host.updatePosition(
          ArtworkWorld.scenes[ArtworkWorld.route]!.position(
            const Offset(480, 737),
          ),
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      await tester.pump();
      await capture('maps-main-causeway');
      await exit('exit.causeway_to_cistern');
      expect(
        host.updatePosition(
          ArtworkWorld.scenes[ArtworkWorld.dungeon]!.position(
            const Offset(627, 580),
          ),
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      await tester.pump();
      await capture('maps-main-cistern-closed');
      expect(painter().sluiceOpen, isFalse);
      expect(
        host.updatePosition(
          ArtworkWorld.scenes[ArtworkWorld.dungeon]!.position(
            const Offset(265, 198),
          ),
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      expect(
        host.openDialogue(
          'quest.cistern.valve',
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      expect(
        host.completeDialogue(
          host.activeDialogue!.token,
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      expect(
        host.updatePosition(
          ArtworkWorld.scenes[ArtworkWorld.dungeon]!.position(
            const Offset(625, 480),
          ),
          expectedRevision: host.revision,
        ),
        isTrue,
      );
      await tester.pump();
      expect(painter().sluiceOpen, isTrue);
      expect(painter().openBackground, isNotNull);
      await capture('maps-main-cistern-open');
      tester.view.physicalSize = const Size(480, 640);
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
