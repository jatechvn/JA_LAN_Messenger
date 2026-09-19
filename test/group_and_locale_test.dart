import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/group_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';

void main() {
  group('LanguageProvider Tests', () {
    setUp(() {
      LanguageProvider.disableDiskPersistenceForTesting = true;
    });

    tearDown(() {
      LanguageProvider.disableDiskPersistenceForTesting = false;
    });

    test('AppLanguage enum values and fromCode resolution', () {
      expect(AppLanguage.fromCode('vi'), equals(AppLanguage.vi));
      expect(AppLanguage.fromCode('en'), equals(AppLanguage.en));
      expect(AppLanguage.fromCode('zh'), equals(AppLanguage.zh));
      expect(AppLanguage.fromCode('cn'), equals(AppLanguage.zh));
      expect(AppLanguage.fromCode('unknown'), equals(AppLanguage.en));
    });

    test('LanguageProvider translation lookup tr() works in all languages', () {
      final provider = LanguageProvider();

      provider.setLanguage(AppLanguage.vi);
      expect(provider.tr('appName'), equals('JA LAN Messenger'));
      expect(provider.tr('tabChats'), equals('Trò chuyện'));
      expect(provider.tr('allUsersTitle'), equals('Toàn thể (All Users)'));

      provider.setLanguage(AppLanguage.en);
      expect(provider.tr('tabChats'), equals('Chats'));
      expect(provider.tr('allUsersTitle'), equals('All Users (Broadcast)'));

      provider.setLanguage(AppLanguage.zh);
      expect(provider.tr('tabChats'), equals('聊天'));
      expect(provider.tr('allUsersTitle'), equals('全体广播 (All Users)'));
    });

    test(
      'LanguageProvider translation lookup tr() works for About, User Guide, and Transfers',
      () {
        final provider = LanguageProvider();

        for (final lang in [AppLanguage.vi, AppLanguage.en, AppLanguage.zh]) {
          provider.setLanguage(lang);
          expect(provider.tr('transfersTitle').isNotEmpty, isTrue);
          expect(provider.tr('openDownloadFolder').isNotEmpty, isTrue);
          expect(provider.tr('transferTo').isNotEmpty, isTrue);
          expect(provider.tr('transferFrom').isNotEmpty, isTrue);
          expect(provider.tr('systemSettings').isNotEmpty, isTrue);
          expect(provider.tr('tabAbout').isNotEmpty, isTrue);
          expect(provider.tr('tabUserGuide').isNotEmpty, isTrue);
          expect(provider.tr('versionLabel').isNotEmpty, isTrue);
          expect(provider.tr('guideStep1Title').isNotEmpty, isTrue);
          expect(provider.tr('guideStep2Title').isNotEmpty, isTrue);
          expect(provider.tr('guideStep3Title').isNotEmpty, isTrue);
          expect(provider.tr('guideStep4Title').isNotEmpty, isTrue);
          expect(provider.tr('searchHistory').isNotEmpty, isTrue);
          expect(provider.tr('clearSearchHistory').isNotEmpty, isTrue);
          expect(provider.tr('toastNewDevice').isNotEmpty, isTrue);
        }
      },
    );

    test('LanguageProvider cycleLanguage rotates VI -> EN -> ZH -> VI', () {
      final provider = LanguageProvider();
      provider.setLanguage(AppLanguage.vi);

      provider.cycleLanguage();
      expect(provider.currentLanguage, equals(AppLanguage.en));

      provider.cycleLanguage();
      expect(provider.currentLanguage, equals(AppLanguage.zh));

      provider.cycleLanguage();
      expect(provider.currentLanguage, equals(AppLanguage.vi));
    });

    test('LanguageProvider isolates disk persistence during tests', () {
      final appData = Platform.environment['APPDATA'];
      final realFile = File('$appData\\JA_LAN_Messenger\\app_preferences.json');
      final existedBefore = realFile.existsSync();

      final provider = LanguageProvider();
      provider.setLanguage(AppLanguage.zh);

      if (!existedBefore) {
        expect(
          realFile.existsSync(),
          isFalse,
          reason:
              'Test mode should never pollute the user real app_preferences.json',
        );
      }
    });

    test('LanguageProvider correctly persists to customFileForTesting', () {
      final tempDir = Directory.systemTemp.createTempSync('lang_test_');
      final tempFile = File('${tempDir.path}/custom_pref.json');

      try {
        LanguageProvider.customFileForTesting = tempFile;
        final provider = LanguageProvider();
        provider.setLanguage(AppLanguage.zh);

        expect(tempFile.existsSync(), isTrue);
        expect(tempFile.readAsStringSync(), contains('"language":"zh"'));

        provider.setLanguage(AppLanguage.vi);
        expect(tempFile.readAsStringSync(), contains('"language":"vi"'));
      } finally {
        LanguageProvider.customFileForTesting = null;
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('GroupModel and PeerModel Group Tests', () {
    test('GroupModel serialization and deserialization', () {
      final group = GroupModel(
        id: 'group_test_1',
        name: 'Technical Dept',
        memberIds: ['192.168.1.5:6475', '192.168.1.8:6475'],
      );

      final jsonMap = group.toJson();
      expect(jsonMap['id'], equals('group_test_1'));
      expect(jsonMap['name'], equals('Technical Dept'));
      expect(
        jsonMap['memberIds'],
        equals(['192.168.1.5:6475', '192.168.1.8:6475']),
      );

      final parsed = GroupModel.fromJson(jsonMap);
      expect(parsed.id, equals(group.id));
      expect(parsed.name, equals(group.name));
      expect(parsed.memberIds, equals(group.memberIds));

      final jsonStr = GroupModel.listToJson([group]);
      final list = GroupModel.listFromJson(jsonStr);
      expect(list.length, equals(1));
      expect(list.first.name, equals('Technical Dept'));
    });

    test('PeerModel all-users channel helper', () {
      final allUsers = PeerModel.createAllUsersPeer();
      expect(allUsers.id, equals('__ALL_USERS__'));
      expect(allUsers.isAllUsers, isTrue);
      expect(allUsers.isGroup, isTrue);
      expect(allUsers.initials, equals('📢'));
    });

    test('PeerModel group conversion helper', () {
      final group = GroupModel(
        id: 'group_100',
        name: 'Design Team',
        memberIds: ['192.168.1.20:6475'],
      );

      final peer = PeerModel.fromGroup(group);
      expect(peer.id, equals('group_100'));
      expect(peer.name, equals('Design Team'));
      expect(peer.isGroup, isTrue);
      expect(peer.isAllUsers, isFalse);
      expect(peer.initials, equals('👥'));
      expect(peer.memberIds, equals(['192.168.1.20:6475']));
    });
  });
}
