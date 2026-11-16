part of '../messenger_coordinator.dart';

extension MessengerCoordinatorGroups on MessengerCoordinator {
  /// Stored member IDs are remote-only; the local user is implicit on each device.
  List<PeerModel> _groupMembersImpl(String groupId) {
    final group = _groups[groupId];
    if (group == null) return [];
    return [
      PeerModel(
        id: 'me',
        name: localUsername,
        ip: '',
        status: localStatus,
        avatarColor: localColor,
      ),
      for (final id in group.memberIds.toSet())
        _findPeerByIpOrId(id) ??
            PeerModel(
              id: id,
              name: group.memberRecords[id]?.first ?? id,
              ip: id.startsWith('hash:') ? '' : id.split(':').first,
              status: PeerStatus.offline,
            ),
    ];
  }

  String get _localUserHash => sha256
      .convert(
        utf8.encode(
          '${Platform.environment['USERNAME'] ?? localUsername}@${Platform.localHostname}:$localTcpPort',
        ),
      )
      .toString();

  List<String> _groupRecord(String id, GroupModel group) {
    final existing = group.memberRecords[id];
    if (existing != null) return existing;
    final peer = _findPeerByIpOrId(id);
    if (peer == null) return group.memberRecords[id] ?? [id, '', id, ''];
    return [peer.name, peer.accountName ?? '', _peerHashes[peer.id] ?? id, ''];
  }

  void _syncGroup(GroupModel group, {String? onlyMember}) {
    final hexColor =
        '#${group.color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    String avatarPayload = hexColor;
    if (group.customAvatarBase64 != null &&
        group.customAvatarBase64!.isNotEmpty) {
      avatarPayload = '$hexColor|b64:${group.customAvatarBase64}';
    } else if (group.avatarPreset != null && group.avatarPreset!.isNotEmpty) {
      avatarPayload = '$hexColor|preset:${group.avatarPreset}';
    }

    for (final id in group.memberIds) {
      if (onlyMember != null && id != onlyMember) continue;
      _sendToPeer(
        id,
        ProtocolBeebeep.buildGroupPacket(
          groupId: group.id,
          name: group.name,
          updatedAt: group.updatedAt,
          invitedAt: group.invitations[id],
          avatarPayload: avatarPayload,
          creatorId: group.creatorId,
          adminIds: _groupAdminIdentities(group).toList(),
          members: [
            for (final other in group.memberIds)
              if (other != id) _groupRecord(other, group),
          ],
        ),
      );
    }
  }

