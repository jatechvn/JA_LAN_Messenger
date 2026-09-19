import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/ime/ime_service.dart';
import 'package:ja_lan_messenger/modules/ime/ime_types.dart';
import 'package:ja_lan_messenger/modules/ime/external_ime_detector.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    ExternalImeDetector.mockDetectedIme = null;
  });

  group('IME Adaptive Language Tests', () {
    test('Adapts mode according to app language', () {
      final ime = ImeService();
      ime.setMode(ImeMode.auto);

      // 1. Tiếng Việt -> Telex
      ime.updateAppLanguage('vi');
      expect(ime.effectiveMode, equals(ImeMode.telex));
      expect(ime.shortStatusLabel, equals('TELEX'));

      // 2. Tiếng Trung -> Pinyin
      ime.updateAppLanguage('zh');
      expect(ime.effectiveMode, equals(ImeMode.pinyin));
      expect(ime.shortStatusLabel, equals('拼音'));

      // 3. Tiếng Anh -> Off (EN)
      ime.updateAppLanguage('en');
      expect(ime.effectiveMode, equals(ImeMode.off));
      expect(ime.shortStatusLabel, equals('EN'));
    });

    test('Manual override overrides auto language mode', () {
      final ime = ImeService();
      ime.updateAppLanguage('vi');

      // Đặt thủ công sang Off
      ime.setMode(ImeMode.off);
      expect(ime.effectiveMode, equals(ImeMode.off));
      expect(ime.engineState, equals(ImeEngineState.disabledManual));

      // Đặt thủ công sang Pinyin dù đang ở giao diện tiếng Việt
      ime.setMode(ImeMode.pinyin);
      expect(ime.effectiveMode, equals(ImeMode.pinyin));
    });
  });

  group('External IME Auto-Bypass Tests', () {
    test('Auto-bypasses internal Telex when EVKey is detected', () async {
      final ime = ImeService();
      ime.setMode(ImeMode.telex);
      ime.setAutoBypassExternal(true);

      // Khi chưa phát hiện bộ gõ ngoài
      ExternalImeDetector.mockDetectedIme = DetectedImeInfo.none;
      await ime.checkExternalImeNow();
      expect(ime.effectiveMode, equals(ImeMode.telex));
      expect(ime.engineState, equals(ImeEngineState.active));

      // Giả lập phát hiện EVKey đang chạy
      ExternalImeDetector.mockDetectedIme = const DetectedImeInfo(
        isDetected: true,
        imeName: 'EVKey',
        imeType: 'vietnamese',
      );
      await ime.checkExternalImeNow();

      expect(ime.effectiveMode, equals(ImeMode.off));
      expect(ime.engineState, equals(ImeEngineState.bypassedExternal));
      expect(ime.shortStatusLabel, equals('EVKey'));
    });
  });

  group('SmartImeInputFormatter Real-time Typing Tests', () {
    test('Transforms typed characters into accented Vietnamese via Formatter', () {
      final ime = ImeService();
      ime.setAutoBypassExternal(false);
      ime.setMode(ImeMode.telex);
      final formatter = ime.inputFormatter;

      // Mô phỏng gõ: 'tiêng' + 's' -> 'tiếng'
      const oldVal = TextEditingValue(
        text: 'tiêng',
        selection: TextSelection.collapsed(offset: 5),
      );
      const newVal = TextEditingValue(
        text: 'tiêngs',
        selection: TextSelection.collapsed(offset: 6),
      );

      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, equals('tiếng'));
      expect(result.selection.baseOffset, equals(5));
    });

    test('Passes raw characters when IME is off', () {
      final ime = ImeService();
      ime.setAutoBypassExternal(false);
      ime.setMode(ImeMode.off);
      final formatter = ime.inputFormatter;

      const oldVal = TextEditingValue(
        text: 'tieng',
        selection: TextSelection.collapsed(offset: 5),
      );
      const newVal = TextEditingValue(
        text: 'tiengs',
        selection: TextSelection.collapsed(offset: 6),
      );

      final result = formatter.formatEditUpdate(oldVal, newVal);
      expect(result.text, equals('tiengs'));
    });
  });

  group('AppPreferences IME Persistence Tests', () {
    late Directory tempDir;
    late File prefFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ime_prefs_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Default values and round-trip persistence', () async {
      final prefs = AppPreferences();
      expect(prefs.imeMode, equals('auto'));
      expect(prefs.imeAutoBypassExternal, isTrue);

      await prefs.setImeSettings(
        mode: 'pinyin',
        autoBypassExternal: false,
      );

      final prefs2 = AppPreferences();
      prefs2.setCustomFileForTesting(prefFile);
      await prefs2.load();

      expect(prefs2.imeMode, equals('pinyin'));
      expect(prefs2.imeAutoBypassExternal, isFalse);
    });
  });

  group('Chat Header Attach File Button Removal Verification', () {
    testWidgets('Header does not have attach_file icon, dock input has it', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      final ime = ImeService();
      addTearDown(() => coordinator.dispose());

      coordinator.selectPeer(
        PeerModel(
          id: 'test-peer-1',
          name: 'Bob',
          ip: '192.168.1.100',
        ),
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
            ChangeNotifierProvider.value(value: ime),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: ChatViewPanel(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Nút attach file chỉ xuất hiện đúng 1 lần duy nhất trong toàn bộ ChatViewPanel
      // (ở khay dock nhập tin nhắn bên dưới, KHÔNG có ở header)
      final attachIconFinder = find.byIcon(Icons.attach_file_rounded);
      expect(attachIconFinder, findsOneWidget);
    });
  });
}
