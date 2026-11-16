import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/models/peer_model.dart';
import 'package:ja_lan_messenger/modules/services/ai_server_locator.dart';
import 'package:ja_lan_messenger/modules/services/ai_service.dart';

void main() {
  final old = Uri.parse('http://192.0.2.8:11434');
  test(
    'online BeeBEEP hostname bypasses DNS and preserves AI port/path',
    () async {
      final probes = <Uri>[];
      final locator = AiServerLocator(
        resolve: (_) => throw StateError('DNS must not be needed'),
        multicastResolve: (_) => throw StateError('mDNS must not be needed'),
        reverse: (_) => throw StateError('PTR must not be needed'),
        probe: (uri) async {
          probes.add(uri);
          return true;
        },
      );
      final found = await locator.locate(
        old.replace(path: '/proxy'),
        [],
        peers: [
          PeerModel(
            id: 'bee',
            name: 'JA-AI-SERVER',
            ip: '192.0.2.9:6477',
            port: 6477,
            hostname: '${AiServerLocator.machineName.toUpperCase()}.local.',
            status: PeerStatus.busy,
            isBeebeep: true,
          ),
        ],
      );
      expect(found, Uri.parse('http://192.0.2.9:11434/proxy'));
      expect(probes, [found]);
    },
  );

  test(
    'unrelated, offline, group and nicknamed peers cannot select an AI server',
    () async {
      final probes = <String>[];
      final locator = AiServerLocator(
        resolve: (_) async => [],
        multicastResolve: (_) async => [],
        reverse: (_) async => 'other-server.local',
        probe: (uri) async {
          probes.add(uri.host);
          return true;
        },
      );
      final peers = [
        PeerModel(
          id: 'other',
          name: 'JA-AI-SERVER',
          hostname: 'unrelated',
          ip: '203.0.113.1',
          customNickname: AiServerLocator.machineName,
        ),
        PeerModel(
          id: 'renamed',
          name: AiServerLocator.machineName,
          hostname: 'another-host',
          ip: '203.0.113.5',
        ),
        PeerModel(
          id: 'offline',
          name: 'AI',
          hostname: AiServerLocator.machineName,
          ip: '203.0.113.2',
          status: PeerStatus.offline,
        ),
        PeerModel(
          id: 'group',
          name: AiServerLocator.machineName,
          ip: '203.0.113.3',
          isGroup: true,
        ),
        PeerModel(
          id: '__AI_ASSISTANT__',
          name: AiServerLocator.machineName,
          ip: '203.0.113.4',
        ),
      ];
      expect(await locator.locate(old, ['192.0.2.0/30'], peers: peers), isNull);
      expect(probes, unorderedEquals(['192.0.2.1', '192.0.2.2']));
    },
  );

  test(
    'matching peer without Ollama is rejected and stale known IPs are not adopted',
    () async {
      final probes = <String>[];
      final locator = AiServerLocator(
        resolve: (_) async => [],
        multicastResolve: (_) async => [],
        probe: (uri) async {
          probes.add(uri.host);
          return uri.host == '203.0.113.9';
        },
      );
      final peer = PeerModel(
        id: 'bee',
        name: 'AI',
        hostname: AiServerLocator.machineName,
        ip: '192.0.2.9',
        knownIps: {'203.0.113.9'},
      );
      expect(
        await locator.locate(old, ['192.0.2.0/30'], peers: [peer]),
        isNull,
      );
      expect(probes, isNot(contains('203.0.113.9')));
    },
  );

  for (final change in ['identity', 'address', 'offline', 'cancelled']) {
    test('peer $change change during probe invalidates discovery', () async {
      final peer = PeerModel(
        id: 'bee',
        name: 'AI',
        hostname: AiServerLocator.machineName,
        ip: '192.0.2.9',
      );
      var cancelled = false;
      final locator = AiServerLocator(
        resolve: (_) async => [],
        multicastResolve: (_) async => [],
        probe: (uri) async {
          if (uri.host != '192.0.2.9') return false;
          switch (change) {
            case 'identity':
              peer.hostname = 'another-host';
            case 'address':
              peer.ip = '192.0.2.10';
            case 'offline':
              peer.status = PeerStatus.offline;
            case 'cancelled':
              cancelled = true;
          }
          return true;
        },
      );
      expect(
        await locator.locate(
          old,
          ['192.0.2.0/30'],
          peers: [peer],
          cancelled: () => cancelled,
        ),
        isNull,
      );
    });
  }
  test('DNS exact machine discovery preserves port and path', () async {
    final locator = AiServerLocator(
      resolve: (_) async => ['192.0.2.9'],
      multicastResolve: (_) async => [],
      probe: (uri) async => uri.host == '192.0.2.9',
    );
    expect(
      await locator.locate(old.replace(path: '/proxy'), []),
      Uri.parse('http://192.0.2.9:11434/proxy'),
    );
  });
  test(
    'advertised account at hostname works when separate hostname is missing',
    () async {
      final locator = AiServerLocator(
        resolve: (_) => throw StateError('DNS must not be needed'),
        multicastResolve: (_) => throw StateError('mDNS must not be needed'),
        probe: (_) async => true,
      );
      final peer = PeerModel(
        id: 'bee',
        name: 'ja-ai@${AiServerLocator.machineName}',
        ip: '192.0.2.9',
      );
      expect((await locator.locate(old, [], peers: [peer]))!.host, '192.0.2.9');
    },
  );
  test(
    'LAN sweep rejects unrelated Ollama and accepts matching hostname',
    () async {
      final locator = AiServerLocator(
        resolve: (_) async => [],
        multicastResolve: (_) async => [],
        probe: (_) async => true,
        reverse: (ip) async => ip.endsWith('.2')
            ? '${AiServerLocator.machineName}.local'
            : 'other-AI.local',
      );
      expect((await locator.locate(old, ['192.0.2.0/30']))!.host, '192.0.2.2');
    },
  );
  test(
    'not found, cancellation, missing adapter and oversized subnet',
    () async {
      final locator = AiServerLocator(
        resolve: (_) async => [],
        multicastResolve: (_) async => [],
        probe: (_) async => false,
      );
      expect(await locator.locate(old, ['192.0.2.0/30']), isNull);
      expect(
        await locator.locate(old, ['192.0.2.0/30'], cancelled: () => true),
        isNull,
      );
      await expectLater(locator.locate(old, []), throwsStateError);
      await expectLater(
        locator.locate(old, ['172.16.0.0/16']),
        throwsFormatException,
      );
    },
  );
  test('mDNS parser accepts exact A record and rejects malformed packets', () {
    final host = '${AiServerLocator.machineName}.local';
    final packet = <int>[0, 1, 0x84, 0, 0, 1, 0, 1, 0, 0, 0, 0];
    for (final label in host.split('.')) {
      packet.addAll([label.length, ...label.codeUnits]);
    }
    packet.addAll([
      0,
      0,
      1,
      0,
      1,
      0xc0,
      12,
      0,
      1,
      0,
      1,
      0,
      0,
      0,
      120,
      0,
      4,
      192,
      0,
      2,
      9,
    ]);
    expect(AiServerLocator.parseMdnsAnswers(packet, host), ['192.0.2.9']);
    expect(AiServerLocator.parseMdnsAnswers(packet, 'other.local'), isEmpty);
    expect(
      AiServerLocator.parseMdnsAnswers(
        packet.sublist(0, packet.length - 1),
        host,
      ),
      isEmpty,
    );
    expect(AiServerLocator.parseMdnsAnswers([0, 1], host), isEmpty);
  });
  test('unreachable preflight recovers once before sending chat', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    var posts = 0;
    server.listen((request) async {
      await request.drain<void>();
      if (request.uri.path == '/api/chat') {
        posts++;
        request.response.write('{"message":{"content":"ok"},"done":true}\n');
      } else {
        request.response.write('{"models":[],"version":"test"}');
      }
      await request.response.close();
    });
    // Reserve then close a port to guarantee an unavailable endpoint.
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final deadPort = dead.port;
    await dead.close();
    final service = AiService(serverUrl: 'http://127.0.0.1:$deadPort');
    var recoveries = 0;
    service.recoverConnection = (url) async {
      recoveries++;
      service.serverUrl = 'http://127.0.0.1:${server.port}';
      return true;
    };
    final chunks = await service
        .chatStream(model: 'test', messages: [])
        .stream
        .toList();
    expect(recoveries, 1);
    expect(posts, 1);
    expect(chunks.last.content, 'ok');
    expect(chunks.last.errorMessage, isNull);
  });
  test('abort during discovery never sends chat', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    final entered = Completer<void>();
    final recovery = Completer<bool>();
    final service = AiService(serverUrl: 'http://127.0.0.1:$port');
    service.recoverConnection = (_) {
      entered.complete();
      return recovery.future;
    };
    final handle = service.chatStream(model: 'test', messages: []);
    final chunks = handle.stream.toList();
    await entered.future;
    handle.abort();
    recovery.complete(true);
    expect(await chunks, isEmpty);
  });
  test('failed recovery emits one terminal error', () async {
    final dead = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = dead.port;
    await dead.close();
    final service = AiService(serverUrl: 'http://127.0.0.1:$port');
    var calls = 0;
    service.recoverConnection = (_) async {
      calls++;
      return false;
    };
    final chunks = await service
        .chatStream(model: 'test', messages: [])
        .stream
        .toList();
    expect(calls, 1);
    expect(chunks.single.isDone, true);
    expect(chunks.single.errorMessage, isNotNull);
  });
  for (final mode in ['httpError', 'partial']) {
    test('$mode does not replay a POST or scan for a model error', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      var posts = 0;
      var recoveries = 0;
      server.listen((request) async {
        await request.drain<void>();
        if (request.uri.path == '/api/chat') {
          posts++;
          if (mode == 'httpError') {
            request.response.statusCode = 404;
            request.response.write('{"error":"missing model"}');
          } else {
            request.response.write(
              '{"message":{"content":"partial"},"done":false}\n',
            );
          }
        } else {
          request.response.write('{"models":[],"version":"test"}');
        }
        await request.response.close();
      });
      final service = AiService(serverUrl: 'http://127.0.0.1:${server.port}');
      service.recoverConnection = (_) async {
        recoveries++;
        return true;
      };
      final chunks = await service
          .chatStream(model: 'test', messages: [])
          .stream
          .toList();
      expect(posts, 1);
      expect(recoveries, mode == 'partial' ? 1 : 0);
      expect(chunks.last.errorMessage, isNotNull);
      if (mode == 'partial') expect(chunks.first.content, 'partial');
    });
  }
}
