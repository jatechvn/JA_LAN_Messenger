import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../localization/app_locale.dart';
import 'message_entity_detector.dart';

/// Helper thực thi các tiện ích nhanh (mở link, gọi điện, soạn email, mở thư mục, copy)
class QuickActionHelper {
  /// Mở liên kết Web an toàn trên trình duyệt mặc định
  static Future<bool> openUrl(String url) async {
    try {
      var target = url.trim();
      if (!target.startsWith('http://') &&
          !target.startsWith('https://') &&
          !target.startsWith('mailto:') &&
          !target.startsWith('tel:')) {
        target = 'https://$target';
      }

      if (Platform.isWindows) {
        // explorer.exe sử dụng Windows ShellExecute, tự động mở trình duyệt mặc định
        // an toàn với các ký tự đặc biệt như '&', '?', '=' mà không dùng shell
        final res = await Process.run('explorer.exe', [target]);
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('open', [target]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [target]);
        return res.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('[QuickActionHelper] openUrl error: $e');
      return false;
    }
  }

  /// Soạn email qua ứng dụng Mail mặc định của Windows
  static Future<bool> composeEmail(String email) async {
    try {
      final cleanEmail = email.trim().replaceFirst(
        RegExp(r'^mailto:', caseSensitive: false),
        '',
      );
      final mailtoUri = 'mailto:$cleanEmail';

      if (Platform.isWindows) {
        final res = await Process.run('explorer.exe', [mailtoUri]);
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('open', [mailtoUri]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [mailtoUri]);
        return res.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('[QuickActionHelper] composeEmail error: $e');
      return false;
    }
  }

  /// Gọi điện thoại qua giao thức tel: (liên kết Phone Link / Skype / ứng dụng gọi mặc định)
  static Future<bool> callPhone(String phone) async {
    try {
      final digits = phone.replaceAll(RegExp(r'[\s.-]'), '');
      final telUri = 'tel:$digits';

      if (Platform.isWindows) {
        final res = await Process.run('explorer.exe', [telUri]);
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('open', [telUri]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [telUri]);
        return res.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('[QuickActionHelper] callPhone error: $e');
      return false;
    }
  }

  /// Mở file hoặc thư mục trên Windows Explorer (UNC hoặc ổ đĩa cục bộ)
  static Future<bool> openPath(String path) async {
    try {
      final cleanPath = path.trim();
      if (Platform.isWindows) {
        // Nếu là file đã tồn tại, dùng /select để mở thư mục và chọn đúng file
        if (File(cleanPath).existsSync()) {
          final res = await Process.run('explorer.exe', [
            '/select,',
            cleanPath,
          ]);
          return res.exitCode == 0;
        }

        // Nếu là thư mục hoặc đường dẫn UNC mạng LAN
        final res = await Process.run('explorer.exe', [cleanPath]);
        return res.exitCode == 0;
      } else if (Platform.isMacOS) {
        final res = await Process.run('open', [cleanPath]);
        return res.exitCode == 0;
      } else if (Platform.isLinux) {
        final res = await Process.run('xdg-open', [cleanPath]);
        return res.exitCode == 0;
      }
      return false;
    } catch (e) {
      debugPrint('[QuickActionHelper] openPath error: $e');
      return false;
    }
  }

  /// Sao chép vào clipboard kèm hiển thị Floating SnackBar
  static Future<void> copyToClipboard(
    BuildContext context,
    String text, {
    String? message,
  }) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message ?? 'Đã sao chép vào bộ nhớ tạm'),
          duration: const Duration(milliseconds: 1400),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// Xử lý mở nhanh từ link click (trong Markdown onTapLink)
  static Future<void> handleActionUrl(
    BuildContext context,
    String? href, {
    LanguageProvider? lang,
  }) async {
    if (href == null || href.trim().isEmpty) return;
    final target = href.trim();

    if (target.startsWith('mailto:')) {
      await composeEmail(target.substring(7));
    } else if (target.startsWith('tel:')) {
      await callPhone(target.substring(4));
    } else if (target.startsWith('file://')) {
      await openPath(target.substring(7));
    } else if (target.startsWith(r'\\') ||
        RegExp(r'^[a-zA-Z]:\\').hasMatch(target)) {
      await openPath(target);
    } else {
      await openUrl(target);
    }
  }

  /// Xử lý thực thể khi người dùng nhấp vào Quick Action Chip
  static Future<void> handleEntityClick(
    BuildContext context,
    MessageEntity entity, {
    LanguageProvider? lang,
  }) async {
    switch (entity.type) {
      case MessageEntityType.url:
        await openUrl(entity.actionUrl);
        break;
      case MessageEntityType.email:
        await composeEmail(entity.value);
        break;
      case MessageEntityType.phone:
        // Với SĐT, mở menu lựa chọn Gọi hoặc Sao chép
        await _showPhoneOptions(context, entity.value, lang);
        break;
      case MessageEntityType.path:
        await openPath(entity.value);
        break;
    }
  }

  static Future<void> _showPhoneOptions(
    BuildContext context,
    String phone,
    LanguageProvider? lang,
  ) async {
    final callText = lang?.tr('callPhone') ?? 'Gọi điện';
    final copyText = lang?.tr('copyPhone') ?? 'Sao chép số';
    final copiedToast =
        lang?.tr('phoneCopiedToast') ?? 'Đã sao chép số điện thoại';

    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.phone_rounded, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(
              phone,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: Text(copyText),
            onPressed: () => Navigator.of(ctx).pop('copy'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.call_rounded, size: 16),
            label: Text(callText),
            onPressed: () => Navigator.of(ctx).pop('call'),
          ),
        ],
      ),
    );

    if (choice == 'call') {
      await callPhone(phone);
    } else if (choice == 'copy' && context.mounted) {
      await copyToClipboard(context, phone, message: copiedToast);
    }
  }
}
