import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/ai_queue_manager.dart';
import 'package:ja_lan_messenger/modules/services/ai_service.dart';

class MockAiService extends AiService {
  final Map<String, StreamController<AiStreamChunk>> activeControllers = {};
  final List<String> abortedRequests = [];

  MockAiService() : super(serverUrl: 'http://localhost:11434');

  @override
  AiChatStreamHandle chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    bool thinking = false,
    int numCtx = 4096,
    Duration timeout = const Duration(seconds: 180),
  }) {
    final controller = StreamController<AiStreamChunk>();
    final reqId = 'req_';
    activeControllers[reqId] = controller;

    return AiChatStreamHandle(
      stream: controller.stream,
      abort: () {
        abortedRequests.add(reqId);
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );
  }
}

void main() {
  test('dispose does not invoke queued UI callbacks', () {
    final queue = AiQueueManager(aiService: MockAiService());
    var callbacks = 0;
    for (final id in ['a', 'b']) {
      queue.enqueue(
        id: id,
        model: 'test',
        messages: [],
        thinking: false,
        onChunk: (_) => callbacks++,
        onDone: () => callbacks++,
        onError: (_) => callbacks++,
      );
    }
    queue.dispose();
    expect(callbacks, 0);
    expect(queue.canEnqueue, false);
  });
  test('clearQueue never dispatches waiting work', () {
    final service = MockAiService();
    final queue = AiQueueManager(aiService: service);
    addTearDown(queue.dispose);
    for (final id in ['a', 'b', 'c']) {
      queue.enqueue(
        id: id,
        model: 'test',
        messages: [],
        thinking: false,
        onChunk: (_) {},
        onDone: () {},
        onError: (_) {},
      );
    }
    final waiting = queue.waitingItems;
    queue.clearQueue();
    expect(queue.isBusy, false);
    expect(queue.queueLength, 0);
    expect(waiting.every((item) => item.streamHandle == null), true);
  });
  test('stream error releases active slot and starts next request', () async {
    final service = MockAiService();
    final queue = AiQueueManager(aiService: service);
    addTearDown(queue.dispose);
    for (final id in ['a', 'b']) {
      queue.enqueue(
        id: id,
        model: 'test',
        messages: [],
        thinking: false,
        onChunk: (_) {},
        onDone: () {},
        onError: (_) {},
      );
    }
    service.activeControllers.values.first.addError(
      StateError('connection lost'),
    );
    await Future<void>.delayed(Duration.zero);
    expect(queue.activeItem?.id, 'b');
  });
  group('AiQueueManager FIFO & Concurrency Tests', () {
    late MockAiService mockService;
    late AiQueueManager queueManager;

    setUp(() {
      mockService = MockAiService();
      queueManager = AiQueueManager(
        aiService: mockService,
        maxConcurrent: 1,
        maxQueue: 4,
      );
    });

    tearDown(() {
      queueManager.dispose();
    });

    test('First request immediately starts processing (isBusy = true)', () {
      expect(queueManager.isBusy, isFalse);
      expect(queueManager.queueLength, 0);

      final item = queueManager.enqueue(
        id: 'msg_1',
        model: 'qwen3.5:4b',
        messages: [
          {'role': 'user', 'content': 'Hello'},
        ],
        thinking: false,
        onChunk: (_) {},
        onDone: () {},
        onError: (_) {},
      );

      expect(item, isNotNull);
      expect(queueManager.isBusy, isTrue);
      expect(queueManager.activeItem?.id, 'msg_1');
      expect(queueManager.queueLength, 0);
      expect(queueManager.getPosition('msg_1'), 0);
    });

    test('Second request is placed in waiting queue (FIFO position 1)', () {
      queueManager.enqueue(
        id: 'msg_1',
        model: 'qwen3.5:4b',
        messages: [
          {'role': 'user', 'content': 'Hello 1'},
        ],
        thinking: false,
        onChunk: (_) {},
        onDone: () {},
        onError: (_) {},
      );

      final item2 = queueManager.enqueue(
        id: 'msg_2',
        model: 'qwen2.5-coder:3b',
        messages: [
          {'role': 'user', 'content': 'Hello 2'},
        ],
        thinking: false,
        onChunk: (_) {},
        onDone: () {},
        onError: (_) {},
      );

      expect(item2, isNotNull);
      expect(queueManager.isBusy, isTrue);
      expect(queueManager.queueLength, 1);
      expect(queueManager.getPosition('msg_1'), 0); // Active
      expect(queueManager.getPosition('msg_2'), 1); // #1 in queue
    });

    test('Queue rejects requests when reaching maxQueue limit of 4', () {
      // 1 active + 4 waiting = 5 total
      for (int i = 1; i <= 5; i++) {
        final item = queueManager.enqueue(
          id: 'msg_',
          model: 'qwen3.5:4b',
          messages: [
            {'role': 'user', 'content': 'Hello '},
          ],
          thinking: false,
          onChunk: (_) {},
          onDone: () {},
          onError: (_) {},
        );
        expect(item, isNotNull, reason: 'Request  should be accepted');
      }

      expect(queueManager.isBusy, isTrue);
      expect(queueManager.queueLength, 4);

      // 6th request should be rejected (returns null)
      final rejected = queueManager.enqueue(
        id: 'msg_6',
        model: 'qwen3.5:4b',
        messages: [
          {'role': 'user', 'content': 'Overflow'},
        ],
        thinking: false,
        onChunk: (_) {},
        onDone: () {},
        onError: (_) {},
      );

      expect(rejected, isNull);
      expect(queueManager.queueLength, 4);
    });

    test(
      'cancelActive stops current processing and advances to next queued item',
      () {
        queueManager.enqueue(
          id: 'msg_1',
          model: 'qwen3.5:4b',
          messages: [
            {'role': 'user', 'content': 'Hello 1'},
          ],
          thinking: false,
          onChunk: (_) {},
          onDone: () {},
          onError: (_) {},
        );

        queueManager.enqueue(
          id: 'msg_2',
          model: 'qwen3.5:4b',
          messages: [
            {'role': 'user', 'content': 'Hello 2'},
          ],
          thinking: false,
          onChunk: (_) {},
          onDone: () {},
          onError: (_) {},
        );

        expect(queueManager.activeItem?.id, 'msg_1');
        expect(queueManager.queueLength, 1);

        // Cancel active
        queueManager.cancelActive();

        expect(mockService.abortedRequests.length, 1);
        // msg_2 should now be automatically promoted to active
        expect(queueManager.activeItem?.id, 'msg_2');
        expect(queueManager.queueLength, 0);
      },
    );

    test(
      'cancelItem removes item from waiting queue and invokes error callback',
      () {
        queueManager.enqueue(
          id: 'msg_1',
          model: 'qwen3.5:4b',
          messages: [
            {'role': 'user', 'content': 'Hello 1'},
          ],
          thinking: false,
          onChunk: (_) {},
          onDone: () {},
          onError: (_) {},
        );

        String? errorReceived;
        queueManager.enqueue(
          id: 'msg_2',
          model: 'qwen3.5:4b',
          messages: [
            {'role': 'user', 'content': 'Hello 2'},
          ],
          thinking: false,
          onChunk: (_) {},
          onDone: () {},
          onError: (err) {
            errorReceived = err;
          },
        );

        expect(queueManager.queueLength, 1);
        final cancelled = queueManager.cancelItem('msg_2');

        expect(cancelled, isTrue);
        expect(queueManager.queueLength, 0);
        expect(errorReceived, contains('Đã hủy'));
        expect(queueManager.activeItem?.id, 'msg_1');
      },
    );
  });
}
