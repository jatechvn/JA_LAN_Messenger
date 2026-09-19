import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:ja_lan_messenger/modules/theme/theme_provider.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/markdown_message_view.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/chat_view_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestable(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  group('MarkdownMessageView Tests', () {
    testWidgets(
      'renders basic markdown and fenced code block with copy button',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const markdownSample = '''
**Tiêu đề in đậm**
Dưới đây là đoạn mã ví dụ:
```python
def hello():
    return "world"
```
''';

        await tester.pumpWidget(
          buildTestable(
            const MarkdownMessageView(
              text: markdownSample,
              isMine: false,
              isStreaming: false,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Verify code block card is created
        expect(find.byType(CodeBlockCard), findsOneWidget);

        // Verify language header
        expect(find.text('python'), findsOneWidget);

        // Verify copy code button exists
        expect(find.byIcon(Icons.copy_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'CodeBlockCard copy button copies code and provides copied feedback',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() => tester.view.resetPhysicalSize());

        const codeContent = 'const pi = 3.14159;';

        await tester.pumpWidget(
          buildTestable(
            const CodeBlockCard(
              code: codeContent,
              language: 'dart',
              isDark: true,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('dart'), findsOneWidget);
        expect(find.byIcon(Icons.copy_rounded), findsOneWidget);

        // Tap the copy button
        await tester.tap(find.byIcon(Icons.copy_rounded));
        await tester.pump();

        // Verify checkmark icon and copied text feedback appear
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      },
    );

    testWidgets('auto-closes unclosed code blocks during streaming', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1000, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Streaming text where closing ``` has not arrived yet
      const streamingSnippet = '''
Đây là kết quả đang tạo:
```dart
void test() {
''';

      await tester.pumpWidget(
        buildTestable(
          const MarkdownMessageView(
            text: streamingSnippet,
            isMine: false,
            isStreaming: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Parser successfully closed the block and rendered CodeBlockCard
      expect(find.byType(CodeBlockCard), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
    });

    testWidgets('ChatViewPanel displays markdown bubble and quick action bar', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final theme = ThemeProvider();
      final lang = LanguageProvider();
      final coordinator = MessengerCoordinator();
      addTearDown(() => coordinator.dispose());

      final peer = coordinator.allUsersPeer;
      coordinator.selectPeer(peer);

      // Add a test message with markdown code
      coordinator.conversationsMap[peer.id] = [
        MessageModel(
          id: 'test_msg_1',
          senderId: 'remote_user',
          senderName: 'Remote User',
          recipientId: peer.id,
          text:
              'Here is some code:\n```dart\nint add(int a, int b) => a + b;\n```',
          timestamp: DateTime.now(),
          isMine: false,
          status: MessageStatus.read,
        ),
      ];

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: theme),
            ChangeNotifierProvider.value(value: lang),
            ChangeNotifierProvider.value(value: coordinator),
          ],
          child: const MaterialApp(home: Scaffold(body: ChatViewPanel())),
        ),
      );

      await tester.pumpAndSettle();

      // Verify code block card is rendered in the chat panel
      expect(find.byType(CodeBlockCard), findsOneWidget);
      expect(find.text('dart'), findsOneWidget);
      expect(find.text('int add(int a, int b) => a + b;'), findsOneWidget);

      // Verify quick action buttons exist
      expect(find.byIcon(Icons.copy_rounded), findsWidgets);
    });
  });
}
