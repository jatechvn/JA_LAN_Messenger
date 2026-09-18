import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';

/// Fixed-size diagnostic files. Never persists arbitrary messages/errors/payloads.
class BoundedLog {
  final Directory directory;
  final String prefix;
  final int maxBytes;
  final int slots;
  int _slot = 0;
  BoundedLog(
    this.directory,
    this.prefix, {
    this.maxBytes = 2 * 1024 * 1024,
    this.slots = 3,
  }) {
    if (maxBytes < 256 || slots < 1) throw ArgumentError('Invalid log limits');
    try {
      directory.createSync(recursive: true);
      DateTime? latest;
      for (var i = 0; i < slots; i++) {
        final file = File('${directory.path}/$prefix-$i.log');
        if (file.existsSync() &&
            (latest == null || file.lastModifiedSync().isAfter(latest))) {
          latest = file.lastModifiedSync();
          _slot = i;
        }
      }
    } catch (_) {}
  }
  void write(LogRecord record) {
    try {
      // Only controlled diagnostic events may carry details onto disk.
      final message = record.loggerName == 'Diagnostics'
          ? record.message
          : 'event';
      final line =
          '${record.time.toIso8601String()} ${record.level.name} $message\n';
      var bytes = utf8.encode(line);
      if (bytes.length > maxBytes) {
        bytes = utf8.encode('diagnostic_event_omitted\n');
      }
      var file = File('${directory.path}/$prefix-$_slot.log');
      if (file.existsSync() && file.lengthSync() + bytes.length > maxBytes) {
        _slot = (_slot + 1) % slots;
        file = File('${directory.path}/$prefix-$_slot.log');
        file.writeAsBytesSync([], flush: true);
      }
      file.writeAsBytesSync(bytes, mode: FileMode.append, flush: true);
    } catch (_) {
      /* Logging must never crash the app. */
    }
  }
}
