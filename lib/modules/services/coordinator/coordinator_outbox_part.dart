part of '../messenger_coordinator.dart';

extension MessengerCoordinatorOutbox on MessengerCoordinator {
  /// Ghi nhận một tin nhắn vào Outbox chờ gửi lại khi peer online

  void _recordPendingOfflineMessageImpl(String targetKey, String messageId) {
    _pendingOfflineMessageIds.putIfAbsent(targetKey, () => {}).add(messageId);
    _ensureOutboxRetryTimer();
    for (final entry in _conversations.entries) {
      for (final msg in entry.value.where(
        (m) => m.id == messageId && _isRetryableText(m),
      )) {
        (msg.pendingRecipients ??= {}).add(targetKey);
        chatHistory.scheduleSave(entry.key, entry.value);
      }
    }
  }

  bool _isRetryableText(MessageModel msg) =>
      msg.isMine &&
      // Buzz uses its own protocol packet. These IDs identify local UI notices,
      // not chat messages; sending them produces an invalid non-numeric wire ID.
      !msg.id.startsWith('buzz-') &&
      !msg.isRevoked &&
      msg.fileAttachment == null &&
      msg.recipientId != '__AI_ASSISTANT__';

  bool _canRetryMessageImpl(MessageModel msg) =>
      _isRetryableText(msg) && msg.status == MessageStatus.failed;

  void _removePendingOfflineMessage(String targetKey, String messageId) {
    _pendingOfflineMessageIds[targetKey]?.remove(messageId);
    if (_pendingOfflineMessageIds[targetKey]?.isEmpty ?? false) {
      _pendingOfflineMessageIds.remove(targetKey);
    }
    if (_pendingOfflineMessageIds.isEmpty) {
      _outboxRetryTimer?.cancel();
      _outboxRetryTimer = null;
    }
  }

  void _ensureOutboxRetryTimer() {
    if (_disposed ||
        _pendingOfflineMessageIds.isEmpty ||
        _outboxRetryTimer != null) {
      return;
    }
    _outboxRetryTimer = Timer.periodic(outboxRetryInterval, (_) {
      unawaited(_retryPendingOutbox());
    });
  }

  Future<void> _retryPendingOutbox() async {
    if (_disposed || _outboxRetryRunning) return;
    if (_pendingOfflineMessageIds.isEmpty) {
      _outboxRetryTimer?.cancel();
      _outboxRetryTimer = null;
      return;
    }
    _outboxRetryRunning = true;
    try {
      await historyLoaded;
      for (final peer in _peers.values.toSet().toList()) {
        if (_disposed) return;
        if (peer.isGroup ||
            peer.isAllUsers ||
            peer.isAiAssistant ||
            (peer.status == PeerStatus.offline &&
                hostnameResolverForTesting == null &&
                !_isInitialized)) {
          continue;
        }
        final keys = {
          peer.id,
          if (peer.ip.isNotEmpty) peer.ip,
          if (peer.ip.isNotEmpty) '${peer.ip}:${peer.port}',
          peer.canonicalIdentity,
          ...chatHistory.aliasesFor(peer.id),
          ...peer.knownIps,
          for (final ip in peer.knownIps) '$ip:${peer.port}',
          if (_peerHashes[peer.id] case final String hash) 'hash:$hash',
        };
        if (!keys.any(_pendingOfflineMessageIds.containsKey)) continue;
        if (_outboxInFlight.any((key) => key.endsWith(':${peer.id}'))) continue;
        try {
          if (!_hasActiveConnectionForPeer(peer)) {
            if (peer.ip.isNotEmpty &&
                peer.status != PeerStatus.offline &&
                hostnameResolverForTesting == null) {
              await _connectPeer(peer.ip, peer.port);
            } else {
              await _probePeerNewEndpointIfNeeded(peer);
            }
          }
          if (!_disposed &&
              identical(_peers[peer.id], peer) &&
              peer.status != PeerStatus.offline) {
            await flushPendingOutgoingMessagesForPeer(peer);
          }
        } catch (error) {
          // Keep pending targets; a later tick or handshake can retry.
          debugPrint('[Outbox] Retry failed: ${error.runtimeType}');
        }
      }
    } finally {
      _outboxRetryRunning = false;
    }
  }

  /// Tự động gửi lại các tin nhắn tồn đọng trong Outbox khi một peer online

