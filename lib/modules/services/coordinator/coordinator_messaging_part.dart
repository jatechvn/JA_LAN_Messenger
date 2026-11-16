part of '../messenger_coordinator.dart';

extension MessengerCoordinatorMessaging on MessengerCoordinator {
  /// Xử lý tin nhắn văn bản nhận được

  void _handleIncomingMessageImpl(
    String senderIp,
    String messageId,
    String text,
    DateTime timestamp, {
    String? groupId,
  }) {
    final decryptedText = text;

    var senderPeer =
        _incomingPeer(senderIp) ??
        _findPeerByIpOrId(senderIp) ??
        PeerModel(
          id: senderIp,
          name: senderIp,
          ip: senderIp.contains(':') ? senderIp.split(':').first : senderIp,
          port: senderIp.contains(':')
              ? int.tryParse(senderIp.split(':').last) ?? defaultListenerPort
              : defaultListenerPort,
          knownIps: {
            senderIp.contains(':') ? senderIp.split(':').first : senderIp,
          },
        );

    // Tìm tất cả peer trùng lặp tương ứng cùng một máy trạm vật lý
    final matchingPeers = _peers.values.where((p) {
      if (p.isGroup || p.isAllUsers || p.isAiAssistant) return false;
      return _isSamePhysicalPeer(p, senderPeer, senderIp: senderIp);
    }).toSet();

    if (matchingPeers.isNotEmpty) {
      final primaryPeer =
          (_selectedPeer != null && matchingPeers.contains(_selectedPeer))
          ? _selectedPeer!
          : matchingPeers.firstWhere(
              (p) => p.status != PeerStatus.offline,
              orElse: () => matchingPeers.first,
            );
      if (primaryPeer.id != senderPeer.id) {
        _mergeConversations(primaryPeer.id, senderPeer.id);
        _peers[senderPeer.id] = primaryPeer;
        senderPeer = primaryPeer;
      }
    }
    _peers[senderPeer.id] = senderPeer;
    senderPeer.lastSeen = DateTime.now();
    if (_peerSessions.forConversation(senderPeer.id).isNotEmpty) {
      _refreshLogicalPeer(senderPeer);
    } else if (senderPeer.status == PeerStatus.offline) {
      senderPeer.status = PeerStatus.online;
    }

    // Khi nhận tin nhắn, xóa trạng thái đang gõ phím của người này
    _typingPeers.remove(senderPeer.id);

    // 1. Kiểm tra tin nhắn toàn thể [All Users]
    if (groupId == null && decryptedText.startsWith('[All Users] ')) {
      final actualText = decryptedText.substring('[All Users] '.length);
      final quote = MessengerCoordinator._parseQuote(actualText);
      final msg = MessageModel(
        id: messageId,
        senderId: senderPeer.id,
        senderName: senderPeer.name,
        recipientId: '__ALL_USERS__',
        text: quote.text,
        timestamp: timestamp,
        isMine: false,
        status: MessageStatus.delivered,
        replyToSender: quote.replySender,
        replyToText: quote.replyText,
      );
      final list = _conversations.putIfAbsent('__ALL_USERS__', () => []);
      list.add(msg);
      chatHistory.scheduleSave('__ALL_USERS__', list);
      _allUsersPeer.lastMessage = '${senderPeer.name}: ${quote.text}';
      _allUsersPeer.lastMessageTime = timestamp;
      _allUsersPeer.unreadCount++;
      _showDesktopNotification(
        title: '[All Users] ${senderPeer.displayName}',
        body: quote.text,
        peer: _allUsersPeer,
      );
    } else {
      // 2. Kiểm tra tin nhắn Nhóm [GroupName]
      GroupModel? targetGroup = groupId == null ? null : _groups[groupId];
      for (final g in _groups.values) {
        if (groupId == null &&
            g.memberIds.contains(senderPeer.id) &&
            decryptedText.startsWith('[${g.name}] ')) {
          targetGroup = g;
          break;
        }
      }

      if (targetGroup != null) {
        final prefix = '[${targetGroup.name}] ';
        final actualText = groupId == null
            ? decryptedText.substring(prefix.length)
            : decryptedText;
        final quote = MessengerCoordinator._parseQuote(actualText);
        final msg = MessageModel(
          id: messageId,
          senderId: senderPeer.id,
          senderName: senderPeer.name,
          recipientId: targetGroup.id,
          text: quote.text,
          timestamp: timestamp,
          isMine: false,
          status: MessageStatus.delivered,
          replyToSender: quote.replySender,
          replyToText: quote.replyText,
        );
        final list = _conversations.putIfAbsent(targetGroup.id, () => []);
        if (list.any((m) => m.id == messageId && m.senderId == senderPeer.id)) {
          return;
        }
        list.add(msg);
        chatHistory.scheduleSave(targetGroup.id, list);

        targetGroup.lastMessage = '${senderPeer.name}: ${quote.text}';
        targetGroup.lastMessageTime = timestamp;
        targetGroup.unreadCount++;
        _groupTypingPeers[targetGroup.id]?.remove(senderPeer.id);
        _saveGroups();
        _notify();

        _showDesktopNotification(
          title: '[${targetGroup.name}] ${senderPeer.displayName}',
          body: quote.text,
          peer: PeerModel.fromGroup(targetGroup),
        );
      } else {
        // 3. Tin nhắn trò chuyện trực tiếp cá nhân
        final quote = MessengerCoordinator._parseQuote(decryptedText);
        final isCurrentChat =
            _selectedPeer != null &&
            _isSamePhysicalPeer(_selectedPeer!, senderPeer, senderIp: senderIp);
        final msg = MessageModel(
          id: messageId,
          senderId: senderPeer.id,
          senderName: senderPeer.name,
          recipientId: 'me',
          text: quote.text,
          timestamp: timestamp,
          isMine: false,
          status: MessageStatus.delivered,
          replyToSender: quote.replySender,
          replyToText: quote.replyText,
        );

        final list = _conversations.putIfAbsent(senderPeer.id, () => []);
        msg.sourceSession = _incomingHash(senderIp, senderPeer);
        if (list.any(
          (m) =>
              !m.isMine &&
              m.id == messageId &&
              m.sourceSession == msg.sourceSession,
        )) {
          return;
        }
        list.add(msg);
        chatHistory.scheduleSave(senderPeer.id, list);

        // Đảm bảo cuộc hội thoại đang mở lập tức đồng bộ tin nhắn mới
        if (_selectedPeer != null &&
            isCurrentChat &&
            _selectedPeer!.id != senderPeer.id) {
          _conversations[_selectedPeer!.id] = list;
          _selectedPeer!.lastMessage = quote.text;
          _selectedPeer!.lastMessageTime = timestamp;
        }

        senderPeer.lastMessage = quote.text;
        senderPeer.lastMessageTime = timestamp;

        senderPeer.unreadCount++;

        _showDesktopNotification(
          title: senderPeer.displayName,
          body: decryptedText,
          peer: senderPeer,
        );
      }
    }

    _notify();
  }

