part of '../messenger_coordinator.dart';

extension MessengerCoordinatorPresenceAndNic on MessengerCoordinator {
  Future<void> _saveNetworkAdaptersImpl(Set<String> disabled) async {
    await networkPreferences.save(disabled);
    _tcpServer.invalidatePendingConnections();
    await _discovery.updateDisabledAdapters(Set.of(disabled));
    for (final entry in _peerSessions.sessions.entries.toList()) {
      if (!_isPeerIpAllowed(entry.value.remote.ip)) {
        entry.value.available = false;
        _tcpServer.closeConnection(entry.key);
      }
    }
    for (final peer in _peers.values.toSet()) {
      if (peer.isGroup || peer.isAllUsers || peer.isAiAssistant) continue;
      if (_peerSessions.forConversation(peer.id).isNotEmpty) {
        _refreshLogicalPeer(peer);
      } else if (!_isPeerIpAllowed(peer.ip)) {
        peer.status = PeerStatus.offline;
      }
      if (peer.status == PeerStatus.offline) {
        peer.statusDescription = 'Ngoài dải card mạng đã chọn';
        _failUnackedMessagesForPeer(peer);
      }
    }
    _notify();
  }

  /// Xác định định danh phần cứng/thiết bị chuẩn tắc để gộp kết nối và cuộc trò chuyện
  String _canonicalDeviceKey(PeerModel p) {
    if (p.isAiAssistant || p.isAllUsers || p.isGroup) return p.id;
    final identity =
        PeerSessionRegistry.identity(p) ?? _peerSessions.identities[p.id];
    if (identity != null) return identity;
    if (p.ip.isNotEmpty) {
      // Historical IPs are only a migration hint when exactly one identity owns it.
      final matches = knownDevices.devices.values
          .where(
            (d) =>
                d.id.contains('@') &&
                (d.knownIps.contains(p.ip) || d.lastIp == p.ip),
          )
          .map((d) => d.id.toLowerCase())
          .toSet();
      if (matches.length == 1) return matches.single;
    }
    return 'endpoint:${p.id}';
  }

  /// Kiểm tra 2 PeerModel có đại diện cho cùng một máy trạm vật lý trong mạng LAN không
  bool _isSamePhysicalPeer(PeerModel a, PeerModel b, {String? senderIp}) {
    if (identical(a, b)) return true;
    if (a.isGroup ||
        b.isGroup ||
        a.isAllUsers ||
        b.isAllUsers ||
        a.isAiAssistant ||
        b.isAiAssistant) {
      return false;
    }

    final keyA = _canonicalDeviceKey(a);
    final keyB = _canonicalDeviceKey(b);
    if (!keyA.startsWith('endpoint:') && !keyB.startsWith('endpoint:')) {
      return keyA == keyB;
    }

    final idA =
        PeerSessionRegistry.identity(a) ?? _peerSessions.identities[a.id];
    final idB =
        PeerSessionRegistry.identity(b) ?? _peerSessions.identities[b.id];
    if (idA != null && idB != null) {
      return idA == idB;
    }

    // Nếu a.id == b.id và không có xung đột danh tính đã lưu
    if (a.id == b.id) {
      final savedId = _peerSessions.identities[a.id];
      if (savedId != null && !keyB.startsWith('endpoint:') && savedId != keyB) {
        return false;
      }
      if (idA != null && idB == null && a.ip.isEmpty) {
        return false;
      }
      return true;
    }

    // Trích xuất tập hợp các IP đang thuộc sở hữu của peer.
    // Không lấy lại IP lịch sử trong p.id nếu peer đã có định danh cố định hoặc đã bị thu hồi IP.
    Set<String> extractIps(PeerModel p, String? resolvedIdentity) {
      final set = <String>{if (p.ip.isNotEmpty) p.ip, ...p.knownIps};
      if (set.isEmpty && resolvedIdentity == null) {
        final rawId = p.id.startsWith('endpoint:') ? p.id.substring(9) : p.id;
        final hostPart = rawId.contains(':') ? rawId.split(':').first : rawId;
        if (InternetAddress.tryParse(hostPart) != null) {
          set.add(hostPart);
        }
      }
      set.removeWhere((ip) => ip.isEmpty || ip == '0.0.0.0');
      return set;
    }

    final ipsA = extractIps(a, idA);
    final ipsB = extractIps(b, idB);
    if (senderIp != null && senderIp.isNotEmpty) {
      ipsB.add(senderIp);
    }

    final commonIps = ipsA.intersection(ipsB);
    if (commonIps.isNotEmpty) {
      // Đối với loopback localhost, nếu cổng khác nhau rõ ràng thì là 2 tiến trình mock khác nhau
      final onlyLoopback = commonIps.every(
        (ip) => ip == '127.0.0.1' || ip == '::1' || ip == 'localhost',
      );
      if (onlyLoopback && a.port > 0 && b.port > 0 && a.port != b.port) {
        return false;
      }

      if (idA != null && idB != null && idA != idB) {
        return false; // Hai máy khác nhau có identity đã xác thực khác nhau
      }
      return true;
    }

    return false;
  }

  /// Kiểm tra một peer có đang được chọn làm cuộc hội thoại hiện tại không
  bool _isPeerSelectedImpl(PeerModel peer) {
    if (_selectedPeer == null) return false;
    if (identical(_selectedPeer, peer)) return true;
    if (_selectedPeer!.id == peer.id) return true;
    if (_selectedPeer!.isAllUsers && peer.isAllUsers) return true;
    if (_selectedPeer!.isAiAssistant && peer.isAiAssistant) return true;
    if (_selectedPeer!.isGroup || peer.isGroup) return false;
    return _isSamePhysicalPeer(_selectedPeer!, peer);
  }

  /// Hợp nhất tin nhắn giữa 2 ID cuộc hội thoại của cùng một thiết bị/người dùng
  void _mergeConversations(String targetId, String sourceId) {
    if (targetId == sourceId) return;
    for (final entry in _peerSessions.sessions.entries.toList()) {
      if (entry.value.conversationId == sourceId) {
        _peerSessions.sessions[entry.key] = PeerTransportSession(
          targetId,
          entry.value.remote,
          entry.value.hash,
        )..available = entry.value.available;
      }
    }
    final targetList = _conversations[targetId];
    final sourceList = _conversations[sourceId];
    if (targetList == null && sourceList == null) return;
    final aliases =
        _conversations.entries
            .where(
              (e) =>
                  (targetList != null && identical(e.value, targetList)) ||
                  (sourceList != null && identical(e.value, sourceList)),
            )
            .map((e) => e.key)
            .toSet()
          ..addAll([sourceId, targetId]);
    final combinedMap = <String, MessageModel>{};
    for (final m in [...?targetList, ...?sourceList]) {
      if (m.isMine && aliases.contains(m.recipientId)) m.recipientId = targetId;
      if (!m.isMine && aliases.contains(m.senderId)) m.senderId = targetId;
      if (m.pendingRecipients != null &&
          m.pendingRecipients!.any(aliases.contains)) {
        m.pendingRecipients!.removeWhere(aliases.contains);
        m.pendingRecipients!.add(targetId);
      }
      final key = '${m.isMine}:${m.sourceSession ?? ''}:${m.id}';
      combinedMap.putIfAbsent(key, () => m);
    }

    final merged = combinedMap.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    chatHistory.linkConversations(aliases);
    for (final alias in aliases) {
      _conversations[alias] = merged;
      final pending = _pendingOfflineMessageIds.remove(alias);
      if (pending != null) {
        _pendingOfflineMessageIds
            .putIfAbsent(targetId, () => {})
            .addAll(pending);
      }
      // Keep legacy files recoverable and synchronized, without deleting history.
      chatHistory.scheduleSave(alias, merged);
    }
  }