  Future<void> _flushPendingOutgoingMessagesForPeerImpl(PeerModel peer) async {
    await historyLoaded;
    if (_disposed) return;
    final candidateKeys = <String>{
      peer.id,
      if (peer.ip.isNotEmpty) peer.ip,
      if (peer.ip.isNotEmpty) '${peer.ip}:${peer.port}',
      peer.canonicalIdentity,
      ...peer.knownIps,
      for (final ip in peer.knownIps) '$ip:${peer.port}',
      ..._peers.entries
          .where((e) => identical(e.value, peer))
          .map((e) => e.key),
      ...chatHistory.aliasesFor(peer.id),
      if (_peerHashes[peer.id] case final String hash) 'hash:$hash',
    };

    // Thu thập tin nhắn cần gửi lại
    final messagesToRetry = <({String convId, MessageModel msg})>[];
    final collectedMsgIds = <String>{};

    // 1. Quét tin nhắn 1-1 chưa gửi được trong các conversation tương ứng
    for (final convEntry in _conversations.entries) {
      final convId = convEntry.key;
      final isDirectChat =
          candidateKeys.contains(convId) &&
          (_peers[convId] == null || identical(_peers[convId], peer));
      if (isDirectChat) {
        for (final msg in convEntry.value) {
          final isPending =
              msg.pendingRecipients?.any(candidateKeys.contains) == true ||
              _pendingOfflineMessageIds.entries.any(
                (e) =>
                    candidateKeys.contains(e.key) && e.value.contains(msg.id),
              );
          final needsRetry =
              msg.isMine &&
              _isRetryableText(msg) &&
              (msg.status == MessageStatus.failed ||
                  msg.status == MessageStatus.sending ||
                  (msg.status == MessageStatus.sent && isPending));
          if (needsRetry && collectedMsgIds.add(msg.id)) {
            messagesToRetry.add((convId: convId, msg: msg));
          }
        }
      }
    }

    // 2. Thu thập tin nhắn nhóm mà peer này bị ghi nhận là chưa nhận được
    for (final key in candidateKeys) {
      final pendingMsgIds = _pendingOfflineMessageIds[key];
      if (pendingMsgIds != null && pendingMsgIds.isNotEmpty) {
        for (final msgId in pendingMsgIds.toList()) {
          for (final convEntry in _conversations.entries) {
            final group = _groups[convEntry.key];
            if (convEntry.key == '__ALL_USERS__' ||
                (group != null &&
                    group.memberIds.any((id) => candidateKeys.contains(id)))) {
              final groupMsgs = convEntry.value;
              for (final msg in groupMsgs) {
                if (msg.id == msgId &&
                    _isRetryableText(msg) &&
                    collectedMsgIds.add(msg.id)) {
                  messagesToRetry.add((convId: convEntry.key, msg: msg));
                }
              }
            }
          }
        }
      }
    }

    if (messagesToRetry.isEmpty) return;

    // Sắp xếp tin nhắn theo thời gian gửi từ cũ đến mới
    messagesToRetry.sort((a, b) => a.msg.timestamp.compareTo(b.msg.timestamp));

    // Đợi 100ms để kết nối socket hoàn tất ổn định sau handshake
    await Future.delayed(const Duration(milliseconds: 100));

    final savedConvs = <String>{};
    for (final item in messagesToRetry) {
      if (_disposed || peer.status == PeerStatus.offline) break;
      final msg = item.msg;
      final convId = item.convId;
      if (!_isRetryableText(msg) ||
          !(_conversations[convId]?.contains(msg) ?? false)) {
        continue;
      }
      if (_outboxInFlight.contains('${msg.id}:${peer.id}')) continue;
      final isPending =
          (msg.pendingRecipients?.any(candidateKeys.contains) ?? false) ||
          _pendingOfflineMessageIds.entries.any(
            (e) => candidateKeys.contains(e.key) && e.value.contains(msg.id),
          );
      if (!isPending &&
          msg.status != MessageStatus.failed &&
          msg.status != MessageStatus.sending) {
        continue;
      }
      final currentGroup = _groups[convId];
      if (currentGroup == null &&
          convId != '__ALL_USERS__' &&
          !candidateKeys.contains(convId)) {
        continue;
      }
      if (convId.startsWith('group_') &&
          (currentGroup == null ||
              !currentGroup.memberIds.any(candidateKeys.contains))) {
        continue;
      }

      final isGroup = _groups.containsKey(convId);
      final networkPayload =
          msg.replyToSender != null && msg.replyToText != null
          ? '> [${msg.replyToSender}]: ${msg.replyToText!.replaceAll('\n', ' ')}\n\n${msg.text}'
          : msg.text;

      final packet = isGroup
          ? ProtocolBeebeep.buildChatPacket(
              messageId: msg.id,
              text: networkPayload,
              groupId: convId,
              groupName: _groups[convId]?.name,
              groupUpdatedAt: _groups[convId]?.updatedAt,
            )
          : ProtocolBeebeep.buildChatPacket(
              messageId: msg.id,
              text: convId == '__ALL_USERS__'
                  ? '[All Users] $networkPayload'
                  : networkPayload,
            );

      final success = _sendToPeer(peer.id, packet);
      if (success) {
        if (msg.status != MessageStatus.read &&
            msg.status != MessageStatus.delivered) {
          msg.status = MessageStatus.sent;
        }
        for (final k in candidateKeys) {
          _removePendingOfflineMessage(k, msg.id);
          msg.pendingRecipients?.remove(k);
        }
        savedConvs.add(convId);
        _notify();
        await Future.delayed(const Duration(milliseconds: 40));
      }
    }

    for (final cId in savedConvs) {
      final list = _conversations[cId];
      if (list != null) {
        chatHistory.scheduleSave(cId, list);
      }
    }
  }

