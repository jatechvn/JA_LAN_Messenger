import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/ai_config_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';

void main() {
  group('Smart Heuristic Detection Tests', () {
    test('Detects Vision capability correctly across models', () {
      final m1 = AiModelInfo.fromModelTag(
        'llama3.2-vision:11b',
        paramSize: '11B',
      );
      expect(m1.supportsVision, isTrue);
      expect(m1.supportsThinking, isFalse);
      expect(m1.displayName, contains('11B'));

      final m2 = AiModelInfo.fromModelTag('llava:latest', paramSize: '7B');
      expect(m2.supportsVision, isTrue);

      final m3 = AiModelInfo.fromModelTag(
        'custom-model',
        families: ['clip', 'llama'],
      );
      expect(m3.supportsVision, isTrue);

      final m4 = AiModelInfo.fromModelTag('minicpm-v:8b');
      expect(m4.supportsVision, isTrue);
    });

    test('Detects Reasoning / Thinking capability correctly', () {
      final r1 = AiModelInfo.fromModelTag('deepseek-r1:7b', paramSize: '7B');
      expect(r1.supportsThinking, isTrue);
      expect(r1.supportsVision, isFalse);
      expect(r1.displayName, contains('Deepseek R1'));

      final qwq = AiModelInfo.fromModelTag('qwq:32b', paramSize: '32B');
      expect(qwq.supportsThinking, isTrue);

      final qwen35 = AiModelInfo.fromModelTag('qwen3.5:9b', paramSize: '9B');
      expect(qwen35.supportsThinking, isTrue);
      expect(qwen35.supportsVision, isTrue); // Qwen 3.5 supports both

      final reasoning = AiModelInfo.fromModelTag('my-custom-reasoning:latest');
      expect(reasoning.supportsThinking, isTrue);
    });

    test('Detects Coder capability correctly', () {
      final coder = AiModelInfo.fromModelTag(
        'deepseek-coder-v2:16b',
        paramSize: '16B',
      );
      expect(coder.id, 'deepseek-coder-v2:16b');
      expect(coder.supportsThinking, isFalse);
      expect(coder.supportsVision, isFalse);
      expect(coder.displayName, contains('Coder'));
    });

    test('Formats display names cleanly and strips :latest suffix', () {
      final m1 = AiModelInfo.fromModelTag('llama3:latest', paramSize: '8B');
      expect(m1.displayName, 'Llama3 (8B)');

      final m2 = AiModelInfo.fromModelTag('mistral-nemo:12b');
      expect(m2.displayName, contains('Mistral Nemo'));

      final m3 = AiModelInfo.fromModelTag('phi3:mini');
      expect(m3.displayName, 'Phi3 (Mini)');
    });
  });

  group('AiModelInfo Serialization & Registry Tests', () {
    test('Registry removes duplicate model IDs case-insensitively', () {
      final models = [
        AiModelInfo.fromModelTag('qwen2.5-vl:3b'),
        AiModelInfo.fromModelTag(' QWEN2.5-VL:3B '),
        AiModelInfo.fromModelTag('qwen3.5:4b'),
      ];
      AiModelInfo.updateDiscoveredModels(models);
      expect(AiModelInfo.currentModels.map((m) => m.id), [
        'qwen2.5-vl:3b',
        'qwen3.5:4b',
      ]);
      AiModelInfo.resetDiscoveredModels();
    });

    test(
      'JA-AI selection hides backup and alias tags when production set is complete',
      () {
        final models = [
          AiModelInfo.fromModelTag('qwen2.5-vl:3b'),
          AiModelInfo.fromModelTag('qwen2.5-vl:3b-nosystem'),
          AiModelInfo.fromModelTag('qwen2.5-vl:3b.backup-20260917-english'),
          AiModelInfo.fromModelTag('qwen2.5vl:3b'),
          AiModelInfo.fromModelTag('qwen2.5-vl:latest'),
          AiModelInfo.fromModelTag('qwen3.5:4b'),
          AiModelInfo.fromModelTag('qwen2.5:3b'),
          AiModelInfo.fromModelTag('qwen2.5-coder:3b'),
        ];
        expect(
          AiModelInfo.forServerSelection(models).map((model) => model.id),
          ['qwen2.5-vl:3b', 'qwen3.5:4b', 'qwen2.5-coder:3b'],
        );
      },
    );

    setUp(() {
      AiModelInfo.resetDiscoveredModels();
    });

    tearDown(() {
      AiModelInfo.resetDiscoveredModels();
    });

    test('AiModelInfo toJson and fromJson round-trip', () {
      final original = AiModelInfo(
        id: 'deepseek-r1:7b',
        displayName: 'DeepSeek R1 (7B)',
        supportsThinking: true,
        supportsVision: false,
        description: 'Lập luận chuyên sâu',
      );

      final json = original.toJson();
      final restored = AiModelInfo.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.displayName, original.displayName);
      expect(restored.supportsThinking, isTrue);
      expect(restored.supportsVision, isFalse);
      expect(restored.description, original.description);
    });

    test('Registry updates and resets dynamic models correctly', () {
      expect(
        AiModelInfo.currentModels.length,
        AiModelInfo.supportedModels.length,
      );

      final newModels = [
        AiModelInfo.fromModelTag('deepseek-r1:7b'),
        AiModelInfo.fromModelTag('llama3.2-vision:11b'),
      ];

      AiModelInfo.updateDiscoveredModels(newModels);
      expect(AiModelInfo.currentModels.length, 2);
      expect(AiModelInfo.currentModels[0].id, 'deepseek-r1:7b');
      expect(AiModelInfo.currentModels[1].id, 'llama3.2-vision:11b');

      AiModelInfo.resetDiscoveredModels();
      expect(
        AiModelInfo.currentModels.length,
        AiModelInfo.supportedModels.length,
      );
    });

    test('findById searches discovered models before fallback', () {
      final discovered = [
        AiModelInfo.fromModelTag('custom-assistant:latest', paramSize: '14B'),
      ];
      AiModelInfo.updateDiscoveredModels(discovered);

      final found = AiModelInfo.findById('custom-assistant:latest');
      expect(found.id, 'custom-assistant:latest');
      expect(found.displayName, contains('Custom Assistant'));
    });
  });

  group('AppPreferences Caching & Auto-Switch Tests', () {
    late Directory tempDir;
    late File tempFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ja_ai_dynamic_test_');
      tempFile = File('${tempDir.path}/user_preferences.json');
      AppPreferences().setCustomFileForTesting(tempFile);
      AiModelInfo.resetDiscoveredModels();
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      AiModelInfo.resetDiscoveredModels();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Caches discovered models and reloads them on startup', () async {
      final prefs = AppPreferences();
      final sampleModels = [
        AiModelInfo.fromModelTag('deepseek-r1:7b', paramSize: '7B'),
        AiModelInfo.fromModelTag('llama3.2:3b', paramSize: '3B'),
      ];

      await prefs.setCachedAiModels(sampleModels);
      expect(prefs.cachedDiscoveredModels.length, 2);

      // Verify file content has cachedDiscoveredModels
      final fileContent = await tempFile.readAsString();
      final decoded = jsonDecode(fileContent) as Map<String, dynamic>;
      expect(decoded.containsKey('cachedDiscoveredModels'), isTrue);
      final list = decoded['cachedDiscoveredModels'] as List;
      expect(list.length, 2);

      // Simulate app restart: reload preferences into a new instance
      AiModelInfo.resetDiscoveredModels();
      final newPrefs = AppPreferences();
      newPrefs.setCustomFileForTesting(tempFile);
      await newPrefs.load();

      expect(newPrefs.cachedDiscoveredModels.length, 2);
      expect(AiModelInfo.currentModels.length, 2);
      expect(AiModelInfo.currentModels.first.id, 'deepseek-r1:7b');
    });

    test(
      'Auto-switches selected model if current model does not exist on new server',
      () async {
        final prefs = AppPreferences();
        await prefs.setAiConfig(selectedModel: 'old-server-model:7b');
        expect(prefs.aiSelectedModel, 'old-server-model:7b');

        final serverModels = [
          AiModelInfo.fromModelTag('new-server-model:8b'),
          AiModelInfo.fromModelTag('qwen2.5-vl:3b'),
        ];

        // If current selectedModel is not in serverModels, auto-switch to first model
        if (!serverModels.any((m) => m.id == prefs.aiSelectedModel)) {
          await prefs.setAiConfig(selectedModel: serverModels.first.id);
        }

        expect(prefs.aiSelectedModel, 'new-server-model:8b');
      },
    );

    test('Preserves selected model if it is available on new server', () async {
      final prefs = AppPreferences();
      await prefs.setAiConfig(selectedModel: 'shared-model:7b');

      final serverModels = [
        AiModelInfo.fromModelTag('first-model:3b'),
        AiModelInfo.fromModelTag('shared-model:7b'),
      ];

      if (!serverModels.any((m) => m.id == prefs.aiSelectedModel)) {
        await prefs.setAiConfig(selectedModel: serverModels.first.id);
      }

      // Should keep 'shared-model:7b'
      expect(prefs.aiSelectedModel, 'shared-model:7b');
    });
  });
}
