import 'dart:async';
import 'dart:io';
import 'package:logging/logging.dart';
import 'bounded_log.dart';

StreamSubscription<LogRecord>? _subscription;
void setupReleaseLogger() {
  disposeReleaseLogger();
  Logger.root.level = Level.INFO;
  final root = Platform.environment['LOCALAPPDATA'] ?? Directory.current.path;
  final log = BoundedLog(Directory('$root/JA_LAN_Messenger/logs'), 'release');
  _subscription = Logger.root.onRecord.listen(log.write);
}

void disposeReleaseLogger() {
  _subscription?.cancel();
  _subscription = null;
}