  void _handleGroupPacketImpl(String endpoint, Map<String, dynamic> message) {
    final sender = _incomingPeer(endpoint);
    final meta = ProtocolBeebeep.groupMetadata(message);
    if (sender == null || meta == null) return;
    if (meta.updatedAt.isAfter(
      DateTime.now().add(const Duration(minutes: 5)),
    )) {
      return;
    }
    final flags = message['flags'] as int? ?? 0;
    final isDisband =
        flags & ProtocolBeebeep.flagGroupDisbanded != 0 && meta.disbanded;
    final isKicked = flags & ProtocolBeebeep.flagGroupKicked != 0 && !isDisband;
    final isLeft = flags & ProtocolBeebeep.flagGroupLeft != 0;
    final isControl = isDisband || isKicked || isLeft;
    final priorMembers = _leftGroupMembers[meta.id];
    final senderIdentity = _incomingHash(endpoint, sender);
    final expectedHash = _groups[meta.id]?.memberRecords[sender.id]
        ?.elementAtOrNull(2);
    if (expectedHash != null &&
        expectedHash != sender.id &&
        expectedHash != senderIdentity) {
      return;
    }
    final canRejoin =
        !isControl &&
        flags & ProtocolBeebeep.flagGroupUpdate != 0 &&
        _leftGroupIds.contains(meta.id) &&
        meta.invitedAt != null &&
        _leftGroupAt[meta.id] != null &&
        meta.invitedAt!.isAfter(_leftGroupAt[meta.id]!) &&
        (priorMembers == null ||
            priorMembers.contains(senderIdentity) ||
            priorMembers.contains(sender.id));
    if (_disbandedGroupIds.contains(meta.id) ||
        (_leftGroupIds.contains(meta.id) && !canRejoin)) {
      // Bản danh sách cũ từ máy chưa nhận tin rời/giải tán. Nhắc lại rồi bỏ.
      if (!isControl) {
        final disbanded = _disbandedGroupIds.contains(meta.id);
        _sendDeparture(
          meta.id,
          meta.name,
          sender.id,
          removed: disbanded,
          left: !disbanded,
        );
      }
      return;
    }
    final existing = _groups[meta.id];
    // A known group can only be updated by one of its current members.
    if (existing != null && !existing.memberIds.contains(sender.id)) return;
    if (existing != null) {
      final stale = isControl
          ? meta.hasRevision && meta.updatedAt.isBefore(existing.updatedAt)
          : !meta.updatedAt.isAfter(existing.updatedAt);
      if (stale) return;
    }
    final senderIsAdmin =
        existing != null &&
        (existing.isAdmin(sender.id) || existing.isAdmin(senderIdentity));
    if ((isDisband || isKicked) && !senderIsAdmin) return;
    // Co-admins cannot remove the owner from their own group.
    if (isKicked && existing != null && existing.isCreator(_localUserHash)) {
      return;
    }
    if (isDisband) {
      if (existing != null) {
        final gName = existing.name;
        _disbandedGroupIds.add(meta.id);
        _leftGroupIds.remove(meta.id);
        _saveDepartures();
        deleteGroup(meta.id, notifyPeers: false);
        showToast('groupDisbandedToast', [gName]);
      }
      return;
    }
    if (isKicked) {
      if (existing != null) {
        final gName = existing.name;
        _rememberLeftGroup(existing, meta.updatedAt);
        _saveDepartures();
        deleteGroup(meta.id, notifyPeers: false);
        showToast('removedFromGroupToast', [gName]);
      }
      return;
    }
    if (isLeft) {
      if (existing == null) return;
      _appendGroupNotice(
        existing,
        messageId:
            'leave_${meta.id}_${sender.id}_${meta.updatedAt.microsecondsSinceEpoch}',
        localeKey: 'groupMemberLeftNotice',
        args: [sender.name],
        fallback: '${sender.name} đã rời nhóm',
      );
      final records = Map<String, List<String>>.from(existing.memberRecords)
        ..remove(sender.id);
      final updated = existing.copyWith(
        memberIds: existing.memberIds.where((id) => id != sender.id).toList(),
        memberRecords: records,
        invitations: Map.of(existing.invitations)..remove(sender.id),
        updatedAt: meta.updatedAt.isAfter(existing.updatedAt)
            ? meta.updatedAt
            : existing.updatedAt.add(const Duration(microseconds: 1)),
      );
      _groups[meta.id] = updated;
      _saveGroups();
      if (_selectedPeer?.id == meta.id) {
        _selectedPeer = PeerModel.fromGroup(updated);
      }
      _notify();
      return;
    }
    if (flags & ProtocolBeebeep.flagGroupUpdate == 0) return;
    // Snapshots are authoritative mutations, including avatar and roster edits.
    // A regular member may leave above, but cannot advance the group revision.
    if (existing != null && !senderIsAdmin) return;
    final records = ProtocolBeebeep.groupRecords(
      message['text'] as String? ?? '',
    );
    if (records == null) return;
    if (canRejoin) {
      _leftGroupIds.remove(meta.id);
      _leftGroupAt.remove(meta.id);
      _leftGroupMembers.remove(meta.id);
      _saveDepartures();
    }
    final memberRecords = <String, List<String>>{
      sender.id: [sender.name, sender.accountName ?? '', senderIdentity, ''],
    };
    for (final record in records) {
      final hash = record[2];
      if (hash.isEmpty || hash == _localUserHash) continue;
      final known = _peerHashes.entries.where((entry) => entry.value == hash);
      final session = _peerSessions.sessions.values
          .where((s) => s.hash == hash)
          .firstOrNull;
      final id =
          session?.conversationId ??
          (known.isEmpty ? 'hash:$hash' : known.first.key);
      memberRecords[id] = record;
    }
    if (existing != null &&
        existing.memberIds.any(
          (id) =>
              (existing.isCreator(id) ||
                  existing.isCreator(_groupMemberIdentity(id, existing))) &&
              !memberRecords.containsKey(id),
        )) {
      return;
    }
    String? creatorId = existing?.creatorId;
    if (existing == null) {
      final prefix = GroupModel.creatorHashPrefix(meta.id);
      if (prefix == null) {
        // Native/legacy groups do not carry verifiable owner metadata.
        creatorId = senderIdentity;
      } else {
        final candidates = [
          _localUserHash,
          senderIdentity,
          ...memberRecords.values.map((record) => record[2]),
        ];
        creatorId = candidates.where((id) => id.startsWith(prefix)).firstOrNull;
      }
    }
    Color? groupColor = existing?.color;
    String? groupPreset = existing?.avatarPreset;
    String? groupBase64 = existing?.customAvatarBase64;

    if (meta.avatarPayload != null && meta.avatarPayload!.isNotEmpty) {
      final parts = meta.avatarPayload!.split('|');
      final colorStr = parts[0].trim();
      if (colorStr.startsWith('#') &&
          (colorStr.length == 7 || colorStr.length == 9)) {
        try {
          final hex = colorStr.replaceFirst('#', '');
          groupColor = Color(
            int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16),
          );
        } catch (_) {}
      }
      if (parts.length > 1) {
        for (int i = 1; i < parts.length; i++) {
          final p = parts[i].trim();
          if (p.startsWith('preset:')) {
            groupPreset = p.substring(7).trim();
            groupBase64 = null;
          } else if (p.startsWith('b64:')) {
            groupBase64 = p.substring(4).trim();
            groupPreset = null;
          }
        }
      }
    }

