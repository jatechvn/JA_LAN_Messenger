import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/message_model.dart';
import 'app_preferences.dart';

/// Dịch vụ lưu trữ lịch sử tin nhắn bền vững trên ổ đĩa
/// Mỗi cuộc trò chuyện (AI, All Users, Peer, Group) được lưu trong 1 file JSON riêng
/// trong thư mục %APPDATA%\JA_LAN_Messenger\conversations\
class ChatHistoryService {
  static final ChatHistoryService _instance = ChatHistoryService._internal();
  factory ChatHistoryService() => _instance;
  ChatHistoryService._internal();

  static const int maxMessagesPerConversation = 1000;
  final Map<String, Timer> _debounceTimers = {};
  Directory? _customDir;
  final Map<String, List<MessageModel>> _pending = {};
  Future<void> _writes = Future.value();
  final Map<String, Object> _writeErrors = {};
  final Map<String, Set<String>> _aliases = {};

  void linkConversations(Set<String> ids) {
    final linked = <String>{...ids};
    for (final id in ids) {
      linked.addAll(_aliases[id] ?? {});
    }
    for (final id in linked) {
      _aliases[id] = linked;
    }
  }

  Set<String> aliasesFor(String conversationId) =>
      Set.of(_aliases[conversationId] ?? const {});

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _writes.then((_) => action());
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> flush() async {
    final pending = Map.of(_pending);
    _cancelAllTimers();
    for (final entry in pending.entries) {
      await saveImmediately(entry.key, entry.value);
    }
    await _writes;
    if (_writeErrors.isNotEmpty) {
      throw FileSystemException('Cannot save chat history');
    }
  }

  @visibleForTesting
  void setCustomDirectoryForTesting(Directory? dir) {
    _cancelAllTimers();
    _customDir = dir;
    _aliases.clear();
    _writeErrors.clear();
  }