  /// Xử lý gói tin ACK từ phía nhận
  void _handleMessageAck(String senderIp, String messageId) {
    final peer = _incomingPeer(senderIp);
    final convId = peer?.id ?? senderIp;

    void processFound(
      String targetConvId,
      List<MessageModel> list,
      MessageModel msg,
    ) {
      if (msg.status != MessageStatus.read) {
        msg.status = MessageStatus.delivered;
        chatHistory.scheduleSave(targetConvId, list);
      }
      for (final key in _pendingOfflineMessageIds.keys.toList()) {
        _removePendingOfflineMessage(key, messageId);
      }
      msg.pendingRecipients?.clear();
      _notify();
    }

    final directList = _conversations[convId];
    if (directList != null) {
      for (final msg in directList) {
        if (msg.id == messageId && msg.isMine) {
          processFound(convId, directList, msg);
          return;
        }
      }
    }

    for (final entry in _conversations.entries) {
      for (final msg in entry.value) {
        if (msg.id == messageId && msg.isMine) {
          processFound(entry.key, entry.value, msg);
          return;
        }
      }
    }
  }

  /// Kích hoạt rung cửa sổ native và tự động đưa cửa sổ lên trên cùng (Proposals B & D)
  Future<void> _triggerNativeBuzzAlert() async {
    if (_disposed) return;
    final generation = ++_buzzGeneration;
    _buzzTopTimer?.cancel();
    final prefs = AppPreferences();

    // Proposal D: Auto Bring to Front
    if (prefs.buzzBringToFront) {
      try {
        if (_isCompactMode) {
          await toggleCompactMode();
        }
        await AppPowerManager.instance.showWindow();

        // Tạm thời ghim Always on Top trong 3 giây nếu hiện tại chưa bật
        if (!_isAlwaysOnTop) {
          await windowManager.setAlwaysOnTop(true);
          if (_disposed || generation != _buzzGeneration) return;
          _buzzTopTimer = Timer(const Duration(seconds: 3), () async {
            if (!_isAlwaysOnTop &&
                !_disposed &&
                generation == _buzzGeneration) {
              try {
                await windowManager.setAlwaysOnTop(false);
              } catch (_) {}
            }
          });
        }
      } catch (e) {
        debugPrint('[BuzzAlert] Bring to front error: $e');
      }
    }

    // Proposal B: Native Window Shake (Rung vật lý khung cửa sổ hệ điều hành)
    if (prefs.buzzShakeWindow && !_buzzShakeActive && !_disposed) {
      _buzzShakeActive = true;
      Offset? originalPos;
      try {
        if (await windowManager.isMaximized() ||
            await windowManager.isMinimized()) {
          return;
        }
        originalPos = await windowManager.getPosition();
        const offsets = [
          Offset(12, -2),
          Offset(-12, 2),
          Offset(10, -1),
          Offset(-10, 1),
          Offset(6, 0),
          Offset(-6, 0),
          Offset(3, 0),
          Offset.zero,
        ];

        for (var i = 0; i < offsets.length; i++) {
          await Future.delayed(const Duration(milliseconds: 40));
          if (_disposed) break;
          final offset = offsets[i];
          await windowManager.setPosition(
            Offset(originalPos.dx + offset.dx, originalPos.dy + offset.dy),
          );
        }
      } catch (e) {
        debugPrint('[BuzzAlert] Native window shake error: $e');
      } finally {
        if (originalPos != null) {
          try {
            await windowManager.setPosition(originalPos);
          } catch (e) {
            debugPrint('[BuzzAlert] Restore position error: $e');
          }
        }
        _buzzShakeActive = false;
      }
    }
  }