  /// Hợp nhất các peer và cuộc hội thoại đã tải từ đĩa lúc khởi động ứng dụng
  void _consolidateLoadedPeersAndConversations() {
    final nonGroupPeers = _peers.values
        .where((p) => !p.isGroup && !p.isAllUsers && !p.isAiAssistant)
        .toSet()
        .toList();

    for (int i = 0; i < nonGroupPeers.length; i++) {
      final a = nonGroupPeers[i];
      for (int j = i + 1; j < nonGroupPeers.length; j++) {
        final b = nonGroupPeers[j];
        if (identical(a, b)) continue;
        if (_isSamePhysicalPeer(a, b)) {
          a.knownIps.addAll(b.knownIps);
          if (b.ip.isNotEmpty) a.knownIps.add(b.ip);
          if (a.customNickname == null && b.customNickname != null) {
            a.customNickname = b.customNickname;
          }
          if ((a.accountName == null || a.accountName!.isEmpty) &&
              b.accountName != null &&
              b.accountName!.isNotEmpty) {
            a.accountName = b.accountName;
          }
          if ((a.hostname == null || a.hostname!.isEmpty) &&
              b.hostname != null &&
              b.hostname!.isNotEmpty) {
            a.hostname = b.hostname;
          }
          a.isPinned = a.isPinned || b.isPinned;

          if (a.status == PeerStatus.offline &&
              b.status != PeerStatus.offline) {
            a.status = b.status;
            a.statusDescription = b.statusDescription;
            if (b.ip.isNotEmpty) a.ip = b.ip;
            if (b.port > 0) a.port = b.port;
            if (b.lastSeen.isAfter(a.lastSeen)) a.lastSeen = b.lastSeen;
            a.isBeebeep = b.isBeebeep;
          }

          final idB =
              _peerSessions.identities[b.id] ?? PeerSessionRegistry.identity(b);
          if (idB != null) {
            _peerSessions.remember(a.id, idB);
          }

          _mergeConversations(a.id, b.id);

          final pending = _pendingOfflineMessageIds.remove(b.id);
          if (pending != null) {
            _pendingOfflineMessageIds
                .putIfAbsent(a.id, () => {})
                .addAll(pending);
          }

          for (final key in _peers.keys.toList()) {
            if (identical(_peers[key], b)) {
              _peers[key] = a;
            }
          }
          _peers[b.id] = a;
          if (identical(_selectedPeer, b)) {
            _selectedPeer = a;
          }
          if (_peerSessions.forConversation(a.id).isNotEmpty) {
            _refreshLogicalPeer(a);
          }
        }
      }
    }
  }

  /// Same presence rule as the Online tab, including away/busy peers.
  /// Uses the deduplicated, search-filtered contact list (including enabled AI).
  List<PeerModel> get _onlinePeersImpl =>
      peers.where((peer) => peer.status != PeerStatus.offline).toList();

  List<PeerModel> get _peersImpl => _contactPeers();

