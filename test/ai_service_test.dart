import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/ai_config_model.dart';
import 'package:ja_lan_messenger/modules/services/ai_service.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';

void main() {
  group('AiModelInfo Tests', () {
    test('Supported models contain all 3 required JA-AI models', () {
      final models = AiModelInfo.supportedModels;
      expect(models.length, 3);
      expect(models.any((m) => m.id == 'qwen3.5:4b'), isTrue);
      expect(models.any((m) => m.id == 'qwen2.5-vl:3b'), isTrue);
      expect(models.any((m) => m.id == 'qwen2.5-coder:3b'), isTrue);
    });

    test('Qwen 3.5 4B supports thinking and vision', () {
      final qwen35 = AiModelInfo.findById('qwen3.5:4b');
      expect(qwen35.supportsThinking, isTrue);
      expect(qwen35.supportsVision, isTrue);
      expect(qwen35.displayName, contains('Qwen 3.5'));
    });

    test('Qwen 2.5 VL 3B supports vision but not thinking', () {
      final qwenVl = AiModelInfo.findById('qwen2.5-vl:3b');
      expect(qwenVl.supportsThinking, isFalse);
      expect(qwenVl.supportsVision, isTrue);
    });

    test('Qwen 2.5 Coder 3B is specialized for coding without thinking', () {
      final coder = AiModelInfo.findById('qwen2.5-coder:3b');
      expect(coder.supportsThinking, isFalse);
      expect(coder.supportsVision, isFalse);
    });

    test('Auto-create dynamic model on unknown id, fallback on empty id', () {
      final unknown = AiModelInfo.findById('unknown-model');
      expect(unknown.id, 'unknown-model');
      expect(unknown.displayName, isNotEmpty);

      final empty = AiModelInfo.findById('');
      expect(empty.id, 'qwen2.5-vl:3b');
    });
  });

  group('AiService Configuration Tests', () {
    test('Normalizes server URL by removing trailing slashes', () {
      final service1 = AiService(serverUrl: 'http://172.21.175.20:11434/');
      expect(service1.normalizedUrl, 'http://172.21.175.20:11434');

      final service2 = AiService(serverUrl: 'http://172.21.175.20:11434///');
      expect(service2.normalizedUrl, 'http://172.21.175.20:11434');

      final service3 = AiService(serverUrl: '  http://172.21.175.20:11434  ');
      expect(service3.normalizedUrl, 'http://172.21.175.20:11434');
    });
  });

  group('AppPreferences AI Settings Tests', () {
    late Directory tempDir;
    late File tempFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ja_ai_pref_test_');
      tempFile = File('${tempDir.path}/user_preferences.json');
      AppPreferences().setCustomFileForTesting(tempFile);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Default AI preferences are configured correctly', () {
      final prefs = AppPreferences();
      expect(prefs.aiEnabled, isTrue);
      expect(prefs.aiServerUrl, 'http://172.21.175.20:11434');
      expect(prefs.aiSelectedModel, 'qwen2.5-vl:3b');
      expect(prefs.aiThinkingEnabled, isFalse);
    });

    test('AI preferences persist to disk and reload accurately', () async {
      final prefs = AppPreferences();
      await prefs.setAiConfig(
        enabled: true,
        serverUrl: 'http://10.0.0.5:11434',
        selectedModel: 'qwen2.5-coder:3b',
        thinkingEnabled: true,
      );

      expect(prefs.aiServerUrl, 'http://10.0.0.5:11434');
      expect(prefs.aiSelectedModel, 'qwen2.5-coder:3b');
      expect(prefs.aiThinkingEnabled, isTrue);

      // Verify file reload
      final prefs2 = AppPreferences();
      prefs2.setCustomFileForTesting(tempFile);
      await prefs2.load();

      expect(prefs2.aiServerUrl, 'http://10.0.0.5:11434');
      expect(prefs2.aiSelectedModel, 'qwen2.5-coder:3b');
      expect(prefs2.aiThinkingEnabled, isTrue);
    });
  });
}
