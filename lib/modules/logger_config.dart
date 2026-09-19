import 'build_info.dart';
import 'logger_debug.dart';
import 'logger_release.dart';
import 'package:logging/logging.dart';

export 'logger_debug.dart';
export 'logger_release.dart';

void setupLogger() {
  disposeLogger();
  if (BuildInfo.isDebug) {
    setupDebugLogger();
  } else {
    setupReleaseLogger();
  }
  Logger(
    'Diagnostics',
  ).info('app_started mode=${BuildInfo.isDebug ? 'debug' : 'release'}');
}

void disposeLogger() {
  disposeDebugLogger();
  disposeReleaseLogger();
}
