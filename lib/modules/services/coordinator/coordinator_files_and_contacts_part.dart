part of '../messenger_coordinator.dart';

extension MessengerCoordinatorFilesAndContacts on MessengerCoordinator {
  /// Trích xuất danh sách tệp hoặc ảnh chụp màn hình từ Clipboard mà không gửi ngay
  Future<List<File>> _getClipboardAttachmentsImpl() async {
    final result = <File>[];
    try {
      // 1. Kiểm tra ảnh trong Clipboard (chụp màn hình Snipping Tool, Win+Shift+S, PrtScn)
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final tempDir = Directory.systemTemp;
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final imageFile = File('${tempDir.path}\\screenshot_$timestamp.png');
        await imageFile.writeAsBytes(await clipboardImageToPng(imageBytes));
        if (await imageFile.exists()) {
          result.add(imageFile);
          return result;
        }
      }

      // 2. Kiểm tra danh sách tệp trong Clipboard (copy từ Windows Explorer)
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        for (final path in files) {
          final file = File(path);
          if (await file.exists()) {
            result.add(file);
          }
        }
      }
    } catch (e) {
      debugPrint('[Coordinator] Get clipboard attachments error: $e');
    }
    return result;
  }

  /// Dán hình ảnh hoặc tệp tin trực tiếp từ Clipboard (hỗ trợ gửi ngay khi cần)
  Future<bool> _pasteFromClipboardImpl() async {
    if (_selectedPeer == null) return false;

    try {
      final files = await getClipboardAttachments();
      if (files.isNotEmpty) {
        await sendFiles(files);
        return true;
      }
    } catch (e) {
      debugPrint('[Coordinator] Clipboard paste error: $e');
    }

    return false;
  }

  /// Gửi rung chuông Buzz
  Future<void> _sendBuzzImpl() async {
    if (_selectedPeer == null) return;
    final targetPeer = _selectedPeer!;
    final conversationId = targetPeer.id;
    final targetName = targetPeer.displayName;

    bool sentSuccess = false;
    if (targetPeer.isAllUsers) {
      for (final p in _peers.values.toSet().where(
        (p) => p.status != PeerStatus.offline,
      )) {
        final ok = _sendToPeer(
          p.id,
          ProtocolBeebeep.packet(
            ProtocolBeebeep.headerBuzz,
            '22',
            text: '*',
            flags: 1,
          ),
        );
        if (ok) sentSuccess = true;
      }
    } else if (targetPeer.isGroup) {
      for (final memberId in targetPeer.memberIds) {
        final p = _peers[memberId];
        if (p != null && p.status != PeerStatus.offline) {
          final ok = _sendToPeer(
            p.id,
            ProtocolBeebeep.packet(
              ProtocolBeebeep.headerBuzz,
              '22',
              text: '*',
              flags: 1,
            ),
          );
          if (ok) sentSuccess = true;
        }
      }
    } else {
      // Chat cá nhân 1-1:
      // Nếu trạng thái hiển thị hiện tại là offline, trước tiên thăm dò kết nối TCP tới port ứng dụng (6475)
      // để nếu ứng dụng bên đối phương thực tế đang chạy thì lập tức nhận diện online và gửi Buzz bình thường,
      // hoàn toàn không gọi lệnh WinRM hay hiển thị thông báo WinRM gây hiểu lầm.
      if (targetPeer.status == PeerStatus.offline) {
        final targetIp = targetPeer.ip.isNotEmpty
            ? targetPeer.ip
            : (targetPeer.knownIps.isNotEmpty ? targetPeer.knownIps.first : '');
        if (targetIp.isNotEmpty) {
          final port = targetPeer.port > 0
              ? targetPeer.port
              : defaultListenerPort;
          final connected = await _connectPeer(
            targetIp,
            port,
            timeout: const Duration(milliseconds: 500),
          );
          if (connected) {
            // HELLO may resolve a different owner of a reused endpoint. Only
            // its handler may update the intended conversation's presence.
            final session = _peerSessions.sessions['$targetIp:$port'];
            if (session == null || session.conversationId != targetPeer.id) {
              final recovered = await _probePeerNewEndpointIfNeeded(targetPeer);
              if (!recovered) return;
            } else {
              _refreshLogicalPeer(targetPeer);
            }
          } else {
            await _probePeerNewEndpointIfNeeded(targetPeer);
          }
        } else {
          await _probePeerNewEndpointIfNeeded(targetPeer);
        }
      }

      if (targetPeer.status == PeerStatus.offline) {
        await _handleOfflineBuzz(targetPeer);
        return;
      }

      sentSuccess = _sendToPeer(
        targetPeer.id,
        ProtocolBeebeep.packet(
          ProtocolBeebeep.headerBuzz,
          '22',
          text: '*',
          flags: 1,
        ),
      );
    }

    // Ghi nhận tin nhắn rung chuông vào cuộc hội thoại của chính người gửi
    final sentText =
        '🔔 ${languageProvider?.tr('buzzSent', [targetName]) ?? 'Bạn đã gửi rung chuông tới $targetName'}';
    final message = MessageModel(
      id: 'buzz-sent-${DateTime.now().microsecondsSinceEpoch}',
      senderId: 'me',
      senderName: localUsername,
      recipientId: conversationId,
      text: sentText,
      isMine: true,
      status: sentSuccess ? MessageStatus.delivered : MessageStatus.failed,
    );
    final messages = _conversations.putIfAbsent(conversationId, () => []);
    messages.add(message);
    chatHistory.scheduleSave(conversationId, messages);
    targetPeer.lastMessage = sentText;
    targetPeer.lastMessageTime = message.timestamp;
    _notify();
  }

  /// Xử lý gửi lệnh khởi động ứng dụng từ xa qua WinRM khi peer đang offline
  Future<void> _handleOfflineBuzz(PeerModel targetPeer) async {
    final conversationId = targetPeer.id;
    final targetName = targetPeer.displayName;
    final prefs = AppPreferences();

    if (!prefs.winrmEnabled) {
      final msgText =
          '⚠️ ${languageProvider?.tr('winrmDisabledToast') ?? 'Tính năng WinRM chưa được bật trong Cài đặt.'}';
      final message = MessageModel(
        id: 'buzz-offline-disabled-${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'System',
        recipientId: conversationId,
        text: msgText,
        isMine: false,
        status: MessageStatus.delivered,
      );
      final messages = _conversations.putIfAbsent(conversationId, () => []);
      messages.add(message);
      chatHistory.scheduleSave(conversationId, messages);
      targetPeer.lastMessage = msgText;
      targetPeer.lastMessageTime = message.timestamp;
      showToast('winrmDisabledToast', []);
      _notify();
      return;
    }

    final targetIp = targetPeer.ip.isNotEmpty
        ? targetPeer.ip
        : (targetPeer.knownIps.isNotEmpty ? targetPeer.knownIps.first : '');

    if (targetIp.isEmpty) {
      final msgText =
          '⚠️ ${languageProvider?.tr('winrmNoIp') ?? 'Không tìm thấy địa chỉ IP của thiết bị.'}';
      final message = MessageModel(
        id: 'buzz-no-ip-${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'System',
        recipientId: conversationId,
        text: msgText,
        isMine: false,
        status: MessageStatus.delivered,
      );
      final messages = _conversations.putIfAbsent(conversationId, () => []);
      messages.add(message);
      chatHistory.scheduleSave(conversationId, messages);
      targetPeer.lastMessage = msgText;
      targetPeer.lastMessageTime = message.timestamp;
      showToast('winrmNoIp', []);
      _notify();
      return;
    }

    final creds = prefs.resolveWinrmCredentials(targetPeer.canonicalIdentity);
    if (creds.username.isEmpty) {
      final msgText =
          '⚠️ ${languageProvider?.tr('winrmNotConfigured') ?? 'Chưa cấu hình tài khoản WinRM trong Cài đặt.'}';
      final message = MessageModel(
        id: 'buzz-no-creds-${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'System',
        recipientId: conversationId,
        text: msgText,
        isMine: false,
        status: MessageStatus.delivered,
      );
      final messages = _conversations.putIfAbsent(conversationId, () => []);
      messages.add(message);
      chatHistory.scheduleSave(conversationId, messages);
      targetPeer.lastMessage = msgText;
      targetPeer.lastMessageTime = message.timestamp;
      showToast('winrmNotConfigured', []);
      _notify();
      return;
    }

    // Ghi nhớ để tự động gửi Buzz ngay khi peer online (kiểm tra chặt chẽ danh tính và IP)
    if (prefs.winrmAutoBuzzOnConnect) {
      _pendingBuzzTargets.removeWhere(
        (t) => t.canonicalIdentity == targetPeer.canonicalIdentity,
      );
      _pendingBuzzTargets.add(
        PendingBuzzTarget(
          peerId: targetPeer.id,
          canonicalIdentity: targetPeer.canonicalIdentity,
          hostname: targetPeer.hostname,
          accountName: targetPeer.accountName,
          targetIp: targetIp,
          createdAt: DateTime.now(),
        ),
      );
    }

    // Hiển thị thông báo đang khởi chạy
    final launchingText =
        '🚀 ${languageProvider?.tr('winrmLaunchingApp') ?? 'Đang gửi lệnh WinRM để mở ứng dụng trên máy đối phương...'} ($targetName - $targetIp)';
    final launchingMsg = MessageModel(
      id: 'buzz-winrm-launching-${DateTime.now().microsecondsSinceEpoch}',
      senderId: 'me',
      senderName: localUsername,
      recipientId: conversationId,
      text: launchingText,
      isMine: true,
      status: MessageStatus.sent,
    );
    final messages = _conversations.putIfAbsent(conversationId, () => []);
    messages.add(launchingMsg);
    chatHistory.scheduleSave(conversationId, messages);
    targetPeer.lastMessage = launchingText;
    targetPeer.lastMessageTime = launchingMsg.timestamp;
    _notify();

    // Thực thi lệnh WinRM bất đồng bộ
    final result = await winrmLauncher.launchRemoteApp(
      ip: targetIp,
      port: creds.port,
      username: creds.username,
      password: creds.password,
      customAppPath: creds.customAppPath,
    );

    if (result.success) {
      final successText = '✅ ${result.message}';
      final resultMsg = MessageModel(
        id: 'buzz-winrm-ok-${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'WinRM',
        recipientId: conversationId,
        text: successText,
        isMine: false,
        status: MessageStatus.delivered,
      );
      messages.add(resultMsg);
      chatHistory.scheduleSave(conversationId, messages);
      targetPeer.lastMessage = successText;
      targetPeer.lastMessageTime = resultMsg.timestamp;
      showToast('winrmLaunchSuccess', []);
    } else {
      // Xóa khỏi pending buzz nếu khởi động thất bại
      _pendingBuzzTargets.removeWhere(
        (t) => t.canonicalIdentity == targetPeer.canonicalIdentity,
      );

      final errorText = '❌ WinRM: ${result.message}';
      final resultMsg = MessageModel(
        id: 'buzz-winrm-err-${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'system',
        senderName: 'WinRM',
        recipientId: conversationId,
        text: errorText,
        isMine: false,
        status: MessageStatus.failed,
      );
      messages.add(resultMsg);
      chatHistory.scheduleSave(conversationId, messages);
      targetPeer.lastMessage = errorText;
      targetPeer.lastMessageTime = resultMsg.timestamp;
      showToast('winrmLaunchFailed', [result.message]);
    }
    _notify();
  }

  /// Quét lại toàn bộ mạng LAN
  void _refreshPeersImpl() {
    _discovery.sendBroadcastAnnounce();
    unawaited(_probeKnownAndRestoredPeers());
  }

  /// Cập nhật trạng thái hiển thị của bản thân
  Future<void> _updateProfileImpl({
    String? username,
    PeerStatus? status,
    String? statusDesc,
    Color? color,
    String? workgroup,
  }) async {
    if (_disposed) return;
    if (username != null && username.trim().isNotEmpty) {
      localUsername = username.trim();
      _notify();
      await AppPreferences().setLocalNickname(localUsername);
      if (_disposed) return;
    }
    if (status != null) localStatus = status;
    if (statusDesc != null) localStatusDescription = statusDesc;
    if (color != null) localColor = color;
    if (workgroup != null) localWorkgroup = workgroup;

    if (username == null && color == null && workgroup == null) {
      _tcpServer.sendToAll(
        ProtocolBeebeep.buildUserStatusPacket(
          status: localStatus,
          statusDescription: localStatusDescription,
        ),
      );
    } else {
      // Identity/profile changes still renegotiate their HELLO metadata.
      _tcpServer.closeConnections();
      _discovery.sendBroadcastAnnounce();
    }
    _notify();
  }

  /// Cập nhật ảnh đại diện / màu sắc người dùng và thông báo cho toàn mạng LAN
  Future<void> _updateUserAvatarImpl({
    String? type,
    String? preset,
    String? customPath,
    Color? color,
  }) async {
    final prefs = AppPreferences();
    String? colorHex;
    if (color != null) {
      colorHex =
          '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
      localColor = color;
    }

    String? thumbnailBase64;
    final effType = type ?? prefs.userAvatarType;
    final effPath = customPath ?? prefs.userAvatarCustomPath;
    if (effType == 'custom' && effPath.isNotEmpty) {
      thumbnailBase64 = await AvatarUtils.generateAvatarThumbnailBase64(
        effPath,
      );
    }

    await prefs.setUserAvatar(
      type: type,
      preset: preset,
      customPath: customPath,
      color: colorHex,
      base64: thumbnailBase64 ?? (effType != 'custom' ? '' : null),
    );

    // Xây dựng payload avatar mới
    final hex = '#${localColor.toARGB32().toRadixString(16).substring(2)}';
    var jaPayload = '';
    var photoBase64 = '';
    if (prefs.userAvatarType == 'preset') {
      jaPayload = '$hex|preset:${prefs.userAvatarPreset}';
    } else if (prefs.userAvatarType == 'custom' &&
        prefs.userAvatarBase64.isNotEmpty) {
      photoBase64 = prefs.userAvatarBase64;
    } else {
      jaPayload = '$hex|preset:initials';
    }

    // 1. Gửi gói tin cập nhật avatar tức thì đến tất cả các kết nối TCP hiện tại
    _tcpServer.sendToAll(
      ProtocolBeebeep.buildAvatarUpdatePacket(
        nickname: localUsername,
        colorHex: hex,
        photoBase64: photoBase64,
        jaPayload: jaPayload,
      ),
    );

    // 2. Phát sóng UDP announce cho toàn mạng
    _discovery.sendBroadcastAnnounce();

    _notify();
  }

  /// Thêm thủ công một địa chỉ IP (cho máy khác lớp mạng hoặc VPN)
  Future<ManualPeerResult> _addManualPeerImpl(
    String ip, [
    int port = defaultListenerPort,
  ]) => _addManualPeer(ip, port, matchPort: port != defaultListenerPort);

  Future<ManualPeerResult> _addManualEndpointImpl(String ip, int port) =>
      _addManualPeer(ip, port, matchPort: true);

  Future<ManualPeerResult> _addManualPeer(
    String ip,
    int port, {
    required bool matchPort,
  }) async {
    final cleanIp = ip.trim();
    if (!NetworkUtils.isValidIp(cleanIp) || port < 1 || port > 65535) {
      return ManualPeerResult(status: ManualAddStatus.invalidIp, ip: cleanIp);
    }

    final localIps = {
      '127.0.0.1',
      'localhost',
      ...enabledAdapters.map((a) => a.ip),
      ...activeAdapters.map((a) => a.ip),
    };
    if (localIps.contains(cleanIp) && port == localTcpPort) {
      return ManualPeerResult(status: ManualAddStatus.ownIp, ip: cleanIp);
    }

    // Kiểm tra xem IP này đã có trong danh sách peers online chưa
    final endpoint = '$cleanIp:$port';
    final lookup = matchPort ? endpoint : cleanIp;
    final existingPeer = _findPeerByIpOrId(lookup);
    if (existingPeer != null && existingPeer.status != PeerStatus.offline) {
      markNewlyAddedPeer(existingPeer.id);
      _notify();
      return ManualPeerResult(
        status: ManualAddStatus.alreadyExists,
        peer: existingPeer,
        ip: cleanIp,
      );
    }

    // Thực hiện kết nối TCP và trao đổi gói tin HELLO
    final connected = await _connectPeer(
      cleanIp,
      port,
      timeout: const Duration(milliseconds: 3200),
    );

    if (connected) {
      final targetPeer =
          _findPeerByIpOrId(lookup) ??
          _peers[endpoint] ??
          _peers.values.firstWhere(
            (p) =>
                (!matchPort || p.port == port) &&
                (p.ip == cleanIp || p.knownIps.contains(cleanIp)),
            orElse: () => PeerModel(
              id: endpoint,
              name: cleanIp,
              ip: cleanIp,
              port: port,
              status: PeerStatus.online,
            ),
          );
      markNewlyAddedPeer(targetPeer.id);
      _notify();
      return ManualPeerResult(
        status: ManualAddStatus.success,
        peer: targetPeer,
        ip: cleanIp,
      );
    }

    return ManualPeerResult(status: ManualAddStatus.unreachable, ip: cleanIp);
  }

  /// Lưu một liên hệ thủ công ngoại tuyến vào danh bạ (khi chưa kết nối được)
  PeerModel _addOfflineManualPeerImpl(
    String ip, [
    int port = defaultListenerPort,
  ]) {
    final cleanIp = ip.trim();
    final endpoint = '$cleanIp:$port';
    final peer =
        _peers[endpoint] ??
        PeerModel(
          id: endpoint,
          name: cleanIp,
          ip: cleanIp,
          port: port,
          status: PeerStatus.offline,
        );
    _peers[endpoint] = peer;
    markNewlyAddedPeer(peer.id);
    _notify();
    return peer;
  }

  /// Ghim / bỏ ghim cuộc trò chuyện
  void _togglePinPeerImpl(String peerId) {
    if (peerId == '__ALL_USERS__') {
      _allUsersPeer.isPinned = !_allUsersPeer.isPinned;
      AppPreferences().setPeerPinned('__ALL_USERS__', _allUsersPeer.isPinned);
      _notify();
      return;
    }
    if (peerId == '__AI_ASSISTANT__') {
      _aiPeer.isPinned = !_aiPeer.isPinned;
      AppPreferences().setPeerPinned('__AI_ASSISTANT__', _aiPeer.isPinned);
      _notify();
      return;
    }
    final peer = _peers[peerId];
    if (peer != null) {
      peer.isPinned = !peer.isPinned;
      AppPreferences().setPeerPinned(peer.canonicalIdentity, peer.isPinned);
      _notify();
    }
  }

  /// Ghim hoặc bỏ ghim tin nhắn trong cuộc hội thoại
  void _togglePinMessageImpl(String conversationId, String messageId) {
    final list = _conversations[conversationId];
    if (list == null || list.isEmpty) return;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final msg = list[index];
    msg.isPinned = !msg.isPinned;
    chatHistory.scheduleSave(conversationId, list);
    _notify();
  }

  /// Lấy danh sách tin nhắn đã ghim của cuộc hội thoại
  List<MessageModel> _getPinnedMessagesImpl(String conversationId) {
    final list = _conversations[conversationId];
    if (list == null) return const [];
    return list.where((m) => m.isPinned && !m.isRevoked).toList();
  }

  /// Bật / tắt thông báo cuộc trò chuyện
  void _toggleMutePeerImpl(String peerId) {
    if (peerId == '__ALL_USERS__') {
      _allUsersPeer.isMuted = !_allUsersPeer.isMuted;
      _notify();
      return;
    }
    final peer = _peers[peerId];
    if (peer != null) {
      peer.isMuted = !peer.isMuted;
      _notify();
    }
  }

  /// Đặt biệt danh cho liên hệ (hoặc đổi tên nhóm nếu là group ID)
  void _setPeerNicknameImpl(String peerId, String? nickname) {
    if (_groups.containsKey(peerId)) {
      if (nickname != null && nickname.trim().isNotEmpty) {
        renameGroup(peerId, nickname.trim());
      }
      return;
    }
    final peer = _peers[peerId];
    if (peer != null) {
      peer.customNickname = (nickname != null && nickname.trim().isNotEmpty)
          ? nickname.trim()
          : null;
      final identityKey =
          PeerSessionRegistry.identity(peer) ?? peer.canonicalIdentity;
      if (identityKey.isNotEmpty) {
        knownDevices.recordDevice(
          identityKey: identityKey,
          username: peer.name,
          ip: peer.ip,
          preservedIdentityKeys: _coexistingIdentities(peer.ip),
          accountName: peer.accountName,
          hostname: peer.hostname,
          customNickname: peer.customNickname ?? '',
          userHash: _peerHashes[peer.id],
          port: peer.port,
          avatarColorValue: peer.avatarColor.toARGB32(),
          avatarPreset: peer.avatarPreset,
          customAvatarBase64: peer.customAvatarBase64,
        );
      }
      _notify();
    }
  }

  /// Xóa toàn bộ lịch sử tin nhắn của cuộc trò chuyện
  void _clearConversationImpl(String peerId) {
    final list = _conversations[peerId];
    list?.clear();
    for (final entry in _conversations.entries) {
      if (list != null && identical(entry.value, list)) {
        _pendingOfflineMessageIds.remove(entry.key);
        chatHistory.scheduleSave(entry.key, list);
      }
    }
    final peer = _peers[peerId];
    if (peer != null) {
      peer.lastMessage = null;
      peer.lastMessageTime = null;
    } else if (peerId == '__ALL_USERS__') {
      _allUsersPeer.lastMessage = null;
      _allUsersPeer.lastMessageTime = null;
    } else if (peerId == '__AI_ASSISTANT__') {
      _aiPeer.lastMessage = null;
      _aiPeer.lastMessageTime = null;
    }
    chatHistory.deleteConversation(peerId);
    _notify();
  }

  /// Xóa toàn bộ lịch sử tin nhắn của tất cả cuộc trò chuyện
  Future<void> _clearAllChatHistoryImpl() async {
    _conversations.clear();
    _aiPeer.lastMessage = null;
    _aiPeer.lastMessageTime = null;
    _allUsersPeer.lastMessage = null;
    _allUsersPeer.lastMessageTime = null;
    for (final p in _peers.values) {
      p.lastMessage = null;
      p.lastMessageTime = null;
    }
    await chatHistory.clearAllHistory();
    _notify();
  }

  /// Lấy danh sách tin nhắn chứa hình ảnh / video của cuộc trò chuyện
  List<MessageModel> _getMediaMessagesImpl(String peerId) {
    final list = _conversations[peerId] ?? const [];
    return list
        .where(
          (m) =>
              m.hasAttachment &&
              m.fileAttachment != null &&
              MessengerCoordinator.isImageFile(m.fileAttachment!.fileName),
        )
        .toList();
  }

  /// Lấy danh sách tin nhắn chứa tài liệu / tệp tin khác của cuộc trò chuyện
  List<MessageModel> _getFileMessagesImpl(String peerId) {
    final list = _conversations[peerId] ?? const [];
    return list
        .where(
          (m) =>
              m.hasAttachment &&
              m.fileAttachment != null &&
              !MessengerCoordinator.isImageFile(m.fileAttachment!.fileName),
        )
        .toList();
  }

  /// Nhóm chỉ nhận file khi người gửi đúng là thành viên. Mã nhóm giả rơi về chat riêng.
  GroupModel? _groupForIncomingFile(FileTransferTask task) {
    final groupId = task.groupId;
    if (groupId == null) return null;
    final group = _groups[groupId];
    if (group == null) return null;
    final sender = _incomingPeer(task.peerId) ?? _incomingPeer(task.peerIp);
    if (sender == null || !group.memberIds.contains(sender.id)) return null;
    final expectedHash = group.memberRecords[sender.id]?.elementAtOrNull(2);
    if (expectedHash != null &&
        expectedHash != sender.id &&
        expectedHash != _incomingHash(task.peerId, sender)) {
      return null;
    }
    return group;
  }

  void _receiveFileForTestingImpl(FileTransferTask task) {
    _handleIncomingFileCompleted(task);
  }

  /// Xử lý khi nhận hoàn tất một file truyền về từ peer
  void _handleIncomingFileCompleted(FileTransferTask task) {
    final completed = task.status == TransferStatus.completed;
    final failed =
        task.status == TransferStatus.failed ||
        task.status == TransferStatus.cancelled;
    final group = _groupForIncomingFile(task);

    final senderPeer =
        _incomingPeer(task.peerId) ??
        _incomingPeer(task.peerIp) ??
        _peers.values.firstWhere(
          (p) => p.ip == task.peerIp,
          orElse: () =>
              PeerModel(id: task.peerIp, name: task.peerName, ip: task.peerIp),
        );
    if (group == null) {
      _peers[senderPeer.id] = senderPeer;
    }

    final conversationId = group?.id ?? senderPeer.id;
    final list = _conversations.putIfAbsent(conversationId, () => []);
    final existingIndex = list.indexWhere((m) => m.id == 'file_${task.id}');
    final preview = MessengerCoordinator.isImageFile(task.fileName)
        ? '📷 [Ảnh] ${task.fileName}'
        : '📁 [Tệp] ${task.fileName}';

    final msg = MessageModel(
      id: 'file_${task.id}',
      attachmentBatchId: task.attachmentBatchId,
      sourceSession: _incomingHash(task.peerId, senderPeer),
      senderId: senderPeer.id,
      senderName: senderPeer.displayName,
      recipientId: group?.id ?? 'me',
      text: failed
          ? 'Không nhận được ${task.fileName}: ${task.errorMessage ?? 'Đã hủy'}'
          : completed
          ? 'Đã nhận: ${task.fileName}'
          : 'Đang nhận: ${task.fileName}',
      isMine: false,
      status: failed
          ? MessageStatus.failed
          : completed
          ? MessageStatus.delivered
          : MessageStatus.sending,
      fileAttachment: FileAttachmentInfo(
        fileName: task.fileName,
        fileSize: task.fileSize,
        localPath: completed ? task.filePath : null,
        isTransferComplete: completed,
      ),
    );

    if (existingIndex >= 0) {
      if (list[existingIndex].status == MessageStatus.read) {
        msg.status = MessageStatus.read;
      }
      list[existingIndex] = msg;
      chatHistory.scheduleSave(conversationId, list);
      if (completed) {
        _showDesktopNotification(
          title: '📁 ${task.fileName}',
          body: 'Đã nhận thành công từ ${senderPeer.displayName}',
          peer: group == null ? senderPeer : PeerModel.fromGroup(group),
        );
      }
      return;
    }
    list.add(msg);
    chatHistory.scheduleSave(conversationId, list);
    if (group != null) {
      group.lastMessage = '${senderPeer.displayName}: $preview';
      group.lastMessageTime = DateTime.now();
      group.unreadCount++;
      _saveGroups();
    } else {
      senderPeer.lastMessage = preview;
      senderPeer.lastMessageTime = DateTime.now();
      senderPeer.unreadCount++;
    }

    if (completed) {
      _showDesktopNotification(
        title: '📁 ${task.fileName}',
        body: 'Đã nhận thành công từ ${senderPeer.displayName}',
        peer: group == null ? senderPeer : PeerModel.fromGroup(group),
      );
    }
  }
}
