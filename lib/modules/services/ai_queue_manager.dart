import 'dart:async';
import 'dart:collection';
import 'package:logging/logging.dart';
import 'ai_service.dart';

enum AiRequestStatus { queued, processing, completed, cancelled, failed }

class AiQueueItem {
  final String id;
  final String model;
  final List<Map<String, dynamic>> messages;
  final bool thinking;
  final int numCtx;
  final DateTime queuedAt;
  AiRequestStatus status;
  final void Function(AiStreamChunk chunk) onChunk;
  final void Function() onDone;
  final void Function(String error) onError;
  AiChatStreamHandle? streamHandle;

  AiQueueItem({
    required this.id,
    required this.model,
    required this.messages,
    required this.thinking,
    this.numCtx = 4096,
    required this.onChunk,
    required this.onDone,
    required this.onError,
    DateTime? queuedAt,
    this.status = AiRequestStatus.queued,
  }) : queuedAt = queuedAt ?? DateTime.now();
}

class AiQueueManager {
  static final Logger _logger = Logger('AiQueueManager');

  final AiService aiService;
  final int maxConcurrent;
  final int maxQueue;

  final Queue<AiQueueItem> _waitingQueue = Queue<AiQueueItem>();
  AiQueueItem? _activeItem;
  bool _isDisposed = false;

  void Function()? onQueueChanged;

  AiQueueManager({
    required this.aiService,
    this.maxConcurrent = 1,
    this.maxQueue = 4,
  });

  bool get isBusy => _activeItem != null;
  int get queueLength => _waitingQueue.length;
  bool get canEnqueue => !_isDisposed && _waitingQueue.length < maxQueue;
  AiQueueItem? get activeItem => _activeItem;
  List<AiQueueItem> get waitingItems => _waitingQueue.toList();

  int getPosition(String id) {
    if (_activeItem?.id == id) return 0; // Đang chạy
    var idx = 1;
    for (final item in _waitingQueue) {
      if (item.id == id) return idx;
      idx++;
    }
    return -1; // Không có trong hàng đợi
  }

  /// Đưa một request vào hàng đợi
  AiQueueItem? enqueue({
    required String id,
    required String model,
    required List<Map<String, dynamic>> messages,
    required bool thinking,
    int numCtx = 4096,
    required void Function(AiStreamChunk chunk) onChunk,
    required void Function() onDone,
    required void Function(String error) onError,
  }) {
    if (_isDisposed) return null;
    if (_waitingQueue.length >= maxQueue) {
      _logger.warning('AI Queue is full (>=  items). Request  rejected.');
      return null;
    }

    final item = AiQueueItem(
      id: id,
      model: model,
      messages: messages,
      thinking: thinking,
      numCtx: numCtx,
      onChunk: onChunk,
      onDone: onDone,
      onError: onError,
    );

    _waitingQueue.add(item);
    _logger.info('Enqueued AI request . Queue length: ');
    _notifyChange();
    _processNext();
    return item;
  }

  /// Hủy request đang chạy
  void cancelActive() {
    if (_activeItem != null) {
      _logger.info('Cancelling active AI request ');
      _activeItem!.status = AiRequestStatus.cancelled;
      _activeItem!.streamHandle?.abort();
      _activeItem = null;
      _notifyChange();
      _processNext();
    }
  }

  /// Hủy một request cụ thể trong danh sách chờ
  bool cancelItem(String id) {
    if (_activeItem?.id == id) {
      cancelActive();
      return true;
    }
    final initialLen = _waitingQueue.length;
    _waitingQueue.removeWhere((item) {
      if (item.id == id) {
        item.status = AiRequestStatus.cancelled;
        item.onError('Đã hủy khỏi hàng đợi');
        return true;
      }
      return false;
    });
    if (_waitingQueue.length != initialLen) {
      _logger.info('Cancelled queued AI request ');
      _notifyChange();
      return true;
    }
    return false;
  }

  /// Xóa toàn bộ hàng đợi
  void clearQueue() {
    final active = _activeItem;
    _activeItem = null;
    if (active != null) {
      active.status = AiRequestStatus.cancelled;
      active.streamHandle?.abort();
    }
    while (_waitingQueue.isNotEmpty) {
      final item = _waitingQueue.removeFirst();
      item.status = AiRequestStatus.cancelled;
      if (!_isDisposed) item.onError('Hàng đợi đã bị xóa');
    }
    _notifyChange();
  }

  /// Xử lý request tiếp theo trong hàng đợi
  void _processNext() {
    if (_isDisposed || _activeItem != null || _waitingQueue.isEmpty) {
      return;
    }

    final nextItem = _waitingQueue.removeFirst();
    _activeItem = nextItem;
    nextItem.status = AiRequestStatus.processing;
    _logger.info('Starting processing AI request  with model ');
    _notifyChange();

    try {
      final handle = aiService.chatStream(
        model: nextItem.model,
        messages: nextItem.messages,
        thinking: nextItem.thinking,
        numCtx: nextItem.numCtx,
      );
      nextItem.streamHandle = handle;

      StreamSubscription<AiStreamChunk>? sub;
      sub = handle.stream.listen(
        (chunk) {
          if (_isDisposed || nextItem.status == AiRequestStatus.cancelled) {
            return;
          }
          if (chunk.errorMessage != null) {
            nextItem.status = AiRequestStatus.failed;
            nextItem.onError(chunk.errorMessage!);
          } else {
            nextItem.onChunk(chunk);
          }
          if (chunk.isDone) {
            if (nextItem.status != AiRequestStatus.failed &&
                nextItem.status != AiRequestStatus.cancelled) {
              nextItem.status = AiRequestStatus.completed;
            }
          }
        },
        onError: (err) {
          if (_isDisposed || nextItem.status == AiRequestStatus.cancelled) {
            return;
          }
          _logger.warning('Error in AI stream for : ');
          nextItem.status = AiRequestStatus.failed;
          try {
            nextItem.onError(err.toString());
          } finally {
            if (identical(_activeItem, nextItem)) _activeItem = null;
            _notifyChange();
            _processNext();
          }
        },
        onDone: () {
          sub?.cancel();
          if (nextItem.status == AiRequestStatus.processing ||
              nextItem.status == AiRequestStatus.completed) {
            nextItem.onDone();
          }
          if (_activeItem?.id == nextItem.id) {
            _activeItem = null;
          }
          _notifyChange();
          _processNext();
        },
        cancelOnError: true,
      );
    } catch (e) {
      _logger.warning('Failed to dispatch AI stream for : ');
      nextItem.status = AiRequestStatus.failed;
      nextItem.onError(e.toString());
      if (_activeItem?.id == nextItem.id) {
        _activeItem = null;
      }
      _notifyChange();
      _processNext();
    }
  }

  void _notifyChange() {
    if (!_isDisposed) {
      try {
        onQueueChanged?.call();
      } catch (_) {}
    }
  }

  void dispose() {
    _isDisposed = true;
    clearQueue();
  }
}
