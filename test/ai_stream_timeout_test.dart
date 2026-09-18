import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/ai_service.dart';

void main() {
  for (final mode in ['stall', 'eof', 'done']) {
    test('AI stream $mode completes with correct terminal status', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        await request.drain<void>();
        request.response.bufferOutput = false;
        request.response.headers.contentType = ContentType(
          'application',
          'x-ndjson',
        );
        request.response.write(
          '{"message":{"content":"hello"},"done":false}\n',
        );
        await request.response.flush();
        if (mode == 'done') request.response.write('{"done":true}\n');
        if (mode != 'stall') await request.response.close();
      });
      final handle = AiService(serverUrl: 'http://127.0.0.1:${server.port}')
          .chatStream(
            model: 'test',
            messages: [],
            timeout: const Duration(milliseconds: 700),
          );
      final chunks = await handle.stream.toList().timeout(
        const Duration(seconds: 3),
      );
      expect(chunks.first.content, 'hello');
      expect(chunks.last.isDone, true);
      expect(chunks.last.errorMessage, mode == 'done' ? isNull : isNotNull);
    });
  }
}
