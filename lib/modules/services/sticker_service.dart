import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class StickerItem {
  final String id;
  final String packId;
  final String previewPath;
  final String spritePath;
  final bool isFromFile;

  const StickerItem({
    required this.id,
    required this.packId,
    required this.previewPath,
    required this.spritePath,
    this.isFromFile = false,
  });

  /// Token định danh gửi qua mạng LAN: [sticker:0/subfolder_id]
  String get token => '[sticker:$packId/$id]';
}

class StickerPack {
  final String id;
  final String name;
  final String iconPath;
  final bool isFromFile;
  final List<StickerItem> stickers;

  const StickerPack({
    required this.id,
    required this.name,
    required this.iconPath,
    this.isFromFile = false,
    required this.stickers,
  });
}

class StickerService with ChangeNotifier {
  static final StickerService _instance = StickerService._internal();
  factory StickerService() => _instance;
  StickerService._internal();

  final List<StickerPack> _packs = [];
  List<StickerPack> get packs => List.unmodifiable(_packs);

  bool _isInitialized = false;
  bool get isInitialized => _isInitialized;

  /// Nạp các bộ sticker tự động:
  /// Ưu tiên quét trực tiếp thư mục `assets/sticker` (giữ nguyên cấu trúc gốc của Zalo, không cần đổi tên)
  Future<void> loadPacks({String? customSearchPath}) async {
    _packs.clear();

    // 1. Quét trực tiếp thư mục trên ổ đĩa (assets/sticker hoặc assets/stickers)
    await _loadFromLocalFilesystem(customSearchPath);

    // 2. Nếu chưa có trên ổ đĩa, thử nạp từ AssetManifest (Flutter Bundled)
    if (_packs.isEmpty) {
      await _loadFromAssetManifest();
    }

    _isInitialized = true;
    notifyListeners();
    debugPrint('[StickerService] Đã sẵn sàng với ${_packs.length} bộ sticker.');
  }

