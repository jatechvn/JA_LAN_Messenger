import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Bộ tiện ích xử lý ảnh đại diện (Avatar Utilities)
class AvatarUtils {
  /// Đọc file ảnh từ đường dẫn và nén thành thumbnail nhỏ gọn (mặc định 96x96 PNG),
  /// trả về chuỗi Base64 thích hợp để gửi qua gói tin LAN P2P.
  static Future<String?> generateAvatarThumbnailBase64(
    String filePath, {
    int maxSize = 96,
  }) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final bytes = await file.readAsBytes();
      return bytesToThumbnailBase64(bytes, maxSize: maxSize);
    } catch (_) {
      return null;
    }
  }

  /// Nén mảng bytes ảnh thành thumbnail Base64
  static Future<String?> bytesToThumbnailBase64(
    Uint8List bytes, {
    int maxSize = 96,
  }) async {
    if (bytes.isEmpty) return null;

    try {
      // Thử nén qua engine đồ họa Flutter dart:ui
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: maxSize,
        targetHeight: maxSize,
      );
      final frame = await codec.getNextFrame();
      final byteData = await frame.image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        final pngBytes = byteData.buffer.asUint8List();
        return base64Encode(pngBytes);
      }
    } catch (_) {
      // Fallback khi chạy unit test (chưa có engine render) hoặc codec lỗi:
      // Nếu kích thước gốc <= 48KB, mã hóa base64 trực tiếp
      if (bytes.length <= 49152) {
        return base64Encode(bytes);
      }
    }
    return null;
  }
}
