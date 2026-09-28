import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'app_icon_decoder.dart';
import 'package:crypto/crypto.dart';

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
    try {
      final asset = await rootBundle.load('assets/app_icon.ico');
      final iconBytes = asset.buffer.asUint8List(
        asset.offsetInBytes,
        asset.lengthInBytes,
      );
      final cacheKey = '${sha256.convert(iconBytes)}_$badgeText';

      if (_cache.containsKey(cacheKey)) {
        final cachedPath = _cache[cacheKey]!;
        if (await File(cachedPath).exists()) {
          return cachedPath;
        }
      }

      final tempDir = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}ja_tray_cache',
      );
      if (!tempDir.existsSync()) {
        tempDir.createSync(recursive: true);
      }

      final targetFile = File(
        '${tempDir.path}${Platform.pathSeparator}tray_badge_$cacheKey.ico',
      );

      final pngBytes = await _renderBadgePng(badgeText, iconBytes);
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
  static Future<Uint8List?> _renderBadgePng(
    String badgeText,
    Uint8List iconBytes,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 32, 32));

    final base = await decodeAppIcon(iconBytes);
    final fitted = applyBoxFit(
      BoxFit.contain,
      Size(base.width.toDouble(), base.height.toDouble()),
      const Size(32, 32),
    );
    canvas.drawImageRect(
      base,
      Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
      Alignment.center.inscribe(
        fitted.destination,
        const Rect.fromLTWH(0, 0, 32, 32),
      ),
      Paint()..filterQuality = FilterQuality.medium,
    );

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
    try {
      final image = await picture.toImage(32, 32);
      try {
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        return byteData?.buffer.asUint8List();
      } finally {
        image.dispose();
      }
    } finally {
      picture.dispose();
      base.dispose();
      textPainter.dispose();
    }
  }
}