  /// Quét trực tiếp thư mục Zalo nguyên bản (tên ngẫu nhiên, tự động nhận diện bằng kích thước ảnh)
  Future<void> _loadFromLocalFilesystem([String? customSearchPath]) async {
    try {
      String? exeDir;
      try {
        exeDir = File(Platform.resolvedExecutable).parent.path;
      } catch (_) {}

      final possibleDirs = [
        if (customSearchPath != null) Directory(customSearchPath),
        Directory('${Directory.current.path}/assets/sticker'),
        Directory('${Directory.current.path}/assets/stickers'),
        if (exeDir != null) ...[
          Directory('$exeDir/assets/sticker'),
          Directory('$exeDir/assets/stickers'),
        ],
        Directory('assets/sticker'),
        Directory('assets/stickers'),
      ];

      Directory? validDir;
      for (final dir in possibleDirs) {
        if (dir.existsSync()) {
          validDir = dir;
          break;
        }
      }

      if (validDir == null) return;

      final packDirs = validDir.listSync().whereType<Directory>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

      for (final packDir in packDirs) {
        final packId = packDir.path.split(Platform.pathSeparator).last;
        final subEntries = packDir.listSync(recursive: true);

        // Nhóm các file theo từng thư mục con (mỗi sticker thường là 1 thư mục con)
        final Map<String, List<File>> groups = {};
        for (final entry in subEntries) {
          if (entry is File) {
            final parent = entry.parent.path;
            groups.putIfAbsent(parent, () => []).add(entry);
          }
        }

        final List<StickerItem> items = [];
        String? packIconPath;

        for (final entry in groups.entries) {
          final parentDirName = entry.key.split(Platform.pathSeparator).last;
          if (parentDirName == packId && groups.length > 1) {
            // File nằm trực tiếp ở root của pack (có thể là icon)
            continue;
          }

          final files = entry.value;
          if (files.isEmpty) continue;

          File? spriteFile;
          File? previewFile;

          if (files.length == 1) {
            final dims = _getImageDimensions(files.first);
            if (dims != null && dims.width > dims.height * 1.5) {
              spriteFile = files.first;
            } else {
              previewFile = files.first;
            }
          } else {
            // TỰ ĐỘNG PHÂN BIỆT BẰNG TỈ LỆ KÍCH THƯỚC ẢNH
            File? widest;
            double maxRatio = 0.0;

            for (final f in files) {
              final dims = _getImageDimensions(f);
              if (dims != null) {
                final ratio = dims.width / dims.height;
                if (ratio > maxRatio) {
                  maxRatio = ratio;
                  widest = f;
                }
              }
            }

            if (maxRatio > 1.5 && widest != null) {
              spriteFile = widest;
              previewFile = files.firstWhere(
                (f) => f.path != widest!.path,
                orElse: () => files.first,
              );
            } else {
              // Fallback theo dung lượng file
              files.sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));
              spriteFile = files.first;
              previewFile = files.last;
            }
          }

          if (previewFile != null || spriteFile != null) {
            final preview = (previewFile ?? spriteFile)!.path;
            final sprite = (spriteFile ?? previewFile)!.path;
            packIconPath ??= preview;

            items.add(
              StickerItem(
                id: parentDirName,
                packId: packId,
                previewPath: preview,
                spritePath: sprite,
                isFromFile: true,
              ),
            );
          }
        }

        if (items.isNotEmpty) {
          _packs.add(
            StickerPack(
              id: packId,
              name: _formatPackName(packId),
              iconPath: packIconPath ?? items.first.previewPath,
              isFromFile: true,
              stickers: items,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint(
        '[StickerService] Quét thư mục sticker trên ổ đĩa gặp lỗi: $e',
      );
    }
  }

  /// Nạp từ AssetManifest.json (nếu đã đóng gói asset)
  Future<void> _loadFromAssetManifest() async {
    try {
      final manifestJson = await rootBundle.loadString('AssetManifest.json');
      final Map<String, dynamic> manifestMap = json.decode(manifestJson);

      final stickerAssets = manifestMap.keys.where((String key) {
        return (key.startsWith('assets/sticker/') ||
                key.startsWith('assets/stickers/')) &&
            (key.endsWith('.png') || key.endsWith('.webp'));
      }).toList();

      if (stickerAssets.isEmpty) return;

      final Map<String, List<String>> packFiles = {};
      for (final asset in stickerAssets) {
        final parts = asset.split('/');
        if (parts.length >= 3) {
          final packName = parts[2];
          packFiles.putIfAbsent(packName, () => []).add(asset);
        }
      }

      for (final entry in packFiles.entries) {
        final packId = entry.key;
        final files = entry.value;

        final Map<String, String> previews = {};
        final Map<String, String> sprites = {};

        for (final file in files) {
          final fileName = file.split('/').last;
          if (fileName.contains('_preview')) {
            final id = fileName
                .replaceAll('_preview.png', '')
                .replaceAll('_preview.webp', '');
            previews[id] = file;
          } else if (fileName.contains('_sprite')) {
            final id = fileName
                .replaceAll('_sprite.png', '')
                .replaceAll('_sprite.webp', '');
            sprites[id] = file;
          }
        }

        final List<StickerItem> items = [];
        final allIds = {...previews.keys, ...sprites.keys}.toList()..sort();

        for (final id in allIds) {
          items.add(
            StickerItem(
              id: id,
              packId: packId,
              previewPath: previews[id] ?? sprites[id]!,
              spritePath: sprites[id] ?? previews[id]!,
              isFromFile: false,
            ),
          );
        }

        if (items.isNotEmpty) {
          _packs.add(
            StickerPack(
              id: packId,
              name: _formatPackName(packId),
              iconPath: items.first.previewPath,
              isFromFile: false,
              stickers: items,
            ),
          );
        }
      }
    } catch (_) {}
  }

  String _formatPackName(String packId) {
    if (packId == '0' || packId == 'pack_0') return 'Zalo Gốc';
    if (packId.startsWith('pack_')) {
      return 'Zalo ${packId.replaceFirst('pack_', '')}';
    }
    return 'Zalo $packId';
  }

  /// Kiểm tra tin nhắn có phải token sticker
  static bool isSticker(String text) {
    final trimmed = text.trim();
    return RegExp(r'^\[sticker:[^/\s\[\]]+/[^/\s\[\]]+\]$').hasMatch(trimmed);
  }

  /// Kiểm tra chuỗi có chứa hoặc kết thúc bằng token sticker (hỗ trợ cả tiền tố "Tên: [sticker:...]")
  static bool containsSticker(String text) {
    final trimmed = text.trim();
    if (isSticker(trimmed)) return true;
    final colonIndex = trimmed.indexOf(': [sticker:');
    if (colonIndex != -1 && trimmed.endsWith(']')) {
      final sub = trimmed.substring(colonIndex + 2).trim();
      return isSticker(sub);
    }
    return false;
  }

  /// Trích xuất text hiển thị gọn cho tin nhắn cuối cùng (Last Message)
  /// Ví dụ: "[sticker:0/1]" -> "[Nhãn dán]"
  /// "Nam: [sticker:0/1]" -> "Nam: [Nhãn dán]"
  static String formatLastMessagePreview(String text, String stickerLabel) {
    final trimmed = text.trim();
    if (isSticker(trimmed)) {
      return '[$stickerLabel]';
    }
    final colonIndex = trimmed.indexOf(': [sticker:');
    if (colonIndex != -1 && trimmed.endsWith(']')) {
      final prefix = trimmed.substring(0, colonIndex + 2);
      final sub = trimmed.substring(colonIndex + 2).trim();
      if (isSticker(sub)) {
        return '$prefix[$stickerLabel]';
      }
    }
    return text;
  }

  /// Parse token sticker thành (packId, stickerId)
  static (String, String)? parseStickerToken(String text) {
    if (!isSticker(text)) return null;
    final content = text.trim().substring(9, text.trim().length - 1);
    final parts = content.split('/');
    if (parts.length >= 2) {
      return (parts[0], parts[1]);
    }
    return null;
  }

  /// Tìm StickerItem theo token
  StickerItem? findByToken(String token) {
    final parsed = parseStickerToken(token);
    if (parsed == null) return null;
    final (packId, stickerId) = parsed;

    // 1. Khớp chính xác hoặc tương đương packId
    for (final pack in _packs) {
      final isMatch =
          pack.id == packId ||
          pack.id == 'pack_$packId' ||
          'pack_${pack.id}' == packId;
      if (isMatch) {
        for (final sticker in pack.stickers) {
          if (sticker.id == stickerId) return sticker;
        }
      }
    }

    return null;
  }
}

class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);
}

/// Đọc siêu tốc kích thước PNG từ IHDR header (bytes 16..24) mà không cần decode ảnh
ImageDimensions? _getImageDimensions(File file) {
  try {
    final bytes = file.readAsBytesSync();
    if (bytes.length < 24) return null;

    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      final buffer = ByteData.sublistView(
        Uint8List.fromList(bytes.sublist(16, 24)),
      );
      final width = buffer.getUint32(0, Endian.big);
      final height = buffer.getUint32(4, Endian.big);
      return ImageDimensions(width, height);
    }
  } catch (_) {}
  return null;
}
