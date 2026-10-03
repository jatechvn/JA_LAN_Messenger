import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/constants.dart';

/// Source contracts only: Task Manager rendering requires a rebuilt native EXE.
void main() {
  test('Flutter application always provides its shell name', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(appName, 'JA LAN Messenger');
    expect(source, contains('title: appName,'));
    expect(source, isNot(contains('title: effectiveTitle')));
  });
  test('native startup uses the same friendly name', () {
    final source = File('windows/runner/main.cpp').readAsStringSync();
    expect(source, contains('window.Create(L"$appName", origin, size)'));
  });
  test(
    'native window never replaces the title with an empty Windows 10 caption',
    () {
      final source = File('windows/runner/win32_window.cpp').readAsStringSync();
      expect(
        source,
        contains('window_class, title.c_str(), WS_OVERLAPPEDWINDOW'),
      );
      expect(
        source,
        isNot(contains('IsWindows11OrGreater() ? title.c_str() : L""')),
      );
    },
  );
  test(
    'desktop window helper applies window title on Windows initialization',
    () {
      final source = File('lib/modules/window_helper.dart').readAsStringSync();
      expect(source, contains('await windowManager.setTitle(title);'));
    },
  );
  test('EXE description, company, product and copyright match branding', () {
    final source = File('windows/runner/Runner.rc').readAsStringSync();
    for (final field in ['FileDescription', 'ProductName']) {
      expect(source, contains('VALUE "$field", "$appName"'));
    }
    expect(source, contains('VALUE "CompanyName", "JA Tech"'));
    expect(
      source,
      contains(
        'VALUE "LegalCopyright", "Copyright (C) 2026 JA Tech. All rights reserved."',
      ),
    );
    expect(
      source,
      contains('VALUE "OriginalFilename", "ja_lan_messenger.exe"'),
    );
  });
}
