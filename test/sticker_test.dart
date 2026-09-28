import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/sticker_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StickerService Token Detection and Parsing', () {
    test('isSticker correctly identifies sticker tokens', () {
      expect(StickerService.isSticker('[sticker:0/1]'), isTrue);
      expect(StickerService.isSticker('[sticker:pack_0/5]'), isTrue);
      expect(StickerService.isSticker('  [sticker:pack_0/1]  '), isTrue);
      expect(StickerService.isSticker('hello world'), isFalse);
      expect(StickerService.isSticker('[sticker:'), isFalse);
      expect(StickerService.isSticker('[sticker:0/1'), isFalse);
      expect(StickerService.isSticker('sticker:0/1]'), isFalse);
      expect(StickerService.isSticker(''), isFalse);
      expect(StickerService.isSticker('[sticker:/1]'), isFalse);
      expect(StickerService.isSticker('[sticker:0/1] text [other]'), isFalse);
      expect(StickerService.isSticker('[sticker:0/1/extra]'), isFalse);
    });

    test('parseStickerToken extracts packId and stickerId', () {
      final res1 = StickerService.parseStickerToken('[sticker:0/1]');
      expect(res1, isNotNull);
      expect(res1!.$1, equals('0'));
      expect(res1.$2, equals('1'));

      final res2 = StickerService.parseStickerToken(
        '[sticker:pack_12/item_99]',
      );
      expect(res2, isNotNull);
      expect(res2!.$1, equals('pack_12'));
      expect(res2.$2, equals('item_99'));

      expect(StickerService.parseStickerToken('not a sticker'), isNull);
      expect(StickerService.parseStickerToken('[sticker:no_slash]'), isNull);
    });

    test('containsSticker detects tokens with sender prefix', () {
      expect(StickerService.containsSticker('[sticker:0/1]'), isTrue);
      expect(StickerService.containsSticker('Alice: [sticker:0/1]'), isTrue);
      expect(
        StickerService.containsSticker('Bob: [sticker:pack_1/10]'),
        isTrue,
      );
      expect(StickerService.containsSticker('Alice: Hello there!'), isFalse);
      expect(StickerService.containsSticker('Just text'), isFalse);
    });

    test('formatLastMessagePreview formats tokens cleanly for chat list', () {
      expect(
        StickerService.formatLastMessagePreview('[sticker:0/1]', 'Nhãn dán'),
        equals('[Nhãn dán]'),
      );
      expect(
        StickerService.formatLastMessagePreview(
          'Alice: [sticker:0/1]',
          'Nhãn dán',
        ),
        equals('Alice: [Nhãn dán]'),
      );
      expect(
        StickerService.formatLastMessagePreview('Alice: Xin chào', 'Nhãn dán'),
        equals('Alice: Xin chào'),
      );
    });

    test('StickerItem token getter produces correct protocol format', () {
      const item = StickerItem(
        id: '1',
        packId: 'pack_0',
        previewPath: 'path/preview.png',
        spritePath: 'path/sprite.png',
      );
      expect(item.token, equals('[sticker:pack_0/1]'));
    });
  });

  group('StickerService Automatic Sprite Sheet & Preview Detection', () {
    late Directory tempDir;

    Uint8List createMockPngHeader({required int width, required int height}) {
      final bytes = Uint8List(33);
      // PNG Signature
      bytes.setRange(0, 8, [137, 80, 78, 71, 13, 10, 26, 10]);
      // IHDR chunk length: 13
      bytes.setRange(8, 12, [0, 0, 0, 13]);
      // 'IHDR'
      bytes.setRange(12, 16, [73, 72, 68, 82]);
      // Width (32-bit big endian)
      bytes[16] = (width >> 24) & 0xFF;
      bytes[17] = (width >> 16) & 0xFF;
      bytes[18] = (width >> 8) & 0xFF;
      bytes[19] = width & 0xFF;
      // Height (32-bit big endian)
      bytes[20] = (height >> 24) & 0xFF;
      bytes[21] = (height >> 16) & 0xFF;
      bytes[22] = (height >> 8) & 0xFF;
      bytes[23] = height & 0xFF;
      // Bit depth, color type, compression, filter, interlace
      bytes[24] = 8;
      bytes[25] = 6;
      bytes[26] = 0;
      bytes[27] = 0;
      bytes[28] = 0;
      // CRC dummy
      bytes.setRange(29, 33, [0, 0, 0, 0]);
      return bytes;
    }

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('ja_sticker_test_');
      final packDir = Directory('${tempDir.path}/assets/sticker/pack_0');
      await packDir.create(recursive: true);

      // Sticker 1 folder with Sprite Sheet (ratio > 1.5) and Preview (ratio <= 1.5)
      final sticker1Dir = Directory('${packDir.path}/1');
      await sticker1Dir.create(recursive: true);

      // Sprite file: width 3200, height 130 (ratio = 24.6 > 1.5)
      final spriteFile = File('${sticker1Dir.path}/sprite_sheet.png');
      await spriteFile.writeAsBytes(
        createMockPngHeader(width: 3200, height: 130),
      );

      // Preview file: width 130, height 130 (ratio = 1.0 <= 1.5)
      final previewFile = File('${sticker1Dir.path}/preview_thumb.png');
      await previewFile.writeAsBytes(
        createMockPngHeader(width: 130, height: 130),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Scans disk directory and auto-classifies sprite and preview',
      () async {
        final service = StickerService();
        // Scan explicitly from test directory
        final stickerRoot = Directory('${tempDir.path}/assets/sticker');
        expect(await stickerRoot.exists(), isTrue);

        await service.loadPacks(customSearchPath: stickerRoot.path);

        expect(service.packs, isNotEmpty);
        final pack = service.packs.firstWhere((p) => p.id == 'pack_0');
        expect(pack.stickers, isNotEmpty);

        final sticker1 = pack.stickers.firstWhere((s) => s.id == '1');
        expect(sticker1.isFromFile, isTrue);
        expect(sticker1.spritePath.contains('sprite_sheet.png'), isTrue);
        expect(sticker1.previewPath.contains('preview_thumb.png'), isTrue);

        // Verify token search resilience
        final foundExact = service.findByToken('[sticker:pack_0/1]');
        expect(foundExact, isNotNull);
        expect(foundExact!.id, equals('1'));

        final foundWithoutPrefix = service.findByToken('[sticker:0/1]');
        expect(foundWithoutPrefix, isNotNull);
        expect(foundWithoutPrefix!.id, equals('1'));
        expect(service.findByToken('[sticker:missing_pack/1]'), isNull);
      },
    );
  });
}
