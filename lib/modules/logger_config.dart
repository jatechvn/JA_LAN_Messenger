import 'build_info.dart';
import 'logger_debug.dart';
import 'logger_release.dart';

export 'logger_debug.dart';
export 'logger_release.dart';

void setupLogger() {
  disposeLogger();
  if (BuildInfo.isDebug) {
    setupDebugLogger();
  } else {
    setupReleaseLogger();
  }
}

void disposeLogger() {
  disposeDebugLogger();
  disposeReleaseLogger();
}
