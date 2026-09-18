import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/clipboard_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Windows BMP clipboard is encoded as real PNG with same pixel',
    () async {
      final bmp = Uint8List(58);
      final view = ByteData.sublistView(bmp);
      bmp.setRange(0, 2, [0x42, 0x4d]);
      view.setUint32(2, 58, Endian.little);
      view.setUint32(10, 54, Endian.little);
      view.setUint32(14, 40, Endian.little);
      view.setInt32(18, 1, Endian.little);
      view.setInt32(22, 1, Endian.little);
      view.setUint16(26, 1, Endian.little);
      view.setUint16(28, 24, Endian.little);
      view.setUint32(34, 4, Endian.little);
      bmp.setRange(54, 58, [0, 0, 255, 0]);
      final png = await clipboardImageToPng(bmp);
      expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      final codec = await ui.instantiateImageCodec(png);
      final frame = await codec.getNextFrame();
      expect(frame.image.width, 1);
      expect(frame.image.height, 1);
      final rgba = await frame.image.toByteData();
      expect(rgba!.buffer.asUint8List(), [255, 0, 0, 255]);
      frame.image.dispose();
      codec.dispose();
    },
  );
}
