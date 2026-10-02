import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

class ZipArchiveEntry {
  const ZipArchiveEntry({
    required this.name,
    required this.uncompressedSize,
    required this.compressedSize,
    required this.isDirectory,
    this.localOffset = 0,
    this.method = 0,
    this.flags = 0,
  });
  final String name;
  final int uncompressedSize, compressedSize, localOffset, method, flags;
  final bool isDirectory;
}

List<ZipArchiveEntry> readZipCentralDirectory(
  String path, {
  int maxEntries = 100,
}) {
  RandomAccessFile? file;
  try {
    file = File(path).openSync();
    final length = file.lengthSync();
    if (length < 22) return [];
    final tailStart = length > 65557 ? length - 65557 : 0;
    file.setPositionSync(tailStart);
    final tail = ByteData.sublistView(file.readSync(length - tailStart));
    var end = -1;
    for (var i = tail.lengthInBytes - 22; i >= 0; i--) {
      if (tail.getUint32(i, Endian.little) == 0x06054b50 &&
          i + 22 + tail.getUint16(i + 20, Endian.little) ==
              tail.lengthInBytes) {
        end = i;
        break;
      }
    }
    if (end < 0 ||
        tail.getUint16(end + 4, Endian.little) != 0 ||
        tail.getUint16(end + 6, Endian.little) != 0) {
      return [];
    }
    final count = tail.getUint16(end + 10, Endian.little);
    final size = tail.getUint32(end + 12, Endian.little);
    final offset = tail.getUint32(end + 16, Endian.little);
    if (count == 0xffff ||
        offset == 0xffffffff ||
        offset + size > tailStart + end) {
      return [];
    }
    final entries = <ZipArchiveEntry>[];
    file.setPositionSync(offset);
    for (var i = 0; i < count && entries.length < maxEntries; i++) {
      if (file.positionSync() + 46 > offset + size) return [];
      final bytes = file.readSync(46);
      if (bytes.length != 46) return [];
      final header = ByteData.sublistView(bytes);
      if (header.getUint32(0, Endian.little) != 0x02014b50) return [];
      final nameSize = header.getUint16(28, Endian.little);
      final extra =
          header.getUint16(30, Endian.little) +
          header.getUint16(32, Endian.little);
      if (file.positionSync() + nameSize + extra > offset + size) return [];
      final name = utf8.decode(file.readSync(nameSize), allowMalformed: true);
      file.setPositionSync(file.positionSync() + extra);
      entries.add(
        ZipArchiveEntry(
          name: name,
          uncompressedSize: header.getUint32(24, Endian.little),
          compressedSize: header.getUint32(20, Endian.little),
          isDirectory: name.endsWith('/') || name.endsWith('\\'),
          localOffset: header.getUint32(42, Endian.little),
          method: header.getUint16(10, Endian.little),
          flags: header.getUint16(8, Endian.little),
        ),
      );
    }
    return entries;
  } catch (_) {
    return [];
  } finally {
    file?.closeSync();
  }
}

class _BoundedBytes implements Sink<List<int>> {
  final bytes = BytesBuilder();
  int length = 0;
  @override
  void add(List<int> chunk) {
    length += chunk.length;
    if (length > 2 * 1024 * 1024) {
      throw const FormatException('Workbook too large');
    }
    bytes.add(chunk);
  }

  @override
  void close() {}
}

List<String> readXlsxSheetNames(String path) {
  RandomAccessFile? file;
  try {
    final matches = readZipCentralDirectory(
      path,
      maxEntries: 65535,
    ).where((entry) => entry.name == 'xl/workbook.xml');
    if (matches.isEmpty) return [];
    final entry = matches.first;
    if (entry.flags & 1 != 0 ||
        entry.compressedSize > 2 * 1024 * 1024 ||
        entry.uncompressedSize > 2 * 1024 * 1024 ||
        (entry.method != 0 && entry.method != 8)) {
      return [];
    }
    file = File(path).openSync();
    file.setPositionSync(entry.localOffset);
    final headerBytes = file.readSync(30);
    if (headerBytes.length != 30) return [];
    final header = ByteData.sublistView(headerBytes);
    if (header.getUint32(0, Endian.little) != 0x04034b50) return [];
    final start =
        entry.localOffset +
        30 +
        header.getUint16(26, Endian.little) +
        header.getUint16(28, Endian.little);
    if (start + entry.compressedSize > file.lengthSync()) return [];
    file.setPositionSync(start);
    final compressed = file.readSync(entry.compressedSize);
    final sink = _BoundedBytes();
    if (entry.method == 0) {
      sink.add(compressed);
    } else {
      final decoder = ZLibDecoder(raw: true).startChunkedConversion(sink);
      decoder.add(compressed);
      decoder.close();
    }
    final bytes = sink.bytes.takeBytes();
    if (bytes.length != entry.uncompressedSize) return [];
    final document = XmlDocument.parse(utf8.decode(bytes));
    return document.descendants
        .whereType<XmlElement>()
        .where(
          (node) =>
              node.name.local == 'sheet' &&
              node.parent is XmlElement &&
              (node.parent as XmlElement).name.local == 'sheets',
        )
        .map((node) => node.getAttribute('name'))
        .whereType<String>()
        .toList();
  } catch (_) {
    return [];
  } finally {
    file?.closeSync();
  }
}

Future<String> calculateFileSha256(String path) => Isolate.run(() async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString().toUpperCase();
});

Future<({List<ZipArchiveEntry> entries, List<String> sheets})>
inspectFileArchive(String path, String extension) => Isolate.run(
  () => (
    entries: readZipCentralDirectory(path, maxEntries: 101),
    sheets: extension == 'xlsx' ? readXlsxSheetNames(path) : <String>[],
  ),
);

Future<String?> queryDefaultFileApplication(String extension) async {
  if (!Platform.isWindows || !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(extension)) {
    return null;
  }
  try {
    return await const MethodChannel(
      'ja_lan_messenger/file_preview',
    ).invokeMethod<String>('defaultApplication', '.$extension');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}
