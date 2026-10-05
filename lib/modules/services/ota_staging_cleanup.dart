import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Cleans only the validated staging session passed by the updater.
/// Backup, installer and logs deliberately remain available for rollback.
class OtaStagingCleanup {
  static const argumentPrefix = '--ota-session=';

  static Future<void> register(Directory session, String executable) async {
    await File(p.join(session.path, 'session.json')).writeAsString(
      jsonEncode({'executable': p.normalize(p.absolute(executable))}),
      flush: true,
    );
  }

  static Future<void> complete(
    List<String> args, {
    Directory? tempRoot,
    String? executable,
  }) async {
    final matches = args
        .where((arg) => arg.startsWith(argumentPrefix))
        .toList();
    if (matches.length != 1) return;
    final root = tempRoot ?? Directory.systemTemp;
    final session = Directory(matches.single.substring(argumentPrefix.length));
    final rootPath = await root.resolveSymbolicLinks();
    if (await FileSystemEntity.type(session.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    final sessionPath = await session.resolveSymbolicLinks();
    if (!p.isWithin(rootPath, sessionPath) ||
        !p.equals(p.dirname(sessionPath), rootPath) ||
        !p.basename(sessionPath).startsWith('JA_LAN_Messenger_Update_')) {
      return;
    }
    final marker = File(p.join(sessionPath, 'session.json'));
    if (await FileSystemEntity.type(marker.path, followLinks: false) !=
        FileSystemEntityType.file) {
      return;
    }
    final data =
        jsonDecode(await marker.readAsString()) as Map<String, dynamic>;
    final actual = p.normalize(
      p.absolute(executable ?? Platform.resolvedExecutable),
    );
    final expected = data['executable'];
    if (expected is! String ||
        (Platform.isWindows
            ? expected.toLowerCase() != actual.toLowerCase()
            : expected != actual)) {
      return;
    }
    // Called only after the new app renders its first frame.
    final ready = File(p.join(sessionPath, 'startup.ok'));
    final readyType = await FileSystemEntity.type(
      ready.path,
      followLinks: false,
    );
    if (readyType != FileSystemEntityType.notFound &&
        readyType != FileSystemEntityType.file) {
      return;
    }
    await ready.writeAsString('ready', flush: true);
    for (final name in ['update.zip', 'extracted']) {
      final target = p.join(sessionPath, name);
      if (!p.isWithin(sessionPath, target)) continue;
      final type = await FileSystemEntity.type(target, followLinks: false);
      if (type == FileSystemEntityType.notFound) continue;
      if (type == FileSystemEntityType.file && name == 'update.zip') {
        await File(target).delete();
      } else if (type == FileSystemEntityType.directory &&
          name == 'extracted') {
        final dir = Directory(target);
        if (!p.isWithin(sessionPath, await dir.resolveSymbolicLinks())) {
          continue;
        }
        // Refuse junction/symlink trees instead of traversing external data.
        var safe = true;
        await for (final entry in dir.list(
          recursive: true,
          followLinks: false,
        )) {
          if (entry is Link ||
              !p.isWithin(sessionPath, await entry.resolveSymbolicLinks())) {
            safe = false;
            break;
          }
        }
        if (safe) await dir.delete(recursive: true);
      }
    }
  }
}
