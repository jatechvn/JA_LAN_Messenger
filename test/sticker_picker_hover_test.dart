import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/services/sticker_service.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/sticker_picker_popover.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/sprite_sticker_widget.dart';

void main() {
  testWidgets(
    'localized pack, hover animates, exit stops, click selects once',
    (tester) async {
      final service = StickerService();
      late String spritePath;
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp('sticker_hover_');
        final itemDir = Directory('${dir.path}/0/1')
          ..createSync(recursive: true);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 8, 8),
          Paint()..color = Colors.red,
        );
        canvas.drawRect(
          const Rect.fromLTWH(8, 0, 8, 8),
          Paint()..color = Colors.blue,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(16, 8);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        spritePath = '${itemDir.path}/sprite.png';
        File(spritePath).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
        await service.loadPacks(customSearchPath: dir.path);
      });
      final lang = LanguageProvider()..setLanguage(AppLanguage.en);
      final theme = ThemeProvider();
      var selected = 0;
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: service),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: theme),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: StickerPickerPopover(
                onClose: () {},
                onSelectSticker: (_) => selected++,
              ),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => precacheImage(
          FileImage(File(spritePath)),
          tester.element(find.byType(StickerPickerPopover)),
        ),
      );
      await tester.pump();
      expect(find.text('Zalo Original'), findsOneWidget);
      lang.setLanguage(AppLanguage.zh);
      await tester.pump();
      expect(find.text('Zalo 原版'), findsOneWidget);
      lang.setLanguage(AppLanguage.vi);
      await tester.pump();
      expect(find.text('Zalo gốc'), findsOneWidget);
      final tile = find.byKey(const ValueKey('[sticker:0/1]'));
      expect(find.byType(SpriteStickerWidget), findsNothing);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(700, 500));
      await mouse.moveTo(tester.getCenter(tile));
      await tester.pump();
      expect(find.byType(SpriteStickerWidget), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        final loading = find.descendant(
          of: find.byType(SpriteStickerWidget),
          matching: find.byType(CircularProgressIndicator),
        );
        if (loading.evaluate().isEmpty) break;
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      final paint = find.descendant(
        of: find.byType(SpriteStickerWidget),
        matching: find.byType(CustomPaint),
      );
      final dynamic first = tester.widget<CustomPaint>(paint).painter;
      expect(first.currentFrame, 0);
      await tester.pump(const Duration(milliseconds: 50));
      final dynamic beforeTick = tester.widget<CustomPaint>(paint).painter;
      expect(beforeTick.currentFrame, 0);
      await tester.pump(const Duration(milliseconds: 50));
      final dynamic next = tester.widget<CustomPaint>(paint).painter;
      expect(next.currentFrame, 1);
      await tester.tap(tile);
      expect(selected, 1);
      await mouse.moveTo(const Offset(700, 500));
      await tester.pump();
      expect(find.byType(SpriteStickerWidget), findsNothing);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      lang.dispose();
      theme.dispose();
      expect(tester.takeException(), isNull);
    },
  );
}
