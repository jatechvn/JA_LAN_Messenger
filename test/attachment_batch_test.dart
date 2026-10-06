import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/app_power_manager.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/known_devices_registry.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

MessageModel attachment(
  String id, {
  String? batch = 'batch_1',
  String sender = 'me',
  String? session,
  String? fileName,
}) => MessageModel(
  id: id,
  senderId: sender,
  senderName: sender,
  recipientId: 'peer',
  sourceSession: session,
  text: '',
  isMine: true,
  attachmentBatchId: batch,
  fileAttachment: FileAttachmentInfo(
    fileName: fileName ?? '$id.txt',
    fileSize: 10,
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MessengerCoordinator coordinator;
  setUp(() async {
    final dir = await Directory.systemTemp.createTemp('ja_batch_');
    AppPreferences().setCustomFileForTesting(File('${dir.path}/prefs.json'));
    await AppPreferences().load();
    ChatHistoryService().setCustomDirectoryForTesting(
      Directory('${dir.path}/history')..createSync(),
    );
    MessengerCoordinator.customGroupsFileForTesting = File(
      '${dir.path}/groups.json',
    );
    coordinator = MessengerCoordinator(
      knownDevices: KnownDevicesRegistry('${dir.path}/devices.json'),
    );
    await coordinator.historyLoaded;
    coordinator.selectPeer(
      PeerModel(id: 'peer', name: 'Peer', ip: '192.0.2.1'),
    );
  });
  tearDown(() async {
    await coordinator.chatHistory.flush();
    coordinator.dispose();
    ChatHistoryService().setCustomDirectoryForTesting(null);
    AppPreferences().setCustomFileForTesting(null);
    MessengerCoordinator.customGroupsFileForTesting = null;
  });

  test(
    'batch metadata roundtrips; legacy and different sessions do not merge',
    () {
      final first = attachment('a');
      final next = MessageModel.fromJson(attachment('b').toJson());
      expect(first.sharesAttachmentBatch(next), isTrue);
      expect(
        first.sharesAttachmentBatch(attachment('c', batch: null)),
        isFalse,
      );
      expect(
        first.sharesAttachmentBatch(attachment('c', sender: 'other')),
        isFalse,
      );
      expect(
        first.sharesAttachmentBatch(attachment('c', session: 'other')),
        isFalse,
      );
      next.isRevoked = true;
      expect(first.sharesAttachmentBatch(next), isFalse);
    },
  );

  test(
    'missing first file does not discard remaining files or batch history',
    () async {
      final dir = await Directory.systemTemp.createTemp('ja_missing_batch_');
      final valid = await File(
        '${dir.path}/second.txt',
      ).writeAsString('second');
      // Without a listening transport the second file has a failed offer, but it
      // must still be attempted and represented independently of the missing one.
      await expectLater(
        coordinator.sendFiles([File('${dir.path}/missing.txt'), valid]),
        throwsStateError,
      );
      final messages = coordinator.conversationsMap['peer']!;
      expect(messages, hasLength(2));
      expect(messages.every((m) => m.status == MessageStatus.failed), isTrue);
      expect(messages[0].sharesAttachmentBatch(messages[1]), isTrue);
      expect(messages[1].fileAttachment!.fileSize, 6);
      await coordinator.chatHistory.flush();
      final restored = await coordinator.chatHistory.loadConversation('peer');
      expect(restored, hasLength(2));
      expect(restored[0].sharesAttachmentBatch(restored[1]), isTrue);
    },
  );

  for (final imageGrid in [false, true]) {
    testWidgets('offscreen attachments stay unread, imageGrid=$imageGrid', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(960, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
      const channel = MethodChannel('window_manager');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'isFocused' || call.method == 'isVisible') {
              return true;
            }
            if (call.method == 'isMinimized') return false;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        AppPowerManager.instance.resetForTesting(enableIdleSleep: false);
      });
      final messages = List.generate(
        15,
        (i) => MessageModel(
          id: 'file_remote_$i',
          senderId: 'peer',
          senderName: 'Peer',
          recipientId: 'me',
          text: '',
          isMine: false,
          status: MessageStatus.delivered,
          attachmentBatchId: 'batch_incoming',
          sourceSession: '192.0.2.1:6475',
          fileAttachment: FileAttachmentInfo(
            fileName: 'attachment_$i.${imageGrid ? 'png' : 'txt'}',
            fileSize: 20,
          ),
        ),
      );
      coordinator.conversationsMap['peer'] = messages;
      final theme = ThemeProvider()..setPerfTierMode(PerfTierMode.lite);
      final lang = LanguageProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: coordinator),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView).first, const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 650)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(messages.first.status, MessageStatus.delivered);
      expect(messages.last.status, MessageStatus.read);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(coordinator.chatHistory.flush);
      theme.dispose();
      lang.dispose();
    });
  }

  testWidgets('multiple real image thumbnails share one bubble', (
    tester,
  ) async {
    final files = await tester.runAsync(() async {
      final dir = await Directory.systemTemp.createTemp('ja_batch_images_');
      final bytes = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
      );
      return [
        await File('${dir.path}/one.png').writeAsBytes(bytes),
        await File('${dir.path}/two.png').writeAsBytes(bytes),
      ];
    });
    coordinator.conversationsMap['peer'] = [
      for (var i = 0; i < files!.length; i++)
        MessageModel(
          id: 'image_$i',
          senderId: 'me',
          senderName: 'me',
          recipientId: 'peer',
          text: '',
          isMine: true,
          status: i == 0 ? MessageStatus.delivered : MessageStatus.read,
          attachmentBatchId: 'batch_images',
          fileAttachment: FileAttachmentInfo(
            fileName: i == 0 ? 'one.png' : 'two.png',
            fileSize: 70,
            localPath: files[i].path,
          ),
        ),
    ];
    final theme = ThemeProvider()..setPerfTierMode(PerfTierMode.lite);
    final lang = LanguageProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: coordinator),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('attachment-batch-image_0')),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNWidgets(2));
    expect(find.text('one.png'), findsOneWidget);
    expect(find.text('two.png'), findsOneWidget);
    expect(find.text(lang.tr('attachmentReceived')), findsOneWidget);
    expect(find.text(lang.tr('seen')), findsNothing);
    expect(
      find.byKey(const ValueKey('attachment-batch-footer-image_0')),
      findsOneWidget,
    );
    final firstTile = tester.getRect(
      find.byKey(const ValueKey('attachment-tile-image_0')),
    );
    final secondTile = tester.getRect(
      find.byKey(const ValueKey('attachment-tile-image_1')),
    );
    expect(firstTile.top, secondTile.top);
    expect(firstTile.right, lessThan(secondTile.left));
    expect(firstTile.width, lessThan(190));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
    lang.dispose();
  });

  for (final scenario in [
    (3, 960.0, 3),
    (4, 960.0, 2),
    (7, 400.0, 2),
    (7, 960.0, 3),
  ]) {
    testWidgets(
      'adaptive image grid ${scenario.$1} images at ${scenario.$2}px',
      (tester) async {
        tester.view.physicalSize = Size(scenario.$2, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        coordinator.conversationsMap['peer'] = [
          for (var i = 0; i < scenario.$1; i++)
            MessageModel(
              id: 'grid_$i',
              senderId: 'me',
              senderName: 'me',
              recipientId: 'peer',
              text: '',
              isMine: true,
              status: i == 0 ? MessageStatus.failed : MessageStatus.read,
              attachmentBatchId: 'batch_grid',
              fileAttachment: FileAttachmentInfo(
                fileName: 'image_$i.png',
                fileSize: 10,
              ),
            ),
        ];
        final theme = ThemeProvider()..setPerfTierMode(PerfTierMode.lite);
        final lang = LanguageProvider();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: coordinator),
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
            ],
            child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
          ),
        );
        await tester.pumpAndSettle();
        final first = tester.getRect(
          find.byKey(const ValueKey('attachment-tile-grid_0')),
        );
        final lastOnRow = tester.getRect(
          find.byKey(ValueKey('attachment-tile-grid_${scenario.$3 - 1}')),
        );
        expect(first.top, lastOnRow.top);
        if (scenario.$1 > scenario.$3) {
          final next = tester.getRect(
            find.byKey(ValueKey('attachment-tile-grid_${scenario.$3}')),
          );
          expect(next.top, greaterThan(first.top));
        }
        expect(first.width, lessThan(200));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        theme.dispose();
        lang.dispose();
      },
    );
  }

  testWidgets('mixed batch keeps file rows full width and original order', (
    tester,
  ) async {
    coordinator.conversationsMap['peer'] = [
      attachment('mixed_0', fileName: 'first.png'),
      attachment('mixed_1', fileName: 'second.png'),
      attachment('mixed_2', fileName: 'document.pdf'),
      attachment('mixed_3', fileName: 'third.png'),
    ];
    final theme = ThemeProvider()..setPerfTierMode(PerfTierMode.lite);
    final lang = LanguageProvider();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: coordinator),
          ChangeNotifierProvider.value(value: theme),
          ChangeNotifierProvider.value(value: lang),
        ],
        child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getRect(
      find.byKey(const ValueKey('attachment-tile-mixed_0')),
    );
    final second = tester.getRect(
      find.byKey(const ValueKey('attachment-tile-mixed_1')),
    );
    final document = tester.getRect(
      find.byKey(const ValueKey('attachment-tile-mixed_2')),
    );
    final last = tester.getRect(
      find.byKey(const ValueKey('attachment-tile-mixed_3')),
    );
    expect(first.top, second.top);
    expect(document.width, greaterThan(first.width * 2));
    expect(document.top, greaterThan(first.top));
    expect(last.top, greaterThan(document.top));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    theme.dispose();
    lang.dispose();
  });

  for (final width in [400.0, 960.0]) {
    testWidgets('one shared bubble with individual attachments, width=$width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      coordinator.conversationsMap['peer'] = [
        attachment('a')..status = MessageStatus.delivered,
        attachment('b')..status = MessageStatus.read,
      ];
      final theme = ThemeProvider()..setPerfTierMode(PerfTierMode.lite);
      final lang = LanguageProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: coordinator),
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
          ],
          child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('attachment-batch-a')), findsOneWidget);
      expect(find.text('a.txt'), findsOneWidget);
      expect(find.text('b.txt'), findsOneWidget);
      expect(find.text(lang.tr('attachmentReceived')), findsOneWidget);
      expect(find.text(lang.tr('seen')), findsNothing);
      expect(
        find.byKey(const ValueKey('attachment-batch-footer-a')),
        findsOneWidget,
      );
      final first = coordinator.conversationsMap['peer']!.first;
      final time = first.timestamp.toLocal();
      final stamp =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
      expect(find.text(stamp), findsOneWidget);
      first.status = MessageStatus.read;
      coordinator.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text(lang.tr('seen')), findsOneWidget);
      expect(find.text(lang.tr('attachmentReceived')), findsNothing);
      expect(find.text(stamp), findsOneWidget);
      first.status = MessageStatus.sending;
      coordinator.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text(lang.tr('seen')), findsNothing);
      expect(find.text(lang.tr('attachmentReceived')), findsNothing);
      first.status = MessageStatus.failed;
      coordinator.notifyListeners();
      await tester.pumpAndSettle();
      expect(find.text('${lang.tr('transferFailed')} (1/2)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      theme.dispose();
      lang.dispose();
    });
  }
}
