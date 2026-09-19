import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/buzz_flash_overlay.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Buzz Alert Localization Tests', () {
    test('All Buzz Alert keys exist in vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'buzzAlertSettings',
        'buzzFlashScreen',
        'buzzFlashScreenDesc',
        'buzzShakeWindow',
        'buzzShakeWindowDesc',
        'buzzBringToFront',
        'buzzBringToFrontDesc',
      ];

      for (final code in ['vi', 'en', 'zh']) {
        lang.setLanguage(AppLanguage.fromCode(code));
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" should have a valid translation in "$code"',
          );
          expect(translated.isNotEmpty, isTrue);
        }
      }
    });
  });

  group('AppPreferences Buzz Alert Settings Tests', () {
    late Directory tempDir;
    late File prefFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('buzz_prefs_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Default values are true and persist round-trip', () async {
      final prefs = AppPreferences();
      expect(prefs.buzzFlashScreen, isTrue);
      expect(prefs.buzzShakeWindow, isTrue);
      expect(prefs.buzzBringToFront, isTrue);

      await prefs.setBuzzAlertSettings(
        flashScreen: false,
        shakeWindow: false,
        bringToFront: false,
      );
      expect(prefs.buzzFlashScreen, isFalse);
      expect(prefs.buzzShakeWindow, isFalse);
      expect(prefs.buzzBringToFront, isFalse);

      // Reload from disk
      final newPrefs = AppPreferences();
      await newPrefs.load();
      expect(newPrefs.buzzFlashScreen, isFalse);
      expect(newPrefs.buzzShakeWindow, isFalse);
      expect(newPrefs.buzzBringToFront, isFalse);
    });
  });

  group('BuzzFlashOverlay Widget Tests', () {
    testWidgets(
      'Renders child and triggers White Strobe Flash on buzzTrigger',
      (tester) async {
        int triggerCount = 0;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      ElevatedButton(
                        onPressed: () => setState(() => triggerCount++),
                        child: const Text('Buzz Button'),
                      ),
                      Expanded(
                        child: BuzzFlashOverlay(
                          buzzTrigger: triggerCount,
                          enableFlash: true,
                          enableShake: true,
                          child: const Center(
                            child: Text('Main Window Content'),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump();

        expect(find.text('Main Window Content'), findsOneWidget);

        // Trigger buzz
        await tester.tap(find.text('Buzz Button'));
        await tester.pump(); // Start animation
        await tester.pump(const Duration(milliseconds: 100)); // Inside pulse 1

        // Flash overlay container should be active
        expect(find.byType(BuzzFlashOverlay), findsOneWidget);

        // Advance through remaining pulses to completion
        await tester.pump(const Duration(milliseconds: 1000));
        await tester.pumpAndSettle();

        // Content remains intact
        expect(find.text('Main Window Content'), findsOneWidget);
      },
    );

    testWidgets('Respects enableFlash: false and enableShake: false', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BuzzFlashOverlay(
              buzzTrigger: 1,
              enableFlash: false,
              enableShake: false,
              child: Text('Quiet Content'),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Quiet Content'), findsOneWidget);
    });
  });

  group('MessengerCoordinator Buzz Logic Tests', () {
    test(
      'Incoming buzz is stored under its sender without changing another chat',
      () async {
        final folder = await Directory.systemTemp.createTemp('buzz_history_');
        final history = ChatHistoryService();
        history.setCustomDirectoryForTesting(folder);
        final prefs = AppPreferences();
        prefs.setCustomFileForTesting(File('${folder.path}/prefs.json'));
        await prefs.setBuzzAlertSettings(
          flashScreen: false,
          shakeWindow: false,
          bringToFront: false,
        );
        final coordinator = MessengerCoordinator();
        addTearDown(() {
          coordinator.dispose();
          history.setCustomDirectoryForTesting(null);
          prefs.setCustomFileForTesting(null);
        });
        final sender = PeerModel(
          id: '192.0.2.10:6475',
          name: 'Buzz sender',
          ip: '192.0.2.10',
        );
        final other = PeerModel(
          id: '192.0.2.11:6475',
          name: 'Other chat',
          ip: '192.0.2.11',
        );
        coordinator.peersMap[sender.id] = sender;
        coordinator.peersMap[other.id] = other;
        coordinator.selectPeer(other);
        coordinator.handleIncomingBuzz(sender.id);
        final messages = coordinator.conversationsMap[sender.id]!;
        expect(messages, hasLength(1));
        expect(messages.single.senderName, 'Buzz sender');
        expect(messages.single.text, contains('Buzz sender'));
        expect(messages.single.isMine, false);
        expect(sender.unreadCount, 1);
        expect(sender.lastMessage, messages.single.text);
        expect(coordinator.selectedPeer, same(other));
        expect(coordinator.conversationsMap[other.id] ?? [], isEmpty);
        await history.flush();
        final files = folder.listSync().whereType<File>().where(
          (f) => f.path.endsWith('.json') && !f.path.endsWith('prefs.json'),
        );
        expect(
          files.any((f) => f.readAsStringSync().contains('Buzz sender')),
          true,
        );
      },
    );
    test(
      'Buzz restores compact to saved standard geometry before focus',
      () async {
        final folder = await Directory.systemTemp.createTemp('buzz_restore_');
        final prefs = AppPreferences();
        prefs.setCustomFileForTesting(File('${folder.path}/prefs.json'));
        final focused = Completer<void>();
        final calls = <MethodCall>[];
        const channel = MethodChannel('window_manager');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              switch (call.method) {
                case 'isMinimized':
                  return true;
                case 'isVisible':
                  return false;
                case 'getBounds':
                  return {
                    'x': 10.0,
                    'y': 20.0,
                    'width': 340.0,
                    'height': 560.0,
                  };
                case 'focus':
                  if (!focused.isCompleted) focused.complete();
              }
              return null;
            });
        await prefs.saveNormalGeometry(width: 960, height: 640, x: 100, y: 100);
        await prefs.setCompactMode(true);
        await prefs.setBuzzAlertSettings(
          flashScreen: false,
          shakeWindow: false,
          bringToFront: true,
        );
        final coordinator = MessengerCoordinator();
        addTearDown(() {
          coordinator.dispose();
          prefs.setCustomFileForTesting(null);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        coordinator.triggerBuzzAlertForTesting();
        await focused.future.timeout(const Duration(seconds: 3));
        await Future<void>.delayed(Duration.zero);
        expect(coordinator.isCompactMode, false);
        expect(prefs.isCompactMode, false);
        expect(prefs.compactWidth, 340);
        final resize = calls.firstWhere(
          (c) => c.method == 'setBounds' && c.arguments['width'] != null,
        );
        expect(resize.arguments['width'], 960);
        expect(resize.arguments['height'], 640);
        expect(
          calls.indexOf(resize),
          lessThan(calls.indexWhere((c) => c.method == 'focus')),
        );
        expect(
          calls.map((c) => c.method),
          containsAllInOrder(['restore', 'show', 'focus']),
        );
      },
    );
    testWidgets('Repeated buzz preserves position and renews temporary pin', (
      tester,
    ) async {
      const channel = MethodChannel('window_manager');
      var position = const Offset(100, 200);
      final pins = <bool>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'isMinimized':
              case 'isMaximized':
                return false;
              case 'isVisible':
                return true;
              case 'getBounds':
                return {
                  'x': position.dx,
                  'y': position.dy,
                  'width': 340.0,
                  'height': 560.0,
                };
              case 'setBounds':
                position = Offset(
                  (call.arguments['x'] as num).toDouble(),
                  (call.arguments['y'] as num).toDouble(),
                );
              case 'setAlwaysOnTop':
                pins.add(call.arguments['isAlwaysOnTop'] as bool);
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final prefs = AppPreferences();
      await tester.runAsync(
        () => prefs.setBuzzAlertSettings(
          flashScreen: true,
          shakeWindow: true,
          bringToFront: true,
        ),
      );
      final coordinator = MessengerCoordinator();
      coordinator.triggerBuzzAlertForTesting();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      expect(position, isNot(const Offset(100, 200)));
      coordinator.triggerBuzzAlertForTesting();
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      expect(position, const Offset(100, 200));
      await tester.pump(const Duration(seconds: 2));
      coordinator.triggerBuzzAlertForTesting();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(pins, isNot(contains(false)));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 40));
      }
      await tester.pump(const Duration(seconds: 2));
      expect(pins.last, false);
      coordinator.dispose();
      await tester.pump();
    });
    test('triggerBuzzAlertForTesting increments buzzTriggerCount', () {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      expect(coordinator.buzzTriggerCount, equals(0));
      coordinator.triggerBuzzAlertForTesting();
      expect(coordinator.buzzTriggerCount, equals(1));
      expect(coordinator.lastBuzzTime, isNotNull);
    });
  });

  group('SettingsDialog Buzz Alert UI Integration Tests', () {
    testWidgets(
      'Displays Buzz alert section and Test Buzz button in Settings',
      (tester) async {
        tester.view.physicalSize = const Size(800, 700);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        final theme = ThemeProvider();
        final lang = LanguageProvider();
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
              ChangeNotifierProvider.value(value: coordinator),
            ],
            child: const MaterialApp(home: Scaffold(body: SettingsDialog())),
          ),
        );
        await tester.pumpAndSettle();

        // Look for buzz section header
        expect(find.text(lang.tr('buzzAlertSettings')), findsOneWidget);
        expect(find.text(lang.tr('buzzFlashScreen')), findsOneWidget);
        expect(find.text(lang.tr('buzzShakeWindow')), findsOneWidget);
        expect(find.text(lang.tr('buzzBringToFront')), findsOneWidget);

        // Find Test Buzz button and tap it
        final testBuzzFinder = find.text('Test Buzz');
        expect(testBuzzFinder, findsOneWidget);
        await tester.ensureVisible(testBuzzFinder);
        await tester.pumpAndSettle();

        final initialCount = coordinator.buzzTriggerCount;
        await tester.tap(testBuzzFinder);
        await tester.pump();

        expect(coordinator.buzzTriggerCount, equals(initialCount + 1));
      },
    );
  });
}
