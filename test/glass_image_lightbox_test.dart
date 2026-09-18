import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_image_lightbox.dart';

void main() {
  testWidgets('GlassImageLightbox renders and closes on empty space tap', (
    tester,
  ) async {
    final theme = ThemeProvider();
    theme.setThemeMode('light');
    final lang = LanguageProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showGlassImageLightbox(
                    context: context,
                    filePath: 'non_existent_file.png',
                    fileName: 'test_sample.png',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    // Open lightbox
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    // Verify fileName is visible
    expect(find.text('test_sample.png'), findsWidgets);

    // Tap on empty space (bottom corner) -> should pop
    await tester.tapAt(const Offset(30, 500));
    await tester.pumpAndSettle();

    // Lightbox should be dismissed, only Open button remains
    expect(find.byType(GlassImageLightbox), findsNothing);
  });

  testWidgets('GlassImageLightbox closes on Esc key', (tester) async {
    final theme = ThemeProvider();
    theme.setThemeMode('light');
    final lang = LanguageProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  showGlassImageLightbox(
                    context: context,
                    filePath: 'dummy.png',
                    fileName: 'esc_test.png',
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(GlassImageLightbox), findsOneWidget);

    // Press Escape
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.byType(GlassImageLightbox), findsNothing);
  });
}
