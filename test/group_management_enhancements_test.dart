import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/group_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late File prefFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('group_test_');
    prefFile = File('${tempDir.path}/prefs.json');
    AppPreferences().setCustomFileForTesting(prefFile);
    await AppPreferences().load();
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${tempDir.path}/groups.json',
    );
  });

  tearDown(() async {
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  group('GroupModel copyWith Unit Tests', () {
    test(
      'copyWith properly overrides specified fields while keeping original ones',
      () {
        final original = GroupModel(
          id: 'grp_1',
          name: 'Backend Devs',
          memberIds: ['peer_a', 'peer_b'],
          color: const Color(0xFF3B82F6),
        );

        final modified = original.copyWith(
          name: 'Fullstack Devs',
          memberIds: ['peer_a', 'peer_b', 'peer_c'],
        );

        expect(modified.id, equals('grp_1'));
        expect(modified.name, equals('Fullstack Devs'));
        expect(modified.memberIds, equals(['peer_a', 'peer_b', 'peer_c']));
        expect(modified.color, equals(const Color(0xFF3B82F6)));
      },
    );
  });

  group('MessengerCoordinator Group Management Unit Tests', () {
    test(
      'addGroupMembers adds members and deduplicates without breaking state',
      () {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        coordinator.createGroup('Frontend Team', ['peer_1', 'peer_2']);
        expect(coordinator.groups.length, equals(1));
        final groupId = coordinator.groups.first.id;

        expect(
          coordinator.groups.first.memberIds,
          equals(['peer_1', 'peer_2']),
        );
        expect(coordinator.selectedPeer?.id, equals(groupId));
        expect(coordinator.selectedPeer?.memberIds.length, equals(2));

        // Add peer_3 and duplicate peer_1
        coordinator.addGroupMembers(groupId, ['peer_1', 'peer_3']);
        final updatedGroup = coordinator.groups.firstWhere(
          (g) => g.id == groupId,
        );
        expect(updatedGroup.memberIds, equals(['peer_1', 'peer_2', 'peer_3']));
        expect(coordinator.selectedPeer?.memberIds.length, equals(3));
      },
    );

    test('removeGroupMember removes member and updates selectedPeer', () {
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      coordinator.createGroup('Mobile Team', ['peer_x', 'peer_y', 'peer_z']);
      final groupId = coordinator.groups.first.id;

      coordinator.removeGroupMember(groupId, 'peer_y');
      final updatedGroup = coordinator.groups.firstWhere(
        (g) => g.id == groupId,
      );
      expect(updatedGroup.memberIds, equals(['peer_x', 'peer_z']));
      expect(coordinator.selectedPeer?.memberIds, equals(['peer_x', 'peer_z']));
    });
  });

  group('MessengerCoordinator Unread Count & markAllAsRead Unit Tests', () {
    test(
      'totalUnreadCount sums unread across peers and markAllAsRead resets all to 0',
      () {
        final coordinator = MessengerCoordinator();
        addTearDown(() => coordinator.dispose());

        // Simulate unread on allUsersPeer
        coordinator.allUsersPeer.unreadCount = 5;
        coordinator.aiPeer.unreadCount = 2;

        expect(coordinator.totalUnreadCount, greaterThanOrEqualTo(5));

        // Mark all as read
        coordinator.markAllAsRead();

        expect(coordinator.allUsersPeer.unreadCount, equals(0));
        expect(coordinator.aiPeer.unreadCount, equals(0));
        expect(coordinator.totalUnreadCount, equals(0));
      },
    );
  });
}
