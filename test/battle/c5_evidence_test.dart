import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/battle/demo/c5.dart';
import 'package:app_4/battle/ui/battle_screen.dart';
import 'package:app_4/ui/game_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture C5 Hollow Bell review battle', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': const String.fromEnvironment('C5_TEXT_FONT'),
        'MaterialIcons': const String.fromEnvironment('C5_ICON_FONT'),
      }.entries) {
        final loader = FontLoader(entry.key)
          ..addFont(
            Future.value(
              (await File(entry.value).readAsBytes()).buffer.asByteData(),
            ),
          );
        await loader.load();
      }
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: lanternTheme(),
          debugShowCheckedModeBanner: false,
          home: BattleScreen(
            session: createC5DemoSession('enemy.hollow_bell'),
            title: 'C5 balance review',
            names: const {'enemy.hollow_bell': 'The Hollow Bell'},
            onCompleted: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('The Hollow Bell'), findsOneWidget);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('docs/evidence/c5-hollow-bell.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }, skip: !const bool.fromEnvironment('C5_CAPTURE'));
}
