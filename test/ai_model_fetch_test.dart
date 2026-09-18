import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/ai_service.dart';

void main() {
  test('fetchAvailableModels returns one entry per model ID', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response
        ..headers.contentType = ContentType.json
        ..write(
          jsonEncode({
            'models': [
              {
                'name': 'qwen2.5-vl:3b',
                'details': {'family': 'qwen2'},
              },
              {
                'name': 'QWEN2.5-VL:3B',
                'details': {'family': 'qwen2'},
              },
              {
                'name': 'qwen3.5:4b',
                'details': {'family': 'qwen3'},
              },
              {
                'name': 'qwen2.5-coder:3b',
                'details': {'family': 'qwen2'},
              },
              {
                'name': 'qwen2.5-vl:3b-nosystem',
                'details': {'family': 'qwen2'},
              },
            ],
          }),
        )
        ..close();
    });

    final models = await AiService(
      serverUrl: 'http://127.0.0.1:${server.port}',
    ).fetchAvailableModels();
    expect(models.map((model) => model.id), [
      'qwen2.5-vl:3b',
      'qwen3.5:4b',
      'qwen2.5-coder:3b',
    ]);
  });
}
