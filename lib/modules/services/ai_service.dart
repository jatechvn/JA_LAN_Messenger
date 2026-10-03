import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:logging/logging.dart';
import '../models/ai_config_model.dart';

class AiConnectionResult {
  final bool success;
  final int pingMs;
  final String version;
  final List<String> availableModels;
  final List<AiModelInfo> models;
  final String? error;
  final bool connectionFailed;

  const AiConnectionResult({
    required this.success,
    this.pingMs = 0,
    this.version = '',
    this.availableModels = const [],
    this.models = const [],
    this.error,
    this.connectionFailed = false,
  });
}

class AiStreamChunk {
  final String? content;
  final String? thinkingContent;
  final bool isDone;
  final int? totalDurationMs;
  final String? errorMessage;
  final bool connectionFailed;

  const AiStreamChunk({
    this.content,
    this.thinkingContent,
    this.isDone = false,
    this.totalDurationMs,
    this.errorMessage,
    this.connectionFailed = false,
  });
}

class AiChatStreamHandle {
  final Stream<AiStreamChunk> stream;
  final void Function() abort;

  const AiChatStreamHandle({required this.stream, required this.abort});
}

class AiService {
  static final Logger _logger = Logger('AiService');
  String serverUrl;
  Future<bool> Function(String failedUrl)? recoverConnection;

  AiService({this.serverUrl = 'http://172.21.175.20:11434'});