  List<PeerModel> _contactPeers({bool applySearch = true}) {
    // Deduplicate peers by canonical device identity
    final Map<String, PeerModel> uniqueMap = {};
    for (final p in _peers.values) {
      if (p.isGroup || p.isAllUsers) continue;
      final key = _canonicalDeviceKey(p);

      final existing = uniqueMap[key];
      if (existing == null) {
        uniqueMap[key] = p;
      } else {
        PeerModel winner;
        // Ưu tiên trạng thái online và đồng bộ sang _selectedPeer nếu có
        if (existing.status == PeerStatus.offline &&
            p.status != PeerStatus.offline) {
          if (identical(existing, _selectedPeer)) {
            existing.status = p.status;
            existing.statusDescription = p.statusDescription;
            existing.ip = p.ip;
            existing.port = p.port;
            existing.lastSeen = p.lastSeen;
            winner = existing;
          } else {
            winner = p;
          }
        } else if (p.status == PeerStatus.offline &&
            existing.status != PeerStatus.offline) {
          if (identical(p, _selectedPeer)) {
            p.status = existing.status;
            p.statusDescription = existing.statusDescription;
            p.ip = existing.ip;
            p.port = existing.port;
            p.lastSeen = existing.lastSeen;
            winner = p;
          } else {
            winner = existing;
          }
        } else if (identical(existing, _selectedPeer)) {
          winner = existing;
        } else if (identical(p, _selectedPeer)) {
          winner = p;
        } else if ((p.status == PeerStatus.offline) ==
                (existing.status == PeerStatus.offline) &&
            p.lastSeen.isAfter(existing.lastSeen)) {
          winner = p;
        } else {
          winner = existing;
        }

        uniqueMap[key] = winner;
      }
    }

    final list = uniqueMap.values.toList();
    if (AppPreferences().aiEnabled) {
      list.add(_aiPeer);
    }
    list.sort((a, b) {
      // 1. Pinned items first
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;

      // 2. Among pinned items: if one has more recent message, that one comes first
      if (a.isPinned && b.isPinned) {
        if (a.lastMessageTime != null && b.lastMessageTime != null) {
          final cmp = b.lastMessageTime!.compareTo(a.lastMessageTime!);
          if (cmp != 0) return cmp;
        } else if (a.lastMessageTime != null) {
          return -1;
        } else if (b.lastMessageTime != null) {
          return 1;
        }
        // AI assistant default at top of pinned if neither has recent messages
        if (a.isAiAssistant != b.isAiAssistant) return a.isAiAssistant ? -1 : 1;
      }

      // 2.5. Bạn mới thêm ưu tiên lên đầu (ngay sau các mục đã ghim)
      final aNew = isNewlyAddedPeer(a.id);
      final bNew = isNewlyAddedPeer(b.id);
      if (aNew != bNew) return aNew ? -1 : 1;
      if (aNew && bNew) {
        final aTime =
            _newlyAddedPeers[a.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            _newlyAddedPeers[b.id] ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = bTime.compareTo(aTime);
        if (cmp != 0) return cmp;
      }

      // 3. Unread messages first
      final aUnread = a.unreadCount > 0;
      final bUnread = b.unreadCount > 0;
      if (aUnread != bUnread) return aUnread ? -1 : 1;

      // 4. Most recent message time first
      if (a.lastMessageTime != null && b.lastMessageTime != null) {
        final cmp = b.lastMessageTime!.compareTo(a.lastMessageTime!);
        if (cmp != 0) return cmp;
      } else if (a.lastMessageTime != null) {
        return -1;
      } else if (b.lastMessageTime != null) {
        return 1;
      }

      // 5. If unpinned and one is AI assistant (and neither has messages)
      if (a.isAiAssistant != b.isAiAssistant) return a.isAiAssistant ? -1 : 1;

      // 6. Online status first
      if (a.status != b.status) {
        return a.status.index.compareTo(b.status.index);
      }

      // 7. Display name alphabetical
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });

    if (!applySearch || _searchQuery.trim().isEmpty) return list;
    final query = _searchQuery.toLowerCase();
    return list
        .where(
          (p) =>
              p.displayName.toLowerCase().contains(query) ||
              p.name.toLowerCase().contains(query) ||
              p.ip.toLowerCase().contains(query) ||
              p.knownIps.any((ip) => ip.toLowerCase().contains(query)),
        )
        .toList();
  }

  Map<String, PeerModel> get _peersMapImpl => _peers;

  Map<String, List<MessageModel>> get _conversationsMapImpl => _conversations;

  PeerModel? get _selectedPeerImpl => _selectedPeer;
  String get _searchQueryImpl => _searchQuery;

  List<MessageModel> get _currentMessagesImpl {
    if (_selectedPeer == null) return const [];
    final direct = _conversations[_selectedPeer!.id];
    if (direct != null && direct.isNotEmpty) return direct;

    if (!_selectedPeer!.isGroup &&
        !_selectedPeer!.isAllUsers &&
        !_selectedPeer!.isAiAssistant) {
      for (final alias in chatHistory.aliasesFor(_selectedPeer!.id)) {
        final list = _conversations[alias];
        if (list != null && list.isNotEmpty) {
          _conversations[_selectedPeer!.id] = list;
          return list;
        }
      }
      for (final entry in _peers.entries) {
        if (identical(entry.value, _selectedPeer) &&
            entry.key != _selectedPeer!.id) {
          final list = _conversations[entry.key];
          if (list != null && list.isNotEmpty) {
            _conversations[_selectedPeer!.id] = list;
            return list;
          }
        }
      }
    }
    return direct ?? const [];
  }

  List<FileTransferTask> get _fileTasksImpl => _fileEngine.tasks;

  // Trạng thái quét mạng LAN thời gian thực
  DiscoveryScanState get _scanStateImpl => _discovery.scanState;
  bool get _isScanningImpl => _discovery.scanState.isSweeping;
  double get _scanProgressImpl => _discovery.scanState.progress;
  String get _scanStatusImpl => _discovery.scanState.statusText;
  List<NetworkInterfaceDetails> get _activeAdaptersImpl =>
      _discovery.availableAdapters;
  List<NetworkInterfaceDetails> get _enabledAdaptersImpl =>
      _discovery.enabledAdapters;

  /// Gợi ý các tiền tố 2 số đầu tiên (ví dụ 172.21. hoặc 192.168.) dựa trên các card mạng đang dùng
  List<String> get _suggestedIpPrefixesImpl {
    final prefixes = <String>{};
    final adapters = enabledAdapters.isNotEmpty
        ? enabledAdapters
        : activeAdapters;

    // Sắp xếp ưu tiên: LAN vật lý trước, card khác tiếp theo, card ảo sau cùng
    final sortedAdapters = List.of(adapters)
      ..sort((a, b) {
        if (!a.isVirtual && a.isPrivateLan) return -1;
        if (!b.isVirtual && b.isPrivateLan) return 1;
        if (!a.isVirtual && b.isVirtual) return -1;
        if (a.isVirtual && !b.isVirtual) return 1;
        return 0;
      });

    for (final a in sortedAdapters) {
      final ip = a.ip.trim();
      if (ip.isEmpty || ip.startsWith('127.')) continue;
      final parts = ip.split('.');
      if (parts.length >= 2) {
        prefixes.add('${parts[0]}.${parts[1]}.');
      }
    }

    if (prefixes.isEmpty) {
      prefixes.add('192.168.');
    }
    return prefixes.toList();
  }

  bool _isNewlyAddedPeerImpl(String peerId) =>
      _newlyAddedPeers.containsKey(peerId);

  void _markNewlyAddedPeerImpl(String peerId) {
    _newlyAddedPeers[peerId] = DateTime.now();
    _notify();
  }

  void _dismissNewlyAddedPeerImpl(String peerId) {
    if (_newlyAddedPeers.remove(peerId) != null) {
      _notify();
    }
  }

  String _getLocalizedScanStatusImpl(LanguageProvider lang) {
    final state = _discovery.scanState;
    if (state.isSweeping) {
      final percent = (state.progress * 100).toInt();
      final subnets = state.activeSubnets.isNotEmpty
          ? ' • ${state.activeSubnets.join(', ')}'
          : '';

      switch (state.activePhase) {
        case 'subnet_sweep':
          int done = state.sweepDone;
          int total = state.sweepTotal;
          int sent = state.sweepSent;

          // Double-guard fallback: if metrics were 0, try parsing statusText
          if (total <= 0 && state.statusText.isNotEmpty) {
            final match = RegExp(
              r'(\d+)\s*/\s*(\d+).*?(\d+)',
            ).firstMatch(state.statusText);
            if (match != null) {
              done = int.tryParse(match.group(1) ?? '') ?? done;
              total = int.tryParse(match.group(2) ?? '') ?? total;
              sent = int.tryParse(match.group(3) ?? '') ?? sent;
            }
          }

          if (total > 0) {
            return lang.tr('scanSubnetProgress', [done, total, sent]);
          }
          return '${lang.tr('scanning')} ($percent%)$subnets';

        case 'broadcasting':
          final count = state.activeAdaptersCount > 0
              ? state.activeAdaptersCount
              : (state.activeSubnets.isNotEmpty
                    ? state.activeSubnets.length
                    : 1);
          return lang.tr('scanBroadcastingMultiNic', [count]);

        case 'arp_sweep':
          int arpCount = state.arpCount;
          if (arpCount <= 0 && state.statusText.isNotEmpty) {
            final match = RegExp(r'\((\d+)\s*').firstMatch(state.statusText);
            if (match != null) {
              arpCount = int.tryParse(match.group(1) ?? '') ?? arpCount;
            }
          }
          if (arpCount > 0) {
            return lang.tr('scanArpChecking', [arpCount]);
          }
          return '${lang.tr('scanning')} ($percent%)$subnets';

        case 'initializing':
          return lang.tr('scanPreparing');

        case 'adapters_updated':
          return lang.tr('scanAdaptersUpdated');

        default:
          return '${lang.tr('scanning')} ($percent%)$subnets';
      }
    }

    // Khi không quét (isSweeping == false)
    switch (state.activePhase) {
      case 'no_adapters':
        return lang.tr('scanNoAdaptersSelected');

      case 'error':
        return lang.tr('scanIncomplete', [state.errorMessage ?? '']);

      case 'stopped':
        return lang.tr('scanStopped');

      case 'sweep_finished':
        if (state.sweepDone > 0) {
          return lang.tr('scanCompletedDetail', [
            state.sweepDone,
            state.sweepSent,
          ]);
        }
        break;
    }

    final subnetSummary = state.activeSubnets.isNotEmpty
        ? state.activeSubnets.join(', ')
        : 'LAN';
    return '${lang.tr('realtimeListening')} • $subnetSummary';
  }

  void _resetFilterAndSelectLatestImpl() {
    _searchQuery = '';

    PeerModel? latestCandidate;
    DateTime? latestTime;

    if (_allUsersPeer.lastMessageTime != null) {
      latestTime = _allUsersPeer.lastMessageTime;
      latestCandidate = _allUsersPeer;
    }

    final sorted = peers;
    if (sorted.isNotEmpty) {
      final firstPeer = sorted.first;
      if (firstPeer.unreadCount > 0 ||
          latestTime == null ||
          (firstPeer.lastMessageTime != null &&
              firstPeer.lastMessageTime!.isAfter(latestTime))) {
        latestCandidate = firstPeer;
      }
    }

    _selectedPeer = latestCandidate ?? _allUsersPeer;
    _notify();
  }

  int get _totalUnreadCountImpl {
    var count = _allUsersPeer.unreadCount;
    for (final p in _contactPeers(applySearch: false)) {
      count += p.unreadCount;
    }
    for (final g in _groups.values) {
      count += g.unreadCount;
    }
    return count;
  }

  void _markAllAsReadImpl() {
    for (final id in _conversations.keys.toList()) {
      markConversationAsRead(id);
    }
    _allUsersPeer.unreadCount = 0;
    _aiPeer.unreadCount = 0;
    for (final p in _peers.values) {
      p.unreadCount = 0;
    }
    for (final g in _groups.values) {
      g.unreadCount = 0;
    }
    _saveGroups();
    _notify();
  }

  int get _activeTransfersCountImpl {
    return _fileEngine.tasks
        .where((t) => t.status == TransferStatus.transferring)
        .length;
  }

  /// Chuyển đổi giữa chế độ chuẩn (Standard Mode) và chế độ thu nhỏ (Compact Mode)
  Future<void> _toggleCompactModeImpl() async {
    final prefs = AppPreferences();
    final targetMode = !_isCompactMode;
    _isCompactMode = targetMode;
    _notify();

    try {
      if (targetMode) {
        // Standard -> Compact
        final currentSize = await windowManager.getSize();
        final currentPos = await windowManager.getPosition();
        await prefs.saveNormalGeometry(
          width: currentSize.width,
          height: currentSize.height,
          x: currentPos.dx,
          y: currentPos.dy,
        );

        await windowManager.setMinimumSize(
          const Size(minCompactWidth, minCompactHeight),
        );

        if (await windowManager.isMaximized()) {
          await windowManager.unmaximize();
        }
        final targetW = restoredCompactWidth(prefs.compactWidth);
        final targetH = restoredCompactHeight(
          prefs.compactWidth,
          prefs.compactHeight,
        );
        await windowManager.setSize(Size(targetW, targetH));

        if (prefs.compactPosX != null && prefs.compactPosY != null) {
          await windowManager.setPosition(
            Offset(prefs.compactPosX!, prefs.compactPosY!),
          );
        }
        if (_isAlwaysOnTop) {
          await windowManager.setAlwaysOnTop(true);
        }
      } else {
        // Compact -> Standard
        final currentSize = await windowManager.getSize();
        final currentPos = await windowManager.getPosition();
        await prefs.saveCompactGeometry(
          width: currentSize.width,
          height: currentSize.height,
          x: currentPos.dx,
          y: currentPos.dy,
        );

        await windowManager.setMinimumSize(
          const Size(minWindowWidth, minWindowHeight),
        );

        final targetW = prefs.normalWidth ?? defaultWindowWidth;
        final targetH = prefs.normalHeight ?? defaultWindowHeight;
        await windowManager.setSize(Size(targetW, targetH));

        if (prefs.normalPosX != null && prefs.normalPosY != null) {
          await windowManager.setPosition(
            Offset(prefs.normalPosX!, prefs.normalPosY!),
          );
        }
      }
    } catch (e) {
      debugPrint('[CompactMode] Window manager resize error: $e');
    }

    await prefs.setCompactMode(targetMode);
  }

  /// Cài đặt ghim cửa sổ trên cùng (Always on Top)
  Future<void> _setAlwaysOnTopImpl(bool value) async {
    _isAlwaysOnTop = value;
    _notify();
    try {
      await windowManager.setAlwaysOnTop(value);
    } catch (e) {
      debugPrint('[AlwaysOnTop] Window manager error: $e');
    }
    await AppPreferences().setAlwaysOnTop(value);
  }

  /// Bật/tắt ghim trên cùng
  Future<void> _toggleAlwaysOnTopImpl() async {
    await setAlwaysOnTop(!_isAlwaysOnTop);
  }

  void _setCompactModeForTestingImpl(bool value) {
    _isCompactMode = value;
    _notify();
  }

  void _setAlwaysOnTopForTestingImpl(bool value) {
    _isAlwaysOnTop = value;
    _notify();
  }

  /// Kích hoạt quét lại mạng LAN chủ động tức thì
  Future<void> _rescanNetworkImpl({Set<String>? adapterIps}) async {
    if (_isActivelyRescanning) return;
    _isActivelyRescanning = true;
    showToast('toastScanning');
    try {
      unawaited(_probeKnownAndRestoredPeers());
      await _discovery.triggerActiveScan(adapterIps: adapterIps);
      await Future.delayed(const Duration(milliseconds: 1500));
    } finally {
      _isActivelyRescanning = false;
    }
    if (_disposed) return;
    final activeCount = peers
        .where((p) => p.status != PeerStatus.offline)
        .length;
    _discovery.updateDiscoveredPeersCount(activeCount);
    showToast('toastScanDone', ['$activeCount']);
  }

  /// Xử lý khi phát hiện một peer mới qua UDP Broadcast / Multicast
  void _handlePeerDiscovered(String ip, int port) {
    // A broadcast is only a candidate. Publish the user after authenticated HELLO.
    unawaited(_connectPeer(ip, port));
  }

  /// Ảnh tùy chỉnh cũ chỉ lưu đường dẫn. Sinh Base64 một lần để HELLO gửi được ảnh.

  Future<void> _migratePersonalAvatarIfNeededImpl() async {
    final prefs = AppPreferences();
    if (prefs.userAvatarType != 'custom') return;
    if (prefs.userAvatarBase64.isNotEmpty) return;
    final path = prefs.userAvatarCustomPath.trim();
    if (path.isEmpty) return;
    try {
      final thumbnail = await AvatarUtils.generateAvatarThumbnailBase64(path);
      if (_disposed || thumbnail == null || thumbnail.isEmpty) return;
      await prefs.setUserAvatar(base64: thumbnail);
    } catch (e) {
      debugPrint('[Coordinator] Avatar migration error: $e');
    }
  }

  List<int> _buildHello(String publicKey) {
    final hexColor = '#${localColor.toARGB32().toRadixString(16).substring(2)}';
    final prefs = AppPreferences();
    final avatarType = prefs.userAvatarType;
    String avatarPayload = hexColor;
    if (avatarType == 'preset') {
      avatarPayload = '$hexColor|preset:${prefs.userAvatarPreset}';
    } else if (avatarType == 'custom') {
      final b64 = prefs.userAvatarBase64;
      avatarPayload = b64.isNotEmpty
          ? '$hexColor|b64:$b64'
          : '$hexColor|preset:initials';
    } else {
      // Explicitly clear a previously advertised preset on remote peers.
      avatarPayload = '$hexColor|preset:initials';
    }
    return ProtocolBeebeep.buildHelloPacket(
      localPort: localTcpPort,
      username: localUsername,
      status: localStatus,
      statusDescription: localStatusDescription,
      accountName: Platform.environment['USERNAME'] ?? localUsername,
      appVersion: appVersion,
      avatarHexColor: avatarPayload,
      workgroup: localWorkgroup,
      password: security.isEncryptionEnabled ? security.password : '',
      publicKey: publicKey,
      hostname: Platform.localHostname,
    );
  }

  /// Xử lý khi nhận được gói tin BEE-CIAO từ peer

  void _handlePeerHandshakeImpl(
    String senderIp,
    Map<String, dynamic> data,
    Socket socket,
  ) {
    var username = (data['username'] as String? ?? '').trim();
    final status = data['status'] as PeerStatus? ?? PeerStatus.online;
    final statusDesc = data['statusDescription'] as String? ?? '';
    final workgroup = data['workgroup'] as String? ?? '';
    final remotePort = data['port'] as int? ?? defaultListenerPort;
    final account = (data['account'] as String? ?? '').trim();
    final hostname = (data['hostname'] as String? ?? '').trim();
    final colorRaw = (data['color'] as String? ?? '').trim();

    // Loại bỏ username ??? và suy diễn tên hợp lệ
    if (username.isEmpty || username == '???') {
      if (hostname.isNotEmpty &&
          hostname != '???' &&
          hostname.toLowerCase() != 'localhost') {
        if (account.isNotEmpty &&
            account != '???' &&
            account.toLowerCase() != 'user' &&
            account.toLowerCase() != 'administrator' &&
            account.toLowerCase() != 'admin') {
          username = '$account@$hostname';
        } else {
          username = hostname;
        }
      } else if (account.isNotEmpty &&
          account != '???' &&
          account.toLowerCase() != 'user' &&
          account.toLowerCase() != 'administrator' &&
          account.toLowerCase() != 'admin') {
        username = '$account ($senderIp)';
      } else {
        username = senderIp;
      }
    }

    if (_disposed) return;

    // Kiểm tra nếu IP của peer đến từ card mạng đã bị vô hiệu hóa
    if (_discovery.disabledAdapterNames.isNotEmpty &&
        !_discovery.enabledAdapters.any(
          (a) => NetworkUtils.isIpInSubnet(senderIp, a.subnet),
        )) {
      socket.destroy();
      return;
    }

    final endpoint = '$senderIp:$remotePort';
    final version = data['version'] as String? ?? '';
    final client = data['client'] as String? ?? '';
    final isBeebeepClient = ProtocolBeebeep.isRemoteBeebeep(
      version: version,
      color: colorRaw,
      client: client,
    );

    // Tạo đối tượng tạm để tính canonicalIdentity chính xác theo máy vật lý
    final candidate = PeerModel(
      id: endpoint,
      name: username,
      ip: senderIp,
      port: remotePort,
      status: status,
      statusDescription: statusDesc,
      workgroup: workgroup,
      isBeebeep: isBeebeepClient,
      accountName: account.isNotEmpty && account != '???' ? account : null,
      hostname: hostname.isNotEmpty && hostname != '???' ? hostname : null,
      knownIps: {senderIp},
    );
    if (colorRaw.isNotEmpty) {
      candidate.updateAvatarFromRaw(colorRaw);
    }

    final candidateIdentity = PeerSessionRegistry.identity(candidate);
    final identityKey = candidateIdentity ?? candidate.canonicalIdentity;

    // Bước 1: Thu hồi (Evict) senderIp khỏi mọi Peer có định danh khác đã từng dùng IP này
    if (candidateIdentity != null && senderIp.isNotEmpty) {
      // A distinct live endpoint may belong to another account on this host.
      // Only a reused endpoint, or stale IP history, establishes reassignment.
      final retainedIdentities = _coexistingIdentities(
        senderIp,
        excludingEndpoint: endpoint,
      );
      knownDevices.evictIpFromOtherDevices(
        senderIp,
        ownerIdentityKey: candidateIdentity,
        preservedIdentityKeys: retainedIdentities,
      );
      for (final other in _peers.values.toSet()) {
        if (other.isGroup || other.isAllUsers || other.isAiAssistant) continue;
        final otherIdentity =
            PeerSessionRegistry.identity(other) ??
            _peerSessions.identities[other.id];
        if (otherIdentity != null &&
            otherIdentity != candidateIdentity &&
            !retainedIdentities.contains(otherIdentity)) {
          other.knownIps.remove(senderIp);
          for (final sessionEntry in _peerSessions.sessions.entries.toList()) {
            if (sessionEntry.value.conversationId == other.id &&
                (sessionEntry.key == endpoint ||
                    sessionEntry.value.remote.ip == senderIp)) {
              sessionEntry.value.available = false;
              _peerSessions.sessions.remove(sessionEntry.key);
            }
          }
          if (other.ip == senderIp) {
            final remainingActive = _peerSessions
                .forConversation(other.id)
                .where((s) => s.available && s.remote.ip.isNotEmpty)
                .toList();
            other.ip = remainingActive.isNotEmpty
                ? remainingActive.first.remote.ip
                : '';
          }
          _refreshLogicalPeer(other);
        }
      }
    }

    // Tìm tất cả peer hiện tại tương ứng với cùng một máy vật lý
    final matchingPeers = _peers.values.where((p) {
      if (p.isGroup || p.isAllUsers || p.isAiAssistant) return false;
      return _isSamePhysicalPeer(p, candidate, senderIp: senderIp);
    }).toSet();

    PeerModel primaryPeer;
    if (_selectedPeer != null && matchingPeers.contains(_selectedPeer)) {
      primaryPeer = _selectedPeer!;
    } else if (_peers.containsKey(endpoint) &&
        matchingPeers.contains(_peers[endpoint])) {
      primaryPeer = _peers[endpoint]!;
    } else if (matchingPeers.isNotEmpty) {
      primaryPeer = matchingPeers.firstWhere(
        (p) => p.status != PeerStatus.offline,
        orElse: () => matchingPeers.first,
      );
    } else {
      final occupied = _peers[endpoint];
      final remembered = _peerSessions.identities[endpoint];
      final conflict =
          (occupied != null && !matchingPeers.contains(occupied)) ||
          (remembered != null && remembered != candidateIdentity);
      final id = conflict
          ? 'peer_${sha256.convert(utf8.encode(candidateIdentity ?? endpoint))}'
          : endpoint;
      primaryPeer = _peers[id] ?? candidate.copyWith(id: id);
    }

    final previousSession = _peerSessions.sessions[endpoint];
    if (previousSession != null &&
        previousSession.conversationId != primaryPeer.id) {
      previousSession.available = false;
      final previousPeer = _peers[previousSession.conversationId];
      _peerSessions.sessions.remove(endpoint);
      if (previousPeer != null) _refreshLogicalPeer(previousPeer);
    }
    _peerSessions.remember(primaryPeer.id, candidateIdentity);
    _peerSessions.sessions[endpoint] = PeerTransportSession(
      primaryPeer.id,
      candidate,
      data['hash'] as String? ?? '',
    );

    final now = DateTime.now();
    primaryPeer.isBeebeep = isBeebeepClient;
    primaryPeer.isPinned =
        AppPreferences().isPeerPinned(identityKey) ||
        AppPreferences().isPeerPinned(primaryPeer.canonicalIdentity) ||
        primaryPeer.isPinned;
    if (colorRaw.isNotEmpty) {
      primaryPeer.updateAvatarFromRaw(colorRaw);
    }

    // Cập nhật thông tin mới nhất cho peer
    if (username.isNotEmpty && username != '???') {
      primaryPeer.name = username;
    }
    primaryPeer.ip = senderIp;
    primaryPeer.port = remotePort;
    primaryPeer.status = status;
    primaryPeer.statusDescription = statusDesc;
    primaryPeer.workgroup = workgroup;
    primaryPeer.lastSeen = now;
    if (account.isNotEmpty && account != '???') {
      primaryPeer.accountName = account;
    }
    if (hostname.isNotEmpty && hostname != '???') {
      primaryPeer.hostname = hostname;
    }

    // Gộp tất cả peer trùng lặp khác vào primaryPeer và gộp lịch sử trò chuyện
    for (final other in matchingPeers) {
      if (identical(other, primaryPeer)) continue;
      if (other.customNickname != null && primaryPeer.customNickname == null) {
        primaryPeer.customNickname = other.customNickname;
      }
      primaryPeer.isPinned = primaryPeer.isPinned || other.isPinned;

      _mergeConversations(primaryPeer.id, other.id);

      final otherPending = _pendingOfflineMessageIds.remove(other.id);
      if (otherPending != null) {
        _pendingOfflineMessageIds
            .putIfAbsent(primaryPeer.id, () => {})
            .addAll(otherPending);
      }

      for (final key in _peers.keys.toList()) {
        if (identical(_peers[key], other)) {
          _peers[key] = primaryPeer;
        }
      }
      _peers[other.id] = primaryPeer;
    }

    // Làm sạch danh sách IP đang hoạt động của primaryPeer:
    // chỉ giữ lại các IP đang có phiên kết nối thực sự cùng senderIp mới
    final activeSessionIps = _peerSessions
        .forConversation(primaryPeer.id)
        .where((s) => s.available && s.remote.status != PeerStatus.offline)
        .map((s) => s.remote.ip)
        .where((ip) => ip.isNotEmpty)
        .toSet();
    if (candidateIdentity != null) {
      primaryPeer.knownIps
        ..clear()
        ..addAll(activeSessionIps)
        ..add(senderIp);
    } else {
      primaryPeer.knownIps.add(senderIp);
      primaryPeer.knownIps.addAll(candidate.knownIps);
    }

    // Gộp hội thoại với endpoint hiện tại nếu có lịch sử riêng và không xung đột chủ sở hữu
    if (_peers[endpoint] == null || matchingPeers.contains(_peers[endpoint])) {
      _mergeConversations(primaryPeer.id, endpoint);
    }

    // Đảm bảo selection không bị nhảy nếu đang chọn peer này
    if (_selectedPeer != null &&
        _isSamePhysicalPeer(_selectedPeer!, primaryPeer, senderIp: senderIp)) {
      _selectedPeer = primaryPeer;
    }

    final peer = primaryPeer;

    // Nếu chưa có hostname chuẩn (hoặc là ???), thử phân giải ngược Reverse DNS trong nền
    if (peer.hostname == null ||
        peer.hostname == '???' ||
        peer.hostname!.isEmpty ||
        peer.hostname!.toLowerCase() == 'localhost') {
      InternetAddress(senderIp)
          .reverse()
          .then((resolved) {
            if (_disposed) return;
            final host = resolved.host.trim();
            if (host.isNotEmpty &&
                host != senderIp &&
                host != '???' &&
                host.toLowerCase() != 'localhost') {
              peer.hostname = host;
              if (peer.name == senderIp || peer.name == '???') {
                peer.name =
                    (peer.accountName != null &&
                        peer.accountName!.isNotEmpty &&
                        peer.accountName != '???')
                    ? '${peer.accountName}@$host'
                    : host;
              }
              _notify();
            }
          })
          .catchError((_) {});
    }

    // Đảm bảo endpoint, peer.id và tất cả các IP đã biết cùng trỏ tới thực thể này
    if (_peers[endpoint] == null || matchingPeers.contains(_peers[endpoint])) {
      _peers[endpoint] = peer;
    }
    _peers[peer.id] = peer;
    final userHash = data['hash'] as String? ?? '';
    final resolvedPeerIdentity =
        PeerSessionRegistry.identity(peer) ?? _peerSessions.identities[peer.id];
    _refreshLogicalPeer(peer);
    for (final group in _groups.values) {
      final oldIds = group.memberIds
          .where(
            (id) =>
                id != peer.id &&
                (id == 'hash:$userHash' ||
                    (userHash.isNotEmpty &&
                        group.memberRecords[id]?[2] == userHash) ||
                    (resolvedPeerIdentity != null &&
                        (_peerSessions.identities[id] == resolvedPeerIdentity ||
                            (_peers[id] != null &&
                                identical(_peers[id], peer))))),
          )
          .toList();
      for (final id in oldIds) {
        for (final msg in _conversations[group.id] ?? <MessageModel>[]) {
          if (msg.pendingRecipients?.remove(id) ?? false) {
            msg.pendingRecipients!.add(peer.id);
            _removePendingOfflineMessage(id, msg.id);
            _pendingOfflineMessageIds
                .putIfAbsent(peer.id, () => {})
                .add(msg.id);
            chatHistory.scheduleSave(group.id, _conversations[group.id]!);
          }
        }
        group.memberIds.remove(id);
        group.memberRecords.remove(id);
        final invitation = group.invitations.remove(id);
        if (invitation != null) group.invitations[peer.id] = invitation;
        if (!group.memberIds.contains(peer.id)) group.memberIds.add(peer.id);
      }
      if (group.memberIds.contains(peer.id)) {
        group.memberRecords.putIfAbsent(
          peer.id,
          () => [
            peer.name,
            peer.accountName ?? '',
            userHash.isNotEmpty ? userHash : peer.id,
            '',
          ],
        );
        _syncGroup(group, onlyMember: peer.id);
        if (_selectedPeer?.id == group.id) {
          _selectedPeer = PeerModel.fromGroup(group);
        }
      }
    }
    _saveGroups();

    // Ghi nhớ vào cơ sở dữ liệu thiết bị tin cậy (known_devices.json)
    // Chỉ trả về true nếu đây là lần ĐẦU TIÊN THỰC SỰ thiết bị này xuất hiện trong mạng
    final isTrulyNewDevice = knownDevices.recordDevice(
      identityKey: identityKey,
      username: peer.name,
      ip: senderIp,
      preservedIdentityKeys: _coexistingIdentities(
        senderIp,
        excludingEndpoint: endpoint,
      ),
      accountName: peer.accountName,
      hostname: peer.hostname,
      customNickname: peer.customNickname,
      userHash: userHash,
      port: remotePort,
      avatarColorValue: peer.avatarColor.toARGB32(),
      avatarPreset: peer.avatarPreset,
      customAvatarBase64: peer.customAvatarBase64,
    );

    final activeCount = peers
        .where((p) => p.status != PeerStatus.offline)
        .length;
    _discovery.updateDiscoveredPeersCount(activeCount);

    // Chỉ hiển thị toast "Thiết bị mới" nếu là thiết bị mới hoàn toàn và không trong lúc quét chủ động
    if (isTrulyNewDevice && !_isActivelyRescanning) {
      if (_lastDiscoveryToastTime == null ||
          now.difference(_lastDiscoveryToastTime!).inMilliseconds >= 2000) {
        _lastDiscoveryToastTime = now;
        showToast('toastNewDevice', ['$username ($senderIp)']);
      }
    }

    // Tự động gửi lại các tin nhắn tồn đọng trong Outbox cho peer này nếu có
    unawaited(flushPendingOutgoingMessagesForPeer(peer));

    // Tự động kích hoạt rung chuông Buzz nếu trước đó vừa gửi lệnh mở app từ xa
    _triggerPendingBuzzIfNeeded(peer, senderIp);

    _notify();
  }

  /// Tự động gửi lại rung chuông Buzz cho peer nếu nằm trong danh sách chờ sau WinRM
  void _triggerPendingBuzzIfNeeded(PeerModel peer, String senderIp) {
    if (!AppPreferences().winrmAutoBuzzOnConnect) return;

    final matchingIndex = _pendingBuzzTargets.indexWhere(
      (t) => t.matches(peer, senderIp),
    );
    if (matchingIndex == -1) return;

    final sent = _sendToPeer(
      peer.id,
      ProtocolBeebeep.packet(
        ProtocolBeebeep.headerBuzz,
        '22',
        text: '*',
        flags: 1,
      ),
    );

    // Chỉ hoàn thành và ghi nhận tin nhắn khi gói tin thực sự được gửi thành công
    if (sent) {
      _pendingBuzzTargets.removeAt(matchingIndex);
      final autoBuzzText =
          '🔔 ${languageProvider?.tr('winrmAutoBuzzed') ?? 'Đã tự động gửi Buzz sau khi đối phương online!'}';
      final autoBuzzMsg = MessageModel(
        id: 'buzz-auto-${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'me',
        senderName: localUsername,
        recipientId: peer.id,
        text: autoBuzzText,
        isMine: true,
        status: MessageStatus.delivered,
      );
      final msgs = _conversations.putIfAbsent(peer.id, () => []);
      msgs.add(autoBuzzMsg);
      chatHistory.scheduleSave(peer.id, msgs);
      peer.lastMessage = autoBuzzText;
      peer.lastMessageTime = autoBuzzMsg.timestamp;
      showToast('winrmAutoBuzzed', []);
      _notify();
    }
  }

  void _triggerPendingBuzzIfNeededForTestingImpl(
    PeerModel peer,
    String senderIp,
  ) {
    _triggerPendingBuzzIfNeeded(peer, senderIp);
  }

  Future<void> _loadChatHistory() async {
    try {
      final saved = await chatHistory.loadAllConversations();
      if (_disposed) return;
      for (final entry in saved.entries) {
        final convId = entry.key;
        final msgs = entry.value;
        if (msgs.isEmpty) continue;

        final arriving = _conversations[convId];
        if (arriving != null) {
          final existingKeys = msgs
              .map((m) => '${m.isMine}:${m.sourceSession}:${m.id}')
              .toSet();
          msgs.addAll(
            arriving.where(
              (m) => existingKeys.add('${m.isMine}:${m.sourceSession}:${m.id}'),
            ),
          );
          msgs.sort((a, b) => a.timestamp.compareTo(b.timestamp));
        }
        _conversations[convId] = msgs;
        for (final m in msgs) {
          // Older builds incorrectly persisted local Buzz/WinRM notices in
          // the text outbox. Retain history, but retire those retry targets.
          if (m.id.startsWith('buzz-')) m.pendingRecipients = null;
          if (!_isRetryableText(m)) continue;
          if (m.isMine && m.status == MessageStatus.sending) {
            m.status = MessageStatus.failed;
          }
          if (m.pendingRecipients == null &&
              m.status == MessageStatus.failed &&
              !convId.startsWith('group_') &&
              convId != '__ALL_USERS__') {
            m.pendingRecipients = {convId};
          }
          for (final target in m.pendingRecipients ?? <String>{}) {
            _pendingOfflineMessageIds.putIfAbsent(target, () => {}).add(m.id);
          }
        }
        chatHistory.scheduleSave(convId, msgs);

        final last = msgs.last;
        final lastText = last.isRevoked
            ? '[${languageProvider?.tr('messageRevoked') ?? 'Tin nhắn đã thu hồi'}]'
            : (last.fileAttachment != null
                  ? '📁 ${last.fileAttachment!.fileName}'
                  : last.text);

        if (convId == '__AI_ASSISTANT__') {
          _aiPeer.lastMessage = lastText;
          _aiPeer.lastMessageTime = last.timestamp;
        } else if (convId == '__ALL_USERS__') {
          _allUsersPeer.lastMessage = lastText;
          _allUsersPeer.lastMessageTime = last.timestamp;
        } else if (_groups.containsKey(convId)) {
          // Nhóm trò chuyện
          final group = _groups[convId]!;
          group.lastMessage = lastText;
          group.lastMessageTime = last.timestamp;
          final unread = msgs
              .where((m) => !m.isMine && m.status != MessageStatus.read)
              .length;
          group.unreadCount = unread;
        } else {
          final peer = _peers[convId];
          if (peer != null) {
            peer.lastMessage = lastText;
            peer.lastMessageTime = last.timestamp;
          } else {
            // Khôi phục peer từ lịch sử kèm đầy đủ định danh thiết bị đã lưu
            final rawHost = convId.contains(':')
                ? convId.split(':').first
                : convId;
            final isRawIpConvId = InternetAddress.tryParse(rawHost) != null;
            final savedIdentity =
                _peerSessions.identities[convId] ??
                (isRawIpConvId
                    ? () {
                        final matches = knownDevices.devices.values
                            .where(
                              (d) =>
                                  d.id.contains('@') &&
                                  (d.knownIps.contains(rawHost) ||
                                      d.lastIp == rawHost),
                            )
                            .map((d) => d.id.toLowerCase())
                            .toSet();
                        return matches.length == 1 ? matches.single : null;
                      }()
                    : null);
            final deviceInfo = knownDevices.findByIdentity(savedIdentity);

            String? restoredAccount = deviceInfo?.accountName;
            String? restoredHostname = deviceInfo?.hostname;
            if ((restoredAccount == null || restoredHostname == null) &&
                savedIdentity != null &&
                savedIdentity.contains('@')) {
              final parts = savedIdentity.split('@');
              final accPart = parts.first.trim();
              final hostPart = parts.sublist(1).join('@').trim();
              if (restoredHostname == null && hostPart.isNotEmpty) {
                restoredHostname = hostPart;
              }
              if (restoredAccount == null &&
                  accPart.isNotEmpty &&
                  accPart != hostPart) {
                restoredAccount = accPart;
              }
            }

            MessageModel? lastIncoming;
            for (int i = msgs.length - 1; i >= 0; i--) {
              final candidateMsg = msgs[i];
              if (!candidateMsg.isMine &&
                  candidateMsg.senderName.trim().isNotEmpty &&
                  candidateMsg.senderName.trim() != '???') {
                lastIncoming = candidateMsg;
                break;
              }
            }

            final restoredName =
                (deviceInfo != null &&
                    deviceInfo.username.trim().isNotEmpty &&
                    deviceInfo.username.trim() != '???')
                ? deviceInfo.username.trim()
                : (lastIncoming != null
                      ? lastIncoming.senderName.trim()
                      : (restoredAccount != null && restoredAccount.isNotEmpty
                            ? restoredAccount
                            : (restoredHostname != null &&
                                      restoredHostname.isNotEmpty
                                  ? restoredHostname
                                  : (isRawIpConvId ? rawHost : convId))));

            var restoredIp = '';
            if (deviceInfo != null) {
              restoredIp = deviceInfo.lastIp;
            } else if (isRawIpConvId) {
              final claimedByOther = knownDevices.devices.values.any(
                (d) =>
                    savedIdentity != null &&
                    d.id.toLowerCase() != savedIdentity.toLowerCase() &&
                    (d.lastIp == rawHost || d.knownIps.contains(rawHost)),
              );
              if (!claimedByOther) {
                restoredIp = rawHost;
              }
            }

            final restoredPort =
                deviceInfo?.port ??
                (convId.contains(':')
                    ? int.tryParse(convId.split(':').last) ??
                          defaultListenerPort
                    : defaultListenerPort);

            final p = PeerModel(
              id: convId,
              name: restoredName,
              ip: restoredIp,
              port: restoredPort,
              status: PeerStatus.offline,
              accountName: restoredAccount,
              hostname: restoredHostname,
              customNickname: deviceInfo?.customNickname,
              knownIps: {
                if (deviceInfo != null)
                  ...deviceInfo.knownIps.where((ip) => ip.isNotEmpty)
                else if (restoredIp.isNotEmpty)
                  restoredIp,
              },
              avatarColor: deviceInfo?.avatarColorValue != null
                  ? Color(deviceInfo!.avatarColorValue!)
                  : null,
              avatarPreset: deviceInfo?.avatarPreset,
              customAvatarBase64: deviceInfo?.customAvatarBase64,
            );
            if (deviceInfo?.userHash != null &&
                deviceInfo!.userHash!.isNotEmpty) {
              _peerHashes[convId] = deviceInfo.userHash!;
            }
            if (savedIdentity != null) {
              _peerSessions.remember(convId, savedIdentity);
            }
            p.lastMessage = lastText;
            p.lastMessageTime = last.timestamp;
            p.isPinned =
                AppPreferences().isPeerPinned(p.canonicalIdentity) ||
                (savedIdentity != null &&
                    AppPreferences().isPeerPinned(savedIdentity)) ||
                AppPreferences().isPeerPinned(convId);
            _peers[convId] = p;
          }
        }
      }

      // Khởi tạo hợp nhất các cuộc trò chuyện và thiết bị cùng máy vật lý từ lịch sử
      _consolidateLoadedPeersAndConversations();
      _ensureOutboxRetryTimer();

      if (_tcpServer.isListening && !_disposed) {
        unawaited(_probeKnownAndRestoredPeers());
      }

      for (final peer in peers.where((p) => p.status != PeerStatus.offline)) {
        unawaited(flushPendingOutgoingMessagesForPeer(peer));
      }
      _notify();
    } catch (e) {
      debugPrint('[Coordinator] Load chat history error: $e');
    }
  }

  /// Tìm peer theo phiên đang hoạt động, id, IP hiện tại hoặc bất kỳ IP nào trong knownIps
  PeerModel? _findPeerByIpOrId(String ipOrId) {
    final activeSession = _peerSessions.sessions[ipOrId];
    if (activeSession != null && activeSession.available) {
      final sessionPeer = _peers[activeSession.conversationId];
      if (sessionPeer != null) return sessionPeer;
    }
    if (InternetAddress.tryParse(ipOrId) != null) {
      final byActiveIp = _peerSessions.sessions.values
          .where((s) => s.available && s.remote.ip == ipOrId)
          .map((s) => _peers[s.conversationId])
          .whereType<PeerModel>()
          .toSet();
      if (byActiveIp.length == 1) return byActiveIp.single;
    }
    if (_peers.containsKey(ipOrId)) return _peers[ipOrId];
    for (final p in _peers.values) {
      if (p.id == ipOrId || p.ip == ipOrId || p.knownIps.contains(ipOrId)) {
        return p;
      }
    }
    return null;
  }

  bool _hasActiveConnectionForPeer(PeerModel peer) {
    final sessions = _peerSessions.forConversation(peer.id);
    if (sessions.isNotEmpty || _peerSessions.identities.containsKey(peer.id)) {
      return sessions.any(
        (s) =>
            s.available &&
            s.remote.status != PeerStatus.offline &&
            _tcpServer.isConnected(s.endpoint),
      );
    }
    return _tcpServer.isConnected(peer.id) ||
        (peer.ip.isNotEmpty &&
            (_tcpServer.isConnected('${peer.ip}:${peer.port}') ||
                _tcpServer.isConnected(peer.ip)));
  }

  /// Tự động thăm dò kết nối lại hoặc phân giải hostname để tìm IP mới khi peer bị nhảy DHCP IP
  Future<bool> _probePeerNewEndpointIfNeeded(PeerModel peer) async {
    if (_disposed) return false;
    final port = peer.port > 0 ? peer.port : defaultListenerPort;

    // 1. Thử kết nối tới IP hiện tại nếu chưa bị phiên của người khác chiếm giữ
    if (peer.ip.isNotEmpty) {
      final currentEndpoint = '${peer.ip}:$port';
      final existingSession = _peerSessions.sessions[currentEndpoint];
      final occupiedByOther =
          existingSession != null &&
          existingSession.available &&
          existingSession.conversationId != peer.id;
      if (!occupiedByOther) {
        final connected = await _connectPeer(
          peer.ip,
          port,
          timeout: const Duration(milliseconds: 500),
        );
        if (connected) {
          final afterSession = _peerSessions.sessions[currentEndpoint];
          if (afterSession == null || afterSession.conversationId == peer.id) {
            _refreshLogicalPeer(peer);
            if (peer.status != PeerStatus.offline ||
                _hasActiveConnectionForPeer(peer)) {
              return true;
            }
          }
        }
      }
    }

    // 2. Nếu có hostname hợp lệ, phân giải DNS/LLMNR/NetBIOS để tìm IP mới sau khi nhảy DHCP
    final host = (peer.hostname ?? '').trim();
    final validHost =
        host.isNotEmpty &&
        host != '???' &&
        host.toLowerCase() != 'localhost' &&
        InternetAddress.tryParse(host) == null;
    if (validHost && (_isInitialized || hostnameResolverForTesting != null)) {
      try {
        final List<String> resolvedIps;
        if (hostnameResolverForTesting != null) {
          resolvedIps = await hostnameResolverForTesting!(host);
        } else {
          final addrs = await InternetAddress.lookup(
            host,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(milliseconds: 700));
          resolvedIps = addrs.map((a) => a.address).toList();
        }
        for (final candidateIp in resolvedIps) {
          final cleanIp = candidateIp.trim();
          if (cleanIp.isEmpty ||
              cleanIp == '0.0.0.0' ||
              cleanIp.startsWith('127.')) {
            continue;
          }
          final candidateEndpoint = '$cleanIp:$port';
          final existingSession = _peerSessions.sessions[candidateEndpoint];
          if (existingSession != null &&
              existingSession.available &&
              existingSession.conversationId != peer.id) {
            continue;
          }
          final connected = await _connectPeer(
            cleanIp,
            port,
            timeout: const Duration(milliseconds: 500),
          );
          if (connected) {
            final afterSession = _peerSessions.sessions[candidateEndpoint];
            if (afterSession != null &&
                afterSession.conversationId == peer.id) {
              _refreshLogicalPeer(peer);
              return true;
            }
          }
        }
      } catch (_) {}
    }

    if (_isInitialized) {
      _discovery.sendBroadcastAnnounce();
    }
    return false;
  }

  Set<String> _coexistingIdentities(String ip, {String? excludingEndpoint}) =>
      _peerSessions.sessions.entries
          .where(
            (e) =>
                e.key != excludingEndpoint &&
                e.value.available &&
                e.value.remote.ip == ip,
          )
          .map(
            (e) =>
                _peerSessions.identities[e.value.conversationId] ??
                PeerSessionRegistry.identity(e.value.remote),
          )
          .whereType<String>()
          .toSet();

  bool _isPeerIpAllowed(String ip) =>
      _discovery.disabledAdapterNames.isEmpty ||
      _discovery.enabledAdapters.any(
        (a) => NetworkUtils.isIpInSubnet(ip, a.subnet),
      );

  Future<bool> _connectPeer(
    String ip,
    int port, {
    String? sourceAddress,
    Duration timeout = const Duration(seconds: 2),
  }) {
    if (_disposed || !_isPeerIpAllowed(ip)) return Future.value(false);
    if (_discovery.disabledAdapterNames.isNotEmpty) {
      final adapter = _discovery.enabledAdapters
          .where(
            (a) =>
                NetworkUtils.isIpInSubnet(ip, a.subnet) &&
                (sourceAddress == null || a.ip == sourceAddress),
          )
          .firstOrNull;
      if (adapter == null) return Future.value(false);
      sourceAddress = adapter.ip;
    }
    return _tcpServer.connect(
      ip,
      port,
      sourceAddress: sourceAddress,
      timeout: timeout,
    );
  }

  /// Chủ động kết nối TCP trực tiếp tới các thiết bị/liên hệ đã biết lúc khởi động hoặc quét mạng
  Future<void> _probeKnownAndRestoredPeers() async {
    if (_disposed || _probingKnownPeers || !_tcpServer.isListening) return;
    _probingKnownPeers = true;
    try {
      final probedEndpoints = <String>{};
      final offlinePeers = _peers.values
          .where(
            (p) =>
                !p.isGroup &&
                !p.isAllUsers &&
                !p.isAiAssistant &&
                p.status == PeerStatus.offline,
          )
          .toSet()
          .toList();

      const batchSize = 8;
      for (var i = 0; i < offlinePeers.length; i += batchSize) {
        if (_disposed || !_tcpServer.isListening) return;
        final batch = offlinePeers.skip(i).take(batchSize).toList();
        await Future.wait(
          batch.map((peer) async {
            if (_disposed || peer.status != PeerStatus.offline) return;
            final port = peer.port > 0 ? peer.port : defaultListenerPort;
            if (peer.ip.isNotEmpty) {
              probedEndpoints.add('${peer.ip}:$port');
            }
            await _probePeerNewEndpointIfNeeded(peer);
          }),
        );
      }

      // Thăm dò thêm các thiết bị đã lưu trong known_devices.json chưa có phiên kết nối
      final deviceEndpoints = <(String, int)>[];
      for (final d in knownDevices.devices.values) {
        final ip = d.lastIp.trim();
        if (ip.isEmpty || ip == '0.0.0.0') continue;
        final port = (d.port != null && d.port! > 0)
            ? d.port!
            : defaultListenerPort;
        final endpoint = '$ip:$port';
        if (probedEndpoints.contains(endpoint) ||
            _tcpServer.isConnected(endpoint)) {
          continue;
        }
        probedEndpoints.add(endpoint);
        deviceEndpoints.add((ip, port));
      }

      for (var i = 0; i < deviceEndpoints.length; i += batchSize) {
        if (_disposed || !_tcpServer.isListening) return;
        final batch = deviceEndpoints.skip(i).take(batchSize).toList();
        await Future.wait(
          batch.map((target) async {
            if (_disposed || !_tcpServer.isListening) return;
            await _connectPeer(
              target.$1,
              target.$2,
              timeout: const Duration(milliseconds: 600),
            );
          }),
        );
      }
    } catch (e) {
      debugPrint('[Coordinator] Probe known peers error: $e');
    } finally {
      _probingKnownPeers = false;
    }
  }

  Future<void> _probeKnownAndRestoredPeersForTestingImpl() =>
      _probeKnownAndRestoredPeers();

  bool _sendToPeer(String endpoint, List<int> packet) {
    if (sendToPeerForTesting != null) {
      return sendToPeerForTesting!(endpoint, packet);
    }
    final peer = _peers[endpoint];
    if (peer != null) {
      final sessions = _peerSessions.forConversation(peer.id);
      if (sessions.isNotEmpty ||
          _peerSessions.identities.containsKey(peer.id)) {
        final message = ProtocolBeebeep.parseMessage(utf8.decode(packet));
        final groupId = message == null
            ? null
            : ProtocolBeebeep.groupMetadata(message)?.id;
        final expected = _groups[groupId]?.memberRecords[peer.id]
            ?.elementAtOrNull(2);
        for (final session in sessions) {
          if (!session.available ||
              session.remote.status == PeerStatus.offline ||
              !_isPeerIpAllowed(session.remote.ip)) {
            continue;
          }
          if (expected != null &&
              expected != peer.id &&
              session.hash != expected) {
            continue;
          }
          if (_tcpServer.send(session.endpoint, packet)) return true;
        }
        return false;
      }
    }
    final activeSessionAtEndpoint = _peerSessions.sessions[endpoint];
    if (activeSessionAtEndpoint != null &&
        activeSessionAtEndpoint.available &&
        peer != null &&
        activeSessionAtEndpoint.conversationId != peer.id) {
      return false;
    }
    final targetIp = peer?.ip ?? endpoint.split(':').first;
    if (!_isPeerIpAllowed(targetIp)) return false;
    if (_tcpServer.send(endpoint, packet)) return true;
    if (peer == null) return false;
    for (final alias in _peers.entries) {
      if (alias.key != endpoint &&
          identical(alias.value, peer) &&
          _tcpServer.send(alias.key, packet)) {
        return true;
      }
    }
    return false;
  }

  PeerModel? _incomingPeer(String endpoint) {
    final exact = _peerSessions.sessions[endpoint];
    if (exact != null) return _peers[exact.conversationId];
    final hostIp = endpoint.contains(':')
        ? endpoint.split(':').first
        : endpoint;
    final byIp = _peerSessions.sessions.values
        .where((s) => s.remote.ip == hostIp && s.available)
        .map((s) => s.conversationId)
        .toSet();
    if (byIp.length == 1) return _peers[byIp.single];
    return byIp.isEmpty ? _findPeerByIpOrId(endpoint) : null;
  }

  String _incomingHash(String endpoint, PeerModel peer) =>
      _peerSessions.sessions[endpoint]?.hash.isNotEmpty == true
      ? _peerSessions.sessions[endpoint]!.hash
      : (_peerHashes[peer.id] ?? peer.id);

  void _refreshLogicalPeer(PeerModel peer) {
    final sessions = _peerSessions.forConversation(peer.id);
    final available = sessions
        .where(
          (s) =>
              s.available &&
              s.remote.status != PeerStatus.offline &&
              _isPeerIpAllowed(s.remote.ip),
        )
        .toList();
    if (available.isEmpty) {
      peer.status = PeerStatus.offline;
      return;
    }
    final preferred = available.first;
    peer.ip = preferred.remote.ip;
    peer.port = preferred.remote.port;
    peer.status = preferred.remote.status;
    peer.statusDescription = preferred.remote.statusDescription;
    peer.isBeebeep = preferred.remote.isBeebeep;
    peer.avatarColor = preferred.remote.avatarColor;
    peer.avatarPreset = preferred.remote.avatarPreset;
    peer.customAvatarBase64 = preferred.remote.customAvatarBase64;
    // One stable preferred identity for newly created groups; inbound uses the
    // exact sending session and existing groups retain their recorded hash.
    if (preferred.hash.isNotEmpty) _peerHashes[peer.id] = preferred.hash;
  }

  void _handlePeerStatusImpl(String endpoint, Map<String, dynamic> message) {
    final session = _peerSessions.sessions[endpoint];
    if (_disposed || session == null || !session.available) return;
    final status = switch (message['data']) {
      '0' => PeerStatus.offline,
      '1' => PeerStatus.online,
      '2' => PeerStatus.busy,
      '3' => PeerStatus.away,
      _ => null,
    };
    if (status == null) return;
    session.remote.status = status;
    session.remote.statusDescription = message['text'] as String? ?? '';
    final peer = _peers[session.conversationId];
    if (peer == null) return;
    final previousStatus = peer.status;
    peer.lastSeen = DateTime.now();
    _refreshLogicalPeer(peer);
    if (previousStatus == PeerStatus.offline &&
        peer.status != PeerStatus.offline) {
      unawaited(flushPendingOutgoingMessagesForPeer(peer));
    }
    _notify();
  }

  void _handlePeerActivityImpl(String endpoint) {
    final session = _peerSessions.sessions[endpoint];
    if (_disposed || session == null || !session.available) return;
    final peer = _peers[session.conversationId];
    if (peer == null) return;
    peer.lastSeen = DateTime.now();
    final previous = peer.status;
    // Traffic confirms transport activity, not a change in advertised presence.
    _refreshLogicalPeer(peer);
    if (previous != peer.status) _notify();
  }

  void _handlePeerDisconnectedImpl(String endpoint) {
    final session = _peerSessions.sessions[endpoint];
    if (_disposed) return;
    if (session != null) {
      session.available = false;
    }
    final peer = session != null
        ? _peers[session.conversationId]
        : _findPeerByIpOrId(endpoint);
    if (peer != null) {
      _refreshLogicalPeer(peer);
      if (peer.status == PeerStatus.offline) {
        _failUnackedMessagesForPeer(peer);
      }
    }
    _notify();
  }

  void _failUnackedMessagesForPeer(PeerModel peer) {
    final candidateKeys = <String>{
      peer.id,
      peer.ip,
      '${peer.ip}:${peer.port}',
      peer.canonicalIdentity,
      ...peer.knownIps,
      for (final ip in peer.knownIps) '$ip:${peer.port}',
      ..._peers.entries
          .where((e) => identical(e.value, peer))
          .map((e) => e.key),
      ...chatHistory.aliasesFor(peer.id),
      if (_peerHashes[peer.id] case final String hash) 'hash:$hash',
    };

    var changed = false;
    for (final key in candidateKeys) {
      final list = _conversations[key];
      if (list == null) continue;
      for (final msg in list) {
        if (msg.isMine &&
            _isRetryableText(msg) &&
            (msg.status == MessageStatus.sending ||
                msg.status == MessageStatus.sent)) {
          msg.status = MessageStatus.failed;
          recordPendingOfflineMessage(peer.id, msg.id);
          chatHistory.scheduleSave(key, list);
          changed = true;
        }
      }
    }
    if (changed) _notify();
  }
}
