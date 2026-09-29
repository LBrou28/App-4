import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/ui/demo/main.dart';
import 'package:app_4/ui/game_theme.dart';
import 'package:app_4/ui/party_menu.dart';
import 'package:app_4/ui/title_screen.dart';
import 'package:app_4/core/contracts.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture D1 presentation at demo resolution', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': const String.fromEnvironment('D1_TEXT_FONT'),
        'MaterialIcons': const String.fromEnvironment('D1_ICON_FONT'),
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
    final content = DemoContent.decode(
      File('assets/data/lantern_wake.json').readAsStringSync(),
    );
    final host = PreviewHost(content);
    final pages = <String, Widget>{
      'title': TitleScreen(
        availability: SaveMissing(),
        hasActiveProgress: false,
        onNewGame: () async {},
        onContinue: () async {},
      ),
      for (final page in PartyPage.values)
        page.name: PartyMenu(
          host: host,
          content: content,
          onBack: () {},
          initialPage: page,
        ),
    };
    for (final page in pages.entries) {
      await tester.pumpWidget(const SizedBox());
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: MaterialApp(
            theme: lanternTheme(),
            debugShowCheckedModeBanner: false,
            home: page.value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('docs/evidence/d1-${page.key}.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
    await tester.pumpWidget(const SizedBox());
    host.dispose();
  }, skip: !const bool.fromEnvironment('D1_CAPTURE'));
}
