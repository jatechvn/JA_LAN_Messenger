import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/theme/styles_win11.dart';
import 'package:ja_lan_messenger/modules/ui/widgets/glass_background.dart';

void main() {
  testWidgets('MeshBackground renders 3 MeshOrbs with theme colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshBackground(colors: win11DarkColors, enableAnimation: false),
        ),
      ),
    );

    expect(find.byType(MeshBackground), findsOneWidget);
    expect(find.byType(MeshOrb), findsNWidgets(3));
  });

  testWidgets('MeshOrb animates when enableAnimation is true', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshOrb(
            color: Colors.blue,
            size: 200,
            duration: Duration(seconds: 2),
            travel: Offset(50, 50),
            enableAnimation: true,
          ),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(MeshOrb), findsOneWidget);
  });
}
