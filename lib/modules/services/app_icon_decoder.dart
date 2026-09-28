import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

/// Decodes PNG or uncompressed 32-bit DIB entries without a second icon asset.
Future<ui.Image> decodeAppIcon(Uint8List bytes) async {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 6 || data.getUint16(2, Endian.little) != 1) {
    throw const FormatException('Invalid ICO header');
  }
  final count = data.getUint16(4, Endian.little);
  if (count == 0 || bytes.length < 6 + count * 16) {
    throw const FormatException('Invalid ICO directory');
  }
  final entries = List.generate(count, (i) => 6 + i * 16);
  int dimension(int offset) => bytes[offset] == 0 ? 256 : bytes[offset];
  entries.sort(
    (a, b) => (dimension(b) * dimension(b + 1)).compareTo(
      dimension(a) * dimension(a + 1),
    ),
  );
  for (final entry in entries) {
    final length = data.getUint32(entry + 8, Endian.little);
    final offset = data.getUint32(entry + 12, Endian.little);
    if (length < 8 ||
        offset < 6 + count * 16 ||
        offset + length > bytes.length) {
      continue;
    }
    final payload = Uint8List.sublistView(bytes, offset, offset + length);
    if (payload[0] == 137 &&
        payload[1] == 80 &&
        payload[2] == 78 &&
        payload[3] == 71) {
      final codec = await ui.instantiateImageCodec(payload);
      try {
        return (await codec.getNextFrame()).image;
      } finally {
        codec.dispose();
      }
    }
    if (length < 40) continue;
    final dib = ByteData.sublistView(payload);
    if (dib.getUint32(0, Endian.little) != 40 ||
        dib.getUint16(14, Endian.little) != 32 ||
        dib.getUint32(16, Endian.little) != 0) {
      continue;
    }
    final width = dimension(entry);
    final height = dimension(entry + 1);
    if (dib.getInt32(4, Endian.little) != width ||
        dib.getInt32(8, Endian.little) != height * 2) {
      continue;
    }
    final maskStride = ((width + 31) ~/ 32) * 4;
    final maskOffset = 40 + width * height * 4;
    if (length < maskOffset + maskStride * height) continue;
    final rgba = Uint8List(width * height * 4);
    var hasAlpha = false;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final src = 40 + ((height - 1 - y) * width + x) * 4;
        final dst = (y * width + x) * 4;
        rgba[dst] = payload[src + 2];
        rgba[dst + 1] = payload[src + 1];
        rgba[dst + 2] = payload[src];
        rgba[dst + 3] = payload[src + 3];
        hasAlpha |= payload[src + 3] != 0;
      }
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final masked =
            payload[maskOffset + (height - 1 - y) * maskStride + x ~/ 8] &
                (0x80 >> (x % 8)) !=
            0;
        final alpha = (y * width + x) * 4 + 3;
        if (masked) {
          rgba[alpha] = 0;
        } else if (!hasAlpha) {
          rgba[alpha] = 255;
        }
      }
    }
    final result = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      result.complete,
    );
    return result.future;
  }
  throw const FormatException('ICO has no supported PNG/32-bit DIB entry');
}