    final oldMemberIds = existing?.memberIds.toSet() ?? const <String>{};
    final newMemberIds = memberRecords.keys.toSet();
    if (existing != null) {
      for (final id in newMemberIds.difference(oldMemberIds)) {
        final label = memberRecords[id]!.first;
        _appendGroupNotice(
          existing,
          messageId:
              'add_${meta.id}_${id}_${meta.updatedAt.microsecondsSinceEpoch}',
          localeKey: 'groupMemberAddedNotice',
          args: [sender.name, label],
          fallback: '${sender.name} đã thêm $label vào nhóm',
        );
      }
      if (senderIsAdmin) {
        for (final id in oldMemberIds.difference(newMemberIds)) {
          _appendGroupNotice(
            existing,
            messageId:
                'remove_${meta.id}_${id}_${meta.updatedAt.microsecondsSinceEpoch}',
            localeKey: 'groupMemberRemovedNotice',
            args: [sender.name, _groupMemberLabel(id, existing)],
            fallback:
                '${sender.name} đã mời ${_groupMemberLabel(id, existing)} ra khỏi nhóm',
          );
        }
      }
    }

    final nameChanged = existing != null && existing.name != meta.name;
    final appliedName = nameChanged && !senderIsAdmin
        ? existing.name
        : meta.name;
    if (nameChanged && senderIsAdmin) {
      _appendGroupRenameNotice(
        existing,
        who: sender.name,
        oldName: existing.name,
        newName: appliedName,
        messageId: 'rename_${meta.id}_${meta.updatedAt.microsecondsSinceEpoch}',
      );
    }

    if (meta.creatorId != null &&
        meta.creatorId!.isNotEmpty &&
        (existing == null ||
            existing.isCreator(sender.id) ||
            existing.isCreator(senderIdentity))) {
      creatorId = meta.creatorId;
    }
    final senderIsCreator =
        existing != null &&
        (existing.isCreator(sender.id) || existing.isCreator(senderIdentity));
    final adminIds =
        meta.adminIds != null && (existing == null || senderIsCreator)
        ? meta.adminIds!
        : (existing?.adminIds ?? <String>[]);