  /// Kích hoạt cảnh báo Buzz cục bộ (dành cho kiểm thử hoặc xem trước hiệu ứng)
  Future<void> _triggerBuzzAlertForTestingImpl() {
    lastBuzzTime = DateTime.now();
    _buzzTriggerCount++;
    final work = _triggerNativeBuzzAlert();
    _notify();
    return work;
  }

  /// Xử lý rung chuông Buzz

  void _handleIncomingBuzzImpl(String senderIp) {
    lastBuzzTime = DateTime.now();
    _buzzTriggerCount++;
    unawaited(_triggerNativeBuzzAlert());

    final peer = _incomingPeer(senderIp);
    final senderName = peer?.displayName ?? senderIp;
    final conversationId = peer?.id ?? senderIp;
    final text =
        '🔔 $senderName ${languageProvider?.tr('toastNudge') ?? 'vừa rung chuông Nudge!'}';
    final message = MessageModel(
      id: 'buzz-${DateTime.now().microsecondsSinceEpoch}-$_buzzTriggerCount',
      senderId: conversationId,
      senderName: senderName,
      recipientId: 'me',
      text: text,
      isMine: false,
      status: MessageStatus.delivered,
    );
    final messages = _conversations.putIfAbsent(conversationId, () => []);
    messages.add(message);
    chatHistory.scheduleSave(conversationId, messages);
    if (peer != null) {
      peer.lastMessage = text;
      peer.lastMessageTime = message.timestamp;
      peer.unreadCount++;
    }
    showToast('toastNudge', [senderName]);
    _showDesktopNotification(
      title: '🔔 Nudge - $senderName',
      body:
          languageProvider?.tr('nudgeNotificationBody') ??
          'Đã gửi một tín hiệu rung chuông!',
      peer: peer,
    );
    _notify();
  }

  void _checkTypingExpiry() {
    if (_disposed) return;
    var changed = false;
    final now = DateTime.now();
    if (_typingPeers.isNotEmpty) {
      final expired = _typingPeers.entries
          .where((e) => now.difference(e.value).inSeconds >= 4)
          .map((e) => e.key)
          .toList();
      for (final key in expired) {
        _typingPeers.remove(key);
        changed = true;
      }
    }
    if (_groupTypingPeers.isNotEmpty) {
      for (final groupEntry in _groupTypingPeers.entries) {
        final expiredMembers = groupEntry.value.entries
            .where((e) => now.difference(e.value).inSeconds >= 4)
            .map((e) => e.key)
            .toList();
        for (final mId in expiredMembers) {
          groupEntry.value.remove(mId);
          changed = true;
        }
      }
    }
    if (changed) {
      _notify();
    }
  }

  /// Kiểm tra xem đối phương có đang soạn tin nhắn hay không
  bool _isPeerTypingImpl(String peerId) {
    final time = _typingPeers[peerId];
    if (time == null) return false;
    return DateTime.now().difference(time).inSeconds < 4;
  }

  /// Kiểm tra xem có thành viên nào trong nhóm đang soạn tin nhắn hay không
  bool _isGroupTypingImpl(String groupId) {
    final map = _groupTypingPeers[groupId];
    if (map == null || map.isEmpty) return false;
    final now = DateTime.now();
    return map.values.any((t) => now.difference(t).inSeconds < 4);
  }

  /// Lấy chuỗi mô tả các thành viên đang soạn tin trong nhóm (chuẩn Zalo/Telegram)
  String? _getGroupTypingTextImpl(String groupId, LanguageProvider lang) {
    final map = _groupTypingPeers[groupId];
    if (map == null || map.isEmpty) return null;
    final now = DateTime.now();
    final activeMemberIds = map.entries
        .where((e) => now.difference(e.value).inSeconds < 4)
        .map((e) => e.key)
        .toList();
    if (activeMemberIds.isEmpty) return null;

    final names = activeMemberIds.map((id) {
      final p = _findPeerByIpOrId(id);
      return p?.displayName ?? id;
    }).toList();

    if (names.length == 1) {
      return '${names.first} ${lang.tr('typing')}';
    } else if (names.length == 2) {
      return '${names[0]}, ${names[1]} ${lang.tr('typing')}';
    } else {
      return '${names.length} ${lang.tr('peopleTyping')}';
    }
  }

  void _setPeerTypingForTestingImpl(String peerId, bool isTyping) {
    if (isTyping) {
      _typingPeers[peerId] = DateTime.now();
    } else {
      _typingPeers.remove(peerId);
    }
    _notify();
  }

  void _setGroupTypingForTestingImpl(
    String groupId,
    String memberId,
    bool isTyping,
  ) {
    final map = _groupTypingPeers.putIfAbsent(groupId, () => {});
    if (isTyping) {
      map[memberId] = DateTime.now();
    } else {
      map.remove(memberId);
    }
    _notify();
  }