  /// Thử gửi lại một tin nhắn bị lỗi (thủ công từ UI hoặc gọi trực tiếp)
  Future<bool> _retrySendMessageImpl(
    MessageModel msg, {
    String? conversationId,
  }) async {
    await historyLoaded;
    if (_disposed || !canRetryMessage(msg)) return false;
    final convId = conversationId ?? msg.conversationId;
    final list = _conversations[convId];
    if (list == null || !list.contains(msg)) return false;
    if (!_groups.containsKey(convId) &&
        convId != '__ALL_USERS__' &&
        _peers[convId] == null &&
        _findPeerByIpOrId(convId) == null &&
        _selectedPeer?.id != convId) {
      return false;
    }
    if (convId.startsWith('group_') && !_groups.containsKey(convId)) {
      return false;
    }

    msg.status = MessageStatus.sending;
    _notify();

    final networkPayload = msg.replyToSender != null && msg.replyToText != null
        ? '> [${msg.replyToSender}]: ${msg.replyToText!.replaceAll('\n', ' ')}\n\n${msg.text}'
        : msg.text;

    var success = false;
    if (_groups.containsKey(convId)) {
      // Gửi vào nhóm
      final group = _groups[convId]!;
      for (final memberId in group.memberIds) {
        final peer = _peers[memberId] ?? _findPeerByIpOrId(memberId);
        final targets = {
          memberId,
          if (peer != null) peer.id,
          if (peer != null && _peerHashes[peer.id] != null)
            'hash:${_peerHashes[peer.id]}',
        };
        if (msg.pendingRecipients != null &&
            !msg.pendingRecipients!.any(targets.contains)) {
          continue;
        }
        var ok = false;
        if (peer != null && peer.status != PeerStatus.offline) {
          ok = _sendToPeer(
            peer.id,
            ProtocolBeebeep.buildChatPacket(
              messageId: msg.id,
              text: networkPayload,
              groupId: group.id,
              groupName: group.name,
              groupUpdatedAt: group.updatedAt,
            ),
          );
          if (ok) success = true;
        }
        if (ok) {
          for (final key in targets) {
            _removePendingOfflineMessage(key, msg.id);
            msg.pendingRecipients?.remove(key);
          }
        } else {
          recordPendingOfflineMessage(memberId, msg.id);
        }
      }
    } else if (convId == '__ALL_USERS__') {
      final onlinePeers = peers
          .where(
            (p) =>
                !p.isGroup &&
                !p.isAllUsers &&
                !p.isAiAssistant &&
                p.status != PeerStatus.offline,
          )
          .toList();
      for (final peer in onlinePeers) {
        if (msg.pendingRecipients != null &&
            !msg.pendingRecipients!.contains(peer.id)) {
          continue;
        }
        final ok = _sendToPeer(
          peer.id,
          ProtocolBeebeep.buildChatPacket(
            messageId: msg.id,
            text: '[All Users] $networkPayload',
          ),
        );
        if (ok) success = true;
        if (ok) {
          _removePendingOfflineMessage(peer.id, msg.id);
          msg.pendingRecipients?.remove(peer.id);
        } else {
          recordPendingOfflineMessage(peer.id, msg.id);
        }
      }
    } else {
      // Chat cá nhân 1-1
      final peer =
          _peers[convId] ??
          _findPeerByIpOrId(convId) ??
          (_selectedPeer?.id == convId ? _selectedPeer : null);
      if (peer != null) {
        final flightKey = '${msg.id}:${peer.id}';
        _outboxInFlight.add(flightKey);
        try {
          if (!_hasActiveConnectionForPeer(peer)) {
            if (peer.ip.isNotEmpty && hostnameResolverForTesting == null) {
              await _connectPeer(peer.ip, peer.port);
            } else {
              await _probePeerNewEndpointIfNeeded(peer);
            }
          }
          if (!_disposed &&
              _isRetryableText(msg) &&
              (_conversations[convId]?.contains(msg) ?? false)) {
            success = _sendToPeer(
              peer.id,
              ProtocolBeebeep.buildChatPacket(
                messageId: msg.id,
                text: networkPayload,
              ),
            );
          }
        } catch (e) {
          debugPrint('[Outbox] Connection failed: ${e.runtimeType}');
        } finally {
          _outboxInFlight.remove(flightKey);
        }
      } else {
        success = _sendToPeer(
          convId,
          ProtocolBeebeep.buildChatPacket(
            messageId: msg.id,
            text: networkPayload,
          ),
        );
      }
    }

    if (_disposed ||
        !_isRetryableText(msg) ||
        !(_conversations[convId]?.contains(msg) ?? false)) {
      return false;
    }
    if (msg.status != MessageStatus.read &&
        msg.status != MessageStatus.delivered) {
      msg.status = success ? MessageStatus.sent : MessageStatus.failed;
    }
    if (!success && !_groups.containsKey(convId) && convId != '__ALL_USERS__') {
      recordPendingOfflineMessage(convId, msg.id);
    } else if (success) {
      _removePendingOfflineMessage(convId, msg.id);
      msg.pendingRecipients?.remove(convId);
      showToast('messageResentSuccess');
    }
    chatHistory.scheduleSave(convId, list);
    _notify();
    return success;
  }
}
