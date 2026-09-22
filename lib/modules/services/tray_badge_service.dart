import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Dịch vụ tạo icon thanh tác vụ (System Tray Icon) có hiển thị huy hiệu (badge)
/// thông báo số lượng tin nhắn chưa đọc cho Windows Desktop.
class TrayBadgeService {
  static final Map<String, String> _cache = {};

  /// Chuyển đổi dữ liệu ảnh PNG thành định dạng tệp .ICO chuẩn Windows (PNG-in-ICO container).
  static Uint8List wrapPngAsIco(
    Uint8List pngBytes, {
    int width = 32,
    int height = 32,
  }) {
    final builder = BytesBuilder();
    // ICONDIR Header (6 bytes): Reserved(2), Type(2=Icon), Count(2=1)
    builder.add([0, 0, 1, 0, 1, 0]);

    // ICONDIRENTRY (16 bytes)
    final w = (width >= 256) ? 0 : width;
    final h = (height >= 256) ? 0 : height;
    final len = pngBytes.length;

    builder.add([
      w,
      h,
      0, // Color count (0 = >=8bpp)
      0, // Reserved
      1,
      0, // Color planes (1)
      32,
      0, // Bits per pixel (32)
      len & 0xFF,
      (len >> 8) & 0xFF,
      (len >> 16) & 0xFF,
      (len >> 24) & 0xFF, // Image size
      22,
      0,
      0,
      0, // Offset of image data (6 + 16 = 22)
    ]);

    builder.add(pngBytes);
    return builder.toBytes();
  }

  /// Trả về đường dẫn tệp .ico có huy hiệu số lượng tin nhắn chưa đọc.
  /// Trả về null nếu unreadCount <= 0 (để ứng dụng dùng icon gốc assets/app_icon.ico).
  static Future<String?> getBadgeIconPath(int unreadCount) async {
    if (unreadCount <= 0) return null;

    final badgeText = unreadCount > 9 ? '9+' : '$unreadCount';
    final cacheKey = 'badge_$badgeText';

    if (_cache.containsKey(cacheKey)) {
      final cachedPath = _cache[cacheKey]!;
      if (await File(cachedPath).exists()) {
        return cachedPath;
      }
    }

    try {
      final tempDir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}ja_tray_cache',
      );
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      final targetFile = File(
        '${tempDir.path}${Platform.pathSeparator}tray_badge_$badgeText.ico',
      );

      final pngBytes = await _renderBadgePng(badgeText);
      if (pngBytes == null) return null;

      final icoBytes = wrapPngAsIco(pngBytes, width: 32, height: 32);
      await targetFile.writeAsBytes(icoBytes, flush: true);

      _cache[cacheKey] = targetFile.path;
      return targetFile.path;
    } catch (e) {
      debugPrint('[TrayBadgeService] Error generating badged tray icon: $e');
      return null;
    }
  }

  /// Vẽ biểu tượng ứng dụng và huy hiệu màu đỏ chứa số bằng Canvas
  static Future<Uint8List?> _renderBadgePng(String badgeText) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 32, 32));

    // 1. Nền icon ứng dụng: Hình tròn hoặc bo tròn màu xanh dương gradient JA LAN Messenger
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), const Offset(32, 32), [
        const Color(0xFF2563EB),
        const Color(0xFF0D9488),
      ]);
    final bgRRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(2, 2, 28, 28),
      const Radius.circular(8),
    );
    canvas.drawRRect(bgRRect, bgPaint);

    // 2. Vẽ biểu tượng chat bubble tinh gọn ở giữa
    final iconPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final bubbleRect = RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, 8, 18, 13),
      const Radius.circular(4),
    );
    canvas.drawRRect(bubbleRect, iconPaint);

    // Đuôi chat bubble
    final tailPath = ui.Path()
      ..moveTo(10, 20)
      ..lineTo(7, 24)
      ..lineTo(14, 21)
      ..close();
    canvas.drawPath(tailPath, iconPaint);

    // 3. Vẽ Huy hiệu đỏ nổi bật (Badge) ở góc trên bên phải
    final badgePaint = Paint()
      ..color = const Color(0xFFEF4444)
      ..style = PaintingStyle.fill;
    final badgeBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final isPlus = badgeText.contains('+');
    final badgeWidth = isPlus ? 16.0 : 13.0;
    final badgeHeight = 13.0;
    final badgeRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(32 - badgeWidth - 0.5, 0.5, badgeWidth, badgeHeight),
      Radius.circular(badgeHeight / 2),
    );

    canvas.drawRRect(badgeRect, badgePaint);
    canvas.drawRRect(badgeRect, badgeBorderPaint);

    // 4. Vẽ chữ số trong huy hiệu
    final textPainter = TextPainter(
      text: TextSpan(
        text: badgeText,
        style: TextStyle(
          color: Colors.white,
          fontSize: isPlus ? 8.0 : 8.5,
          fontWeight: FontWeight.w900,
          fontFamily: 'Segoe UI',
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    );
    textPainter.layout(minWidth: badgeWidth, maxWidth: badgeWidth);
    textPainter.paint(
      canvas,
      Offset(
        32 - badgeWidth - 0.5,
        0.5 + (badgeHeight - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(32, 32);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }
}
