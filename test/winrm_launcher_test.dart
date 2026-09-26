import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/models/message_model.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/network/protocol_beebeep.dart';
import 'package:ja_lan_messenger/modules/services/app_preferences.dart';
import 'package:ja_lan_messenger/modules/services/messenger_coordinator.dart';
import 'package:ja_lan_messenger/modules/services/winrm_launcher_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final secretPrefix = Platform.isWindows ? 'enc:dpapi:' : 'enc:v2:';

  test(
    'PowerShell decrypts DPAPI script password without plaintext on disk',
    () async {
      const password = "O'Brien Tiếng Việt";
      ProcessResult? localResult;
      final launcher = WinrmLauncherService(
        processRunner: (exe, args) async {
          final script = await File(args.last).readAsString();
          expect((await File(args.last).readAsBytes()).take(3), [
            0xef,
            0xbb,
            0xbf,
          ]);
          expect(script, isNot(contains(password)));
          expect(script, isNot(contains(base64Encode(utf8.encode(password)))));
          // Run only local credential construction; never execute Invoke-Command.
          final local = script.split(r'$sessionOpt').first;
          final probe =
              '''
$local
if (\$cred.GetNetworkCredential().Password -ceq 'O''Brien Tiếng Việt') { Write-Output 'PASSWORD_OK' } else { exit 1 }
''';
          final result = await Process.run(exe, [
            '-NoProfile',
            '-NonInteractive',
            '-ExecutionPolicy',
            'Bypass',
            '-EncodedCommand',
            WinrmLauncherService.encodePowerShellCommand(probe),
          ]);
          localResult = result;
          expect(result.exitCode, 0, reason: result.stderr.toString());
          expect(result.stdout.toString().trim(), 'PASSWORD_OK');
          return ProcessResult(1, 0, 'WINRM_TEST_OK:local-fixture', '');
        },
      );
      final checked = await launcher.testConnection(
        ip: '192.0.2.1',
        port: 5985,
        username: 'review',
        password: password,
      );
      expect(localResult?.exitCode, 0, reason: localResult?.stderr.toString());
      expect(checked.success, isTrue, reason: checked.message);
    },
    skip: !Platform.isWindows,
  );

  test('pending Buzz rejects missing account even when nickname matches', () {
    final target = PendingBuzzTarget(
      peerId: '192.0.2.1:6475',
      canonicalIdentity: 'alice@pc',
      hostname: 'pc',
      accountName: 'alice',
      targetIp: '192.0.2.1',
      createdAt: DateTime.now(),
    );
    final peer = PeerModel(
      id: '192.0.2.1:6475',
      name: 'alice',
      hostname: 'pc',
      ip: '192.0.2.1',
    );
    expect(target.matches(peer, '192.0.2.1'), isFalse);
  });

  group('Timestamp Localization Tests', () {
    test('MessageModel constructor converts UTC timestamp to local time', () {
      final utcTime = DateTime.utc(2026, 9, 26, 2, 28, 0);
      final model = MessageModel(
        id: 'msg-1',
        senderId: 'user1',
        senderName: 'Alice',
        recipientId: 'user2',
        text: 'Hello',
        timestamp: utcTime,
        isMine: false,
      );

      expect(model.timestamp.isUtc, isFalse);
      expect(model.timestamp, equals(utcTime.toLocal()));
      expect(model.timestamp.hour, equals(utcTime.toLocal().hour));
    });

    test(
      'MessageModel.fromJson converts ISO8601 UTC timestamp to local time',
      () {
        final json = {
          'id': 'msg-2',
          'senderId': 'user1',
          'senderName': 'Alice',
          'recipientId': 'user2',
          'text': 'Hello from UTC',
          'timestamp': '2026-09-26T02:28:00.000Z',
          'isMine': false,
          'status': 'sent',
        };

        final model = MessageModel.fromJson(json);
        expect(model.timestamp.isUtc, isFalse);
        final expectedLocal = DateTime.parse(
          '2026-09-26T02:28:00.000Z',
        ).toLocal();
        expect(model.timestamp.hour, equals(expectedLocal.hour));
        expect(model.timestamp.minute, equals(expectedLocal.minute));
      },
    );

    test('ProtocolBeebeep.parseMessage returns timestamp in local time', () {
      final payload = [
        ProtocolBeebeep.headerChat,
        '10',
        '5',
        '0',
        '',
        '2026-09-26T02:28:00Z',
        'Hello',
      ].join(ProtocolBeebeep.protocolFieldSeparator);
      final parsed = ProtocolBeebeep.parseMessage(payload);
      expect(parsed, isNotNull);
      final ts = parsed!['timestamp'] as DateTime;
      expect(ts.isUtc, isFalse);
      final expectedLocal = DateTime.parse('2026-09-26T02:28:00Z').toLocal();
      expect(ts.hour, equals(expectedLocal.hour));
      expect(ts.minute, equals(expectedLocal.minute));
    });
  });

  group('WinRM Localization Tests', () {
    test('All WinRM localization keys exist in vi, en, zh', () {
      final lang = LanguageProvider();
      const keys = [
        'winrmSettings',
        'winrmEnableDesc',
        'winrmDefaultUser',
        'winrmDefaultPass',
        'winrmPort',
        'winrmAutoBuzz',
        'winrmTestConnection',
        'winrmTestIpHint',
        'winrmTesting',
        'winrmTestSuccess',
        'winrmTestFailed',
        'winrmLaunchingApp',
        'winrmLaunchSuccess',
        'winrmAlreadyRunning',
        'winrmLaunchFailed',
        'winrmAutoBuzzed',
        'winrmContactConfig',
        'winrmUseCustomConfig',
        'winrmUseDefaultConfig',
        'winrmCustomAppPath',
        'winrmCustomAppPathHint',
        'winrmConfigure',
        'winrmNotConfigured',
        'winrmNoIp',
        'winrmDisabledToast',
        'buzzOfflineTooltip',
      ];

      for (final code in ['vi', 'en', 'zh']) {
        lang.setLanguage(AppLanguage.fromCode(code));
        for (final key in keys) {
          final translated = lang.tr(key);
          expect(
            translated,
            isNot(equals(key)),
            reason: 'Key "$key" should have a valid translation in "$code"',
          );
          expect(translated.isNotEmpty, isTrue);
        }
      }
    });
  });

  group('WinrmPeerConfig & Password Protection Tests (P1 - AES-256 & Random IV)', () {
    test(
      'Password protection uses AES-256 (enc:v2:) with random IV per encryption',
      () {
        const password = "O'Brien_P@\$\$'w\"o`r\$d_123!";

        // Encrypting twice must produce DIFFERENT ciphertexts due to cryptographically random IV
        final enc1 = AppPreferences.protectSecret(password);
        final enc2 = AppPreferences.protectSecret(password);

        expect(enc1, startsWith(secretPrefix));
        expect(enc2, startsWith(secretPrefix));
        expect(
          enc1,
          isNot(equals(enc2)),
          reason: 'Random IV ensures non-deterministic ciphertexts',
        );
        expect(enc1, isNot(equals(password)));

        // Decryption must restore the exact original password
        expect(AppPreferences.unprotectSecret(enc1), equals(password));
        expect(AppPreferences.unprotectSecret(enc2), equals(password));
      },
    );

    test('Password protection roundtrip with edge cases and Unicode', () {
      const passwords = [
        'user',
        "O'Brien",
        'P@\$\$\'w"o`r\$d',
        'Tiếng Việt có dấu 123 !@#\$%^&*()',
        'Single\'Quote"Double`Backtick\$Dollar',
        '',
      ];

      for (final pass in passwords) {
        if (pass.isEmpty) {
          expect(AppPreferences.protectSecret(pass), isEmpty);
          expect(AppPreferences.unprotectSecret(''), isEmpty);
          continue;
        }
        final protected = AppPreferences.protectSecret(pass);
        expect(protected, startsWith(secretPrefix));
        expect(AppPreferences.unprotectSecret(protected), equals(pass));
      }
    });

    test(
      'Backward compatibility with legacy enc:v1: and plain text passwords',
      () {
        // Legacy enc:v1: format
        const legacyV1 =
            'enc:v1:GSQ8PiQ6DzI2MEVfQFJuZXpv'; // 'SecretPassword123!'
        final decodedV1 = AppPreferences.unprotectSecret(legacyV1);
        expect(decodedV1, equals('SecretPassword123!'));

        // Plain text password from older versions
        expect(
          AppPreferences.unprotectSecret('plain_text_pass'),
          equals('plain_text_pass'),
        );
      },
    );

    test(
      'WinrmPeerConfig serialization masks password with enc:v2: and deserializes cleanly',
      () {
        const config = WinrmPeerConfig(
          useCustom: true,
          username: 'admin',
          password: "O'Brien_Secret123!",
          port: 5986,
          customAppPath: r'D:\Apps\JA_LAN_Messenger\ja_lan_messenger.exe',
        );

        final json = config.toJson();
        expect(json['useCustom'], isTrue);
        expect(json['username'], equals('admin'));
        // Must NOT be stored in plain text
        expect(json['password'], startsWith(secretPrefix));
        expect(json['password'], isNot(equals("O'Brien_Secret123!")));
        expect(json['port'], equals(5986));
        expect(
          json['customAppPath'],
          equals(r'D:\Apps\JA_LAN_Messenger\ja_lan_messenger.exe'),
        );

        final restored = WinrmPeerConfig.fromJson(json);
        expect(restored.useCustom, isTrue);
        expect(restored.username, equals('admin'));
        expect(restored.password, equals("O'Brien_Secret123!"));
        expect(restored.port, equals(5986));
        expect(
          restored.customAppPath,
          equals(r'D:\Apps\JA_LAN_Messenger\ja_lan_messenger.exe'),
        );
      },
    );

    test('Defaults when fromJson has missing fields', () {
      final restored = WinrmPeerConfig.fromJson({});
      expect(restored.useCustom, isFalse);
      expect(restored.username, isEmpty);
      expect(restored.password, isEmpty);
      expect(restored.port, equals(5985));
      expect(restored.customAppPath, isNull);
    });
  });

  group('AppPreferences WinRM Settings Persistence Tests', () {
    late Directory tempDir;
    late File prefFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('winrm_prefs_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test(
      'Persists global settings to disk with AES-256 protected password',
      () async {
        final prefs = AppPreferences();
        await prefs.setWinrmGlobalSettings(
          enabled: false,
          defaultUsername: 'administrator',
          defaultPassword: "O'Brien_P@\$\$word",
          defaultPort: 5986,
          autoBuzzOnConnect: false,
        );

        expect(prefs.winrmEnabled, isFalse);
        expect(prefs.winrmDefaultUsername, equals('administrator'));
        expect(prefs.winrmDefaultPassword, equals("O'Brien_P@\$\$word"));
        expect(prefs.winrmDefaultPort, equals(5986));
        expect(prefs.winrmAutoBuzzOnConnect, isFalse);

        // Verify that the disk file contains the protected password, NOT plain text
        final rawFileContent = await prefFile.readAsString();
        expect(rawFileContent.contains("O'Brien_P@\$\$word"), isFalse);
        expect(rawFileContent.contains(secretPrefix), isTrue);

        // Reload from disk and verify transparent decryption
        await prefs.load();
        expect(prefs.winrmEnabled, isFalse);
        expect(prefs.winrmDefaultUsername, equals('administrator'));
        expect(prefs.winrmDefaultPassword, equals("O'Brien_P@\$\$word"));
        expect(prefs.winrmDefaultPort, equals(5986));
        expect(prefs.winrmAutoBuzzOnConnect, isFalse);
      },
    );

    test('Peer-specific config override and credential resolution', () async {
      final prefs = AppPreferences();
      await prefs.setWinrmGlobalSettings(
        defaultUsername: 'global_user',
        defaultPassword: 'global_pass',
        defaultPort: 5985,
      );

      // Peer without custom config -> fallback to global
      final credsFallback = prefs.resolveWinrmCredentials('peer_unknown');
      expect(credsFallback.username, equals('global_user'));
      expect(credsFallback.password, equals('global_pass'));
      expect(credsFallback.port, equals(5985));
      expect(credsFallback.customAppPath, isNull);

      // Set peer custom config
      await prefs.setWinrmConfigForPeer(
        'peer_desktop_01',
        const WinrmPeerConfig(
          useCustom: true,
          username: 'custom_user',
          password: 'custom_pass',
          port: 5986,
          customAppPath: r'C:\MyTools\app.exe',
        ),
      );

      final credsCustom = prefs.resolveWinrmCredentials('peer_desktop_01');
      expect(credsCustom.username, equals('custom_user'));
      expect(credsCustom.password, equals('custom_pass'));
      expect(credsCustom.port, equals(5986));
      expect(credsCustom.customAppPath, equals(r'C:\MyTools\app.exe'));

      // If useCustom is false -> fallback to global
      await prefs.setWinrmConfigForPeer(
        'peer_desktop_01',
        const WinrmPeerConfig(
          useCustom: false,
          username: 'ignored_user',
          password: 'ignored_pass',
        ),
      );
      final credsDisabled = prefs.resolveWinrmCredentials('peer_desktop_01');
      expect(credsDisabled.username, equals('global_user'));
      expect(credsDisabled.password, equals('global_pass'));
    });
  });

  group('WinrmLauncherService CLI Security & Interactive Session Tests (P1 & P2)', () {
    test(
      'powershell process is executed with -File temp script and no credentials on CLI args',
      () async {
        String? capturedStdinScript;
        List<String>? capturedArgs;

        final service = WinrmLauncherService(
          processRunner: (exe, args, {stdinScript}) async {
            expect(exe, equals('powershell.exe'));
            capturedArgs = args;
            capturedStdinScript = stdinScript;

            return ProcessResult(
              1234,
              0,
              'WINRM_TEST_OK:PONG:TARGET_PC:TargetUser\r\n',
              '',
            );
          },
        );

        const complexPass = "O'Brien's P@\$\$'w\"o`r\$d";
        final result = await service.testConnection(
          ip: '192.168.1.150',
          port: 5985,
          username: 'admin',
          password: complexPass,
        );

        expect(result.success, isTrue);
        expect(capturedArgs, isNotNull);

        // Verify NO passwords or base64 scripts in CLI args (P1 Fix)
        expect(capturedArgs!.contains('-EncodedCommand'), isFalse);
        expect(capturedArgs, contains('-File'));
        for (final arg in capturedArgs!) {
          expect(arg.contains(complexPass), isFalse);
        }

        // Verify script was passed over stdin
        expect(capturedStdinScript, isNotNull);
        expect(capturedStdinScript!.contains('TrustedHosts'), isFalse);
        expect(
          capturedStdinScript!.contains('[System.Convert]::FromBase64String'),
          isTrue,
        );
      },
    );

    test(
      'launchRemoteApp checks SessionId > 0 to prevent false ALREADY_RUNNING on Session 0',
      () async {
        String? capturedStdinScript;

        final service = WinrmLauncherService(
          processRunner: (exe, args, {stdinScript}) async {
            capturedStdinScript = stdinScript;
            return ProcessResult(
              1234,
              0,
              'WINRM_EXEC_OK:LAUNCH_SUCCESS:C:\\Program Files\\JA_LAN_Messenger\\ja_lan_messenger.exe',
              '',
            );
          },
        );

        final result = await service.launchRemoteApp(
          ip: '192.168.1.150',
          port: 5985,
          username: 'admin',
          password: 'pass',
        );

        expect(result.success, isTrue);
        expect(capturedStdinScript, isNotNull);

        // Verify the script specifically checks SessionId > 0 for ALREADY_RUNNING (P1 Fix)
        expect(
          capturedStdinScript!.contains(r'$_.SessionId -gt 0'),
          isTrue,
          reason:
              'Must filter for interactive session SessionId > 0 to ignore dead/service Session 0 processes',
        );

        // Verify polling and final check also filter for SessionId > 0
        expect(
          capturedStdinScript!.contains('Where-Object { \$_.SessionId -gt 0 }'),
          isTrue,
        );
      },
    );

    test(
      'launchRemoteApp translates LAUNCH_FAILED to clear error message',
      () async {
        final service = WinrmLauncherService(
          processRunner: (exe, args, {stdinScript}) async {
            return ProcessResult(
              1234,
              1,
              '',
              'LAUNCH_FAILED: Đã gửi lệnh khởi động nhưng không tìm thấy tiến trình ja_lan_messenger chạy trong phiên tương tác người dùng.',
            );
          },
        );

        final result = await service.launchRemoteApp(
          ip: '192.168.1.150',
          port: 5985,
          username: 'user',
          password: 'pass',
        );

        expect(result.success, isFalse);
        expect(
          result.message,
          contains(
            'Không thể khởi động ứng dụng trên máy đích (tiến trình không phản hồi)',
          ),
        );
      },
    );

    test('launchRemoteApp already running parsing', () async {
      final service = WinrmLauncherService(
        processRunner: (exe, args, {stdinScript}) async {
          return ProcessResult(1234, 0, 'WINRM_EXEC_OK:ALREADY_RUNNING', '');
        },
      );

      final result = await service.launchRemoteApp(
        ip: '192.168.1.150',
        port: 5985,
        username: 'user',
        password: 'user',
      );

      expect(result.success, isTrue);
      expect(result.message, contains('Ứng dụng đã đang chạy trên máy đích'));
    });
  });

  group('MessengerCoordinator Auto-Buzz Strict Matching & Handshake Flow (P2)', () {
    late Directory tempDir;
    late File prefFile;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('coord_winrm_test_');
      prefFile = File('${tempDir.path}\\prefs.json');
      AppPreferences().setCustomFileForTesting(prefFile);
    });

    tearDown(() async {
      AppPreferences().setCustomFileForTesting(null);
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('PendingBuzzTarget strictly rejects wrong device reusing the same IP', () {
      final target = PendingBuzzTarget(
        peerId: '192.168.1.100:6475',
        canonicalIdentity: 'alice@workstation01',
        hostname: 'Workstation01',
        accountName: 'Alice',
        targetIp: '192.168.1.100',
        createdAt: DateTime(2026),
      );

      // Case 1: Exact matching device on same IP -> MATCHES
      final exactPeer = PeerModel(
        id: '192.168.1.100:6475',
        name: 'Alice',
        hostname: 'Workstation01',
        accountName: 'Alice',
        ip: '192.168.1.100',
      );
      expect(target.matches(exactPeer, '192.168.1.100'), isTrue);

      // Case 2: Different device that was assigned the same IP via DHCP -> REJECTED
      final roguePeerSameIp = PeerModel(
        id: '192.168.1.100:6475',
        name: 'Bob',
        hostname: 'Workstation99',
        accountName: 'Bob',
        ip: '192.168.1.100',
      );
      expect(target.matches(roguePeerSameIp, '192.168.1.100'), isFalse);

      // Case 3: Device with matching name but coming from unauthorized rogue IP -> REJECTED
      final spoofedPeerWrongIp = PeerModel(
        id: '192.168.1.250:6475',
        name: 'Alice',
        hostname: 'Workstation01',
        accountName: 'Alice',
        ip: '192.168.1.250',
      );
      expect(target.matches(spoofedPeerWrongIp, '192.168.1.250'), isFalse);
    });

    test(
      'Offline Buzz enqueues strict target, and matching handshake triggers Buzz',
      () async {
        final coordinator = MessengerCoordinator();
        bool runnerCalled = false;

        coordinator.winrmLauncherForTesting = WinrmLauncherService(
          processRunner: (exe, args, {stdinScript}) async {
            runnerCalled = true;
            return ProcessResult(
              1234,
              0,
              'WINRM_EXEC_OK:LAUNCH_SUCCESS:app.exe',
              '',
            );
          },
        );

        final offlinePeer = PeerModel(
          id: '192.168.1.200:6475',
          name: 'Workstation02',
          ip: '192.168.1.200',
          port: 6475,
          status: PeerStatus.offline,
          hostname: 'Workstation02',
        );

        coordinator.selectPeer(offlinePeer);
        await coordinator.sendBuzz();

        expect(runnerCalled, isTrue);
        expect(coordinator.pendingBuzzTargetsForTesting.length, equals(1));
        final pending = coordinator.pendingBuzzTargetsForTesting.first;
        expect(
          pending.canonicalIdentity,
          equals(offlinePeer.canonicalIdentity),
        );
        expect(pending.targetIp, equals('192.168.1.200'));

        // Simulate handshake from a DIFFERENT machine reusing IP 192.168.1.200
        final differentPeer = PeerModel(
          id: '192.168.1.200:9999',
          name: 'PrinterOrGuest',
          hostname: 'GuestPC',
          ip: '192.168.1.200',
        );
        coordinator.triggerPendingBuzzIfNeededForTesting(
          differentPeer,
          '192.168.1.200',
        );

        // Auto-buzz must NOT be triggered for the wrong device!
        expect(coordinator.pendingBuzzTargetsForTesting.length, equals(1));

        // Simulate handshake from the RIGHT machine
        bool buzzSent = false;
        coordinator.sendToPeerForTesting = (endpoint, packet) {
          buzzSent = true;
          return true;
        };
        coordinator.triggerPendingBuzzIfNeededForTesting(
          offlinePeer,
          '192.168.1.200',
        );

        expect(buzzSent, isTrue);
        expect(coordinator.pendingBuzzTargetsForTesting.isEmpty, isTrue);
      },
    );

    test(
      'WinRM launch failure cleans up pending queue and records failure status',
      () async {
        final coordinator = MessengerCoordinator();

        coordinator.winrmLauncherForTesting = WinrmLauncherService(
          processRunner: (exe, args, {stdinScript}) async {
            return ProcessResult(1234, 1, '', 'Access is denied.');
          },
        );

        final offlinePeer = PeerModel(
          id: '192.168.1.201:6475',
          name: 'Workstation03',
          ip: '192.168.1.201',
          port: 6475,
          status: PeerStatus.offline,
          hostname: 'Workstation03',
        );

        coordinator.selectPeer(offlinePeer);
        await coordinator.sendBuzz();

        // Pending queue should NOT contain target because launch failed
        expect(coordinator.pendingBuzzTargetsForTesting.isEmpty, isTrue);

        final messages = coordinator.conversationsMap[offlinePeer.id] ?? [];
        expect(messages.any((m) => m.status == MessageStatus.failed), isTrue);
      },
    );
  });
}
