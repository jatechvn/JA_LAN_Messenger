import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/ota_staging_cleanup.dart';
import 'package:ja_lan_messenger/modules/services/ota_update_service.dart';

void main() {
  test(
    'only successful update launch receives staging argument; rollback retains files',
    () {
      final script = OtaUpdateService.generateApplyUpdateScript(
        oldPid: 123,
        sourceDir: r'C:\temp\payload',
        targetDir: r'C:\apps\JA_LAN_Messenger',
        exeName: 'ja_lan_messenger.exe',
      );
      expect('--ota-session='.allMatches(script).length, 1);
      expect(script.split(':rollback').last, isNot(contains('--ota-session=')));
      expect(script, contains('/XF user_preferences.json'));
      expect(script, isNot(contains('rd /s')));
    },
  );
  late Directory root;
  late Directory session;
  late String exe;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('ja_cleanup_fixture_');
    session = await Directory(
      '${root.path}/JA_LAN_Messenger_Update_fixture',
    ).create();
    exe = '${root.path}/installed/ja_lan_messenger.exe';
    await OtaStagingCleanup.register(session, exe);
    await File('${session.path}/update.zip').writeAsString('package');
    await Directory('${session.path}/extracted/data').create(recursive: true);
    await File(
      '${session.path}/extracted/data/app.so',
    ).writeAsString('runtime');
    await Directory('${session.path}/backup').create();
    await File(
      '${session.path}/backup/user_preferences.json',
    ).writeAsString('keep');
    await File('${session.path}/apply.log').writeAsString('keep');
  });
  tearDown(() => root.delete(recursive: true));
  test(
    'startup acknowledgement cleans only zip and extraction; repeat is safe',
    () async {
      final args = ['--ota-session=${session.path}'];
      await OtaStagingCleanup.complete(args, tempRoot: root, executable: exe);
      expect(File('${session.path}/update.zip').existsSync(), isFalse);
      expect(Directory('${session.path}/extracted').existsSync(), isFalse);
      expect(File('${session.path}/startup.ok').existsSync(), isTrue);
      expect(
        File('${session.path}/backup/user_preferences.json').readAsStringSync(),
        'keep',
      );
      expect(File('${session.path}/apply.log').existsSync(), isTrue);
      await OtaStagingCleanup.complete(args, tempRoot: root, executable: exe);
    },
  );
  test(
    'wrong executable, missing marker, broad path and duplicate arguments are refused',
    () async {
      final arg = '--ota-session=${session.path}';
      await OtaStagingCleanup.complete(
        [arg],
        tempRoot: root,
        executable: '${root.path}/other.exe',
      );
      await OtaStagingCleanup.complete(
        [arg, arg],
        tempRoot: root,
        executable: exe,
      );
      await OtaStagingCleanup.complete(
        ['--ota-session=${root.path}'],
        tempRoot: root,
        executable: exe,
      );
      await File('${session.path}/session.json').delete();
      await OtaStagingCleanup.complete([arg], tempRoot: root, executable: exe);
      expect(File('${session.path}/update.zip').existsSync(), isTrue);
      expect(Directory('${session.path}/extracted').existsSync(), isTrue);
      expect(File('${session.path}/startup.ok').existsSync(), isFalse);
    },
  );
}
