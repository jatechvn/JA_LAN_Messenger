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
import 'modules/services/app_preferences.dart';
import 'modules/services/autostart_service.dart';
import 'modules/services/ota_update_service.dart';
import 'modules/ime/ime_service.dart';
import 'modules/ime/ime_types.dart';
import 'modules/services/sticker_service.dart';
import 'modules/services/app_power_manager.dart';
import 'modules/ui/widgets/app_power_scope.dart';
import 'modules/services/ota_staging_cleanup.dart';
import 'modules/power_aware_binding.dart';

void main(List<String> args) async {
  PowerAwareWidgetsBinding();

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
  final prefs = AppPreferences();
  if (kReleaseMode) {
    await AutostartService.ensureDefaultForNewInstallation(
      preferencesFile: prefs.preferencesFile,
    );
  }
  await prefs.load();
  AppPowerManager.instance.configure(
    enableIdleSleep: prefs.enableIdleSleep,
    idleTimeoutSeconds: prefs.idleTimeoutSeconds,
  );
  // Tự động nạp cấu hình OTA từ update_config.json nếu có
  await OtaUpdateService().syncExternalConfigToPreferences();

  // Khởi tạo bộ gõ IME từ cấu hình đã lưu
  final ime = ImeService();
  ime.setMode(ImeMode.fromId(prefs.imeMode));
  ime.setAutoBypassExternal(prefs.imeAutoBypassExternal);

  // Tự động nạp bộ nhãn dán Sticker
  await StickerService().loadPacks();

  await initGlassWindow(
    title: appName,
    size: prefs.isCompactMode
        ? Size(
            restoredCompactWidth(prefs.compactWidth),
            restoredCompactHeight(prefs.compactWidth, prefs.compactHeight),
          )
        : const Size(defaultWindowWidth, defaultWindowHeight),
    minSize: prefs.isCompactMode
        ? const Size(minCompactWidth, minCompactHeight)
        : const Size(minWindowWidth, minWindowHeight),
  );

  await AppPowerManager.instance.synchronizeNative();
  runApp(const JaLanMessengerApp());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await OtaStagingCleanup.complete(args);
    } catch (error) {
      debugPrint('[OTA] Staging cleanup deferred: $error');
    }
  });
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
        ChangeNotifierProvider.value(value: ImeService()),
        ChangeNotifierProvider.value(value: StickerService()),
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
    final lang = context.watch<LanguageProvider>();
    // Đồng bộ ngôn ngữ sang bộ gõ để thích ứng tự động
    context.read<ImeService>().updateAppLanguage(lang.code);

    return MaterialApp(
      // Keep the shell/app-switcher title nonempty on every Windows version.
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: theme.isDark ? Brightness.dark : Brightness.light,
        scaffoldBackgroundColor: Colors.transparent,
        popupMenuTheme: PopupMenuThemeData(
          color: theme.isDark ? const Color(0xFF1E293B) : Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.1,
              ),
              width: 1,
            ),
          ),
        ),
      ),
      builder: (context, child) {
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) =>
              AppPowerManager.instance.recordUserInteraction(),
          onPointerMove: (_) =>
              AppPowerManager.instance.recordUserInteraction(),
          onPointerHover: (_) =>
              AppPowerManager.instance.recordUserInteraction(),
          onPointerSignal: (_) =>
              AppPowerManager.instance.recordUserInteraction(),
          child: Focus(
            autofocus: false,
            onKeyEvent: (_, _) {
              AppPowerManager.instance.recordUserInteraction();
              return KeyEventResult.ignored;
            },
            child: AppPowerScope(child: child ?? const SizedBox.shrink()),
          ),
        );
      },
      home: const MainMessengerWindow(),
    );
  }
}
