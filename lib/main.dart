import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:local_notifier/local_notifier.dart';
import 'modules/theme/theme_provider.dart';
import 'modules/localization/app_locale.dart';
import 'modules/services/messenger_coordinator.dart';
import 'modules/ui/main_messenger_window.dart';
import 'modules/build_info.dart';
import 'modules/constants.dart';
import 'modules/logger_config.dart';
import 'modules/window_helper.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  if (args.contains('-debug') ||
      args.contains('--debug') ||
      args.contains('-d')) {
    BuildInfo.isCliDebug = true;
  }
  setupLogger();

  // Khởi tạo thông báo Desktop Windows & Linux
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux)) {
    try {
      await localNotifier.setup(
        appName: appName,
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
    } catch (e) {
      debugPrint('[Notification] Setup error: $e');
    }
  }

  // Khởi tạo cửa sổ Desktop nhỏ gọn, nhẹ, tốc độ cao
  await initGlassWindow(
    title: appName,
    size: const Size(defaultWindowWidth, defaultWindowHeight),
    minSize: const Size(minWindowWidth, minWindowHeight),
  );

  runApp(const JaLanMessengerApp());
}

class JaLanMessengerApp extends StatelessWidget {
  const JaLanMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => MessengerCoordinator()),
      ],
      child: const _MessengerAppContent(),
    );
  }
}

class _MessengerAppContent extends StatelessWidget {
  const _MessengerAppContent();

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final effectiveTitle = (!kIsWeb && Platform.isWindows && !theme.isWin11)
        ? ''
        : appName;

    return MaterialApp(
      title: effectiveTitle,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: theme.isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: const MainMessengerWindow(),
    );
  }
}
