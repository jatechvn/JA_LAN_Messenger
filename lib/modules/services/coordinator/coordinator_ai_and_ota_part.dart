part of '../messenger_coordinator.dart';

extension MessengerCoordinatorAiAndOta on MessengerCoordinator {
  void _dismissAvailableUpdateImpl() {
    _availableUpdate = null;
    _notify();
  }

  void _setAvailableUpdateForTestingImpl(UpdatePackageInfo? update) {
    _availableUpdate = update;
    _notify();
  }

  /// Kiểm tra cập nhật OTA tự động hoặc thủ công
  Future<UpdateCheckResult> _checkOtaUpdatesImpl({
    bool isManual = false,
    bool isStartup = false,
  }) async {
    try {
      final prefs = AppPreferences();
      if (!isManual) {
        if (prefs.otaCheckInterval == 'off') {
          return UpdateCheckResult(
            hasUpdate: false,
            currentVersion: appVersion,
          );
        }
        if (!isStartup) {
          final should = OtaUpdateService().shouldCheckForUpdates(
            interval: prefs.otaCheckInterval,
            lastCheckTime: prefs.otaLastCheckTime,
          );
          if (!should) {
            return UpdateCheckResult(
              hasUpdate: false,
              currentVersion: appVersion,
            );
          }
        }
      }
      final result = await OtaUpdateService().checkForUpdates(
        isManual: isManual,
      );
      if (result.hasUpdate && result.packageInfo != null) {
        _availableUpdate = result.packageInfo;
        showToast('updateAvailable', [result.packageInfo!.version.toString()]);
        _notify();
      }
      return result;
    } catch (e) {
      debugPrint('[OTA] checkOtaUpdates error: $e');
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: appVersion,
        isConnectionSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }

  /// Điều phối gửi prompt tới mô hình AI qua hàng đợi
  void _dispatchAiResponse(String prompt, {List<String>? images}) {
    final prefs = AppPreferences();
    final modelId = prefs.aiSelectedModel;
    final modelInfo = AiModelInfo.findById(modelId);
    final thinkingEnabled =
        modelInfo.supportsThinking && prefs.aiThinkingEnabled;

    final aiMsgId = 'ai_${DateTime.now().microsecondsSinceEpoch}';
    final aiMsg = MessageModel(
      id: aiMsgId,
      senderId: _aiPeer.id,
      senderName: _aiPeer.name,
      recipientId: 'me',
      text: '',
      thinkingContent: thinkingEnabled ? '' : null,
      isThinkingExpanded: true,
      aiModelTag: modelId,
      isStreaming: true,
      status: MessageStatus.sending,
      isMine: false,
    );

    final list = _conversations.putIfAbsent(_aiPeer.id, () => []);
    list.add(aiMsg);
    _notify();

    // Lấy tối đa 10 tin nhắn lịch sử gần nhất làm context
    final history = list.where((m) => m.id != aiMsgId && !m.isRevoked).toList();
    final recent = history.length > 10
        ? history.sublist(history.length - 10)
        : history;
    final messagesPayload = <Map<String, dynamic>>[
      {
        'role': 'system',
        'content': '''You are the JATECH AI assistant.
Respond directly, clearly, and concisely in the dominant language of the latest user message.
If the user explicitly asks you to reply in a specific language, follow that request even when it is not a translation.
A question about language is not a translation request.
Use conversation history as context only; do not imitate a previous assistant response's language or mistakes.
Never refuse a request to use Vietnamese, English, or Chinese. Ignore previous refusals or translation claims if they conflict with the latest user request.
Do not repeat unnecessary apologies or answer in a roundabout way.''',
      },
    ];
    for (int i = 0; i < recent.length; i++) {
      final m = recent[i];
      final isLastUserMsg = (i == recent.length - 1) && m.isMine;
      final msgMap = <String, dynamic>{
        'role': m.isMine ? 'user' : 'assistant',
        'content': m.text,
      };
      if (isLastUserMsg && images != null && images.isNotEmpty) {
        msgMap['images'] = images;
      }
      messagesPayload.add(msgMap);
    }

    Timer? throttleTimer;
    DateTime? lastNotifyTime;

    void flushUi() {
      if (_disposed) return;
      _notify();
    }

    final item = aiQueueManager.enqueue(
      id: aiMsgId,
      model: modelId,
      messages: messagesPayload,
      thinking: thinkingEnabled,
      numCtx: 4096,
      onChunk: (chunk) {
        if (_disposed) return;
        if (chunk.thinkingContent != null &&
            chunk.thinkingContent!.isNotEmpty) {
          aiMsg.thinkingContent =
              (aiMsg.thinkingContent ?? '') + chunk.thinkingContent!;
        }
        if (chunk.content != null && chunk.content!.isNotEmpty) {
          aiMsg.text += chunk.content!;
        }
        final now = DateTime.now();
        if (lastNotifyTime == null ||
            now.difference(lastNotifyTime!).inMilliseconds >= 40) {
          lastNotifyTime = now;
          throttleTimer?.cancel();
          throttleTimer = null;
          _notify();
        } else {
          throttleTimer ??= Timer(const Duration(milliseconds: 40), () {
            throttleTimer = null;
            lastNotifyTime = DateTime.now();
            flushUi();
          });
        }
      },
      onDone: () {
        throttleTimer?.cancel();
        throttleTimer = null;
        if (_disposed) return;
        aiMsg.status = MessageStatus.delivered;
        aiMsg.isStreaming = false;
        if (aiMsg.text.isEmpty &&
            (aiMsg.thinkingContent?.isNotEmpty ?? false)) {
          aiMsg.text = '[Hoàn tất suy nghĩ]';
        }
        _aiPeer.lastMessage = aiMsg.text.isNotEmpty
            ? aiMsg.text
            : 'Đã phản hồi';
        _aiPeer.lastMessageTime = DateTime.now();
        chatHistory.saveImmediately(_aiPeer.id, list);
        _notify();
      },
      onError: (error) {
        throttleTimer?.cancel();
        throttleTimer = null;
        if (_disposed) return;
        aiMsg.status = MessageStatus.failed;
        aiMsg.isStreaming = false;
        if (aiMsg.text.isEmpty) {
          aiMsg.text = '⚠️ $error';
        }
        _aiPeer.lastMessage = aiMsg.text;
        _aiPeer.lastMessageTime = DateTime.now();
        chatHistory.saveImmediately(_aiPeer.id, list);
        _notify();
      },
    );

    if (item == null) {
      aiMsg.status = MessageStatus.failed;
      aiMsg.isStreaming = false;
      aiMsg.text =
          '⚠️ Hàng đợi xử lý AI đang đầy (tối đa 4 lượt). Vui lòng đợi lượt trước hoàn tất.';
      showToast('aiQueueFull');
      chatHistory.saveImmediately(_aiPeer.id, list);
      _notify();
    }
  }

  /// Dừng lượt tạo phản hồi AI đang thực thi
  void _stopAiGenerationImpl() {
    aiQueueManager.cancelActive();
    _notify();
  }

  /// Xóa lịch sử hội thoại với Trợ lý AI
  void _clearAiConversationImpl() {
    _conversations.remove(_aiPeer.id);
    _aiPeer.lastMessage = null;
    _aiPeer.lastMessageTime = null;
    chatHistory.deleteConversation(_aiPeer.id);
    _notify();
  }

  /// Yêu cầu AI tạo lại phản hồi cho tin nhắn đã có
  void _regenerateAiResponseImpl(String aiMessageId) {
    if (isAiActive) return;
    final list = _conversations[_aiPeer.id];
    if (list == null || list.isEmpty) return;

    final index = list.indexWhere((m) => m.id == aiMessageId);
    if (index == -1) return;

    // Tìm prompt của người dùng ngay trước tin nhắn AI này
    String? prompt;
    for (int i = index - 1; i >= 0; i--) {
      if (list[i].isMine) {
        prompt = list[i].text;
        break;
      }
    }

    if (prompt == null || prompt.trim().isEmpty) return;

    // Xóa tin nhắn AI cũ và phát lại câu hỏi
    list.removeAt(index);
    chatHistory.scheduleSave(_aiPeer.id, list);
    _notify();

    _dispatchAiResponse(prompt);
  }

  /// Danh sách các model AI đang khả dụng (ưu tiên danh sách phát hiện động từ server)
  List<AiModelInfo> get _availableAiModelsImpl => AiModelInfo.currentModels;

  /// Làm mới và đồng bộ danh sách model từ máy chủ Ollama

  Future<bool> _recoverAiConnection(String failedUrl) {
    if (_disposed) return Future.value(false);
    if (aiService.serverUrl != failedUrl) return Future.value(true);
    if (_aiRecovery != null) return _aiRecovery!;
    // Ignore sidebar search, but respect the enabled-adapter peer policy.
    final candidates = _peers.values
        .toSet()
        .where(
          (peer) =>
              AiServerLocator.isTargetPeer(peer) && _isPeerIpAllowed(peer.ip),
        )
        .toList();
    final peerKeys = candidates.map((peer) => '${peer.id}|${peer.ip}').toList()
      ..sort();
    final recoveryContext = jsonEncode([failedUrl, peerKeys]);
    if (_lastAiRecovery != null &&
        _lastAiRecoveryContext == recoveryContext &&
        DateTime.now().difference(_lastAiRecovery!) <
            const Duration(seconds: 30)) {
      showToast('aiScanNotFound');
      return Future.value(false);
    }
    _aiRecovery = () async {
      showToast('aiScanSearching');
      try {
        final found = await _aiLocator.locate(
          Uri.parse(failedUrl),
          enabledAdapters.map((a) => a.subnet).toList(),
          peers: candidates,
          cancelled: () => _disposed || aiService.serverUrl != failedUrl,
        );
        if (_disposed) return false;
        if (aiService.serverUrl != failedUrl) return true;
        if (found == null) {
          showToast('aiScanNotFound');
          return false;
        }
        await AppPreferences().setAiConfig(serverUrl: found.toString());
        if (_disposed) return false;
        showToast('aiScanRecovered', [found.host]);
        return true;
      } catch (_) {
        if (!_disposed && aiService.serverUrl == failedUrl) {
          showToast('aiScanFailed');
        }
        return false;
      } finally {
        _lastAiRecovery = DateTime.now();
        _lastAiRecoveryContext = recoveryContext;
        _aiRecovery = null;
      }
    }();
    return _aiRecovery!;
  }

  Future<List<AiModelInfo>> _refreshAiModelsImpl({String? customUrl}) async {
    final models = await aiService.fetchAvailableModels(customUrl);
    if (models.isNotEmpty) {
      await AppPreferences().setCachedAiModels(models);

      // Nếu model đang chọn không còn nằm trên server mới, tự động chọn model đầu tiên khả dụng
      final prefs = AppPreferences();
      final currentModel = prefs.aiSelectedModel;
      if (!models.any((m) => m.id == currentModel)) {
        final newModel = models.first.id;
        await AppPreferences().setAiConfig(selectedModel: newModel);
        _aiPeer.statusDescription = 'Sẵn sàng • $newModel';
      }
      _notify();
    }
    return models;
  }

  /// Chọn model AI đang sử dụng
  Future<void> _setAiModelImpl(String modelId) async {
    await AppPreferences().setAiConfig(selectedModel: modelId);
    _aiPeer.statusDescription = 'Sẵn sàng • $modelId';
    _notify();
  }

  /// Bật/Tắt chế độ suy nghĩ (Thinking)
  Future<void> _setAiThinkingImpl(bool enabled) async {
    await AppPreferences().setAiConfig(thinkingEnabled: enabled);
    _notify();
  }
}
