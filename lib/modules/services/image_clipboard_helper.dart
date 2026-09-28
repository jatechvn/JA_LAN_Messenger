import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';
import '../localization/app_locale.dart';
import 'clipboard_image.dart';

/// Dịch vụ chuyên trách sao chép hình ảnh vào Clipboard hệ thống (CF_BITMAP)
/// Hỗ trợ đọc từ đường dẫn tệp (local file) hoặc mảng byte (Uint8List),
/// tự động fallback chuyển đổi sang PNG nếu gặp định dạng ảnh không tương thích Windows GDI+.
class ImageClipboardHelper {
  /// Sao chép ảnh vào Clipboard và hiển thị SnackBar thông báo.
  /// Trả về `true` nếu sao chép thành công, `false` nếu thất bại.
  static Future<bool> copyImageToClipboard(
    BuildContext context, {
    String? filePath,
    Uint8List? imageBytes,
    LanguageProvider? lang,
    bool showToast = true,
  }) async {
    try {
      Uint8List? bytes = imageBytes;
      if (bytes == null && filePath != null) {
        final file = File(filePath);
        if (!await file.exists()) {
          if (showToast && context.mounted) {
            _showToast(
              context,
              lang?.tr('fileNotFound') ?? 'Tệp không tồn tại',
            );
          }
          return false;
        }
        bytes = await file.readAsBytes();
      }

      if (bytes == null || bytes.isEmpty) {
        if (showToast && context.mounted) {
          _showToast(
            context,
            lang?.tr('copyImageFailed') ?? 'Không thể sao chép ảnh',
          );
        }
        return false;
      }

      // 1. Thử ghi trực tiếp vào Pasteboard
      bool copied = false;
      try {
        await Pasteboard.writeImage(bytes);
        copied = true;
      } catch (e) {
        debugPrint(
          '[ImageClipboardHelper] Direct writeImage error: $e. Retrying with PNG conversion...',
        );
        // 2. Fallback: Nếu định dạng đặc thù (WebP/TIFF), chuẩn hóa sang PNG bằng Flutter Codec
        try {
          final pngBytes = await clipboardImageToPng(bytes);
          await Pasteboard.writeImage(pngBytes);
          copied = true;
        } catch (e2) {
          debugPrint(
            '[ImageClipboardHelper] Fallback PNG writeImage error: $e2',
          );
        }
      }

      if (copied) {
        if (showToast && context.mounted) {
          _showToast(
            context,
            lang?.tr('imageCopiedToast') ?? 'Đã sao chép ảnh vào clipboard',
          );
        }
        return true;
      } else {
        if (showToast && context.mounted) {
          _showToast(
            context,
            lang?.tr('copyImageFailed') ?? 'Không thể sao chép ảnh',
          );
        }
        return false;
      }
    } catch (e) {
      debugPrint('[ImageClipboardHelper] Exception: $e');
      if (showToast && context.mounted) {
        _showToast(
          context,
          lang?.tr('copyImageFailed') ?? 'Không thể sao chép ảnh',
        );
      }
      return false;
    }
  }

  static void _showToast(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1500),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
