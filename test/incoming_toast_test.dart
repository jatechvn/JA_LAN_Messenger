import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/chat_history_service.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/ui/main_messenger_window.dart';

class _BatchCoordinator extends MessengerCoordinator {
  final recipients = <String?>[];
  final other = PeerModel(id: 'other', name: 'Other', ip: '192.0.2.2');
  @override
  Future<void> sendFile(
    File file, {
    String? caption,
    PeerModel? recipient,
  }) async {
    recipients.add(recipient?.id ?? selectedPeer?.id);
    selectPeer(other);
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Attachment batch keeps original recipient when selected chat changes',
    () async {
      final coordinator = _BatchCoordinator();
      addTearDown(coordinator.dispose);
      coordinator.selectPeer(
        PeerModel(id: 'original', name: 'Original', ip: '192.0.2.1'),
      );
      await coordinator.sendFiles([File('one'), File('two')]);
      expect(coordinator.recipients, ['original', 'original']);
    },
  );

  for (final compact in [false, true]) {
    testWidgets(
      'Incoming toast survives missing Windows plugin, compact=$compact',
      (tester) async {
        tester.view.physicalSize = Size(compact ? 320 : 960, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final history = ChatHistoryService();
        history.setCustomDirectoryForTesting(
          Directory.systemTemp.createTempSync('toast_history_'),
        );
        final coordinator = MessengerCoordinator();
        coordinator.setCompactModeForTesting(compact);
        final theme = ThemeProvider()..setPerfTierMode(PerfTierMode.lite);
        final lang = LanguageProvider();
        final peer = PeerModel(
          id: '192.0.2.1:6475',
          name: 'Toast sender',
          ip: '192.0.2.1',
        );
        coordinator.peersMap[peer.id] = peer;
        addTearDown(() {
          coordinator.dispose();
          history.setCustomDirectoryForTesting(null);
        });
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: coordinator),
              ChangeNotifierProvider.value(value: theme),
              ChangeNotifierProvider.value(value: lang),
            ],
            child: const MaterialApp(home: MainMessengerWindow()),
          ),
        );
        await tester.pump();
        if (!compact) {
          await tester.tap(find.byKey(const ValueKey('own-nickname-button')));
          await tester.pump(const Duration(milliseconds: 400));
          await tester.enterText(
            find.byKey(const ValueKey('own-nickname-input')),
            'Johnny Test',
          );
          await tester.tap(find.text(lang.tr('save')));
          await tester.pump(const Duration(milliseconds: 400));
          expect(coordinator.localUsername, 'Johnny Test');
          expect(find.text('Johnny Test'), findsOneWidget);
        }
        coordinator.handleIncomingMessage(
          peer.id,
          'toast-1',
          'New message',
          DateTime.now(),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('💬 Toast sender: New message'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final firstToast = coordinator.currentToast;
        coordinator.handleIncomingMessage(
          peer.id,
          'toast-2',
          'New message',
          DateTime.now(),
        );
        expect(identical(firstToast, coordinator.currentToast), false);
        await tester.pumpWidget(const SizedBox());
        history.setCustomDirectoryForTesting(null);
      },
    );
  }
}