  /// Gửi tín hiệu đang soạn tin hoặc ngừng soạn tin tới peer hoặc nhóm đang chat
  void _sendTypingStatusImpl(bool isTyping) {
    final peer = _selectedPeer;
    if (peer == null || peer.isAllUsers) return;
    final now = DateTime.now();
    if (isTyping) {
      if (_lastTypingSentTime != null &&
          now.difference(_lastTypingSentTime!).inMilliseconds < 1500) {
        return;
      }
      _lastTypingSentTime = now;
    } else {
      _lastTypingSentTime = null;
    }

    if (peer.isGroup) {
      for (final memberId in peer.memberIds) {
        _sendToPeer(
          memberId,
          ProtocolBeebeep.buildTypingPacket(
            isTyping: isTyping,
            groupId: peer.id,
          ),
        );
      }
    } else {
      _sendToPeer(
        peer.id,
        ProtocolBeebeep.buildTypingPacket(isTyping: isTyping),
      );
    }
  }

  /// Đánh dấu toàn bộ tin nhắn trong cuộc trò chuyện là đã đọc
  void _markConversationAsReadImpl(String peerId) {
    markMessagesAsRead(peerId, _conversations[peerId]?.toSet() ?? {});
  }

  /// Called only for individually observed messages, or explicit mark-read actions.
  void _markMessagesAsReadImpl(
    String peerId,
    Set<MessageModel> visibleMessages,
  ) {
    final list = _conversations[peerId];
    var hadUnread = false;
    if (list != null && list.isNotEmpty) {
      for (final m in list) {
        if (visibleMessages.contains(m) &&
            !m.isMine &&
            (m.fileAttachment == null || m.status == MessageStatus.delivered) &&
            m.status != MessageStatus.read) {
          m.status = MessageStatus.read;
          hadUnread = true;
          final fileId = m.fileAttachment != null
              ? RegExp(r'^file_.+/(\d+)$').firstMatch(m.id)?.group(1)
              : null;
          final receiptId = fileId != null ? 'file_$fileId' : m.id;
          final receiptPeer = fileId != null ? m.senderId : peerId;
          if (fileId != null ||
              (peerId != '__ALL_USERS__' &&
                  !_groups.containsKey(peerId) &&
                  int.tryParse(m.id) != null)) {
            final sessions = _peerSessions
                .forConversation(receiptPeer)
                .where((s) => s.available && s.hash == m.sourceSession);
            if (m.sourceSession != null) {
              if (sessions.isNotEmpty) {
                _tcpServer.send(
                  sessions.first.endpoint,
                  ProtocolBeebeep.buildReadPacket(receiptId),
                );
              }
            } else {
              _sendToPeer(
                receiptPeer,
                ProtocolBeebeep.buildReadPacket(receiptId),
              );
            }
          }
        }
      }
    }
    final remaining = countUnreadMessages(peerId);
    if (_selectedPeer?.id == peerId) _selectedPeer!.unreadCount = remaining;
    final peer = _peers[peerId];
    if (peer != null && peer.unreadCount != remaining) {
      peer.unreadCount = remaining;
      hadUnread = true;
    }
    if (peerId == '__ALL_USERS__' && _allUsersPeer.unreadCount != remaining) {
      _allUsersPeer.unreadCount = remaining;
      hadUnread = true;
    }
    final group = _groups[peerId];
    if (group != null && group.unreadCount != remaining) {
      group.unreadCount = remaining;
      hadUnread = true;
      _saveGroups();
    }
    if (hadUnread) {
      if (list != null) {
        chatHistory.scheduleSave(peerId, list);
      }
      _notify();
    }
  }

  /// Xử lý tín hiệu typing nhận được (hỗ trợ cả cá nhân lẫn nhóm chat)
  void _handleIncomingTyping(
    String senderIp,
    bool isTyping, [
    String? groupId,
  ]) {
    if (_disposed) return;
    final peer =
        _incomingPeer(senderIp) ??
        PeerModel(
          id: senderIp,
          name: senderIp,
          ip: senderIp,
          knownIps: {senderIp},
        );
    if (groupId != null && _groups.containsKey(groupId)) {
      final map = _groupTypingPeers.putIfAbsent(groupId, () => {});
      if (isTyping) {
        map[peer.id] = DateTime.now();
      } else {
        map.remove(peer.id);
      }
    } else {
      if (isTyping) {
        _typingPeers[peer.id] = DateTime.now();
      } else {
        _typingPeers.remove(peer.id);
      }
    }
    _notify();
  }

  void _simulateGroupTypingForTestingImpl(
    String groupId,
    String memberId,
    String memberName,
    bool isTyping,
  ) {
    if (!_peers.containsKey(memberId)) {
      _peers[memberId] = PeerModel(
        id: memberId,
        name: memberName,
        ip: '127.0.0.1',
      );
    }
    final map = _groupTypingPeers.putIfAbsent(groupId, () => {});
    if (isTyping) {
      map[memberId] = DateTime.now();
    } else {
      map.remove(memberId);
    }
    _notify();
  }

