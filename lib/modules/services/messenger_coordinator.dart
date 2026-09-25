import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import '../constants.dart';
import '../models/peer_model.dart';
import '../models/group_model.dart';
import '../models/message_model.dart';
import '../models/file_transfer_task.dart';
import '../network/lan_discovery.dart';
import '../network/network_utils.dart';
import '../network/lan_tcp_server.dart';
import '../network/file_transfer_engine.dart';
import '../network/protocol_beebeep.dart';
import '../network/security_service.dart';
import '../localization/app_locale.dart';
import '../models/ai_config_model.dart';
import 'ai_service.dart';
import 'ai_queue_manager.dart';
import 'app_preferences.dart';
import 'known_devices_registry.dart';
import 'peer_session_registry.dart';
import 'network_preferences.dart';
import 'chat_history_service.dart';
import 'clipboard_image.dart';
import 'ota_update_service.dart';
import '../utils/avatar_utils.dart';

class ToastData {
  final String key;
  final List<String> args;
  final String? rawText;

  const ToastData({required this.key, this.args = const [], this.rawText});

  String format(LanguageProvider lang) {
    if (rawText != null && rawText!.isNotEmpty) return rawText!;
    final base = lang.tr(key);
    if (args.isEmpty) return base;
    switch (key) {
      case 'toastNewDevice':
        return '$base ${args.join(' ')}';
      case 'toastScanDone':
        return '$base ${args.first} ${lang.tr('devicesOnline')}';
      case 'toastNudge':
        return '🔔 ${args.first} ${lang.tr('toastNudge')}';
      case 'toastPastingFiles':
        return '📁 ${lang.tr('pastingFiles')} (${args.first})';
      case 'updateAvailable':
        final rawVer = args.first.trim();
        final ver = rawVer.startsWith('v') ? rawVer : 'v$rawVer';
        return '🚀 ${lang.tr('updateAvailable', [ver])}';
      default:
        if (base.contains('%s') || base.contains('%d')) {
          return lang.tr(key, args);
        }
        return '$base ${args.join(' ')}'.trim();
    }
  }
}

class MessengerCoordinator extends ChangeNotifier {
  // Ngôn ngữ ứng dụng
  LanguageProvider? languageProvider;

  // Thông tin người dùng cục bộ
  String localUsername =
      AppPreferences().localNickname ?? _detectDefaultUsername();
  PeerStatus localStatus = PeerStatus.online;
  String localStatusDescription = 'Sẵn sàng';
  Color localColor = const Color(0xFF3B82F6);
  String localWorkgroup = 'General';
  int localTcpPort = defaultListenerPort;
  int localFilePort = defaultFileTransferPort;

  // Quản lý Peers, Kênh Toàn thể và Nhóm trò chuyện
  final Map<String, PeerModel> _peers = {};
  late final PeerSessionRegistry _peerSessions = PeerSessionRegistry(
    chatHistory.getStorageDirectory(),
  );
  final PeerModel _allUsersPeer = PeerModel.createAllUsersPeer();
  final PeerModel _aiPeer = PeerModel.createAiAssistantPeer();
  late final AiService aiService;
  late final AiQueueManager aiQueueManager;

  PeerModel get aiPeer => _aiPeer;
  bool get isAiActive => aiQueueManager.isBusy;
  int get aiQueueLength => aiQueueManager.queueLength;
  final Map<String, GroupModel> _groups = {};
  // Nhóm đã rời hoặc đã giải tán. Bản đồng bộ muộn không được tạo lại nhóm này.
  final Set<String> _leftGroupIds = {};
  final Map<String, DateTime> _leftGroupAt = {};
  final Map<String, Set<String>> _leftGroupMembers = {};
  final Set<String> _disbandedGroupIds = {};
  final Map<String, String> _peerHashes = {};
  final Map<String, List<MessageModel>> _conversations = {};
  // Hàng đợi tin nhắn ngoại tuyến chờ gửi lại khi peer online (Outbox Queue)
  final Map<String, Set<String>> _pendingOfflineMessageIds = {};
  final Set<String> _outboxInFlight = {};
  late final Future<void> historyLoaded;
  @visibleForTesting
  Map<String, Set<String>> get pendingOfflineMessageIds =>
      _pendingOfflineMessageIds;
  PeerModel? _selectedPeer;
  String _searchQuery = '';

  // Chế độ thu nhỏ (Compact Mode) & Ghim trên cùng (Always on Top)
  bool _isCompactMode = false;
  bool _isAlwaysOnTop = false;

  bool get isCompactMode => _isCompactMode;
  bool get isAlwaysOnTop => _isAlwaysOnTop;

  // Quản lý trạng thái đang gõ phím (typing)
  final Map<String, DateTime> _typingPeers = {};
  final Map<String, Map<String, DateTime>> _groupTypingPeers = {};
  Timer? _typingCleanupTimer;
  DateTime? _lastTypingSentTime;

  // Dịch vụ mạng Pure Dart
  final NetworkPreferences networkPreferences = NetworkPreferences();
  Future<void> saveNetworkAdapters(Set<String> disabled) async {
    await networkPreferences.save(disabled);
    _tcpServer.invalidatePendingConnections();
    await _discovery.updateDisabledAdapters(Set.of(disabled));
    // Đánh dấu offline các peer chỉ thuộc dải mạng của card đã bị tắt
    final enabledSubnets = _discovery.enabledAdapters
        .map((a) => a.subnet)
        .toList();
    for (final peer in _peers.values) {
      if (peer.isGroup || peer.isAllUsers) continue;
      final hasEnabledIp = peer.knownIps.any(
        (ip) => enabledSubnets.any(
          (subnet) => NetworkUtils.isIpInSubnet(ip, subnet),
        ),
      );
      if (!hasEnabledIp && enabledSubnets.isNotEmpty) {
        peer.status = PeerStatus.offline;
        peer.statusDescription = 'Ngoài dải card mạng đã chọn';
      }
    }
    notifyListeners();
  }

  final LanDiscoveryService _discovery = LanDiscoveryService();
  final LanTcpServer _tcpServer;
  final FileTransferEngine _fileEngine = FileTransferEngine();
  final SecurityService security = SecurityService();
  final KnownDevicesRegistry knownDevices;
  final ChatHistoryService chatHistory = ChatHistoryService();

  DateTime? _lastDiscoveryToastTime;
  bool _isActivelyRescanning = false;

  // Thông báo toast / rung chuông gần nhất
  ToastData? currentToast;
  String? get lastToastMessage => currentToast?.rawText;
  set lastToastMessage(String? msg) {
    if (msg == null) {
      currentToast = null;
    } else {
      currentToast = ToastData(key: '', rawText: msg);
    }
    notifyListeners();
  }

  void showToast(String key, [List<String> args = const []]) {
    currentToast = ToastData(key: key, args: args);
    notifyListeners();
  }

  void clearToast() {
    currentToast = null;
    notifyListeners();
  }

  // Quản lý cập nhật OTA
  UpdatePackageInfo? _availableUpdate;
  UpdatePackageInfo? get availableUpdate => _availableUpdate;

  void dismissAvailableUpdate() {
    _availableUpdate = null;
    notifyListeners();
  }

  @visibleForTesting
  void setAvailableUpdateForTesting(UpdatePackageInfo? update) {
    _availableUpdate = update;
    notifyListeners();
  }