  void _cancelAllTimers() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pending.clear();
  }

  Directory getStorageDirectory() {
    if (_customDir != null) return _customDir!;
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory('$appData\\JA_LAN_Messenger\\conversations');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return dir;
    }
    final dir = Directory('conversations');
    if (!dir.existsSync()) {
      try {
        dir.createSync(recursive: true);
      } catch (_) {}
    }
    return dir;
  }

  /// Chuẩn hóa ID cuộc trò chuyện thành tên file hợp lệ trên Windows
  /// Loại bỏ các ký tự cấm: < > : " / \ | ? *
  static String sanitizeConversationId(String conversationId) {
    return conversationId.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  File _getFileForConversation(String conversationId) {
    final dir = getStorageDirectory();
    final sanitized = sanitizeConversationId(conversationId);
    return File('${dir.path}\\$sanitized.json');
  }

  /// Lên lịch ghi đĩa với bộ đệm vi mô (debounce 500ms) để không làm nghẽn I/O
  void scheduleSave(
    String conversationId,
    List<MessageModel> messages, {
    Duration delay = const Duration(milliseconds: 500),
  }) {
    if (!AppPreferences().chatHistoryEnabled) return;

    _debounceTimers[conversationId]?.cancel();
    _pending[conversationId] = messages;
    _debounceTimers[conversationId] = Timer(delay, () {
      _debounceTimers.remove(conversationId);
      saveImmediately(conversationId, messages);
    });
  }

  /// Hủy bỏ toàn bộ timer ghi đĩa đang chờ (dùng khi dispose coordinator hoặc reset)
  void cancelAll() {
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
    _pending.clear();
  }

  /// Ghi ngay lập tức danh sách tin nhắn vào file tương ứng
  Future<void> saveImmediately(
    String conversationId,
    List<MessageModel> messages, {
    bool mirrorAliases = true,
  }) async {
    if (!AppPreferences().chatHistoryEnabled) return;
    if (mirrorAliases) {
      for (final alias in _aliases[conversationId] ?? <String>{}) {
        if (alias != conversationId) {
          await saveImmediately(alias, messages, mirrorAliases: false);
        }
      }
    }

    _debounceTimers.remove(conversationId)?.cancel();
    _pending.remove(conversationId);
    try {
      final file = _getFileForConversation(conversationId);

      // Lọc bỏ tin nhắn AI đang trong trạng thái gõ dở (chưa xong token stream)
      // và chỉ giữ lại tối đa maxMessagesPerConversation tin nhắn gần nhất
      final completedMessages = messages
          .where((m) => !(m.isStreaming && m.text.isEmpty))
          .toList();

      final int startIndex =
          completedMessages.length > maxMessagesPerConversation
          ? completedMessages.length - maxMessagesPerConversation
          : 0;
      final toPersist = completedMessages.sublist(startIndex);

      final payload = {
        'version': 1,
        'conversationId': conversationId,
        'lastUpdated': DateTime.now().toIso8601String(),
        'messages': toPersist.map((m) => m.toJson()).toList(),
      };

      final jsonStr = jsonEncode(payload);
      await _enqueue(() async {
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(jsonStr, flush: true);
        await temporary.rename(file.path);
        _writeErrors.remove(conversationId);
      });
    } catch (e) {
      _writeErrors[conversationId] = e;
      _pending[conversationId] = messages;
      debugPrint(
        '[ChatHistoryService] Error saving conversation $conversationId: $e',
      );
    }
  }

  /// Nạp danh sách tin nhắn của một cuộc hội thoại cụ thể
  Future<List<MessageModel>> loadConversation(String conversationId) async {
    try {
      final file = _getFileForConversation(conversationId);
      if (!await file.exists()) return [];

      final content = await file.readAsString();
      if (content.trim().isEmpty) return [];

      final dynamic decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic> && decoded.containsKey('messages')) {
        final rawList = decoded['messages'] as List<dynamic>? ?? [];
        return rawList
            .whereType<Map<String, dynamic>>()
            .map((item) => MessageModel.fromJson(item))
            .toList();
      } else if (decoded is List<dynamic>) {
        // Hỗ trợ tương thích ngược nếu lưu mảng trực tiếp
        return decoded
            .whereType<Map<String, dynamic>>()
            .map((item) => MessageModel.fromJson(item))
            .toList();
      }
    } catch (e) {
      debugPrint(
        '[ChatHistoryService] Error loading conversation $conversationId: $e',
      );
    }
    return [];
  }

  /// Nạp toàn bộ các cuộc trò chuyện đã lưu trên ổ đĩa khi khởi động app
  Future<Map<String, List<MessageModel>>> loadAllConversations() async {
    final Map<String, List<MessageModel>> result = {};
    try {
      final dir = getStorageDirectory();
      if (!await dir.exists()) return result;

      final entries = dir.listSync();
      for (final entry in entries) {
        if (entry is File && entry.path.endsWith('.json')) {
          try {
            final content = await entry.readAsString();
            if (content.trim().isEmpty) continue;

            final dynamic decoded = jsonDecode(content);
            if (decoded is Map<String, dynamic> &&
                decoded.containsKey('conversationId') &&
                decoded.containsKey('messages')) {
              final convId = decoded['conversationId'] as String;
              final rawList = decoded['messages'] as List<dynamic>? ?? [];
              final list = rawList
                  .whereType<Map<String, dynamic>>()
                  .map((item) => MessageModel.fromJson(item))
                  .toList();
              if (convId.isNotEmpty && list.isNotEmpty) {
                result[convId] = list;
              }
            }
          } catch (err) {
            debugPrint(
              '[ChatHistoryService] Skip corrupt file ${entry.path}: $err',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[ChatHistoryService] Error loading all conversations: $e');
    }
    return result;
  }

  /// Xóa file lịch sử của một cuộc trò chuyện
  Future<void> deleteConversation(String conversationId) {
    _debounceTimers.remove(conversationId)?.cancel();
    _pending.remove(conversationId);
    return _enqueue(() => _deleteConversation(conversationId));
  }

  Future<void> _deleteConversation(String conversationId) async {
    _writeErrors.remove(conversationId);
    try {
      final file = _getFileForConversation(conversationId);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint(
        '[ChatHistoryService] Error deleting conversation $conversationId: $e',
      );
    }
  }

  /// Xóa vĩnh viễn toàn bộ lịch sử trò chuyện trên ổ đĩa
  Future<void> clearAllHistory() {
    _cancelAllTimers();
    return _enqueue(_clearAllHistory);
  }

  Future<void> _clearAllHistory() async {
    _writeErrors.clear();
    try {
      final dir = getStorageDirectory();
      if (await dir.exists()) {
        final entries = dir.listSync();
        for (final entry in entries) {
          if (entry is File && entry.path.endsWith('.json')) {
            try {
              await entry.delete();
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      debugPrint('[ChatHistoryService] Error clearing all history: $e');
    }
  }

  /// Tính tổng dung lượng dữ liệu tin nhắn đã lưu trên đĩa (bytes)
  Future<int> getHistorySizeBytes() async {
    int totalBytes = 0;
    try {
      final dir = getStorageDirectory();
      if (await dir.exists()) {
        final entries = dir.listSync();
        for (final entry in entries) {
          if (entry is File && entry.path.endsWith('.json')) {
            try {
              totalBytes += await entry.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}
    return totalBytes;
  }

  /// Định dạng dung lượng thành chuỗi thân thiện (B, KB, MB)
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
