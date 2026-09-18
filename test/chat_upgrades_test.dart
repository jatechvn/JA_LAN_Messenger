import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

void main() {
  group('Chat Upgrades & Pinning Tests', () {
    late Directory tempDir;
    late File tempFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ja_pin_test_');
      tempFile = File('${tempDir.path}/user_preferences.json');
      AppPreferences().setCustomFileForTesting(tempFile);
      await AppPreferences().load();
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    test('Pinned keys persist to disk and reload accurately', () async {
      final prefs = AppPreferences();
      expect(prefs.isPeerPinned('__AI_ASSISTANT__'), isTrue);

      await prefs.setPeerPinned('user1@desktop', true);
      expect(prefs.isPeerPinned('user1@desktop'), isTrue);

      // Reload into new preferences instance
      final prefs2 = AppPreferences();
      prefs2.setCustomFileForTesting(tempFile);
      await prefs2.load();

      expect(prefs2.isPeerPinned('user1@desktop'), isTrue);
      expect(prefs2.isPeerPinned('__AI_ASSISTANT__'), isTrue);

      await prefs2.setPeerPinned('user1@desktop', false);
      expect(prefs2.isPeerPinned('user1@desktop'), isFalse);
    });

    test('AI Assistant returns custom avatar asset', () {
      final aiPeer = PeerModel.createAiAssistantPeer();
      expect(aiPeer.avatarAsset, 'assets/ai_avatar.png');

      final regularPeer = PeerModel(
        id: '192.168.1.50:64738',
        name: 'Alex',
        ip: '192.168.1.50',
        port: 64738,
      );
      expect(regularPeer.avatarAsset, isNull);
    });

    test(
      'PeerModel effectiveStatusDescription handles VI, EN, and ZH correctly',
      () {
        final aiPeer = PeerModel.createAiAssistantPeer();
        final lang = LanguageProvider();

        // Test English
        lang.setLanguage(AppLanguage.en);
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('Ready'),
        );
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('qwen2.5-vl:3b'),
        );
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            isAiBusy: true,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('Processing'),
        );

        // Test Vietnamese
        lang.setLanguage(AppLanguage.vi);
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('Sẵn sàng'),
        );
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            isAiBusy: true,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('Đang xử lý'),
        );

        // Test Chinese
        lang.setLanguage(AppLanguage.zh);
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('就绪'),
        );
        expect(
          aiPeer.effectiveStatusDescription(
            lang,
            isAiBusy: true,
            selectedModel: 'qwen2.5-vl:3b',
          ),
          contains('正在处理'),
        );
      },
    );

    test(
      'MessengerCoordinator togglePinPeer toggles and updates list sort',
      () {
        final coordinator = MessengerCoordinator();
        final peer = PeerModel(
          id: '192.168.1.100:64738',
          name: 'RemoteDevice',
          ip: '192.168.1.100',
          port: 64738,
          status: PeerStatus.online,
          isPinned: false,
        );
        coordinator.peersMap[peer.id] = peer;

        expect(peer.isPinned, isFalse);

        coordinator.togglePinPeer(peer.id);
        expect(peer.isPinned, isTrue);

        final topPeer = coordinator.peers.first;
        expect(topPeer.isPinned, isTrue);
      },
    );
  });
}
