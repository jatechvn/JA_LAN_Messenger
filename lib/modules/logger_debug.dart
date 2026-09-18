import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'bounded_log.dart';

StreamSubscription<LogRecord>? _subscription;
void setupDebugLogger() {
  disposeDebugLogger();
  Logger.root.level = Level.INFO;
  final root = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
  final log = BoundedLog(Directory('$root/JA_LAN_Messenger/logs'), 'debug');
  _subscription = Logger.root.onRecord.listen(log.write);
}

void disposeDebugLogger() {
  _subscription?.cancel();
  _subscription = null;
}
