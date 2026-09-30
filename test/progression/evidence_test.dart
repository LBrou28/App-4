import 'dart:io';
import 'dart:ui' as ui;

import 'package:app_4/ui/content/demo_content.dart';
import 'package:app_4/ui/demo/main.dart';
import 'package:app_4/ui/game_theme.dart';
import 'package:app_4/ui/party_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('capture a completed C4 job switch at demo resolution', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() async {
      for (final entry in {
        'Roboto': const String.fromEnvironment('C4_TEXT_FONT'),
        'MaterialIcons': const String.fromEnvironment('C4_ICON_FONT'),
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
    final boundaryKey = GlobalKey();
    final host = PreviewHost(content);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: MaterialApp(
          theme: lanternTheme(),
          debugShowCheckedModeBanner: false,
          home: PartyMenu(
            host: host,
            content: content,
            initialPage: PartyPage.jobs,
            onBack: () {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Choose White Mage'));
    await tester.tap(find.text('Choose White Mage'));
    await tester.pumpAndSettle();
    expect(find.text('Current job'), findsOneWidget);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('docs/evidence/c4-job-switching.png');
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    await tester.pumpWidget(const SizedBox());
    host.dispose();
  }, skip: !const bool.fromEnvironment('C4_CAPTURE'));
}
