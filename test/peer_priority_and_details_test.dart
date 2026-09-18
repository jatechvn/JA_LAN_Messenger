import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';

void main() {
  group('PeerModel & Priority Sorting Tests', () {
    test('displayName returns customNickname if set, else name', () {
      final peer = PeerModel(id: '1', name: 'OriginalName', ip: '192.168.1.10');
      expect(peer.displayName, equals('OriginalName'));

      peer.customNickname = 'Boss Workstation';
      expect(peer.displayName, equals('Boss Workstation'));
      expect(peer.initials, equals('BW'));

      peer.customNickname = '';
      expect(peer.displayName, equals('OriginalName'));
    });

    test('isImageFile correctly identifies image formats', () {
      expect(MessengerCoordinator.isImageFile('photo.png'), isTrue);
      expect(MessengerCoordinator.isImageFile('IMAGE.JPG'), isTrue);
      expect(MessengerCoordinator.isImageFile('test.jpeg'), isTrue);
      expect(MessengerCoordinator.isImageFile('anim.gif'), isTrue);
      expect(MessengerCoordinator.isImageFile('banner.webp'), isTrue);
      expect(MessengerCoordinator.isImageFile('icon.bmp'), isTrue);
      expect(MessengerCoordinator.isImageFile('favicon.ico'), isTrue);

      expect(MessengerCoordinator.isImageFile('document.pdf'), isFalse);
      expect(MessengerCoordinator.isImageFile('archive.zip'), isFalse);
      expect(MessengerCoordinator.isImageFile('notes.txt'), isFalse);
      expect(MessengerCoordinator.isImageFile('app.exe'), isFalse);
    });

    test(
      'Peers sort order: Pinned > Unread > Recent LastMessage > Online > Name',
      () {
        final p1 = PeerModel(
          id: '1',
          name: 'Alpha',
          ip: '192.168.1.1',
          status: PeerStatus.online,
        );
        final p2 = PeerModel(
          id: '2',
          name: 'Beta',
          ip: '192.168.1.2',
          status: PeerStatus.online,
          lastMessageTime: DateTime.now().subtract(const Duration(minutes: 5)),
        );
        final p3 = PeerModel(
          id: '3',
          name: 'Charlie',
          ip: '192.168.1.3',
          status: PeerStatus.online,
          unreadCount: 1, // Has unread message
        );
        final p4 = PeerModel(
          id: '4',
          name: 'Delta',
          ip: '192.168.1.4',
          status: PeerStatus.online,
          isPinned: true, // Pinned!
        );

        final list = [p1, p2, p3, p4];

        list.sort((a, b) {
          if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
          final aUnread = a.unreadCount > 0;
          final bUnread = b.unreadCount > 0;
          if (aUnread != bUnread) return aUnread ? -1 : 1;
          if (a.lastMessageTime != null && b.lastMessageTime != null) {
            final cmp = b.lastMessageTime!.compareTo(a.lastMessageTime!);
            if (cmp != 0) return cmp;
          } else if (a.lastMessageTime != null) {
            return -1;
          } else if (b.lastMessageTime != null) {
            return 1;
          }
          if (a.status != b.status) {
            return a.status.index.compareTo(b.status.index);
          }
          return a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          );
        });

        // Verification:
        // 1st: p4 (Pinned)
        expect(list[0].id, equals('4'));
        // 2nd: p3 (Unread message)
        expect(list[1].id, equals('3'));
        // 3rd: p2 (Has recent message 5 mins ago)
        expect(list[2].id, equals('2'));
        // 4th: p1 (No message yet)
        expect(list[3].id, equals('1'));
      },
    );
  });
}
