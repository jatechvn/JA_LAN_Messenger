import 'dart:io';
import 'dart:typed_data';

/// Tool tự động quét, chuẩn hóa và phân loại Sticker Zalo (Sprite Sheet vs Preview)
/// Chạy bằng lệnh: dart run tool/organize_stickers.dart
void main() async {
  final currentDir = Directory.current.path;
  print('======================================================');
  print('=== JA LAN MESSENGER - ZALO STICKER ORGANIZER TOOL ===');
  print('======================================================');
  print('Project root: $currentDir');

  final sourceRoot = Directory('$currentDir/assets/sticker');
  if (!sourceRoot.existsSync()) {
    print('❌ Không tìm thấy thư mục nguồn: ${sourceRoot.path}');
    return;
  }

  final targetRoot = Directory('$currentDir/assets/stickers');
  if (!targetRoot.existsSync()) {
    targetRoot.createSync(recursive: true);
  }

  // Quét các thư mục pack (0, 1, 2...)
  final packDirs = sourceRoot
      .listSync()
      .whereType<Directory>()
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  if (packDirs.isEmpty) {
    print('⚠️ Thư mục assets/sticker trống hoặc không có thư mục con nào.');
    return;
  }

  int totalPacks = 0;
  int totalStickers = 0;

  for (final packDir in packDirs) {
    final packName = packDir.path.split(Platform.pathSeparator).last;
    final targetPackDir = Directory('${targetRoot.path}/pack_$packName');
    if (!targetPackDir.existsSync()) {
      targetPackDir.createSync(recursive: true);
    }

    print('\n📦 Đang xử lý bộ sticker: [pack_$packName] ...');

    // Quét các thư mục con hoặc file bên trong packDir
    final entries = packDir.listSync(recursive: true);
    
    // Nhóm theo thư mục cha chứa 2 file
    final Map<String, List<File>> stickerGroups = {};
    for (final entry in entries) {
      if (entry is File) {
        final ext = entry.path.toLowerCase();
        if (ext.endsWith('.png') || ext.endsWith('.webp') || !ext.contains('.')) {
          final parentPath = entry.parent.path;
          stickerGroups.putIfAbsent(parentPath, () => []).add(entry);
        }
      }
    }

    int stickerIndex = 1;

    for (final entry in stickerGroups.entries) {
      final files = entry.value;
      if (files.isEmpty) continue;

      File? spriteFile;
      File? previewFile;

      if (files.length == 1) {
        // Chỉ có 1 file duy nhất
        final dims = _getImageDimensions(files.first);
        if (dims != null && dims.width > dims.height * 1.5) {
          spriteFile = files.first;
        } else {
          previewFile = files.first;
        }
      } else {
        // Có 2 hoặc nhiều file, phân loại theo tỷ lệ Width / Height hoặc dung lượng
        File? widest;
        double maxRatio = 0.0;

        for (final file in files) {
          final dims = _getImageDimensions(file);
          if (dims != null) {
            final ratio = dims.width / dims.height;
            if (ratio > maxRatio) {
              maxRatio = ratio;
              widest = file;
            }
          }
        }

        if (maxRatio > 1.5 && widest != null) {
          spriteFile = widest;
          previewFile = files.firstWhere((f) => f.path != widest!.path, orElse: () => files.first);
        } else {
          // Fallback: file có dung lượng lớn hơn là file động
          files.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
          spriteFile = files.first;
          previewFile = files.last;
        }
      }

      final idStr = stickerIndex.toString().padLeft(2, '0');

      // Copy file preview
      if (previewFile != null) {
        final targetPreview = File('${targetPackDir.path}/s${idStr}_preview.png');
        previewFile.copySync(targetPreview.path);
      }

      // Copy file sprite sheet
      if (spriteFile != null) {
        final targetSprite = File('${targetPackDir.path}/s${idStr}_sprite.png');
        spriteFile.copySync(targetSprite.path);
      }

      // Tạo icon đại diện cho bộ nếu chưa có
      final packIcon = File('${targetPackDir.path}/icon.png');
      if (!packIcon.existsSync() && previewFile != null) {
        previewFile.copySync(packIcon.path);
      }

      stickerIndex++;
      totalStickers++;
    }

    print('   ✓ Đã chuẩn hóa ${stickerIndex - 1} sticker vào: assets/stickers/pack_$packName/');
    totalPacks++;
  }

  print('\n======================================================');
  print('🎉 HOÀN TẤT! Đã chuẩn hóa $totalStickers sticker trong $totalPacks bộ.');
  print('👉 Thư mục đích: assets/stickers/');
  print('======================================================\n');
}

class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);
}

/// Đọc nhanh kích thước PNG trực tiếp từ IHDR header (bytes 16..24) mà không cần decode ảnh
ImageDimensions? _getImageDimensions(File file) {
  try {
    final bytes = file.readAsBytesSync();
    if (bytes.length < 24) return null;

    // Check PNG signature: 89 50 4E 47 0D 0A 1A 0A
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final buffer = ByteData.sublistView(Uint8List.fromList(bytes.sublist(16, 24)));
      final width = buffer.getUint32(0, Endian.big);
      final height = buffer.getUint32(4, Endian.big);
      return ImageDimensions(width, height);
    }
  } catch (_) {}
  return null;
}