  /// Xử lý tín hiệu đã xem (read receipt) nhận được
  void _handleIncomingReadReceipt(String senderIp, String messageId) {
    if (_disposed) return;
    if (RegExp(r'^file_\d+$').hasMatch(messageId)) {
      final sender = _incomingPeer(senderIp);
      if (sender == null) return;
      final transferId = messageId.substring(5);
      for (final entry in _conversations.entries) {
        for (final message in entry.value) {
          if (!message.isMine || message.fileAttachment == null) continue;
          if (message.attachmentTransfers[sender.id] == transferId) {
            message.updateAttachmentRecipient(sender.id, MessageStatus.read);
          } else if (entry.key == sender.id &&
              message.id == messageId &&
              message.status == MessageStatus.delivered) {
            message.status = MessageStatus.read;
          } else {
            continue;
          }
          chatHistory.scheduleSave(entry.key, entry.value);
          _notify();
        }
      }
      return;
    }
    final peer =
        _incomingPeer(senderIp) ??
        PeerModel(
          id: senderIp,
          name: senderIp,
          ip: senderIp,
          knownIps: {senderIp},
        );
    final list = _conversations[peer.id];
    if (list != null) {
      var updated = false;
      for (int i = list.length - 1; i >= 0; i--) {
        final msg = list[i];
        if (msg.id == messageId &&
            msg.isMine &&
            msg.status != MessageStatus.read) {
          msg.status = MessageStatus.read;
          updated = true;
        }
      }
      if (updated) {
        chatHistory.scheduleSave(peer.id, list);
        _notify();
      }
    }
  }

  /// Xử lý yêu cầu thu hồi tin nhắn nhận được
  void _handleIncomingRevoke(String senderIp, String messageId) {
    if (_disposed) return;
    final sender = _incomingPeer(senderIp);
    if (sender == null) return;
    final origin = _incomingHash(senderIp, sender);
    var found = false;
    for (final entry in _conversations.entries) {
      for (final msg in entry.value) {
        if (msg.id == messageId &&
            !msg.isMine &&
            msg.senderId == sender.id &&
            (msg.sourceSession == null || msg.sourceSession == origin)) {
          msg.isRevoked = true;
          msg.revokedAt = DateTime.now();
          found = true;

          final peer =
              _peers[entry.key] ??
              (entry.key == '__ALL_USERS__' ? _allUsersPeer : null);
          if (peer != null && peer.lastMessageTime == msg.timestamp) {
            peer.lastMessage =
                '[${languageProvider?.tr('messageRevoked') ?? 'Tin nhắn đã thu hồi'}]';
          }
          chatHistory.scheduleSave(entry.key, entry.value);
          break;
        }
      }
      if (found) break;
    }
    if (found) _notify();
  }

  /// Thả hoặc gỡ biểu tượng cảm xúc (Reaction) cho tin nhắn
  Future<void> _toggleMessageReactionImpl(
    String conversationId,
    String messageId,
    String emoji,
  ) async {
    final messages = _conversations[conversationId];
    if (messages == null) return;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final message = messages[index];
    final added = message.toggleReaction(emoji, localUsername);
    _reactionRevision++;
    chatHistory.scheduleSave(conversationId, messages);
    _notify();

    // Phát sóng gói tin Reaction qua mạng LAN tới đối phương
    final peer = _peers[conversationId];
    final packet = ProtocolBeebeep.buildReactionPacket(
      messageId: messageId,
      emoji: emoji,
      action: added ? 'add' : 'remove',
      senderName: localUsername,
    );

    if (conversationId == '__ALL_USERS__') {
      for (final p in _peers.values.toSet().where(
        (p) => p.status != PeerStatus.offline,
      )) {
        _sendToPeer(p.id, packet);
      }
    } else if (peer != null) {
      if (peer.isGroup) {
        for (final memberId in peer.memberIds) {
          final p = _peers[memberId];
          if (p != null && p.status != PeerStatus.offline) {
            _sendToPeer(p.id, packet);
          }
        }
      } else {
        _sendToPeer(peer.id, packet);
      }
    }
  }

  /// Tiếp nhận cập nhật cảm xúc tin nhắn từ đồng nghiệp qua mạng LAN