  /// Kiểm tra cập nhật OTA tự động hoặc thủ công
  Future<UpdateCheckResult> checkOtaUpdates({bool isManual = false}) async {
    try {
      final prefs = AppPreferences();
      if (!isManual) {
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
      final result = await OtaUpdateService().checkForUpdates(
        isManual: isManual,
      );
      if (result.hasUpdate && result.packageInfo != null) {
        _availableUpdate = result.packageInfo;
        showToast('updateAvailable', [result.packageInfo!.version.toString()]);
        notifyListeners();
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

  DateTime? lastBuzzTime;
  int _buzzTriggerCount = 0;
  Timer? _buzzTopTimer;
  int _buzzGeneration = 0;
  bool _buzzShakeActive = false;
  int get buzzTriggerCount => _buzzTriggerCount;

  bool _isInitialized = false;
  bool _disposed = false;
  Timer? _livenessTimer;

  MessengerCoordinator({
    LanTcpServer? tcpServer,
    KnownDevicesRegistry? knownDevices,
  }) : _tcpServer = tcpServer ?? LanTcpServer(),
       knownDevices = knownDevices ?? KnownDevicesRegistry() {
    final prefs = AppPreferences();
    final colorHex = prefs.userAvatarColor.replaceFirst('#', '');
    try {
      final val = int.parse(
        colorHex.length == 6 ? 'FF$colorHex' : colorHex,
        radix: 16,
      );
      localColor = Color(val);
    } catch (_) {}
    _isCompactMode = prefs.isCompactMode;
    _isAlwaysOnTop = prefs.isAlwaysOnTop;
    aiService = AiService(serverUrl: prefs.aiServerUrl);
    aiQueueManager = AiQueueManager(aiService: aiService);
    _aiPeer.statusDescription = 'Sẵn sàng • ${prefs.aiSelectedModel}';
    _aiPeer.isPinned = prefs.isPeerPinned('__AI_ASSISTANT__');
    _allUsersPeer.isPinned = prefs.isPeerPinned('__ALL_USERS__');

    aiQueueManager.onQueueChanged = () {
      if (_disposed) return;
      if (aiQueueManager.isBusy) {
        _aiPeer.status = PeerStatus.away;
        _aiPeer.statusDescription = 'Đang xử lý (${prefs.aiSelectedModel})';
      } else if (aiQueueManager.queueLength > 0) {
        _aiPeer.status = PeerStatus.away;
        _aiPeer.statusDescription = 'Hàng đợi: ${aiQueueManager.queueLength}';
      } else {
        _aiPeer.status = prefs.aiEnabled
            ? PeerStatus.online
            : PeerStatus.offline;
        _aiPeer.statusDescription = prefs.aiEnabled
            ? 'Sẵn sàng • ${prefs.aiSelectedModel}'
            : 'Đã tắt tích hợp AI';
      }
      notifyListeners();
    };

    prefs.addListener(_onPrefsChanged);

    _fileEngine.onTransferUpdated = (task) {
      if (_disposed) return;
      for (final entry in _conversations.entries) {
        for (final message in entry.value) {
          if (message.id == 'file_${task.id}') {
            message.status = task.status == TransferStatus.completed
                ? MessageStatus.delivered
                : task.status == TransferStatus.failed ||
                      task.status == TransferStatus.cancelled
                ? MessageStatus.failed
                : MessageStatus.sending;
            if (task.status == TransferStatus.completed ||
                task.status == TransferStatus.failed ||
                task.status == TransferStatus.cancelled) {
              chatHistory.scheduleSave(entry.key, entry.value);
            }
          }
        }
      }
      if (!task.isUpload) {
        _handleIncomingFileCompleted(task);
      }
      notifyListeners();
    };
    _loadGroups();
    _loadDepartures();
    historyLoaded = _loadChatHistory();
  }

  void _onPrefsChanged() {
    if (_disposed) return;
    final prefs = AppPreferences();
    _isCompactMode = prefs.isCompactMode;
    _isAlwaysOnTop = prefs.isAlwaysOnTop;
    aiService.serverUrl = prefs.aiServerUrl;
    _aiPeer.isPinned = prefs.isPeerPinned('__AI_ASSISTANT__');
    _allUsersPeer.isPinned = prefs.isPeerPinned('__ALL_USERS__');
    for (final p in _peers.values) {
      p.isPinned = prefs.isPeerPinned(p.canonicalIdentity);
    }
    final colorHex = prefs.userAvatarColor.replaceFirst('#', '');
    try {
      final val = int.parse(
        colorHex.length == 6 ? 'FF$colorHex' : colorHex,
        radix: 16,
      );
      localColor = Color(val);
    } catch (_) {}
    if (!aiQueueManager.isBusy && aiQueueManager.queueLength == 0) {
      _aiPeer.status = prefs.aiEnabled ? PeerStatus.online : PeerStatus.offline;
      _aiPeer.statusDescription = prefs.aiEnabled
          ? 'Sẵn sàng • ${prefs.aiSelectedModel}'
          : 'Đã tắt tích hợp AI';
    }
    notifyListeners();
  }

  // Getters
  PeerModel get allUsersPeer => _allUsersPeer;
  List<GroupModel> get groups => _groups.values.toList();
  Map<String, GroupModel> get groupsMap => Map.unmodifiable(_groups);
  bool isGroup(String id) => _groups.containsKey(id);
  PeerModel getPeerForGroup(GroupModel group) => PeerModel.fromGroup(group);

  /// Stored member IDs are remote-only; the local user is implicit on each device.
  List<PeerModel> groupMembers(String groupId) {
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

  @visibleForTesting
  void handleGroupPacket(String endpoint, Map<String, dynamic> message) {
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
      notifyListeners();
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
    notifyListeners();
  }

  @visibleForTesting
  void handleGroupMessage(String endpoint, Map<String, dynamic> message) {
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

  /// Xác định định danh phần cứng/thiết bị chuẩn tắc để gộp kết nối và cuộc trò chuyện
  String _canonicalDeviceKey(PeerModel p) {
    if (p.isAiAssistant || p.isAllUsers || p.isGroup) return p.id;
    final identity =
        PeerSessionRegistry.identity(p) ?? _peerSessions.identities[p.id];
    if (identity != null) return identity;
    // Historical IPs are only a migration hint when exactly one identity owns it.
    final matches = knownDevices.devices.values
        .where(
          (d) =>
              d.id.contains('@') &&
              (d.knownIps.contains(p.ip) || d.lastIp == p.ip),
        )
        .map((d) => d.id.toLowerCase())
        .toSet();
    return matches.length == 1 ? matches.single : 'endpoint:${p.id}';
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
    // A history-only endpoint can acquire its first verified identity. Never
    // use IP overlap to merge two known, conflicting accounts/hosts.
    return a.id == b.id &&
        (!_peerSessions.identities.containsKey(a.id) || keyA == keyB);
  }

  /// Kiểm tra một peer có đang được chọn làm cuộc hội thoại hiện tại không
  bool isPeerSelected(PeerModel peer) {
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
          a.isPinned = a.isPinned || b.isPinned;

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
        }
      }
    }
  }

  List<PeerModel> get peers {
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
        // Giữ nguyên peer đang được chọn nếu có để UI không bị nhảy
        if (identical(existing, _selectedPeer)) {
          winner = existing;
        } else if (identical(p, _selectedPeer)) {
          winner = p;
        } else if (existing.status == PeerStatus.offline &&
            p.status != PeerStatus.offline) {
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

    if (_searchQuery.trim().isEmpty) return list;
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

  @visibleForTesting
  Map<String, PeerModel> get peersMap => _peers;

  @visibleForTesting
  Map<String, List<MessageModel>> get conversationsMap => _conversations;

  PeerModel? get selectedPeer => _selectedPeer;
  String get searchQuery => _searchQuery;

  List<MessageModel> get currentMessages {
    if (_selectedPeer == null) return const [];
    return _conversations[_selectedPeer!.id] ?? const [];
  }

  List<FileTransferTask> get fileTasks => _fileEngine.tasks;

  // Trạng thái quét mạng LAN thời gian thực
  DiscoveryScanState get scanState => _discovery.scanState;
  bool get isScanning => _discovery.scanState.isSweeping;
  double get scanProgress => _discovery.scanState.progress;
  String get scanStatus => _discovery.scanState.statusText;
  List<NetworkInterfaceDetails> get activeAdapters =>
      _discovery.availableAdapters;
  List<NetworkInterfaceDetails> get enabledAdapters =>
      _discovery.enabledAdapters;

  String getLocalizedScanStatus(LanguageProvider lang) {
    if (_discovery.scanState.isSweeping) {
      final percent = (_discovery.scanState.progress * 100).toInt();
      final subnets = _discovery.scanState.activeSubnets.isNotEmpty
          ? ' • ${_discovery.scanState.activeSubnets.join(', ')}'
          : '';
      if (_discovery.scanState.activePhase == 'subnet_sweep') {
        return _discovery.scanState.statusText;
      }
      return '${lang.tr('scanning')} ($percent%)$subnets';
    }
    final subnetSummary = _discovery.scanState.activeSubnets.isNotEmpty
        ? _discovery.scanState.activeSubnets.join(', ')
        : 'LAN';
    return '${lang.tr('realtimeListening')} • $subnetSummary';
  }

  void resetFilterAndSelectLatest() {
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
    notifyListeners();
  }

  int get totalUnreadCount {
    var count = _allUsersPeer.unreadCount;
    for (final p in peers) {
      count += p.unreadCount;
    }
    for (final g in _groups.values) {
      count += g.unreadCount;
    }
    return count;
  }

  void markAllAsRead() {
    _allUsersPeer.unreadCount = 0;
    _aiPeer.unreadCount = 0;
    for (final p in _peers.values) {
      p.unreadCount = 0;
    }
    for (final g in _groups.values) {
      g.unreadCount = 0;
    }
    _saveGroups();
    notifyListeners();
  }

  int get activeTransfersCount {
    return _fileEngine.tasks
        .where((t) => t.status == TransferStatus.transferring)
        .length;
  }

  static String detectDefaultUsername() {
    try {
      String username = 'User';
      String hostname = Platform.localHostname;
      if (Platform.isWindows) {
        username =
            Platform.environment['USERNAME'] ??
            Platform.environment['USER'] ??
            'User';
        hostname =
            Platform.environment['COMPUTERNAME'] ?? Platform.localHostname;
      } else {
        username = Platform.environment['USER'] ?? 'User';
      }
      if (hostname.isNotEmpty) {
        return '$username@$hostname';
      }
      return username;
    } catch (_) {
      return 'User@LAN';
    }
  }

  static String _detectDefaultUsername() => detectDefaultUsername();

  /// Chuyển đổi giữa chế độ chuẩn (Standard Mode) và chế độ thu nhỏ (Compact Mode)
  Future<void> toggleCompactMode() async {
    final prefs = AppPreferences();
    final targetMode = !_isCompactMode;
    _isCompactMode = targetMode;
    notifyListeners();

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
  Future<void> setAlwaysOnTop(bool value) async {
    _isAlwaysOnTop = value;
    notifyListeners();
    try {
      await windowManager.setAlwaysOnTop(value);
    } catch (e) {
      debugPrint('[AlwaysOnTop] Window manager error: $e');
    }
    await AppPreferences().setAlwaysOnTop(value);
  }

  /// Bật/tắt ghim trên cùng
  Future<void> toggleAlwaysOnTop() async {
    await setAlwaysOnTop(!_isAlwaysOnTop);
  }

  @visibleForTesting
  void setCompactModeForTesting(bool value) {
    _isCompactMode = value;
    notifyListeners();
  }

  @visibleForTesting
  void setAlwaysOnTopForTesting(bool value) {
    _isAlwaysOnTop = value;
    notifyListeners();
  }

  /// Khởi tạo toàn bộ dịch vụ mạng
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    if (_isAlwaysOnTop) {
      try {
        await windowManager.setAlwaysOnTop(true);
      } catch (_) {}
    }
    try {
      await networkPreferences.load();
    } catch (e) {
      debugPrint('Cannot load network preferences: $e');
    }
    _discovery.disabledAdapterNames = Set.of(networkPreferences.disabledNames);
    await migratePersonalAvatarIfNeeded();

    // 1. Khởi động TCP Server nhận tin nhắn (Port 6475, tự động fallback nếu bị chiếm)
    _tcpServer.helloBuilder = _buildHello;
    _tcpServer.passwordProvider = () =>
        security.isEncryptionEnabled ? security.password : '';
    _tcpServer.onUserStatus = (id, message) {
      final peer = _incomingPeer(id);
      if (_disposed || peer == null) return;
      peer.status = switch (message['data']) {
        '1' => PeerStatus.online,
        '2' => PeerStatus.busy,
        '3' => PeerStatus.away,
        _ => PeerStatus.offline,
      };
      peer.statusDescription = message['text'] as String;
      final session = _peerSessions.sessions[id];
      if (session != null) {
        session.remote.status = peer.status;
        session.remote.statusDescription = peer.statusDescription;
        _refreshLogicalPeer(peer);
      }
      peer.lastSeen = DateTime.now();
      notifyListeners();
    };
    _tcpServer.onAvatarUpdate = (id, avatarPayload) {
      final peer = _incomingPeer(id);
      if (_disposed || peer == null) return;
      _peerSessions.sessions[id]?.remote.updateAvatarFromRaw(avatarPayload);
      peer.updateAvatarFromRaw(avatarPayload);
      if (_peerSessions.forConversation(peer.id).isNotEmpty) {
        _refreshLogicalPeer(peer);
      }
      peer.lastSeen = DateTime.now();
      notifyListeners();
    };
    _tcpServer.onDisconnected = handlePeerDisconnected;
    _tcpServer.onActivity = (id) {
      _incomingPeer(id)?.lastSeen = DateTime.now();
    };
    _tcpServer.onHandshake = handlePeerHandshake;
    _tcpServer.onMessage = handleIncomingMessage;
    _tcpServer.onGroup = handleGroupPacket;
    _tcpServer.onGroupMessage = handleGroupMessage;
    _tcpServer.onAck = _handleMessageAck;
    _tcpServer.onBuzz = handleIncomingBuzz;
    _tcpServer.onTyping = _handleIncomingTyping;
    _tcpServer.onRead = _handleIncomingReadReceipt;
    _tcpServer.onRevoke = _handleIncomingRevoke;
    _tcpServer.onReaction = handleIncomingReaction;
    if (!await _tcpServer.start(port: localTcpPort)) {
      _isInitialized = false;
      throw StateError('Cannot start BeeBEEP listener');
    }
    localTcpPort = _tcpServer.port;

    // 2. Khởi động File Transfer Server (Port 6476, tự động fallback nếu bị chiếm)
    _fileEngine.helloBuilder = _buildHello;
    _fileEngine.passwordProvider = () =>
        security.isEncryptionEnabled ? security.password : '';
    _fileEngine.sendOffer = _tcpServer.send;
    _fileEngine.isPeerConnected = _tcpServer.isConnected;
    _tcpServer.onFile = (id, message) {
      final peer = _peers[id];
      if (peer != null) {
        unawaited(_fileEngine.receiveOffer(id, peer.ip, peer.name, message));
      }
    };
    await _fileEngine.startServer(port: localFilePort);
    localFilePort = _fileEngine.port;

    // 3. Khởi động UDP Discovery với cổng TCP thực tế
    _discovery.connectCandidate = (ip, port, sourceIp) => _tcpServer.connect(
      ip,
      port,
      sourceAddress: sourceIp,
      timeout: const Duration(milliseconds: 150),
    );
    await _discovery.start(
      localTcpPort: localTcpPort,
      onDiscovered: _handlePeerDiscovered,
      onScanState: (_) {
        if (!_disposed) notifyListeners();
      },
    );

    // Bắt đầu timer định kỳ làm sạch trạng thái peer không phản hồi (> 60s)
    _livenessTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _checkPeerLiveness(),
    );

    // Timer dọn dẹp trạng thái typing đã hết hạn (> 4s)
    _typingCleanupTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _checkTypingExpiry(),
    );

    // Tự động kiểm tra cập nhật OTA ngầm nếu đến hạn kỳ
    unawaited(checkOtaUpdates(isManual: false));

    notifyListeners();
  }

  /// Kích hoạt quét lại mạng LAN chủ động tức thì
  Future<void> rescanNetwork({Set<String>? adapterIps}) async {
    if (_isActivelyRescanning) return;
    _isActivelyRescanning = true;
    showToast('toastScanning');
    try {
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
    unawaited(_tcpServer.connect(ip, port));
  }

  /// Ảnh tùy chỉnh cũ chỉ lưu đường dẫn. Sinh Base64 một lần để HELLO gửi được ảnh.
  @visibleForTesting
  Future<void> migratePersonalAvatarIfNeeded() async {
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
  @visibleForTesting
  void handlePeerHandshake(
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

    final identityKey = candidate.canonicalIdentity;

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
          (remembered != null &&
              remembered != PeerSessionRegistry.identity(candidate));
      final id = conflict
          ? 'peer_${sha256.convert(utf8.encode(PeerSessionRegistry.identity(candidate) ?? endpoint))}'
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
    _peerSessions.remember(
      primaryPeer.id,
      PeerSessionRegistry.identity(candidate),
    );
    _peerSessions.sessions[endpoint] = PeerTransportSession(
      primaryPeer.id,
      candidate,
      data['hash'] as String? ?? '',
    );

    final now = DateTime.now();
    primaryPeer.isBeebeep = isBeebeepClient;
    primaryPeer.isPinned =
        AppPreferences().isPeerPinned(identityKey) || primaryPeer.isPinned;
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
    primaryPeer.knownIps.add(senderIp);
    primaryPeer.knownIps.addAll(candidate.knownIps);

    // Gộp tất cả peer trùng lặp khác vào primaryPeer và gộp lịch sử trò chuyện
    for (final other in matchingPeers) {
      if (identical(other, primaryPeer)) continue;
      primaryPeer.knownIps.addAll(other.knownIps);
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

    // Gộp hội thoại với endpoint hiện tại nếu có lịch sử riêng
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
              notifyListeners();
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
    _refreshLogicalPeer(peer);
    for (final group in _groups.values) {
      final oldIds = group.memberIds
          .where(
            (id) =>
                id != peer.id &&
                (id == 'hash:$userHash' ||
                    (userHash.isNotEmpty &&
                        group.memberRecords[id]?[2] == userHash)),
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
      username: username,
      ip: senderIp,
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

    notifyListeners();
  }

  @visibleForTesting
  static File? customGroupsFileForTesting;

  static String _getGroupsFilePath() {
    if (customGroupsFileForTesting != null) {
      return customGroupsFileForTesting!.path;
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory('$appData\\JA_LAN_Messenger');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return '${dir.path}\\groups.json';
    }
    return 'groups.json';
  }

  void _loadGroups() {
    try {
      final file = File(_getGroupsFilePath());
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
      final file = File(_getGroupsFilePath());
      final json = GroupModel.listToJson(_groups.values.toList());
      file.writeAsStringSync(json);
    } catch (e) {
      debugPrint('[Coordinator] Save groups error: $e');
    }
  }

  File get _departureFile {
    final groups = File(_getGroupsFilePath());
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
            // Khôi phục peer từ lịch sử để hiển thị trong danh bạ với tin nhắn gần nhất
            final p = PeerModel(
              id: convId,
              name:
                  (last.isMine ||
                      last.senderName == '???' ||
                      last.senderName.trim().isEmpty)
                  ? (convId.contains(':') ? convId.split(':').first : convId)
                  : last.senderName,
              ip: convId.contains(':') ? convId.split(':').first : convId,
              port: convId.contains(':')
                  ? int.tryParse(convId.split(':').last) ?? defaultListenerPort
                  : defaultListenerPort,
              status: PeerStatus.offline,
            );
            p.lastMessage = lastText;
            p.lastMessageTime = last.timestamp;
            p.isPinned = AppPreferences().isPeerPinned(p.canonicalIdentity);
            _peers[convId] = p;
          }
        }
      }

      // Khởi tạo hợp nhất các cuộc trò chuyện và thiết bị cùng máy vật lý từ lịch sử
      _consolidateLoadedPeersAndConversations();

      for (final peer in peers.where((p) => p.status != PeerStatus.offline)) {
        unawaited(flushPendingOutgoingMessagesForPeer(peer));
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[Coordinator] Load chat history error: $e');
    }
  }

  Future<void> createGroup(
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
    notifyListeners();
  }

  Future<void> updateGroupAvatar(
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
    notifyListeners();
  }

  /// Đổi tên nhóm. Chỉ quản trị viên. Các máy khác nhận tên mới qua gói nhóm
  /// và tự ghi một dòng thông báo trong khung chat.
  void renameGroup(String groupId, String newName) {
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
    notifyListeners();
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
    final isCurrentChat = _selectedPeer?.id == group.id;
    list.add(
      MessageModel(
        id: messageId,
        senderId: 'system',
        senderName: args.isEmpty ? '' : args.first,
        recipientId: group.id,
        text: notice,
        isMine: false,
        status: isCurrentChat ? MessageStatus.read : MessageStatus.delivered,
      ),
    );
    chatHistory.scheduleSave(group.id, list);
    group.lastMessage = notice;
    group.lastMessageTime = list.last.timestamp;
    if (!isCurrentChat) group.unreadCount++;
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
  bool isGroupAdmin(String groupId) {
    final group = _groups[groupId];
    if (group == null) return false;
    return group.isAdmin(_localUserHash);
  }

  /// Kiểm tra xem người dùng hiện tại có phải là người tạo nhóm (Creator) không
  bool isGroupCreator(String groupId) {
    final group = _groups[groupId];
    if (group == null) return false;
    return group.isCreator(_localUserHash);
  }

  void deleteGroup(String groupId, {bool notifyPeers = true}) {
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
      notifyListeners();
    }
  }

  void leaveGroup(String groupId) {
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

  void addGroupMembers(String groupId, List<String> newMemberIds) {
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
    notifyListeners();
  }

  void removeGroupMember(String groupId, String memberId) {
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
    notifyListeners();
  }

  /// Chỉ người tạo mới chỉ định hoặc gỡ quản trị viên.
  void setGroupAdmin(String groupId, String memberId, {required bool admin}) {
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
    notifyListeners();
  }

  /// Chỉ người tạo mới chuyển quyền sở hữu. Người nhận trở thành người tạo.
  void transferGroupCreator(String groupId, String memberId) {
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
    notifyListeners();
  }

  /// Tìm peer theo id, IP hiện tại hoặc bất kỳ IP nào trong knownIps
  PeerModel? _findPeerByIpOrId(String ipOrId) {
    if (_peers.containsKey(ipOrId)) return _peers[ipOrId];
    for (final p in _peers.values) {
      if (p.id == ipOrId || p.ip == ipOrId || p.knownIps.contains(ipOrId)) {
        return p;
      }
    }
    return null;
  }

  bool _sendToPeer(String endpoint, List<int> packet) {
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
              session.remote.status == PeerStatus.offline) {
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
    final byIp = _peerSessions.sessions.values
        .where((s) => s.remote.ip == endpoint && s.available)
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
        .where((s) => s.available && s.remote.status != PeerStatus.offline)
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

  @visibleForTesting
  void handlePeerDisconnected(String endpoint) {
    final session = _peerSessions.sessions[endpoint];
    if (session == null || _disposed) return;
    session.available = false;
    final peer = _peers[session.conversationId];
    if (peer != null) _refreshLogicalPeer(peer);
    notifyListeners();
  }

  /// Tách thông tin trích dẫn nếu tin nhắn mạng chứa format trích dẫn
  static ({String text, String? replySender, String? replyText}) _parseQuote(
    String raw,
  ) {
    if (raw.startsWith('> [') && raw.contains(']: ') && raw.contains('\n\n')) {
      final sepIndex = raw.indexOf('\n\n');
      final header = raw.substring(0, sepIndex);
      final body = raw.substring(sepIndex + 2);
      final match = RegExp(r'^> \[(.*?)\]: (.*)$').firstMatch(header);
      if (match != null) {
        return (
          text: body,
          replySender: match.group(1),
          replyText: match.group(2),
        );
      }
    }
    return (text: raw, replySender: null, replyText: null);
  }

  /// Xử lý tin nhắn văn bản nhận được
  @visibleForTesting
  void handleIncomingMessage(
    String senderIp,
    String messageId,
    String text,
    DateTime timestamp, {
    String? groupId,
  }) {
    final decryptedText = text;

    final senderPeer =
        _incomingPeer(senderIp) ??
        PeerModel(
          id: senderIp,
          name: senderIp,
          ip: senderIp,
          port: defaultListenerPort,
          knownIps: {senderIp},
        );
    _peers[senderPeer.id] = senderPeer;

    // Khi nhận tin nhắn, xóa trạng thái đang gõ phím của người này
    _typingPeers.remove(senderPeer.id);

    // 1. Kiểm tra tin nhắn toàn thể [All Users]
    if (groupId == null && decryptedText.startsWith('[All Users] ')) {
      final actualText = decryptedText.substring('[All Users] '.length);
      final quote = _parseQuote(actualText);
      final isCurrentChat = _selectedPeer?.id == '__ALL_USERS__';
      final msg = MessageModel(
        id: messageId,
        senderId: senderPeer.id,
        senderName: senderPeer.name,
        recipientId: '__ALL_USERS__',
        text: quote.text,
        timestamp: timestamp,
        isMine: false,
        status: isCurrentChat ? MessageStatus.read : MessageStatus.delivered,
        replyToSender: quote.replySender,
        replyToText: quote.replyText,
      );
      final list = _conversations.putIfAbsent('__ALL_USERS__', () => []);
      list.add(msg);
      chatHistory.scheduleSave('__ALL_USERS__', list);
      _allUsersPeer.lastMessage = '${senderPeer.name}: ${quote.text}';
      _allUsersPeer.lastMessageTime = timestamp;
      if (!isCurrentChat) {
        _allUsersPeer.unreadCount++;
      }
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
        final quote = _parseQuote(actualText);
        final isCurrentChat = _selectedPeer?.id == targetGroup.id;
        final msg = MessageModel(
          id: messageId,
          senderId: senderPeer.id,
          senderName: senderPeer.name,
          recipientId: targetGroup.id,
          text: quote.text,
          timestamp: timestamp,
          isMine: false,
          status: isCurrentChat ? MessageStatus.read : MessageStatus.delivered,
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
        if (!isCurrentChat) {
          targetGroup.unreadCount++;
        }
        _groupTypingPeers[targetGroup.id]?.remove(senderPeer.id);
        _saveGroups();
        notifyListeners();

        _showDesktopNotification(
          title: '[${targetGroup.name}] ${senderPeer.displayName}',
          body: quote.text,
          peer: PeerModel.fromGroup(targetGroup),
        );
      } else {
        // 3. Tin nhắn trò chuyện trực tiếp cá nhân
        final quote = _parseQuote(decryptedText);
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
          status: isCurrentChat ? MessageStatus.read : MessageStatus.delivered,
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

        if (!isCurrentChat) {
          senderPeer.unreadCount++;
        } else {
          // Gửi ngay tín hiệu đã xem (Read receipt) về phía gửi
          _tcpServer.send(
            _peerSessions.sessions.containsKey(senderIp)
                ? senderIp
                : senderPeer.id,
            ProtocolBeebeep.buildReadPacket(messageId),
          );
        }

        _showDesktopNotification(
          title: senderPeer.displayName,
          body: decryptedText,
          peer: senderPeer,
        );
      }
    }

    notifyListeners();
  }

  /// Xử lý gói tin ACK từ phía nhận
  void _handleMessageAck(String senderIp, String messageId) {
    final peer = _incomingPeer(senderIp);
    final convId = peer?.id ?? senderIp;
    final list = _conversations[convId];
    if (list != null) {
      for (final msg in list) {
        if (msg.id == messageId && msg.isMine) {
          if (msg.status != MessageStatus.read) {
            msg.status = MessageStatus.delivered;
            chatHistory.scheduleSave(convId, list);
          }
          notifyListeners();
          break;
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
        if (await windowManager.isMinimized()) {
          await windowManager.restore();
        }
        if (_isCompactMode) {
          await toggleCompactMode();
        }
        if (!await windowManager.isVisible()) {
          await windowManager.show();
        }
        await windowManager.focus();

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
  void triggerBuzzAlertForTesting() {
    lastBuzzTime = DateTime.now();
    _buzzTriggerCount++;
    unawaited(_triggerNativeBuzzAlert());
    notifyListeners();
  }

  /// Xử lý rung chuông Buzz
  @visibleForTesting
  void handleIncomingBuzz(String senderIp) {
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
    notifyListeners();
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
      notifyListeners();
    }
  }

  /// Kiểm tra xem đối phương có đang soạn tin nhắn hay không
  bool isPeerTyping(String peerId) {
    final time = _typingPeers[peerId];
    if (time == null) return false;
    return DateTime.now().difference(time).inSeconds < 4;
  }

  /// Kiểm tra xem có thành viên nào trong nhóm đang soạn tin nhắn hay không
  bool isGroupTyping(String groupId) {
    final map = _groupTypingPeers[groupId];
    if (map == null || map.isEmpty) return false;
    final now = DateTime.now();
    return map.values.any((t) => now.difference(t).inSeconds < 4);
  }

  /// Lấy chuỗi mô tả các thành viên đang soạn tin trong nhóm (chuẩn Zalo/Telegram)
  String? getGroupTypingText(String groupId, LanguageProvider lang) {
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

  @visibleForTesting
  void setPeerTypingForTesting(String peerId, bool isTyping) {
    if (isTyping) {
      _typingPeers[peerId] = DateTime.now();
    } else {
      _typingPeers.remove(peerId);
    }
    notifyListeners();
  }

  @visibleForTesting
  void setGroupTypingForTesting(
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
    notifyListeners();
  }

  /// Gửi tín hiệu đang soạn tin hoặc ngừng soạn tin tới peer hoặc nhóm đang chat
  void sendTypingStatus(bool isTyping) {
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
  void markConversationAsRead(String peerId) {
    final list = _conversations[peerId];
    var hadUnread = false;
    if (list != null && list.isNotEmpty) {
      for (final m in list) {
        if (!m.isMine && m.status != MessageStatus.read) {
          m.status = MessageStatus.read;
          hadUnread = true;
          if (peerId != '__ALL_USERS__' && !_groups.containsKey(peerId)) {
            _sendToPeer(peerId, ProtocolBeebeep.buildReadPacket(m.id));
          }
        }
      }
    }
    final peer = _peers[peerId];
    if (peer != null && peer.unreadCount > 0) {
      peer.unreadCount = 0;
      hadUnread = true;
    }
    if (peerId == '__ALL_USERS__' && _allUsersPeer.unreadCount > 0) {
      _allUsersPeer.unreadCount = 0;
      hadUnread = true;
    }
    final group = _groups[peerId];
    if (group != null && group.unreadCount > 0) {
      group.unreadCount = 0;
      hadUnread = true;
      _saveGroups();
    }
    if (hadUnread) {
      if (list != null) {
        chatHistory.scheduleSave(peerId, list);
      }
      notifyListeners();
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
    notifyListeners();
  }

  @visibleForTesting
  void simulateGroupTypingForTesting(
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
    notifyListeners();
  }

  /// Xử lý tín hiệu đã xem (read receipt) nhận được
  void _handleIncomingReadReceipt(String senderIp, String messageId) {
    if (_disposed) return;
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
      var found = false;
      for (int i = list.length - 1; i >= 0; i--) {
        final msg = list[i];
        if (msg.id == messageId && msg.isMine) {
          found = true;
        }
        if (found && msg.isMine && msg.status != MessageStatus.read) {
          msg.status = MessageStatus.read;
          updated = true;
        }
      }
      if (!found) {
        for (int i = list.length - 1; i >= 0; i--) {
          final msg = list[i];
          if (msg.isMine) {
            if (msg.status != MessageStatus.read) {
              msg.status = MessageStatus.read;
              updated = true;
            }
            break;
          }
        }
      }
      if (updated) {
        chatHistory.scheduleSave(peer.id, list);
        notifyListeners();
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
    if (found) notifyListeners();
  }

  /// Thả hoặc gỡ biểu tượng cảm xúc (Reaction) cho tin nhắn
  Future<void> toggleMessageReaction(
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
    chatHistory.scheduleSave(conversationId, messages);
    notifyListeners();

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
  @visibleForTesting
  void handleIncomingReaction(
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
      notifyListeners();
    }
  }

  /// Chủ động thu hồi một tin nhắn của bản thân
  Future<bool> revokeMessage(String messageId) async {
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
    notifyListeners();

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
    notifyListeners();
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
          if (await windowManager.isMinimized()) {
            await windowManager.restore();
          }
          await windowManager.show();
          await windowManager.focus();
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
          !_peerSessions
              .forConversation(p.id)
              .any((s) => s.available && _tcpServer.isConnected(s.endpoint)) &&
          !_tcpServer.isConnected(p.id) &&
          now.difference(p.lastSeen).inSeconds > 45) {
        p.status = PeerStatus.offline;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Map lưu trữ ID tin nhắn chưa đọc đầu tiên khi người dùng chọn cuộc trò chuyện
  final Map<String, String?> _initialUnreadMessageIds = {};

  /// Lấy ID tin nhắn chưa đọc đầu tiên được lưu tại thời điểm chọn cuộc trò chuyện
  String? getInitialUnreadMessageId(String peerId) =>
      _initialUnreadMessageIds[peerId];

  /// Xóa bộ nhớ đệm tin nhắn chưa đọc đầu tiên
  void clearInitialUnreadMessageId(String peerId) {
    _initialUnreadMessageIds.remove(peerId);
  }

  /// Trả về ID của tin nhắn chưa đọc đầu tiên trong cuộc trò chuyện (nếu có)
  String? getFirstUnreadMessageId(String peerId) {
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
  int countUnreadMessages(String peerId) {
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

  /// Chọn một cuộc trò chuyện
  void selectPeer(PeerModel? peer) {
    _selectedPeer = peer;
    if (peer != null) {
      final firstUnread = getFirstUnreadMessageId(peer.id);
      _initialUnreadMessageIds[peer.id] = firstUnread;
      peer.unreadCount = 0;
      if (peer.isAllUsers) {
        _allUsersPeer.unreadCount = 0;
      }
      // Giữ mốc tin chưa đọc cho dải phân cách, rồi xóa badge ngay khi mở hội thoại.
      markConversationAsRead(peer.id);
    }
    notifyListeners();
  }

  /// Tìm kiếm người dùng
  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  /// Gửi tin nhắn tới peer hoặc kênh đang chọn (hỗ trợ trích dẫn tin nhắn)
  Future<bool> sendMessage(String text, {MessageModel? replyTo}) async {
    await historyLoaded;
    if (_selectedPeer == null || text.trim().isEmpty) return false;

    // Kết thúc trạng thái đang soạn tin khi gửi tin nhắn
    sendTypingStatus(false);

    final msgId = '${DateTime.now().microsecondsSinceEpoch}';
    final plainText = text.trim();

    // Payload định dạng chuẩn gửi qua mạng để tương thích tất cả client
    final networkPayload = replyTo != null
        ? '> [${replyTo.senderName}]: ${replyTo.text.replaceAll('\n', ' ')}\n\n$plainText'
        : plainText;

    final msg = MessageModel(
      id: msgId,
      senderId: 'me',
      senderName: localUsername,
      recipientId: _selectedPeer!.id,
      text: plainText,
      isMine: true,
      status: MessageStatus.sending,
      pendingRecipients: {},
      replyToId: replyTo?.id,
      replyToSender: replyTo?.senderName,
      replyToText: replyTo?.text,
    );

    final list = _conversations.putIfAbsent(_selectedPeer!.id, () => []);
    list.add(msg);
    if (!_selectedPeer!.isAiAssistant) {
      final targets = _selectedPeer!.isGroup
          ? _selectedPeer!.memberIds
          : _selectedPeer!.isAllUsers
          ? peers
                .where(
                  (p) =>
                      p.status != PeerStatus.offline &&
                      !p.isGroup &&
                      !p.isAllUsers &&
                      !p.isAiAssistant,
                )
                .map((p) => p.id)
          : [_selectedPeer!.id];
      for (final target in targets) {
        recordPendingOfflineMessage(target, msgId);
      }
    }
    chatHistory.scheduleSave(_selectedPeer!.id, list);

    _selectedPeer!.lastMessage = plainText;
    _selectedPeer!.lastMessageTime = msg.timestamp;
    notifyListeners();

    if (_selectedPeer!.isAiAssistant) {
      msg.status = MessageStatus.sent;
      _dispatchAiResponse(plainText);
      return true;
    }

    if (_selectedPeer!.isAllUsers) {
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
      chatHistory.scheduleSave(_selectedPeer!.id, list);
      notifyListeners();
      return anySuccess;
    } else if (_selectedPeer!.isGroup) {
      // Gửi tới các thành viên trong nhóm
      var anySuccess = false;
      for (final memberId in _selectedPeer!.memberIds) {
        final peer = _peers[memberId] ?? _findPeerByIpOrId(memberId);
        var ok = false;
        if (peer != null && peer.status != PeerStatus.offline) {
          ok = _sendToPeer(
            peer.id,
            ProtocolBeebeep.buildChatPacket(
              messageId: msgId,
              text: networkPayload,
              groupId: _selectedPeer!.id,
              groupName: _selectedPeer!.name,
              groupUpdatedAt: _groups[_selectedPeer!.id]?.updatedAt,
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
      if (_groups.containsKey(_selectedPeer!.id)) {
        _groups[_selectedPeer!.id]!.lastMessage = plainText;
        _groups[_selectedPeer!.id]!.lastMessageTime = msg.timestamp;
        _saveGroups();
      }
      chatHistory.scheduleSave(_selectedPeer!.id, list);
      notifyListeners();
      return anySuccess;
    } else {
      // Gửi qua TCP tới peer cá nhân
      final success = _sendToPeer(
        _selectedPeer!.id,
        ProtocolBeebeep.buildChatPacket(messageId: msgId, text: networkPayload),
      );
      if (msg.status == MessageStatus.sending) {
        msg.status = success ? MessageStatus.sent : MessageStatus.failed;
      }
      if (!success) {
        recordPendingOfflineMessage(_selectedPeer!.id, msgId);
      } else {
        msg.pendingRecipients?.remove(_selectedPeer!.id);
        _removePendingOfflineMessage(_selectedPeer!.id, msgId);
      }
      chatHistory.scheduleSave(_selectedPeer!.id, list);
      notifyListeners();
      return success;
    }
  }

  /// Ghi nhận một tin nhắn vào Outbox chờ gửi lại khi peer online
  @visibleForTesting
  void recordPendingOfflineMessage(String targetKey, String messageId) {
    _pendingOfflineMessageIds.putIfAbsent(targetKey, () => {}).add(messageId);
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
      !msg.isRevoked &&
      msg.fileAttachment == null &&
      msg.recipientId != '__AI_ASSISTANT__';

  bool canRetryMessage(MessageModel msg) =>
      _isRetryableText(msg) && msg.status == MessageStatus.failed;

  void _removePendingOfflineMessage(String targetKey, String messageId) {
    _pendingOfflineMessageIds[targetKey]?.remove(messageId);
    if (_pendingOfflineMessageIds[targetKey]?.isEmpty ?? false) {
      _pendingOfflineMessageIds.remove(targetKey);
    }
  }

  /// Tự động gửi lại các tin nhắn tồn đọng trong Outbox khi một peer online
  @visibleForTesting
  Future<void> flushPendingOutgoingMessagesForPeer(PeerModel peer) async {
    await historyLoaded;
    if (_disposed) return;
    final candidateKeys = <String>{
      peer.id,
      peer.ip,
      '${peer.ip}:${peer.port}',
      peer.canonicalIdentity,
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
          if (msg.isMine &&
              _isRetryableText(msg) &&
              (msg.status == MessageStatus.failed ||
                  msg.status == MessageStatus.sending) &&
              collectedMsgIds.add(msg.id)) {
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
      if (!(msg.pendingRecipients?.any(candidateKeys.contains) ??
          (msg.status == MessageStatus.failed ||
              msg.status == MessageStatus.sending))) {
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
        notifyListeners();
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
  Future<bool> retrySendMessage(
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
        _findPeerByIpOrId(convId) == null &&
        _selectedPeer?.id != convId) {
      return false;
    }
    if (convId.startsWith('group_') && !_groups.containsKey(convId)) {
      return false;
    }

    msg.status = MessageStatus.sending;
    notifyListeners();

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
          if (!_tcpServer.isConnected(peer.id) && peer.ip.isNotEmpty) {
            await _tcpServer.connect(peer.ip, peer.port);
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
    notifyListeners();
    return success;
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
    notifyListeners();

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
      notifyListeners();
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
          notifyListeners();
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
        notifyListeners();
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
        notifyListeners();
      },
    );

    if (item == null) {
      aiMsg.status = MessageStatus.failed;
      aiMsg.isStreaming = false;
      aiMsg.text =
          '⚠️ Hàng đợi xử lý AI đang đầy (tối đa 4 lượt). Vui lòng đợi lượt trước hoàn tất.';
      showToast('aiQueueFull');
      chatHistory.saveImmediately(_aiPeer.id, list);
      notifyListeners();
    }
  }

  /// Dừng lượt tạo phản hồi AI đang thực thi
  void stopAiGeneration() {
    aiQueueManager.cancelActive();
    notifyListeners();
  }

  /// Xóa lịch sử hội thoại với Trợ lý AI
  void clearAiConversation() {
    _conversations.remove(_aiPeer.id);
    _aiPeer.lastMessage = null;
    _aiPeer.lastMessageTime = null;
    chatHistory.deleteConversation(_aiPeer.id);
    notifyListeners();
  }

  /// Yêu cầu AI tạo lại phản hồi cho tin nhắn đã có
  void regenerateAiResponse(String aiMessageId) {
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
    notifyListeners();

    _dispatchAiResponse(prompt);
  }

  /// Danh sách các model AI đang khả dụng (ưu tiên danh sách phát hiện động từ server)
  List<AiModelInfo> get availableAiModels => AiModelInfo.currentModels;

  /// Làm mới và đồng bộ danh sách model từ máy chủ Ollama
  Future<List<AiModelInfo>> refreshAiModels({String? customUrl}) async {
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
      notifyListeners();
    }
    return models;
  }

  /// Chọn model AI đang sử dụng
  Future<void> setAiModel(String modelId) async {
    await AppPreferences().setAiConfig(selectedModel: modelId);
    _aiPeer.statusDescription = 'Sẵn sàng • $modelId';
    notifyListeners();
  }

  /// Bật/Tắt chế độ suy nghĩ (Thinking)
  Future<void> setAiThinking(bool enabled) async {
    await AppPreferences().setAiConfig(thinkingEnabled: enabled);
    notifyListeners();
  }

  /// Gửi file đính kèm tới peer hoặc kênh đang chọn
  Future<void> sendFile(
    File file, {
    String? caption,
    PeerModel? recipient,
  }) async {
    final selected = recipient ?? _selectedPeer;
    if (selected == null) return;

    final hasCaption = caption != null && caption.trim().isNotEmpty;

    if (selected.isAiAssistant) {
      final isImg = isImageFile(file.path);
      final fileName = file.path.split(Platform.pathSeparator).last;
      final msgId = '';
      final plainText = hasCaption
          ? caption.trim()
          : (isImg
                ? 'Phân tích hình ảnh này giúp tôi.'
                : 'Xem tệp này: $fileName');
      final fileSize = await file.length();
      final msg = MessageModel(
        id: msgId,
        senderId: 'me',
        senderName: localUsername,
        recipientId: _aiPeer.id,
        text: plainText,
        isMine: true,
        status: MessageStatus.sent,
        fileAttachment: FileAttachmentInfo(
          fileName: fileName,
          fileSize: fileSize,
          localPath: file.path,
          isTransferComplete: true,
        ),
      );
      final list = _conversations.putIfAbsent(_aiPeer.id, () => []);
      list.add(msg);
      _aiPeer.lastMessage = hasCaption
          ? caption.trim()
          : (isImg ? '📷 [Ảnh] $fileName' : '📁 [Tệp] $fileName');
      _aiPeer.lastMessageTime = msg.timestamp;
      notifyListeners();

      List<String>? base64Images;
      if (isImg && await file.exists()) {
        try {
          final bytes = await file.readAsBytes();
          base64Images = [base64Encode(bytes)];
        } catch (_) {}
      }
      _dispatchAiResponse(plainText, images: base64Images);
      return;
    }

    final targets = selected.isAllUsers
        ? peers
              .where(
                (p) =>
                    !p.isGroup &&
                    !p.isAllUsers &&
                    p.status != PeerStatus.offline,
              )
              .toList()
        : selected.isGroup
        ? selected.memberIds
              .map((id) => _peers[id] ?? _findPeerByIpOrId(id))
              .whereType<PeerModel>()
              .where((p) => p.status != PeerStatus.offline)
              .toList()
        : [selected];
    if (targets.isEmpty) throw StateError('Không có người nhận trực tuyến');

    final isMultiRecipient = selected.isAllUsers || selected.isGroup;
    MessageModel? multiMsg;
    if (isMultiRecipient) {
      final fileName = file.path.split(Platform.pathSeparator).last;
      final fileSize = await file.length();
      final msgText = hasCaption ? caption.trim() : '📁 $fileName';
      multiMsg = MessageModel(
        id: 'file_multi_${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'me',
        senderName: localUsername,
        recipientId: selected.id,
        text: msgText,
        isMine: true,
        status: MessageStatus.sending,
        fileAttachment: FileAttachmentInfo(
          fileName: fileName,
          fileSize: fileSize,
          localPath: file.path,
          isTransferComplete: true,
        ),
      );
      _conversations.putIfAbsent(selected.id, () => []).add(multiMsg);
      chatHistory.scheduleSave(selected.id, _conversations[selected.id]!);
      selected.lastMessage = hasCaption
          ? caption.trim()
          : '📁 [${languageProvider?.tr('openFile') ?? 'Tệp'}] $fileName';
      selected.lastMessageTime = DateTime.now();
      if (selected.isGroup && _groups.containsKey(selected.id)) {
        _groups[selected.id]!.lastMessage = selected.lastMessage;
        _groups[selected.id]!.lastMessageTime = selected.lastMessageTime;
        _saveGroups();
      }
      notifyListeners();
    }

    var anySuccess = false;
    for (final peer in targets) {
      final expectedHash = selected.isGroup
          ? _groups[selected.id]?.memberRecords[peer.id]?.elementAtOrNull(2)
          : null;
      final routes = _peerSessions.forConversation(peer.id);
      final route = routes
          .where(
            (s) =>
                s.available &&
                s.remote.status != PeerStatus.offline &&
                (expectedHash == null ||
                    expectedHash == peer.id ||
                    s.hash == expectedHash),
          )
          .firstOrNull;
      if (route == null &&
          (routes.isNotEmpty ||
              _peerSessions.identities.containsKey(peer.id))) {
        throw StateError('Recipient session is offline');
      }
      final task = await _fileEngine.sendFile(
        peerId: route?.endpoint ?? peer.id,
        peerIp: route?.remote.ip ?? peer.ip,
        peerName: peer.name,
        file: file,
        groupId: selected.isGroup && !selected.isAllUsers ? selected.id : null,
      );
      if (_disposed) return;
      if (task.status != TransferStatus.failed) {
        anySuccess = true;
      }
      if (!isMultiRecipient) {
        final msgText = hasCaption
            ? caption.trim()
            : '📁 ${task.fileName} → ${peer.displayName}';
        final msg = MessageModel(
          id: 'file_${task.id}',
          senderId: 'me',
          senderName: localUsername,
          recipientId: selected.id,
          text: msgText,
          isMine: true,
          status: task.status == TransferStatus.failed
              ? MessageStatus.failed
              : MessageStatus.sending,
          fileAttachment: FileAttachmentInfo(
            fileName: task.fileName,
            fileSize: task.fileSize,
            localPath: file.path,
          ),
        );
        _conversations.putIfAbsent(selected.id, () => []).add(msg);
        chatHistory.scheduleSave(selected.id, _conversations[selected.id]!);
        selected.lastMessage = hasCaption
            ? caption.trim()
            : '📁 [${languageProvider?.tr('openFile') ?? 'Tệp'}] ${task.fileName}';
        selected.lastMessageTime = DateTime.now();
        notifyListeners();
        if (task.status == TransferStatus.failed) {
          throw StateError(task.errorMessage ?? 'Không gửi được tệp');
        }
      }
    }
    if (isMultiRecipient && multiMsg != null) {
      multiMsg.status = anySuccess ? MessageStatus.sent : MessageStatus.failed;
      notifyListeners();
    }
  }

  /// Gửi nhiều tệp cùng lúc kèm nội dung văn bản / chú thích
  Future<void> sendFiles(
    List<File> files, {
    String? text,
    MessageModel? replyTo,
  }) async {
    final selected = _selectedPeer;
    if (selected == null) return;

    final trimmedText = text?.trim();
    final hasText = trimmedText != null && trimmedText.isNotEmpty;

    if (files.isEmpty) {
      if (hasText) {
        await sendMessage(trimmedText, replyTo: replyTo);
      }
      return;
    }

    if (selected.isAiAssistant) {
      final base64Images = <String>[];
      for (final f in files) {
        if (isImageFile(f.path) && await f.exists()) {
          try {
            final bytes = await f.readAsBytes();
            base64Images.add(base64Encode(bytes));
          } catch (_) {}
        }
      }
      final plainText = hasText
          ? trimmedText
          : (base64Images.isNotEmpty
                ? 'Phân tích ${base64Images.length} hình ảnh này giúp tôi.'
                : 'Xem các tệp này.');

      for (int i = 0; i < files.length; i++) {
        final f = files[i];
        final fileName = f.path.split(Platform.pathSeparator).last;
        final fileSize = await f.length();
        final msg = MessageModel(
          id: 'ai_file_${DateTime.now().microsecondsSinceEpoch}_$i',
          senderId: 'me',
          senderName: localUsername,
          recipientId: _aiPeer.id,
          text: i == 0 ? plainText : '📁 $fileName',
          isMine: true,
          status: MessageStatus.sent,
          fileAttachment: FileAttachmentInfo(
            fileName: fileName,
            fileSize: fileSize,
            localPath: f.path,
            isTransferComplete: true,
          ),
        );
        _conversations.putIfAbsent(_aiPeer.id, () => []).add(msg);
      }
      _aiPeer.lastMessage = plainText;
      _aiPeer.lastMessageTime = DateTime.now();
      notifyListeners();
      _dispatchAiResponse(
        plainText,
        images: base64Images.isNotEmpty ? base64Images : null,
      );
      return;
    }

    if (hasText && replyTo != null) {
      await sendMessage(trimmedText, replyTo: replyTo);
      for (final file in files) {
        await sendFile(file, recipient: selected);
      }
    } else if (hasText) {
      await sendFile(files.first, caption: trimmedText, recipient: selected);
      for (int i = 1; i < files.length; i++) {
        await sendFile(files[i], recipient: selected);
      }
    } else {
      for (final file in files) {
        await sendFile(file, recipient: selected);
      }
    }
  }

  /// Trích xuất danh sách tệp hoặc ảnh chụp màn hình từ Clipboard mà không gửi ngay
  Future<List<File>> getClipboardAttachments() async {
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
  Future<bool> pasteFromClipboard() async {
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
  Future<void> sendBuzz() async {
    if (_selectedPeer == null) return;
    final targetPeer = _selectedPeer!;
    final conversationId = targetPeer.id;
    final targetName = targetPeer.displayName;

    if (targetPeer.isAllUsers) {
      for (final p in _peers.values.toSet().where(
        (p) => p.status != PeerStatus.offline,
      )) {
        _sendToPeer(
          p.id,
          ProtocolBeebeep.packet(
            ProtocolBeebeep.headerBuzz,
            '22',
            text: '*',
            flags: 1,
          ),
        );
      }
    } else if (targetPeer.isGroup) {
      for (final memberId in targetPeer.memberIds) {
        final p = _peers[memberId];
        if (p != null && p.status != PeerStatus.offline) {
          _sendToPeer(
            p.id,
            ProtocolBeebeep.packet(
              ProtocolBeebeep.headerBuzz,
              '22',
              text: '*',
              flags: 1,
            ),
          );
        }
      }
    } else {
      _sendToPeer(
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
      status: MessageStatus.delivered,
    );
    final messages = _conversations.putIfAbsent(conversationId, () => []);
    messages.add(message);
    chatHistory.scheduleSave(conversationId, messages);
    targetPeer.lastMessage = sentText;
    targetPeer.lastMessageTime = message.timestamp;
    notifyListeners();
  }

  /// Quét lại toàn bộ mạng LAN
  void refreshPeers() {
    _discovery.sendBroadcastAnnounce();
  }

  /// Cập nhật trạng thái hiển thị của bản thân
  Future<void> updateProfile({
    String? username,
    PeerStatus? status,
    String? statusDesc,
    Color? color,
    String? workgroup,
  }) async {
    if (username != null && username.trim().isNotEmpty) {
      localUsername = username.trim();
      notifyListeners();
      await AppPreferences().setLocalNickname(localUsername);
      if (_disposed) return;
    }
    if (status != null) localStatus = status;
    if (statusDesc != null) localStatusDescription = statusDesc;
    if (color != null) localColor = color;
    if (workgroup != null) localWorkgroup = workgroup;

    // Renegotiate identity/password instead of changing an authenticated session.
    _tcpServer.closeConnections();
    _discovery.sendBroadcastAnnounce();
    notifyListeners();
  }

  /// Cập nhật ảnh đại diện / màu sắc người dùng và thông báo cho toàn mạng LAN
  Future<void> updateUserAvatar({
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

    notifyListeners();
  }

  /// Thêm thủ công một địa chỉ IP (cho máy khác lớp mạng hoặc VPN)
  void addManualPeer(String ip, [int port = defaultListenerPort]) {
    _handlePeerDiscovered(ip, port);
  }

  /// Ghim / bỏ ghim cuộc trò chuyện
  void togglePinPeer(String peerId) {
    if (peerId == '__ALL_USERS__') {
      _allUsersPeer.isPinned = !_allUsersPeer.isPinned;
      AppPreferences().setPeerPinned('__ALL_USERS__', _allUsersPeer.isPinned);
      notifyListeners();
      return;
    }
    if (peerId == '__AI_ASSISTANT__') {
      _aiPeer.isPinned = !_aiPeer.isPinned;
      AppPreferences().setPeerPinned('__AI_ASSISTANT__', _aiPeer.isPinned);
      notifyListeners();
      return;
    }
    final peer = _peers[peerId];
    if (peer != null) {
      peer.isPinned = !peer.isPinned;
      AppPreferences().setPeerPinned(peer.canonicalIdentity, peer.isPinned);
      notifyListeners();
    }
  }

  /// Ghim hoặc bỏ ghim tin nhắn trong cuộc hội thoại
  void togglePinMessage(String conversationId, String messageId) {
    final list = _conversations[conversationId];
    if (list == null || list.isEmpty) return;
    final index = list.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final msg = list[index];
    msg.isPinned = !msg.isPinned;
    chatHistory.scheduleSave(conversationId, list);
    notifyListeners();
  }

  /// Lấy danh sách tin nhắn đã ghim của cuộc hội thoại
  List<MessageModel> getPinnedMessages(String conversationId) {
    final list = _conversations[conversationId];
    if (list == null) return const [];
    return list.where((m) => m.isPinned && !m.isRevoked).toList();
  }

  /// Bật / tắt thông báo cuộc trò chuyện
  void toggleMutePeer(String peerId) {
    if (peerId == '__ALL_USERS__') {
      _allUsersPeer.isMuted = !_allUsersPeer.isMuted;
      notifyListeners();
      return;
    }
    final peer = _peers[peerId];
    if (peer != null) {
      peer.isMuted = !peer.isMuted;
      notifyListeners();
    }
  }

  /// Đặt biệt danh cho liên hệ
  void setPeerNickname(String peerId, String? nickname) {
    final peer = _peers[peerId];
    if (peer != null) {
      peer.customNickname = (nickname != null && nickname.trim().isNotEmpty)
          ? nickname.trim()
          : null;
      notifyListeners();
    }
  }

  /// Xóa toàn bộ lịch sử tin nhắn của cuộc trò chuyện
  void clearConversation(String peerId) {
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
    notifyListeners();
  }

  /// Xóa toàn bộ lịch sử tin nhắn của tất cả cuộc trò chuyện
  Future<void> clearAllChatHistory() async {
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
    notifyListeners();
  }

  /// Kiểm tra tên tệp hoặc đường dẫn có phải là ảnh
  static bool isImageFile(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp') ||
        lower.endsWith('.ico');
  }

  /// Lấy danh sách tin nhắn chứa hình ảnh / video của cuộc trò chuyện
  List<MessageModel> getMediaMessages(String peerId) {
    final list = _conversations[peerId] ?? const [];
    return list
        .where(
          (m) =>
              m.hasAttachment &&
              m.fileAttachment != null &&
              isImageFile(m.fileAttachment!.fileName),
        )
        .toList();
  }

  /// Lấy danh sách tin nhắn chứa tài liệu / tệp tin khác của cuộc trò chuyện
  List<MessageModel> getFileMessages(String peerId) {
    final list = _conversations[peerId] ?? const [];
    return list
        .where(
          (m) =>
              m.hasAttachment &&
              m.fileAttachment != null &&
              !isImageFile(m.fileAttachment!.fileName),
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

  @visibleForTesting
  void receiveFileForTesting(FileTransferTask task) {
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
    final preview = isImageFile(task.fileName)
        ? '📷 [Ảnh] ${task.fileName}'
        : '📁 [Tệp] ${task.fileName}';

    final msg = MessageModel(
      id: 'file_${task.id}',
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
      if (_selectedPeer?.id != group.id) {
        group.unreadCount++;
      }
      _saveGroups();
    } else {
      senderPeer.lastMessage = preview;
      senderPeer.lastMessageTime = DateTime.now();
      if (_selectedPeer?.id != senderPeer.id) {
        senderPeer.unreadCount++;
      }
    }

    if (completed) {
      _showDesktopNotification(
        title: '📁 ${task.fileName}',
        body: 'Đã nhận thành công từ ${senderPeer.displayName}',
        peer: group == null ? senderPeer : PeerModel.fromGroup(group),
      );
    }
  }

  Future<void> flushHistoryBeforeExit() async {
    aiQueueManager.clearQueue();
    for (final entry in _conversations.entries) {
      await chatHistory.saveImmediately(entry.key, entry.value);
    }
    await chatHistory.flush();
  }

  @override
  void dispose() {
    _buzzTopTimer?.cancel();
    if (_buzzTopTimer != null && !_isAlwaysOnTop) {
      unawaited(windowManager.setAlwaysOnTop(false).catchError((Object _) {}));
    }
    _disposed = true;
    _livenessTimer?.cancel();
    _typingCleanupTimer?.cancel();
    chatHistory.cancelAll();
    _discovery.stop();
    _tcpServer.stop();
    _fileEngine.stop();
    AppPreferences().removeListener(_onPrefsChanged);
    aiQueueManager.dispose();
    super.dispose();
  }
}