    final group = GroupModel(
      id: meta.id,
      name: appliedName,
      memberIds: memberRecords.keys.toList(),
      memberRecords: memberRecords,
      updatedAt: meta.updatedAt,
      createdAt: existing?.createdAt,
      creatorId: creatorId,
      adminIds: adminIds,
      color: groupColor,
      avatarPreset: groupPreset,
      customAvatarBase64: groupBase64,
      unreadCount: existing?.unreadCount ?? 0,
      lastMessage: existing?.lastMessage,
      lastMessageTime: existing?.lastMessageTime,
      invitations: {
        for (final entry
            in (existing?.invitations ?? <String, DateTime>{}).entries)
          if (memberRecords.containsKey(entry.key)) entry.key: entry.value,
      },
    );
    if (existing != null && senderIsCreator) {
      _appendGroupRoleNotices(existing, group, sender.name);
      // Notices update local preview/unread state after the snapshot is built.
      group.lastMessage = existing.lastMessage;
      group.lastMessageTime = existing.lastMessageTime;
      group.unreadCount = existing.unreadCount;
    }
    _groups[group.id] = group;
    _saveGroups();
    if (_selectedPeer?.id == group.id) {
      _selectedPeer = PeerModel.fromGroup(group);
    }
    _notify();
  }

  void _handleGroupMessageImpl(String endpoint, Map<String, dynamic> message) {
    final meta = ProtocolBeebeep.groupMetadata(message);
    final sender = _incomingPeer(endpoint);
    final group = meta == null ? null : _groups[meta.id];
    if (group == null ||
        sender == null ||
        !group.memberIds.contains(sender.id)) {
      return;
    }
    final expectedHash = group.memberRecords[sender.id]?.elementAtOrNull(2);
    if (expectedHash != null &&
        expectedHash != sender.id &&
        expectedHash != _incomingHash(endpoint, sender)) {
      return;
    }
    handleIncomingMessage(
      endpoint,
      message['id'] as String,
      message['text'] as String,
      message['timestamp'] as DateTime,
      groupId: group.id,
    );
  }

  void _loadGroups() {
    try {
      final file = File(MessengerCoordinator._getGroupsFilePath());
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final list = GroupModel.listFromJson(content);
        for (final g in list) {
          _groups[g.id] = g;
        }
      }
    } catch (e) {
      debugPrint('[Coordinator] Load groups error: $e');
    }
  }

  void _saveGroups() {
    try {
      final file = File(MessengerCoordinator._getGroupsFilePath());
      final json = GroupModel.listToJson(_groups.values.toList());
      file.writeAsStringSync(json);
    } catch (e) {
      debugPrint('[Coordinator] Save groups error: $e');
    }
  }

  File get _departureFile {
    final groups = File(MessengerCoordinator._getGroupsFilePath());
    return File(
      '${groups.parent.path}${Platform.pathSeparator}group_departures.json',
    );
  }

  void _loadDepartures() {
    try {
      final file = _departureFile;
      if (!file.existsSync()) return;
      final data = jsonDecode(file.readAsStringSync());
      if (data is! Map) return;
      _leftGroupIds.addAll(
        ((data['left'] as List?) ?? const []).map((e) => e.toString()),
      );
      _disbandedGroupIds.addAll(
        ((data['disbanded'] as List?) ?? const []).map((e) => e.toString()),
      );
      final times = data['leftAt'] as Map? ?? {};
      final members = data['leftMembers'] as Map? ?? {};
      for (final id in _leftGroupIds) {
        // Migrate old ID-only tombstones once; persist this cutoff below.
        _leftGroupAt[id] =
            DateTime.tryParse(times[id]?.toString() ?? '') ?? DateTime.now();
        if (members[id] is List) {
          _leftGroupMembers[id] = (members[id] as List).cast<String>().toSet();
        }
      }
      if (_leftGroupIds.any((id) => !times.containsKey(id))) _saveDepartures();
    } catch (e) {
      debugPrint('[Coordinator] Load group departures error: $e');
    }
  }

  void _saveDepartures() {
    try {
      _departureFile.writeAsStringSync(
        jsonEncode({
          'left': _leftGroupIds.toList(),
          'disbanded': _disbandedGroupIds.toList(),
          'leftAt': _leftGroupAt.map(
            (id, time) => MapEntry(id, time.toUtc().toIso8601String()),
          ),
          'leftMembers': _leftGroupMembers.map(
            (id, members) => MapEntry(id, members.toList()),
          ),
        }),
      );
    } catch (e) {
      debugPrint('[Coordinator] Save group departures error: $e');
    }
  }

  void _rememberLeftGroup(GroupModel group, DateTime eventTime) {
    final now = DateTime.now();
    _leftGroupIds.add(group.id);
    _leftGroupAt[group.id] = eventTime.isAfter(now) ? eventTime : now;
    _leftGroupMembers[group.id] = {
      for (final id in group.memberIds) ...[
        id,
        group.memberRecords[id]?[2] ?? _peerHashes[id] ?? id,
      ],
    };
  }

  void _sendDeparture(
    String groupId,
    String name,
    String endpoint, {
    bool removed = false,
    bool left = false,
    bool kicked = false,
  }) {
    _sendToPeer(
      endpoint,
      ProtocolBeebeep.buildGroupPacket(
        groupId: groupId,
        name: name,
        updatedAt: DateTime.now(),
        members: const [],
        removed: removed,
        left: left,
        kicked: kicked,
      ),
    );
  }

  Future<void> _createGroupImpl(
    String name,
    List<String> memberIds, {
    Color? color,
    String? avatarPreset,
    String? customAvatarPath,
  }) async {
    final id =
        'group_${_localUserHash.substring(0, 12)}_${DateTime.now().microsecondsSinceEpoch}';
    String? thumbnailBase64;
    if (customAvatarPath != null && customAvatarPath.isNotEmpty) {
      thumbnailBase64 = await AvatarUtils.generateAvatarThumbnailBase64(
        customAvatarPath,
      );
    }

    final group = GroupModel(
      id: id,
      name: name.trim(),
      memberIds: memberIds.where((id) => id != 'me').toSet().toList(),
      creatorId: _localUserHash,
      adminIds: [_localUserHash],
      color: color,
      avatarPreset: avatarPreset,
      customAvatarPath: customAvatarPath,
      customAvatarBase64: thumbnailBase64,
    );
    group.memberRecords = {
      for (final id in group.memberIds) id: _groupRecord(id, group),
    };
    group.invitations = {for (final id in group.memberIds) id: group.updatedAt};
    _groups[id] = group;
    _saveGroups();
    selectPeer(PeerModel.fromGroup(group));
    _syncGroup(group);
    _notify();
  }

  Future<void> _updateGroupAvatarImpl(
    String groupId, {
    Color? color,
    String? preset,
    String? customPath,
    String? customBase64,
  }) async {
    final group = _groups[groupId];
    if (group == null || !isGroupAdmin(groupId)) return;

    final hasNewFile = customPath != null && customPath.isNotEmpty;
    final hasRemoteImage = customBase64 != null && customBase64.isNotEmpty;
    String? thumbnailBase64;
    String? storedPath;
    String? storedPreset;
    if (hasNewFile) {
      thumbnailBase64 = await AvatarUtils.generateAvatarThumbnailBase64(
        customPath,
      );
      storedPath = customPath;
      storedPreset = null;
    } else if (hasRemoteImage) {
      thumbnailBase64 = customBase64;
      storedPath = null;
      storedPreset = null;
    } else {
      thumbnailBase64 = null;
      storedPath = null;
      storedPreset = preset;
    }

    // Image conversion yields: membership and roles may change while awaiting it.
    final current = _groups[groupId];
    if (current == null || !isGroupAdmin(groupId)) return;
    final updated = current.copyWith(
      color: color ?? current.color,
      avatarPreset: storedPreset,
      customAvatarPath: storedPath,
      customAvatarBase64: thumbnailBase64,
      updatedAt: DateTime.now(),
    );

    _groups[groupId] = updated;
    _saveGroups();
    if (_selectedPeer?.id == groupId) {
      _selectedPeer = PeerModel.fromGroup(updated);
    }
    _syncGroup(updated);
    _notify();
  }

  /// Đổi tên nhóm. Chỉ quản trị viên. Các máy khác nhận tên mới qua gói nhóm
  /// và tự ghi một dòng thông báo trong khung chat.
  void _renameGroupImpl(String groupId, String newName) {
    final group = _groups[groupId];
    final trimmed = newName.trim();
    if (group == null || trimmed.isEmpty || trimmed.length > 256) return;
    if (trimmed == group.name) return;
    if (!isGroupAdmin(groupId)) return;

    final oldName = group.name;
    final updated = group.copyWith(name: trimmed, updatedAt: DateTime.now());
    _groups[groupId] = updated;
    _appendGroupRenameNotice(
      updated,
      who: localUsername,
      oldName: oldName,
      newName: trimmed,
      messageId:
          'rename_${updated.id}_${updated.updatedAt.microsecondsSinceEpoch}',
    );
    _saveGroups();
    if (_selectedPeer?.id == groupId) {
      _selectedPeer = PeerModel.fromGroup(updated);
    }
    _syncGroup(updated);
    _notify();
  }

  void _appendGroupRenameNotice(
    GroupModel group, {
    required String who,
    required String oldName,
    required String newName,
    required String messageId,
  }) {
    _appendGroupNotice(
      group,
      messageId: messageId,
      localeKey: 'groupRenamedNotice',
      args: [who, oldName, newName],
      fallback: '$who đã đổi tên nhóm từ "$oldName" thành "$newName"',
    );
  }

  void _appendGroupNotice(
    GroupModel group, {
    required String messageId,
    required String localeKey,
    required List<String> args,
    required String fallback,
  }) {
    final list = _conversations.putIfAbsent(group.id, () => []);
    if (list.any((message) => message.id == messageId)) return;
    final notice = languageProvider?.tr(localeKey, args) ?? fallback;
    list.add(
      MessageModel(
        id: messageId,
        senderId: 'system',
        senderName: args.isEmpty ? '' : args.first,
        recipientId: group.id,
        text: notice,
        isMine: false,
        status: MessageStatus.delivered,
      ),
    );
    chatHistory.scheduleSave(group.id, list);
    group.lastMessage = notice;
    group.lastMessageTime = list.last.timestamp;
    group.unreadCount++;
  }

  String _groupMemberLabel(String memberId, GroupModel group) {
    if (memberId == 'me' || memberId == _localUserHash) return localUsername;
    final entry = group.memberRecords.entries
        .where((entry) => entry.value.elementAtOrNull(2) == memberId)
        .firstOrNull;
    if (entry != null) memberId = entry.key;
    final peer = _findPeerByIpOrId(memberId);
    if (peer != null && peer.name.trim().isNotEmpty) return peer.name;
    final recorded = group.memberRecords[memberId];
    if (recorded != null &&
        recorded.isNotEmpty &&
        recorded.first.trim().isNotEmpty) {
      return recorded.first;
    }
    return memberId;
  }

  String _groupMemberIdentity(String id, GroupModel group) => id == 'me'
      ? _localUserHash
      : group.memberRecords[id]?.elementAtOrNull(2) ?? _peerHashes[id] ?? id;

  Set<String> _groupAdminIdentities(GroupModel group) =>
      group.adminIds.map((id) => _groupMemberIdentity(id, group)).toSet();

  void _appendGroupRoleNotices(
    GroupModel previous,
    GroupModel next,
    String who,
  ) {
    final ownerChanged = previous.creatorId != next.creatorId;
    final before = _groupAdminIdentities(previous);
    final after = _groupAdminIdentities(next);
    for (final id in {
      ...before.difference(after),
      ...after.difference(before),
    }) {
      // Owner status is implicit; a transfer gets one dedicated notice.
      if (id == previous.creatorId || id == next.creatorId) continue;
      final promoted = after.contains(id);
      final label = _groupMemberLabel(id, next);
      _appendGroupNotice(
        previous,
        messageId:
            'admin_${next.id}_${id}_${next.updatedAt.microsecondsSinceEpoch}',
        localeKey: promoted
            ? 'groupAdminPromotedNotice'
            : 'groupAdminDemotedNotice',
        args: [who, label],
        fallback: promoted
            ? '$who đã chỉ định $label làm quản trị viên'
            : '$who đã gỡ quyền quản trị của $label',
      );
    }
    if (ownerChanged && next.creatorId != null) {
      final label = _groupMemberLabel(next.creatorId!, next);
      _appendGroupNotice(
        previous,
        messageId:
            'owner_${next.id}_${next.creatorId}_${next.updatedAt.microsecondsSinceEpoch}',
        localeKey: 'groupCreatorTransferredNotice',
        args: [who, label],
        fallback: '$who đã chuyển quyền người tạo cho $label',
      );
    }
  }

  /// Kiểm tra xem người dùng hiện tại có quyền quản trị viên (Admin/Creator) của nhóm không
  bool _isGroupAdminImpl(String groupId) {
    final group = _groups[groupId];
    if (group == null) return false;
    return group.isAdmin(_localUserHash);
  }

  /// Kiểm tra xem người dùng hiện tại có phải là người tạo nhóm (Creator) không
  bool _isGroupCreatorImpl(String groupId) {
    final group = _groups[groupId];
    if (group == null) return false;
    return group.isCreator(_localUserHash);
  }

  void _deleteGroupImpl(String groupId, {bool notifyPeers = true}) {
    final group = _groups[groupId];
    if (group != null) {
      if (notifyPeers) {
        if (!isGroupAdmin(groupId)) {
          debugPrint(
            '[Coordinator] Non-admin cannot disband group $groupId. Falling back to leaveGroup.',
          );
          leaveGroup(groupId);
          return;
        }
        _disbandedGroupIds.add(groupId);
        _leftGroupIds.remove(groupId);
        _leftGroupAt.remove(groupId);
        _leftGroupMembers.remove(groupId);
        _saveDepartures();
        for (final memberId in group.memberIds) {
          _sendDeparture(group.id, group.name, memberId, removed: true);
        }
      }
      _groups.remove(groupId);
      _groupTypingPeers.remove(groupId);
      _saveGroups();
      if (_selectedPeer?.id == groupId) {
        _selectedPeer = _allUsersPeer;
      }
      _notify();
    }
  }

  void _leaveGroupImpl(String groupId) {
    final group = _groups[groupId];
    if (group == null) return;
    _rememberLeftGroup(group, group.updatedAt);
    _disbandedGroupIds.remove(groupId);
    _saveDepartures();
    for (final memberId in group.memberIds) {
      _sendDeparture(group.id, group.name, memberId, left: true);
    }
    deleteGroup(groupId, notifyPeers: false);
  }

  void _addGroupMembersImpl(String groupId, List<String> newMemberIds) {
    final group = _groups[groupId];
    if (group == null || !isGroupAdmin(groupId)) return;
    final added = newMemberIds
        .where((id) => id != 'me' && !group.memberIds.contains(id))
        .toList();
    if (added.isEmpty) return;
    final updatedIds = {...group.memberIds, ...added}.toList();
    final updatedGroup = group.copyWith(
      memberIds: updatedIds,
      updatedAt: DateTime.now(),
    );
    updatedGroup.memberRecords = {
      for (final id in updatedIds) id: _groupRecord(id, group),
    };
    for (final id in updatedIds) {
      if (!group.memberIds.contains(id)) {
        updatedGroup.invitations[id] = updatedGroup.updatedAt;
      }
    }
    _groups[groupId] = updatedGroup;
    for (final id in added) {
      _appendGroupNotice(
        updatedGroup,
        messageId:
            'add_${groupId}_${id}_${updatedGroup.updatedAt.microsecondsSinceEpoch}',
        localeKey: 'groupMemberAddedNotice',
        args: [localUsername, _groupMemberLabel(id, updatedGroup)],
        fallback:
            '$localUsername đã thêm ${_groupMemberLabel(id, updatedGroup)} vào nhóm',
      );
    }
    _syncGroup(updatedGroup);
    _saveGroups();
    if (_selectedPeer?.id == groupId) {
      _selectedPeer = PeerModel.fromGroup(updatedGroup);
    }
    _notify();
  }

  void _removeGroupMemberImpl(String groupId, String memberId) {
    final group = _groups[groupId];
    if (group == null ||
        !isGroupAdmin(groupId) ||
        !group.memberIds.contains(memberId)) {
      return;
    }
    final memberIdentity =
        group.memberRecords[memberId]?[2] ?? _peerHashes[memberId] ?? memberId;
    if (group.isCreator(memberId) || group.isCreator(memberIdentity)) return;
    final memberName = _groupMemberLabel(memberId, group);
    final updatedIds = group.memberIds.where((id) => id != memberId).toList();
    final updatedGroup = group.copyWith(
      memberIds: updatedIds,
      updatedAt: DateTime.now(),
      invitations: Map.of(group.invitations)..remove(memberId),
    );
    _groups[groupId] = updatedGroup;
    _appendGroupNotice(
      updatedGroup,
      messageId:
          'remove_${groupId}_${memberId}_${updatedGroup.updatedAt.microsecondsSinceEpoch}',
      localeKey: 'groupMemberRemovedNotice',
      args: [localUsername, memberName],
      fallback: '$localUsername đã mời $memberName ra khỏi nhóm',
    );
    _sendDeparture(group.id, group.name, memberId, kicked: true);
    _syncGroup(updatedGroup);
    _saveGroups();
    if (_selectedPeer?.id == groupId) {
      _selectedPeer = PeerModel.fromGroup(updatedGroup);
    }
    _notify();
  }

  /// Chỉ người tạo mới chỉ định hoặc gỡ quản trị viên.
  void _setGroupAdminImpl(
    String groupId,
    String memberId, {
    required bool admin,
  }) {
    final group = _groups[groupId];
    if (group == null || !isGroupCreator(groupId)) return;
    if (!group.memberIds.contains(memberId)) return;
    final identity =
        group.memberRecords[memberId]?[2] ?? _peerHashes[memberId] ?? memberId;
    if (group.isCreator(memberId) || group.isCreator(identity)) return;
    final ids = _groupAdminIdentities(group).toList();
    if (admin) {
      if (ids.contains(identity)) return;
      ids.add(identity);
    } else if (!ids.remove(identity)) {
      return;
    }
    final updated = group.copyWith(adminIds: ids, updatedAt: DateTime.now());
    _groups[groupId] = updated;
    _appendGroupNotice(
      updated,
      messageId:
          'admin_${groupId}_${memberId}_${updated.updatedAt.microsecondsSinceEpoch}',
      localeKey: admin ? 'groupAdminPromotedNotice' : 'groupAdminDemotedNotice',
      args: [localUsername, _groupMemberLabel(memberId, updated)],
      fallback: admin
          ? '$localUsername đã chỉ định ${_groupMemberLabel(memberId, updated)} làm quản trị viên'
          : '$localUsername đã gỡ quyền quản trị của ${_groupMemberLabel(memberId, updated)}',
    );
    _saveGroups();
    _syncGroup(updated);
    if (_selectedPeer?.id == groupId) {
      _selectedPeer = PeerModel.fromGroup(updated);
    }
    _notify();
  }

  /// Chỉ người tạo mới chuyển quyền sở hữu. Người nhận trở thành người tạo.
  void _transferGroupCreatorImpl(String groupId, String memberId) {
    final group = _groups[groupId];
    if (group == null || !isGroupCreator(groupId)) return;
    if (!group.memberIds.contains(memberId)) return;
    final identity =
        group.memberRecords[memberId]?[2] ?? _peerHashes[memberId] ?? memberId;
    if (group.isCreator(memberId) || group.isCreator(identity)) return;
    final admins = {
      ..._groupAdminIdentities(group),
      _localUserHash,
      identity,
    }.toList();
    final updated = group.copyWith(
      creatorId: identity,
      adminIds: admins,
      updatedAt: DateTime.now(),
    );
    _groups[groupId] = updated;
    _appendGroupNotice(
      updated,
      messageId:
          'owner_${groupId}_${memberId}_${updated.updatedAt.microsecondsSinceEpoch}',
      localeKey: 'groupCreatorTransferredNotice',
      args: [localUsername, _groupMemberLabel(memberId, updated)],
      fallback:
          '$localUsername đã chuyển quyền người tạo cho ${_groupMemberLabel(memberId, updated)}',
    );
    _saveGroups();
    _syncGroup(updated);
    if (_selectedPeer?.id == groupId) {
      _selectedPeer = PeerModel.fromGroup(updated);
    }
    _notify();
  }
}
