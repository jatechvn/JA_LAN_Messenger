import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_search_history_field.dart';

void main() {
  testWidgets(
    'GlassSearchHistoryField: tapping clear button once clears text and invokes callbacks immediately',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final controller = TextEditingController();
      String lastChanged = '';
      bool clearInvoked = false;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  child: GlassSearchHistoryField(
                    controller: controller,
                    onChanged: (val) => lastChanged = val,
                    onClear: () => clearInvoked = true,
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially no clear icon
      expect(find.byIcon(Icons.clear_rounded), findsNothing);

      // Enter search text
      await tester.enterText(find.byType(TextField), '174.103');
      await tester.pumpAndSettle();

      expect(controller.text, '174.103');
      expect(lastChanged, '174.103');
      expect(find.byIcon(Icons.clear_rounded), findsOneWidget);

      // Tap clear button ONCE
      await tester.tap(find.byIcon(Icons.clear_rounded));
      await tester.pumpAndSettle();

      // Verify it cleared on the VERY FIRST tap
      expect(controller.text, '');
      expect(lastChanged, '');
      expect(clearInvoked, true);
      expect(find.byIcon(Icons.clear_rounded), findsNothing);
    },
  );

  testWidgets(
    'GlassSearchHistoryField: tapping outside closes history dropdown',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final controller = TextEditingController();
      final focusNode = FocusNode();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const SizedBox(height: 50),
                  SizedBox(
                    width: 300,
                    child: GlassSearchHistoryField(
                      controller: controller,
                      focusNode: focusNode,
                      openOverlayOnFocus: true,
                    ),
                  ),
                  const SizedBox(height: 100),
                  const Text('Outside Area'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap text field to open overlay (runAsync allows real File I/O to complete)
      await tester.runAsync(() async {
        await tester.tap(find.byType(TextField));
        await Future.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();

      // Dropdown header should be visible
      expect(find.text(lang.tr('searchHistory')), findsOneWidget);

      // Tap outside
      await tester.tap(find.text('Outside Area'));
      await tester.pumpAndSettle();

      // Dropdown should be dismissed
      expect(find.text(lang.tr('searchHistory')), findsNothing);
    },
  );
}
