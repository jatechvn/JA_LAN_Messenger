import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:ja_lan_messenger/modules/services/file_preview_inspector.dart';

int _crc(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = crc & 1 != 0 ? (crc >> 1) ^ 0xedb88320 : crc >> 1;
    }
  }
  return crc ^ 0xffffffff;
}

// Generates a valid ZIP, including local headers, CRCs, central directory and EOCD.
Uint8List zipFixture(Map<String, String> files, {bool deflate = true}) {
  final output = BytesBuilder();
  final directory = BytesBuilder();
  for (final entry in files.entries) {
    final name = utf8.encode(entry.key);
    final data = utf8.encode(entry.value);
    final compressed = deflate ? ZLibCodec(raw: true).encode(data) : data;
    final offset = output.length;
    final local = ByteData(30);
    local.setUint32(0, 0x04034b50, Endian.little);
    local.setUint16(4, 20, Endian.little);
    local.setUint16(6, 0x800, Endian.little);
    local.setUint16(8, deflate ? 8 : 0, Endian.little);
    local.setUint32(14, _crc(data), Endian.little);
    local.setUint32(18, compressed.length, Endian.little);
    local.setUint32(22, data.length, Endian.little);
    local.setUint16(26, name.length, Endian.little);
    output.add(local.buffer.asUint8List());
    output.add(name);
    output.add(compressed);
    final central = ByteData(46);
    central.setUint32(0, 0x02014b50, Endian.little);
    central.setUint16(4, 20, Endian.little);
    central.setUint16(6, 20, Endian.little);
    central.setUint16(8, 0x800, Endian.little);
    central.setUint16(10, deflate ? 8 : 0, Endian.little);
    central.setUint32(16, _crc(data), Endian.little);
    central.setUint32(20, compressed.length, Endian.little);
    central.setUint32(24, data.length, Endian.little);
    central.setUint16(28, name.length, Endian.little);
    central.setUint32(42, offset, Endian.little);
    directory.add(central.buffer.asUint8List());
    directory.add(name);
  }
  final offset = output.length;
  final size = directory.length;
  output.add(directory.takeBytes());
  final end = ByteData(22);
  end.setUint32(0, 0x06054b50, Endian.little);
  end.setUint16(8, files.length, Endian.little);
  end.setUint16(10, files.length, Endian.little);
  end.setUint32(12, size, Endian.little);
  end.setUint32(16, offset, Endian.little);
  output.add(end.buffer.asUint8List());
  return output.takeBytes();
}

Map<String, String> workbookFixture() => {
  for (var i = 0; i < 120; i++) 'padding/$i.txt': 'padding',
  '[Content_Types].xml':
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="xml" ContentType="application/xml"/><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/></Types>',
  '_rels/.rels':
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
  'xl/workbook.xml':
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Doanh thu &amp; Chi phí" sheetId="2" r:id="rId2"/><sheet name="预算" sheetId="1" r:id="rId1"/></sheets></workbook>',
  'xl/_rels/workbook.xml.rels':
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/></Relationships>',
  'xl/worksheets/sheet1.xml':
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>',
  'xl/worksheets/sheet2.xml':
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData/></worksheet>',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('preview_inspector_'));
  test('valid ZIP lists Unicode files and compressed/original sizes', () {
    final file = File('${dir.path}/archive.zip')
      ..writeAsBytesSync(
        zipFixture({'folder/': '', 'folder/预算.txt': 'content ' * 100}),
      );
    final entries = readZipCentralDirectory(file.path);
    expect(entries.map((e) => e.name), ['folder/', 'folder/预算.txt']);
    expect(entries.first.isDirectory, true);
    expect(entries.last.uncompressedSize, 800);
    expect(entries.last.compressedSize, lessThan(800));
  });
  for (final deflate in [true, false]) {
    test(
      'XLSX preserves names/order past first 100 entries (deflate=$deflate)',
      () {
        final file = File('${dir.path}/book.xlsx')
          ..writeAsBytesSync(zipFixture(workbookFixture(), deflate: deflate));
        expect(readZipCentralDirectory(file.path), hasLength(100));
        expect(readXlsxSheetNames(file.path), ['Doanh thu & Chi phí', '预算']);
      },
    );
  }
  test('truncated ZIP and oversized XML return no sheets', () {
    final bytes = zipFixture(workbookFixture());
    final file = File('${dir.path}/bad.xlsx')
      ..writeAsBytesSync(bytes.sublist(0, bytes.length - 5));
    expect(readXlsxSheetNames(file.path), isEmpty);
    file.writeAsBytesSync(
      zipFixture({'xl/workbook.xml': 'X' * (2 * 1024 * 1024 + 1)}),
    );
    expect(readXlsxSheetNames(file.path), isEmpty);
  });
  test(
    'SHA256 matches known vector and hashes files above old 50MB limit',
    () async {
      final file = File('${dir.path}/abc.bin')..writeAsStringSync('abc');
      expect(
        await calculateFileSha256(file.path),
        'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD',
      );
      final handle = file.openSync(mode: FileMode.write);
      handle.truncateSync(51 * 1024 * 1024);
      handle.closeSync();
      expect(
        await calculateFileSha256(file.path),
        matches(RegExp(r'^[0-9A-F]{64}$')),
      );
    },
  );
  test(
    'default application comes from native association, not extension guess',
    () async {
      const channel = MethodChannel('ja_lan_messenger/file_preview');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'defaultApplication');
            expect(call.arguments, '.xlsx');
            return 'LibreOffice Calc';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      expect(await queryDefaultFileApplication('xlsx'), 'LibreOffice Calc');
    },
  );
}
