import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/close_action_dialog.dart';

void main() {
  testWidgets('CloseActionDialog renders options and confirms minimize', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    Map<String, dynamic>? dialogResult;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await CloseActionDialog.show(context);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Verify dialog content
    expect(find.text(lang.tr('closeDialogTitle')), findsOneWidget);
    expect(find.text(lang.tr('closeActionMinimize')), findsOneWidget);
    expect(find.text(lang.tr('closeActionExit')), findsOneWidget);
    expect(find.text(lang.tr('rememberChoice')), findsOneWidget);

    // Click confirm (default: minimize, remember: false)
    await tester.tap(find.text(lang.tr('confirm')));
    await tester.pumpAndSettle();

    expect(dialogResult, isNotNull);
    expect(dialogResult!['action'], 'minimize');
    expect(dialogResult!['remember'], false);
  });

  testWidgets('CloseActionDialog selects exit and remember choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    Map<String, dynamic>? dialogResult;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await CloseActionDialog.show(context);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Select Exit option
    await tester.tap(find.text(lang.tr('closeActionExit')));
    await tester.pumpAndSettle();

    // Check remember choice
    await tester.tap(find.text(lang.tr('rememberChoice')));
    await tester.pumpAndSettle();

    // Confirm
    await tester.tap(find.text(lang.tr('confirm')));
    await tester.pumpAndSettle();

    expect(dialogResult, isNotNull);
    expect(dialogResult!['action'], 'exit');
    expect(dialogResult!['remember'], true);
  });

  testWidgets('CloseActionDialog cancels when cancel button tapped', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final theme = ThemeProvider();
    final lang = LanguageProvider();
    Map<String, dynamic>? dialogResult = {'initial': true};

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  dialogResult = await CloseActionDialog.show(context);
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Open dialog
    await tester.tap(find.text('Open Dialog'));
    await tester.pumpAndSettle();

    // Tap Cancel
    await tester.tap(find.text(lang.tr('cancel')));
    await tester.pumpAndSettle();

    expect(dialogResult, isNull);
  });
}