  void _handleIncomingReactionImpl(
    String endpoint,
    String messageId,
    String emoji,
    String action,
    String senderName,
  ) {
    if (_disposed || (action != 'add' && action != 'remove')) return;
    final sender = _incomingPeer(endpoint);
    if (sender == null) return;
    bool updated = false;
    for (final entry in _conversations.entries) {
      final group = _groups[entry.key];
      if (entry.key != sender.id &&
          entry.key != '__ALL_USERS__' &&
          !(group?.memberIds.any(
                (id) => identical(_findPeerByIpOrId(id), sender),
              ) ??
              false)) {
        continue;
      }
      final msgs = entry.value;
      final idx = msgs.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final message = msgs[idx];
        if (action == 'add') {
          message.addReaction(emoji, senderName);
        } else {
          message.removeReaction(emoji, senderName);
        }
        chatHistory.scheduleSave(entry.key, msgs);
        updated = true;
        break;
      }
    }
    if (updated) {
      _reactionRevision++;
      _notify();
    }
  }

  /// Chủ động thu hồi một tin nhắn của bản thân
  Future<bool> _revokeMessageImpl(String messageId) async {
    final peer = _selectedPeer;
    if (peer == null) return false;
    final list = _conversations[peer.id];
    if (list == null) return false;
    final index = list.indexWhere((m) => m.id == messageId && m.isMine);
    if (index < 0) return false;
    final msg = list[index];
    msg.isRevoked = true;
    msg.revokedAt = DateTime.now();

    if (peer.lastMessageTime == msg.timestamp) {
      peer.lastMessage =
          '[${languageProvider?.tr('messageRevoked') ?? 'Tin nhắn đã thu hồi'}]';
    }
    chatHistory.scheduleSave(peer.id, list);
    _notify();

    final packet = ProtocolBeebeep.buildRevokePacket(messageId);
    if (peer.isAllUsers) {
      for (final p in _peers.values.toSet().where(
        (p) => p.status != PeerStatus.offline,
      )) {
        _sendToPeer(p.id, packet);
      }
    } else if (peer.isGroup) {
      for (final memberId in peer.memberIds) {
        final p = _peers[memberId];
        if (p != null && p.status != PeerStatus.offline) {
          _sendToPeer(p.id, packet);
        }
      }
    } else {
      _sendToPeer(peer.id, packet);
    }
    return true;
  }

  /// Hiển thị thông báo ngoài màn hình Desktop (Windows / Linux)
  Future<void> _showDesktopNotification({
    required String title,
    required String body,
    PeerModel? peer,
  }) async {
    if (peer != null && peer.isMuted) return;
    if (_disposed) return;
    final preview = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    currentToast = ToastData(
      key: '',
      rawText: '💬 $title: ${String.fromCharCodes(preview.runes.take(160))}',
    );
    _notify();
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;

    try {
      final isFocused = await windowManager.isFocused();
      final isMinimized = await windowManager.isMinimized();
      final isVisible = await windowManager.isVisible();
      final isCurrentChat =
          _selectedPeer != null && peer != null && _selectedPeer!.id == peer.id;

      if (isFocused && !isMinimized && isVisible && isCurrentChat) {
        return;
      }

      final notification = LocalNotification(
        identifier: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: body,
      );

      notification.onClick = () async {
        try {
          await AppPowerManager.instance.showWindow();
          if (peer != null) {
            selectPeer(peer);
          }
        } catch (e) {
          debugPrint('[Notification] Click action error: $e');
        }
      };

      await notification.show();
    } catch (e) {
      debugPrint('[Notification] Show error: $e');
    }
  }

  /// Kiểm tra các máy không còn phản hồi để chuyển sang offline
  void _checkPeerLiveness() {
    final now = DateTime.now();
    var changed = false;
    for (final p in _peers.values) {
      if (!p.isGroup &&
          !p.isAllUsers &&
          p.status != PeerStatus.offline &&
          !_hasActiveConnectionForPeer(p) &&
          now.difference(p.lastSeen).inSeconds > 45) {
        p.status = PeerStatus.offline;
        _failUnackedMessagesForPeer(p);
        changed = true;
      }
    }
    if (changed) _notify();
    unawaited(_probeKnownAndRestoredPeers());
  }

  /// Lấy ID tin nhắn chưa đọc đầu tiên được lưu tại thời điểm chọn cuộc trò chuyện
  String? _getInitialUnreadMessageIdImpl(String peerId) =>
      _initialUnreadMessageIds[peerId];

  /// Xóa bộ nhớ đệm tin nhắn chưa đọc đầu tiên
  void _clearInitialUnreadMessageIdImpl(String peerId) {
    _initialUnreadMessageIds.remove(peerId);
  }

  /// Trả về ID của tin nhắn chưa đọc đầu tiên trong cuộc trò chuyện (nếu có)
  String? _getFirstUnreadMessageIdImpl(String peerId) {
    final list = _conversations[peerId];
    if (list == null || list.isEmpty) return null;
    for (final m in list) {
      if (!m.isMine && m.status != MessageStatus.read) {
        return m.id;
      }
    }
    return null;
  }

  /// Trả về số lượng tin nhắn chưa đọc trong cuộc trò chuyện
  int _countUnreadMessagesImpl(String peerId) {
    final list = _conversations[peerId];
    if (list == null || list.isEmpty) return 0;
    var count = 0;
    for (final m in list) {
      if (!m.isMine && m.status != MessageStatus.read) {
        count++;
      }
    }
    return count;
  }

  int get _reactionRevisionImpl => _reactionRevision;

  /// Lấy nội dung bản nháp đang gõ dở của một cuộc trò chuyện
  String _getDraftImpl(String peerId) => _drafts[peerId] ?? '';

  /// Kiểm tra cuộc trò chuyện có bản nháp khác rỗng hay không
  bool _hasDraftImpl(String peerId) =>
      _drafts[peerId]?.trim().isNotEmpty ?? false;

  /// Lưu hoặc xóa bản nháp của cuộc trò chuyện (chỉ notify khi trạng thái có/không nháp thay đổi hoặc khi được yêu cầu)
  void _setDraftImpl(String peerId, String text, {bool notify = false}) {
    if (peerId.isEmpty) return;
    final prevHasDraft = hasDraft(peerId);
    final prevText = _drafts[peerId] ?? '';
    if (text.isEmpty) {
      _drafts.remove(peerId);
    } else {
      _drafts[peerId] = text;
    }
    final nextHasDraft = hasDraft(peerId);
    if (notify ? prevText != text : prevHasDraft != nextHasDraft) {
      _notify();
    }
  }

  int get _chatFocusRequestIdImpl => _chatFocusRequestId;

  int get _sidebarSearchFocusRequestIdImpl => _sidebarSearchFocusRequestId;

  int get _chatSearchFocusRequestIdImpl => _chatSearchFocusRequestId;

  /// Yêu cầu focus con trỏ vào ô nhập tin nhắn
  void _requestChatInputFocusImpl() {
    _chatFocusRequestId++;
    _notify();
  }

  /// Yêu cầu focus vào ô tìm kiếm liên hệ/nhóm ở Sidebar (Ctrl+K)
  void _requestSidebarSearchFocusImpl() {
    _sidebarSearchFocusRequestId++;
    _notify();
  }

  /// Yêu cầu mở và focus vào thanh tìm kiếm tin nhắn trong hội thoại (Ctrl+F)
  void _requestChatSearchFocusImpl() {
    _chatSearchFocusRequestId++;
    _notify();
  }

  /// Chuyển đổi nhanh sang cuộc trò chuyện liền kề (Alt+Up / Alt+Down)
  void _selectAdjacentPeerImpl(int offset) {
    final navList = <PeerModel>[
      _allUsersPeer,
      for (final g in groups) getPeerForGroup(g),
      ...peers,
    ];
    if (navList.isEmpty) return;
    if (_selectedPeer == null) {
      selectPeer(navList.first);
      return;
    }
    final idx = navList.indexWhere((p) => isPeerSelected(p));
    if (idx == -1) {
      selectPeer(navList.first);
      return;
    }
    final nextIdx = (idx + offset) % navList.length;
    final normalizedIdx = nextIdx < 0 ? nextIdx + navList.length : nextIdx;
    selectPeer(navList[normalizedIdx]);
  }

  /// Chọn một cuộc trò chuyện
  void _selectPeerImpl(PeerModel? peer) {
    _selectedPeer = peer;
    if (peer != null) {
      final firstUnread = getFirstUnreadMessageId(peer.id);
      _initialUnreadMessageIds[peer.id] = firstUnread;
      _chatFocusRequestId++;
    }
    _notify();
  }

  /// Tìm kiếm người dùng
  void _setSearchQueryImpl(String query) {
    _searchQuery = query;
    _notify();
  }

  /// Chuyển tiếp tin nhắn (văn bản, nhãn dán hoặc tệp đính kèm) tới danh sách người nhận/nhóm
  Future<int> _forwardMessageToPeersImpl(
    MessageModel sourceMessage,
    List<PeerModel> recipients, {
    String? note,
  }) async {
    if (recipients.isEmpty) return 0;
    var successCount = 0;
    final attachmentPath = sourceMessage.fileAttachment?.localPath;
    final attachmentFile =
        attachmentPath != null && File(attachmentPath).existsSync()
        ? File(attachmentPath)
        : null;
    final cleanNote = note?.trim() ?? '';

    for (final target in recipients) {
      try {
        if (attachmentFile != null) {
          await sendFile(
            attachmentFile,
            recipient: target,
            caption: cleanNote.isNotEmpty ? cleanNote : null,
          );
          successCount++;
        } else if (sourceMessage.text.trim().isNotEmpty) {
          await sendMessage(sourceMessage.text, recipient: target);
          if (cleanNote.isNotEmpty) {
            await sendMessage(cleanNote, recipient: target);
          }
          successCount++;
        }
      } catch (e) {
        debugPrint('[Forward] Error forwarding to ${target.id}: $e');
      }
    }
    return successCount;
  }

  String _nextMessageId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    if (now <= _lastGeneratedMessageId) {
      _lastGeneratedMessageId++;
    } else {
      _lastGeneratedMessageId = now;
    }
    return '$_lastGeneratedMessageId';
  }

  /// Gửi tin nhắn tới peer hoặc kênh đang chọn (hỗ trợ trích dẫn tin nhắn và chỉ định người nhận)
  Future<bool> _sendMessageImpl(
    String text, {
    MessageModel? replyTo,
    PeerModel? recipient,
  }) async {
    await historyLoaded;
    final targetPeer = recipient ?? _selectedPeer;
    if (targetPeer == null || text.trim().isEmpty) return false;

    // Tự động gỡ huy hiệu "Bạn mới" và bản nháp khi đã gửi tin nhắn trò chuyện
    _newlyAddedPeers.remove(targetPeer.id);
    if (recipient == null) {
      _drafts.remove(targetPeer.id);
      sendTypingStatus(false);
    }

    final msgId = _nextMessageId();
    final plainText = text.trim();

    // Payload định dạng chuẩn gửi qua mạng để tương thích tất cả client
    final networkPayload = replyTo != null
        ? '> [${replyTo.senderName}]: ${replyTo.text.replaceAll('\n', ' ')}\n\n$plainText'
        : plainText;

    final msg = MessageModel(
      id: msgId,
      senderId: 'me',
      senderName: localUsername,
      recipientId: targetPeer.id,
      text: plainText,
      isMine: true,
      status: MessageStatus.sending,
      pendingRecipients: {},
      replyToId: replyTo?.id,
      replyToSender: replyTo?.senderName,
      replyToText: replyTo?.text,
    );

    final list = _conversations.putIfAbsent(targetPeer.id, () => []);
    list.add(msg);
    if (!targetPeer.isAiAssistant) {
      final targets = targetPeer.isGroup
          ? targetPeer.memberIds
          : targetPeer.isAllUsers
          ? peers
                .where(
                  (p) =>
                      p.status != PeerStatus.offline &&
                      !p.isGroup &&
                      !p.isAllUsers &&
                      !p.isAiAssistant,
                )
                .map((p) => p.id)
          : [targetPeer.id];
      for (final target in targets) {
        recordPendingOfflineMessage(target, msgId);
      }
    }
    chatHistory.scheduleSave(targetPeer.id, list);

    targetPeer.lastMessage = plainText;
    targetPeer.lastMessageTime = msg.timestamp;
    if (!targetPeer.isGroup &&
        !targetPeer.isAllUsers &&
        !targetPeer.isAiAssistant &&
        _peers.containsKey(targetPeer.id)) {
      _peers[targetPeer.id]!.lastMessage = plainText;
      _peers[targetPeer.id]!.lastMessageTime = msg.timestamp;
    }
    _notify();

    if (targetPeer.isAiAssistant) {
      msg.status = MessageStatus.sent;
      _dispatchAiResponse(plainText);
      return true;
    }

    if (targetPeer.isAllUsers) {
      // Broadcast tới toàn bộ các peer online (đã lọc trùng lặp card mạng)
      var anySuccess = false;
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
        final ok = _sendToPeer(
          peer.id,
          ProtocolBeebeep.buildChatPacket(
            messageId: msgId,
            text: '[All Users] $networkPayload',
          ),
        );
        if (ok) anySuccess = true;
        if (ok) {
          msg.pendingRecipients?.remove(peer.id);
          _removePendingOfflineMessage(peer.id, msgId);
        }
        if (!ok) recordPendingOfflineMessage(peer.id, msgId);
      }
      msg.status = (anySuccess || onlinePeers.isEmpty)
          ? MessageStatus.sent
          : MessageStatus.failed;
      _allUsersPeer.lastMessage = plainText;
      _allUsersPeer.lastMessageTime = msg.timestamp;
      chatHistory.scheduleSave(targetPeer.id, list);
      _notify();
      return anySuccess;
    } else if (targetPeer.isGroup) {
      // Gửi tới các thành viên trong nhóm
      var anySuccess = false;
      for (final memberId in targetPeer.memberIds) {
        final peer = _peers[memberId] ?? _findPeerByIpOrId(memberId);
        var ok = false;
        if (peer != null && peer.status != PeerStatus.offline) {
          ok = _sendToPeer(
            peer.id,
            ProtocolBeebeep.buildChatPacket(
              messageId: msgId,
              text: networkPayload,
              groupId: targetPeer.id,
              groupName: targetPeer.name,
              groupUpdatedAt: _groups[targetPeer.id]?.updatedAt,
            ),
          );
          if (ok) anySuccess = true;
          if (ok) {
            msg.pendingRecipients?.remove(memberId);
            _removePendingOfflineMessage(memberId, msgId);
          }
        }
        if (!ok) {
          recordPendingOfflineMessage(memberId, msgId);
        }
      }
      msg.status = anySuccess ? MessageStatus.sent : MessageStatus.failed;
      if (_groups.containsKey(targetPeer.id)) {
        _groups[targetPeer.id]!.lastMessage = plainText;
        _groups[targetPeer.id]!.lastMessageTime = msg.timestamp;
        _saveGroups();
      }
      chatHistory.scheduleSave(targetPeer.id, list);
      _notify();
      return anySuccess;
    } else {
      // Gửi qua TCP tới peer cá nhân
      if ((targetPeer.status == PeerStatus.offline || targetPeer.ip.isEmpty) &&
          (targetPeer.ip.isEmpty || hostnameResolverForTesting != null)) {
        await _probePeerNewEndpointIfNeeded(targetPeer);
      }
      final isOffline =
          targetPeer.status == PeerStatus.offline ||
          (_peerSessions.forConversation(targetPeer.id).isNotEmpty &&
              !_peerSessions
                  .forConversation(targetPeer.id)
                  .any((s) => s.available));
      var success = false;
      if (!isOffline) {
        success = _sendToPeer(
          targetPeer.id,
          ProtocolBeebeep.buildChatPacket(
            messageId: msgId,
            text: networkPayload,
          ),
        );
      }
      if (msg.status == MessageStatus.sending) {
        msg.status = success ? MessageStatus.sent : MessageStatus.failed;
      }
      if (!success) {
        recordPendingOfflineMessage(targetPeer.id, msgId);
      } else {
        msg.pendingRecipients?.remove(targetPeer.id);
        _removePendingOfflineMessage(targetPeer.id, msgId);
      }
      chatHistory.scheduleSave(targetPeer.id, list);
      _notify();
      return success;
    }
  }
}
