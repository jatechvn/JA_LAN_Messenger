import 'dart:typed_data';
import 'dart:ui' as ui;

/// Windows clipboard images may be BMP even when the destination ends in .png.
Future<Uint8List> clipboardImageToPng(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    try {
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Cannot encode clipboard image as PNG');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      frame.image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