  String get normalizedUrl {
    var url = serverUrl.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  /// Lấy danh sách các model đang khả dụng từ máy chủ Ollama
  Future<List<AiModelInfo>> fetchAvailableModels([String? customUrl]) async {
    return _fetchAvailableModels(customUrl, retry: true);
  }

  Future<List<AiModelInfo>> _fetchAvailableModels(
    String? customUrl, {
    required bool retry,
  }) async {
    final initialUrl = serverUrl;
    final baseUrl = (customUrl != null && customUrl.trim().isNotEmpty)
        ? customUrl.trim().replaceAll(RegExp(r'/+$'), '')
        : normalizedUrl;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);

    try {
      final tagsUri = Uri.parse('$baseUrl/api/tags');
      final request = await client.getUrl(tagsUri);
      final response = await request.close().timeout(
        const Duration(seconds: 6),
      );

      if (response.statusCode != 200) {
        return [];
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 6));
      final data = jsonDecode(body) as Map<String, dynamic>;
      final result = <AiModelInfo>[];

      if (data['models'] is List) {
        for (final m in data['models']) {
          if (m is Map<String, dynamic> && m['name'] != null) {
            final name = m['name'].toString();
            String? paramSize;
            String? family;
            List<String>? families;

            if (m['details'] is Map) {
              final details = m['details'] as Map;
              paramSize = details['parameter_size']?.toString();
              family = details['family']?.toString();
              if (details['families'] is List) {
                families = (details['families'] as List)
                    .map((e) => e.toString())
                    .toList();
              }
            }

            result.add(
              AiModelInfo.fromModelTag(
                name,
                paramSize: paramSize,
                family: family,
                families: families,
              ),
            );
          }
        }
      }

      return AiModelInfo.forServerSelection(result);
    } catch (e) {
      _logger.warning('Ollama fetchAvailableModels failed: $e');
      client.close(force: true);
      if (retry &&
          customUrl == null &&
          recoverConnection != null &&
          (e is SocketException || e is TimeoutException) &&
          await recoverConnection!(initialUrl)) {
        return _fetchAvailableModels(null, retry: false);
      }
      return [];
    } finally {
      client.close(force: true);
    }
  }

  /// Kiểm tra kết nối tới máy chủ Ollama
  Future<AiConnectionResult> testConnection([String? customUrl]) async {
    final baseUrl = (customUrl != null && customUrl.trim().isNotEmpty)
        ? customUrl.trim().replaceAll(RegExp(r'/+$'), '')
        : normalizedUrl;

    final stopwatch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);

    try {
      final tagsUri = Uri.parse('$baseUrl/api/tags');
      final request = await client.getUrl(tagsUri);
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );

      stopwatch.stop();

      if (response.statusCode != 200) {
        return AiConnectionResult(
          success: false,
          pingMs: stopwatch.elapsedMilliseconds,
          error: 'HTTP ${response.statusCode} (${response.reasonPhrase})',
        );
      }

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 8));
      final data = jsonDecode(body) as Map<String, dynamic>;
      final modelsList = <String>[];
      final parsedModels = <AiModelInfo>[];

      if (data['models'] is List) {
        for (final m in data['models']) {
          if (m is Map<String, dynamic> && m['name'] != null) {
            final name = m['name'].toString();
            modelsList.add(name);

            String? paramSize;
            String? family;
            List<String>? families;

            if (m['details'] is Map) {
              final details = m['details'] as Map;
              paramSize = details['parameter_size']?.toString();
              family = details['family']?.toString();
              if (details['families'] is List) {
                families = (details['families'] as List)
                    .map((e) => e.toString())
                    .toList();
              }
            }

            parsedModels.add(
              AiModelInfo.fromModelTag(
                name,
                paramSize: paramSize,
                family: family,
                families: families,
              ),
            );
          }
        }
      }

      // Lấy thêm thông tin phiên bản Ollama
      var versionStr = '0.20.4';
      try {
        final verUri = Uri.parse('$baseUrl/api/version');
        final verReq = await client.getUrl(verUri);
        final verRes = await verReq.close().timeout(const Duration(seconds: 3));
        if (verRes.statusCode == 200) {
          final verBody = await verRes
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 3));
          final verData = jsonDecode(verBody) as Map<String, dynamic>;
          if (verData['version'] != null) {
            versionStr = verData['version'].toString();
          }
        }
      } catch (_) {}

      final uniqueModels = AiModelInfo.forServerSelection(parsedModels);
      return AiConnectionResult(
        success: true,
        pingMs: stopwatch.elapsedMilliseconds,
        version: versionStr,
        availableModels: uniqueModels.map((model) => model.id).toList(),
        models: uniqueModels,
      );
    } catch (e) {
      stopwatch.stop();
      _logger.warning('Ollama testConnection failed: $e');
      return AiConnectionResult(
        success: false,
        pingMs: stopwatch.elapsedMilliseconds,
        error: e.toString(),
        connectionFailed: e is SocketException || e is TimeoutException,
      );
    } finally {
      client.close(force: true);
    }
  }

  /// Khởi chạy cuộc hội thoại dạng streaming NDJSON
  AiChatStreamHandle chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    bool thinking = false,
    int numCtx = 4096,
    Duration timeout = const Duration(seconds: 180),
  }) {
    if (recoverConnection == null) {
      return _chatStream(
        model: model,
        messages: messages,
        thinking: thinking,
        numCtx: numCtx,
        timeout: timeout,
      );
    }
    final controller = StreamController<AiStreamChunk>();
    AiChatStreamHandle? active;
    var cancelled = false;
    void abort() {
      cancelled = true;
      active?.abort();
      if (!controller.isClosed) controller.close();
    }

    controller.onCancel = abort;
    () async {
      try {
        final url = serverUrl;
        final connection = await testConnection();
        if (cancelled) return;
        if (connection.connectionFailed) {
          final recovered = await recoverConnection!(url);
          if (cancelled) return;
          if (!recovered) {
            controller.add(
              const AiStreamChunk(
                isDone: true,
                errorMessage:
                    'Không kết nối được máy AI. Hãy kiểm tra máy AI và mạng LAN.',
              ),
            );
            return;
          }
        }
        if (cancelled) return;
        final activeUrl = serverUrl;
        active = _chatStream(
          model: model,
          messages: messages,
          thinking: thinking,
          numCtx: numCtx,
          timeout: timeout,
        );
        await for (final chunk in active!.stream) {
          if (cancelled) break;
          controller.add(chunk);
          if (chunk.connectionFailed && !cancelled) {
            // Never replay a chat POST: partial output may already exist.
            await recoverConnection!(activeUrl);
          }
        }
      } catch (e) {
        if (!cancelled && !controller.isClosed) {
          controller.add(
            AiStreamChunk(isDone: true, errorMessage: e.toString()),
          );
        }
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }();
    return AiChatStreamHandle(stream: controller.stream, abort: abort);
  }

  AiChatStreamHandle _chatStream({
    required String model,
    required List<Map<String, dynamic>> messages,
    bool thinking = false,
    int numCtx = 4096,
    Duration timeout = const Duration(seconds: 180),
  }) {
    final controller = StreamController<AiStreamChunk>();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    HttpClientRequest? activeRequest;
    bool isAborted = false;

    void abort() {
      if (!isAborted) {
        isAborted = true;
        _logger.info('Aborting active AI stream request for model ');
        try {
          activeRequest?.abort();
        } catch (_) {}
        client.close(force: true);
        if (!controller.isClosed) {
          controller.add(
            const AiStreamChunk(
              isDone: true,
              errorMessage: 'Lượt tạo đã bị dừng bởi người dùng',
            ),
          );
          controller.close();
        }
      }
    }

    controller.onCancel = () {
      isAborted = true;
      activeRequest?.abort();
      client.close(force: true);
    };

    // Thực hiện request trong luồng async
    () async {
      try {
        final chatUri = Uri.parse('$normalizedUrl/api/chat');
        activeRequest = await client.postUrl(chatUri).timeout(timeout);
        activeRequest!.headers.contentType = ContentType.json;

        final payload = {
          'model': model,
          'messages': messages,
          'stream': true,
          'think': thinking,
          'options': {'num_ctx': numCtx},
        };

        activeRequest!.write(jsonEncode(payload));
        final response = await activeRequest!.close().timeout(timeout);

        if (response.statusCode != 200) {
          final errorBody = await response
              .transform(utf8.decoder)
              .join()
              .timeout(const Duration(seconds: 8));
          if (!controller.isClosed) {
            controller.add(
              AiStreamChunk(
                isDone: true,
                errorMessage: 'Lỗi HTTP ${response.statusCode}: $errorBody',
              ),
            );
            await controller.close();
          }
          return;
        }

        bool insideThinkTag = false;
        bool receivedDone = false;

        await for (final line
            in response
                .transform(utf8.decoder)
                .transform(const LineSplitter())
                .timeout(timeout)) {
          if (isAborted) break;
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;

          try {
            final json = jsonDecode(trimmed) as Map<String, dynamic>;
            if (json['error'] != null) {
              if (!controller.isClosed) {
                controller.add(
                  AiStreamChunk(
                    isDone: true,
                    errorMessage: 'Máy chủ AI báo lỗi',
                  ),
                );
              }
              receivedDone = true;
              break;
            }
            final isDone = json['done'] == true;
            final message = json['message'] as Map<String, dynamic>?;

            String? contentChunk;
            String? thinkingChunk;

            // 1. Kiểm tra trường thinking riêng của Ollama (nếu có)
            if (message != null && message['thinking'] != null) {
              final thinkVal = message['thinking'].toString();
              if (thinkVal.isNotEmpty) {
                thinkingChunk = thinkVal;
              }
            }

            // 2. Kiểm tra content và xử lý thẻ <think>...</think>
            if (message != null && message['content'] != null) {
              var text = message['content'].toString();
              if (text.isNotEmpty) {
                if (text.contains('<think>')) {
                  insideThinkTag = true;
                  final parts = text.split('<think>');
                  if (parts[0].isNotEmpty) contentChunk = parts[0];
                  if (parts.length > 1) {
                    if (parts[1].contains('</think>')) {
                      final subParts = parts[1].split('</think>');
                      thinkingChunk = (thinkingChunk ?? '') + subParts[0];
                      insideThinkTag = false;
                      if (subParts.length > 1 && subParts[1].isNotEmpty) {
                        contentChunk = (contentChunk ?? '') + subParts[1];
                      }
                    } else {
                      thinkingChunk = (thinkingChunk ?? '') + parts[1];
                    }
                  }
                } else if (text.contains('</think>')) {
                  insideThinkTag = false;
                  final parts = text.split('</think>');
                  if (parts[0].isNotEmpty) {
                    thinkingChunk = (thinkingChunk ?? '') + parts[0];
                  }
                  if (parts.length > 1 && parts[1].isNotEmpty) {
                    contentChunk = (contentChunk ?? '') + parts[1];
                  }
                } else if (insideThinkTag) {
                  thinkingChunk = (thinkingChunk ?? '') + text;
                } else {
                  contentChunk = (contentChunk ?? '') + text;
                }
              }
            }

            int? totalDurationMs;
            if (isDone && json['total_duration'] != null) {
              final nanos = json['total_duration'] as num;
              totalDurationMs = (nanos / 1000000).round();
            }

            if (!controller.isClosed) {
              controller.add(
                AiStreamChunk(
                  content: contentChunk,
                  thinkingContent: thinkingChunk,
                  isDone: isDone,
                  totalDurationMs: totalDurationMs,
                ),
              );
            }

            if (isDone) {
              receivedDone = true;
              break;
            }
          } catch (e) {
            _logger.fine('Could not parse streaming chunk line: , error: ');
          }
        }
        if (!receivedDone && !isAborted) {
          throw const HttpException('AI stream ended before done');
        }
      } catch (e) {
        if (!isAborted && !controller.isClosed) {
          _logger.warning('AI chatStream error: ');
          controller.add(
            AiStreamChunk(
              isDone: true,
              errorMessage: e is TimeoutException
                  ? 'AI không phản hồi trong thời gian cho phép'
                  : 'Kết nối AI bị gián đoạn hoặc phản hồi chưa hoàn tất',
              connectionFailed: e is SocketException || e is HttpException,
            ),
          );
        }
      } finally {
        if (!controller.isClosed) {
          await controller.close();
        }
        client.close(force: true);
      }
    }();

    return AiChatStreamHandle(stream: controller.stream, abort: abort);
  }
}
