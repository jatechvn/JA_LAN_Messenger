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
import 'ai_server_locator.dart';
import 'app_power_manager.dart';
import 'ai_queue_manager.dart';
import 'app_preferences.dart';
import 'known_devices_registry.dart';
import 'peer_session_registry.dart';
import 'network_preferences.dart';
import 'chat_history_service.dart';
import 'clipboard_image.dart';
import 'ota_update_service.dart';
import 'winrm_launcher_service.dart';
import '../utils/avatar_utils.dart';

part 'coordinator/coordinator_groups_part.dart';
part 'coordinator/coordinator_presence_and_nic_part.dart';
part 'coordinator/coordinator_messaging_part.dart';
part 'coordinator/coordinator_outbox_part.dart';
part 'coordinator/coordinator_ai_and_ota_part.dart';
part 'coordinator/coordinator_files_and_contacts_part.dart';

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
        if (base.contains('%s') ||
            base.contains('%d') ||
            base.contains('{0}')) {
          return lang.tr(key, args);
        }
        return '$base ${args.join(' ')}'.trim();
    }
  }
}

/// Mục tiêu chờ tự động gửi Buzz sau khi đối phương khởi động app qua WinRM
class PendingBuzzTarget {
  final String peerId;
  final String canonicalIdentity;
  final String? hostname;
  final String? accountName;
  final String targetIp;
  final DateTime createdAt;

  const PendingBuzzTarget({
    required this.peerId,
    required this.canonicalIdentity,
    this.hostname,
    this.accountName,
    required this.targetIp,
    required this.createdAt,
  });

  /// Kiểm tra xem một peer vừa handshake có thực sự khớp với máy đích đã gửi lệnh WinRM không
  bool matches(PeerModel peer, String senderIp) {
    // 1. Phải khớp canonicalIdentity
    if (peer.canonicalIdentity != canonicalIdentity) {
      return false;
    }

    // 2. Nếu máy đích có hostname: Tên máy (hostname) của peer bắt buộc phải trùng khớp
    final targetHost = hostname?.trim().toLowerCase();
    final peerHost = peer.hostname?.trim().toLowerCase();
    if (targetHost == null ||
        targetHost.isEmpty ||
        targetHost == '???' ||
        targetHost == 'localhost') {
      return false;
    }
    if (peerHost != targetHost) {
      return false;
    }

    // 3. Nếu máy đích có accountName: Tên tài khoản người dùng phải trùng khớp
    final targetAccount = accountName?.trim().toLowerCase();
    final peerAccount = peer.accountName?.trim().toLowerCase();
    if (targetAccount != null &&
        targetAccount.isNotEmpty &&
        targetAccount != '???') {
      if (peerAccount != targetAccount) {
        return false;
      }
    }

    // 4. IP kiểm tra: senderIp hoặc peer.ip hoặc knownIps phải chứa targetIp mà lệnh WinRM đã gọi tới
    // Ngăn chặn trường hợp địa chỉ IP được cấp lại (DHCP reuse) cho một thiết bị khác trên mạng LAN
    final isMatchingIp =
        (senderIp == targetIp) ||
        (peer.ip == targetIp) ||
        peer.knownIps.contains(targetIp);
    if (!isMatchingIp) {
      return false;
    }

    return true;
  }
}

enum ManualAddStatus { success, alreadyExists, ownIp, unreachable, invalidIp }

class ManualPeerResult {
  final ManualAddStatus status;
  final PeerModel? peer;
  final String ip;
  final String? message;

  const ManualPeerResult({
    required this.status,
    this.peer,
    required this.ip,
    this.message,
  });

  bool get isSuccess => status == ManualAddStatus.success;
  bool get isAlreadyExists => status == ManualAddStatus.alreadyExists;
  bool get isOwnIp => status == ManualAddStatus.ownIp;
  bool get isUnreachable => status == ManualAddStatus.unreachable;
  bool get isInvalidIp => status == ManualAddStatus.invalidIp;
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

  // Khởi động từ xa qua WinRM & Rung chuông tự động
  WinrmLauncherService winrmLauncher = const WinrmLauncherService();
  final List<PendingBuzzTarget> _pendingBuzzTargets = [];

  @visibleForTesting
  set winrmLauncherForTesting(WinrmLauncherService launcher) {
    winrmLauncher = launcher;
  }

  @visibleForTesting
  Set<String> get pendingBuzzPeersForTesting =>
      _pendingBuzzTargets.map((t) => t.canonicalIdentity).toSet();

  @visibleForTesting
  List<PendingBuzzTarget> get pendingBuzzTargetsForTesting =>
      List.unmodifiable(_pendingBuzzTargets);

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

  final LanDiscoveryService _discovery;
  final LanTcpServer _tcpServer;
  final FileTransferEngine _fileEngine = FileTransferEngine();
  int _lastAttachmentBatchId = 0;
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

  // Trạng thái nội bộ & test hooks (phục vụ các extension part trong thư viện)
  final Map<String, DateTime> _newlyAddedPeers = {};
  final Map<String, String?> _initialUnreadMessageIds = {};
  int _reactionRevision = 0;
  final Map<String, String> _drafts = {};
  int _chatFocusRequestId = 0;
  int _sidebarSearchFocusRequestId = 0;
  int _chatSearchFocusRequestId = 0;
  int _lastGeneratedMessageId = 0;
  bool _probingKnownPeers = false;
  Future<bool>? _aiRecovery;
  DateTime? _lastAiRecovery;
  String? _lastAiRecoveryContext;

  @visibleForTesting
  bool Function(String endpoint, List<int> packet)? sendToPeerForTesting;

  @visibleForTesting
  Future<List<String>> Function(String hostname)? hostnameResolverForTesting;

  void _notify() => notifyListeners();

  DateTime? lastBuzzTime;
  int _buzzTriggerCount = 0;
  Timer? _buzzTopTimer;
  int _buzzGeneration = 0;
  bool _buzzShakeActive = false;
  int get buzzTriggerCount => _buzzTriggerCount;

  bool _isInitialized = false;
  bool _disposed = false;
  final AiServerLocator _aiLocator;
  Timer? _livenessTimer;
  Timer? _otaCheckTimer;
  Timer? _outboxRetryTimer;
  bool _outboxRetryRunning = false;
  final Duration outboxRetryInterval;

  MessengerCoordinator({
    LanDiscoveryService? discovery,
    this.outboxRetryInterval = const Duration(seconds: 5),
    LanTcpServer? tcpServer,
    KnownDevicesRegistry? knownDevices,
    AiServerLocator? aiServerLocator,
  }) : _discovery = discovery ?? LanDiscoveryService(),
       _tcpServer = tcpServer ?? LanTcpServer(),
       _aiLocator = aiServerLocator ?? AiServerLocator(),
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
    aiService.recoverConnection = _recoverAiConnection;
    aiQueueManager = AiQueueManager(aiService: aiService);
    _aiPeer.statusDescription = 'Sẵn sàng • ${prefs.aiSelectedModel}';
    _aiPeer.isPinned = prefs.isPeerPinned('__AI_ASSISTANT__');
    _allUsersPeer.isPinned = prefs.isPeerPinned('__ALL_USERS__');

    _tcpServer.onDisconnected = handlePeerDisconnected;
    _tcpServer.onActivity = handlePeerActivity;
    _tcpServer.onUserStatus = handlePeerStatus;
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
            final status = task.status == TransferStatus.completed
                ? MessageStatus.delivered
                : task.status == TransferStatus.failed ||
                      task.status == TransferStatus.cancelled
                ? MessageStatus.failed
                : MessageStatus.sending;
            if (message.status != MessageStatus.read) message.status = status;
            if (task.status == TransferStatus.completed ||
                task.status == TransferStatus.failed ||
                task.status == TransferStatus.cancelled) {
              chatHistory.scheduleSave(entry.key, entry.value);
            }
          }
          if (task.isUpload) {
            final recipient = message.attachmentTransfers.entries
                .where((e) => e.value == task.id)
                .firstOrNull;
            if (recipient != null) {
              message.updateAttachmentRecipient(
                recipient.key,
                task.status == TransferStatus.completed
                    ? MessageStatus.delivered
                    : task.status == TransferStatus.failed ||
                          task.status == TransferStatus.cancelled
                    ? MessageStatus.failed
                    : MessageStatus.sending,
              );
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

  // Keep public members on the class: extensions alone cannot preserve
  // virtual callbacks, super calls, or dynamic invocation.
  // Public instance API: coordinator_ai_and_ota_part.dart.
  void dismissAvailableUpdate() => _dismissAvailableUpdateImpl();

  @visibleForTesting
  void setAvailableUpdateForTesting(UpdatePackageInfo? update) =>
      _setAvailableUpdateForTestingImpl(update);

  /// Kiểm tra cập nhật OTA tự động hoặc thủ công
  Future<UpdateCheckResult> checkOtaUpdates({
    bool isManual = false,
    bool isStartup = false,
  }) => _checkOtaUpdatesImpl(isManual: isManual, isStartup: isStartup);

  /// Dừng lượt tạo phản hồi AI đang thực thi
  void stopAiGeneration() => _stopAiGenerationImpl();

  /// Xóa lịch sử hội thoại với Trợ lý AI
  void clearAiConversation() => _clearAiConversationImpl();

  /// Yêu cầu AI tạo lại phản hồi cho tin nhắn đã có
  void regenerateAiResponse(String aiMessageId) =>
      _regenerateAiResponseImpl(aiMessageId);

  /// Danh sách các model AI đang khả dụng (ưu tiên danh sách phát hiện động từ server)
  List<AiModelInfo> get availableAiModels => _availableAiModelsImpl;

  Future<List<AiModelInfo>> refreshAiModels({String? customUrl}) =>
      _refreshAiModelsImpl(customUrl: customUrl);

  /// Chọn model AI đang sử dụng
  Future<void> setAiModel(String modelId) => _setAiModelImpl(modelId);

  /// Bật/Tắt chế độ suy nghĩ (Thinking)
  Future<void> setAiThinking(bool enabled) => _setAiThinkingImpl(enabled);

  // Public instance API: coordinator_files_and_contacts_part.dart.
  /// Trích xuất danh sách tệp hoặc ảnh chụp màn hình từ Clipboard mà không gửi ngay
  Future<List<File>> getClipboardAttachments() =>
      _getClipboardAttachmentsImpl();

  /// Dán hình ảnh hoặc tệp tin trực tiếp từ Clipboard (hỗ trợ gửi ngay khi cần)
  Future<bool> pasteFromClipboard() => _pasteFromClipboardImpl();

  /// Gửi rung chuông Buzz
  Future<void> sendBuzz() => _sendBuzzImpl();

  /// Quét lại toàn bộ mạng LAN
  void refreshPeers() => _refreshPeersImpl();

  /// Cập nhật trạng thái hiển thị của bản thân
  Future<void> updateProfile({
    String? username,
    PeerStatus? status,
    String? statusDesc,
    Color? color,
    String? workgroup,
  }) => _updateProfileImpl(
    username: username,
    status: status,
    statusDesc: statusDesc,
    color: color,
    workgroup: workgroup,
  );

  /// Cập nhật ảnh đại diện / màu sắc người dùng và thông báo cho toàn mạng LAN
  Future<void> updateUserAvatar({
    String? type,
    String? preset,
    String? customPath,
    Color? color,
  }) => _updateUserAvatarImpl(
    type: type,
    preset: preset,
    customPath: customPath,
    color: color,
  );

  /// Thêm thủ công một địa chỉ IP (cho máy khác lớp mạng hoặc VPN)
  Future<ManualPeerResult> addManualPeer(
    String ip, [
    int port = defaultListenerPort,
  ]) => _addManualPeerImpl(ip, port);

  Future<ManualPeerResult> addManualEndpoint(String ip, int port) =>
      _addManualEndpointImpl(ip, port);

  /// Lưu một liên hệ thủ công ngoại tuyến vào danh bạ (khi chưa kết nối được)
  PeerModel addOfflineManualPeer(String ip, [int port = defaultListenerPort]) =>
      _addOfflineManualPeerImpl(ip, port);

  /// Ghim / bỏ ghim cuộc trò chuyện
  void togglePinPeer(String peerId) => _togglePinPeerImpl(peerId);

  /// Ghim hoặc bỏ ghim tin nhắn trong cuộc hội thoại
  void togglePinMessage(String conversationId, String messageId) =>
      _togglePinMessageImpl(conversationId, messageId);

  /// Lấy danh sách tin nhắn đã ghim của cuộc hội thoại
  List<MessageModel> getPinnedMessages(String conversationId) =>
      _getPinnedMessagesImpl(conversationId);

  /// Bật / tắt thông báo cuộc trò chuyện
  void toggleMutePeer(String peerId) => _toggleMutePeerImpl(peerId);

  /// Đặt biệt danh cho liên hệ (hoặc đổi tên nhóm nếu là group ID)
  void setPeerNickname(String peerId, String? nickname) =>
      _setPeerNicknameImpl(peerId, nickname);

  /// Xóa toàn bộ lịch sử tin nhắn của cuộc trò chuyện
  void clearConversation(String peerId) => _clearConversationImpl(peerId);

  /// Xóa toàn bộ lịch sử tin nhắn của tất cả cuộc trò chuyện
  Future<void> clearAllChatHistory() => _clearAllChatHistoryImpl();

  /// Lấy danh sách tin nhắn chứa hình ảnh / video của cuộc trò chuyện
  List<MessageModel> getMediaMessages(String peerId) =>
      _getMediaMessagesImpl(peerId);

  /// Lấy danh sách tin nhắn chứa tài liệu / tệp tin khác của cuộc trò chuyện
  List<MessageModel> getFileMessages(String peerId) =>
      _getFileMessagesImpl(peerId);

  @visibleForTesting
  void receiveFileForTesting(FileTransferTask task) =>
      _receiveFileForTestingImpl(task);

  // Public instance API: coordinator_groups_part.dart.
  /// Stored member IDs are remote-only; the local user is implicit on each device.
  List<PeerModel> groupMembers(String groupId) => _groupMembersImpl(groupId);

  @visibleForTesting
  void handleGroupPacket(String endpoint, Map<String, dynamic> message) =>
      _handleGroupPacketImpl(endpoint, message);

  @visibleForTesting
  void handleGroupMessage(String endpoint, Map<String, dynamic> message) =>
      _handleGroupMessageImpl(endpoint, message);

  Future<void> createGroup(
    String name,
    List<String> memberIds, {
    Color? color,
    String? avatarPreset,
    String? customAvatarPath,
  }) => _createGroupImpl(
    name,
    memberIds,
    color: color,
    avatarPreset: avatarPreset,
    customAvatarPath: customAvatarPath,
  );

  Future<void> updateGroupAvatar(
    String groupId, {
    Color? color,
    String? preset,
    String? customPath,
    String? customBase64,
  }) => _updateGroupAvatarImpl(
    groupId,
    color: color,
    preset: preset,
    customPath: customPath,
    customBase64: customBase64,
  );

  /// Đổi tên nhóm. Chỉ quản trị viên. Các máy khác nhận tên mới qua gói nhóm
  /// và tự ghi một dòng thông báo trong khung chat.
  void renameGroup(String groupId, String newName) =>
      _renameGroupImpl(groupId, newName);

  /// Kiểm tra xem người dùng hiện tại có quyền quản trị viên (Admin/Creator) của nhóm không
  bool isGroupAdmin(String groupId) => _isGroupAdminImpl(groupId);

  /// Kiểm tra xem người dùng hiện tại có phải là người tạo nhóm (Creator) không
  bool isGroupCreator(String groupId) => _isGroupCreatorImpl(groupId);

  void deleteGroup(String groupId, {bool notifyPeers = true}) =>
      _deleteGroupImpl(groupId, notifyPeers: notifyPeers);

  void leaveGroup(String groupId) => _leaveGroupImpl(groupId);

  void addGroupMembers(String groupId, List<String> newMemberIds) =>
      _addGroupMembersImpl(groupId, newMemberIds);

  void removeGroupMember(String groupId, String memberId) =>
      _removeGroupMemberImpl(groupId, memberId);

  /// Chỉ người tạo mới chỉ định hoặc gỡ quản trị viên.
  void setGroupAdmin(String groupId, String memberId, {required bool admin}) =>
      _setGroupAdminImpl(groupId, memberId, admin: admin);

  /// Chỉ người tạo mới chuyển quyền sở hữu. Người nhận trở thành người tạo.
  void transferGroupCreator(String groupId, String memberId) =>
      _transferGroupCreatorImpl(groupId, memberId);

  // Public instance API: coordinator_messaging_part.dart.
  /// Xử lý tin nhắn văn bản nhận được
  @visibleForTesting
  void handleIncomingMessage(
    String senderIp,
    String messageId,
    String text,
    DateTime timestamp, {
    String? groupId,
  }) => _handleIncomingMessageImpl(
    senderIp,
    messageId,
    text,
    timestamp,
    groupId: groupId,
  );

  /// Kích hoạt cảnh báo Buzz cục bộ (dành cho kiểm thử hoặc xem trước hiệu ứng)
  Future<void> triggerBuzzAlertForTesting() =>
      _triggerBuzzAlertForTestingImpl();

  /// Xử lý rung chuông Buzz
  @visibleForTesting
  void handleIncomingBuzz(String senderIp) => _handleIncomingBuzzImpl(senderIp);

  /// Kiểm tra xem đối phương có đang soạn tin nhắn hay không
  bool isPeerTyping(String peerId) => _isPeerTypingImpl(peerId);

  /// Kiểm tra xem có thành viên nào trong nhóm đang soạn tin nhắn hay không
  bool isGroupTyping(String groupId) => _isGroupTypingImpl(groupId);

  /// Lấy chuỗi mô tả các thành viên đang soạn tin trong nhóm (chuẩn Zalo/Telegram)
  String? getGroupTypingText(String groupId, LanguageProvider lang) =>
      _getGroupTypingTextImpl(groupId, lang);

  @visibleForTesting
  void setPeerTypingForTesting(String peerId, bool isTyping) =>
      _setPeerTypingForTestingImpl(peerId, isTyping);

  @visibleForTesting
  void setGroupTypingForTesting(
    String groupId,
    String memberId,
    bool isTyping,
  ) => _setGroupTypingForTestingImpl(groupId, memberId, isTyping);

  /// Gửi tín hiệu đang soạn tin hoặc ngừng soạn tin tới peer hoặc nhóm đang chat
  void sendTypingStatus(bool isTyping) => _sendTypingStatusImpl(isTyping);

  /// Đánh dấu toàn bộ tin nhắn trong cuộc trò chuyện là đã đọc
  void markConversationAsRead(String peerId) =>
      _markConversationAsReadImpl(peerId);

  /// Called only for individually observed messages, or explicit mark-read actions.
  void markMessagesAsRead(String peerId, Set<MessageModel> visibleMessages) =>
      _markMessagesAsReadImpl(peerId, visibleMessages);

  @visibleForTesting
  void simulateGroupTypingForTesting(
    String groupId,
    String memberId,
    String memberName,
    bool isTyping,
  ) => _simulateGroupTypingForTestingImpl(
    groupId,
    memberId,
    memberName,
    isTyping,
  );

  /// Thả hoặc gỡ biểu tượng cảm xúc (Reaction) cho tin nhắn
  Future<void> toggleMessageReaction(
    String conversationId,
    String messageId,
    String emoji,
  ) => _toggleMessageReactionImpl(conversationId, messageId, emoji);

  /// Tiếp nhận cập nhật cảm xúc tin nhắn từ đồng nghiệp qua mạng LAN
  @visibleForTesting
  void handleIncomingReaction(
    String endpoint,
    String messageId,
    String emoji,
    String action,
    String senderName,
  ) => _handleIncomingReactionImpl(
    endpoint,
    messageId,
    emoji,
    action,
    senderName,
  );

  /// Chủ động thu hồi một tin nhắn của bản thân
  Future<bool> revokeMessage(String messageId) => _revokeMessageImpl(messageId);

  /// Lấy ID tin nhắn chưa đọc đầu tiên được lưu tại thời điểm chọn cuộc trò chuyện
  String? getInitialUnreadMessageId(String peerId) =>
      _getInitialUnreadMessageIdImpl(peerId);

  /// Xóa bộ nhớ đệm tin nhắn chưa đọc đầu tiên
  void clearInitialUnreadMessageId(String peerId) =>
      _clearInitialUnreadMessageIdImpl(peerId);

  /// Trả về ID của tin nhắn chưa đọc đầu tiên trong cuộc trò chuyện (nếu có)
  String? getFirstUnreadMessageId(String peerId) =>
      _getFirstUnreadMessageIdImpl(peerId);

  /// Trả về số lượng tin nhắn chưa đọc trong cuộc trò chuyện
  int countUnreadMessages(String peerId) => _countUnreadMessagesImpl(peerId);

  int get reactionRevision => _reactionRevisionImpl;

  /// Lấy nội dung bản nháp đang gõ dở của một cuộc trò chuyện
  String getDraft(String peerId) => _getDraftImpl(peerId);

  /// Kiểm tra cuộc trò chuyện có bản nháp khác rỗng hay không
  bool hasDraft(String peerId) => _hasDraftImpl(peerId);

  /// Lưu hoặc xóa bản nháp của cuộc trò chuyện (chỉ notify khi trạng thái có/không nháp thay đổi hoặc khi được yêu cầu)
  void setDraft(String peerId, String text, {bool notify = false}) =>
      _setDraftImpl(peerId, text, notify: notify);

  int get chatFocusRequestId => _chatFocusRequestIdImpl;

  int get sidebarSearchFocusRequestId => _sidebarSearchFocusRequestIdImpl;

  int get chatSearchFocusRequestId => _chatSearchFocusRequestIdImpl;

  /// Yêu cầu focus con trỏ vào ô nhập tin nhắn
  void requestChatInputFocus() => _requestChatInputFocusImpl();

  /// Yêu cầu focus vào ô tìm kiếm liên hệ/nhóm ở Sidebar (Ctrl+K)
  void requestSidebarSearchFocus() => _requestSidebarSearchFocusImpl();

  /// Yêu cầu mở và focus vào thanh tìm kiếm tin nhắn trong hội thoại (Ctrl+F)
  void requestChatSearchFocus() => _requestChatSearchFocusImpl();

  /// Chuyển đổi nhanh sang cuộc trò chuyện liền kề (Alt+Up / Alt+Down)
  void selectAdjacentPeer(int offset) => _selectAdjacentPeerImpl(offset);

  /// Chọn một cuộc trò chuyện
  void selectPeer(PeerModel? peer) => _selectPeerImpl(peer);

  /// Tìm kiếm người dùng
  void setSearchQuery(String query) => _setSearchQueryImpl(query);

  /// Chuyển tiếp tin nhắn (văn bản, nhãn dán hoặc tệp đính kèm) tới danh sách người nhận/nhóm
  Future<int> forwardMessageToPeers(
    MessageModel sourceMessage,
    List<PeerModel> recipients, {
    String? note,
  }) => _forwardMessageToPeersImpl(sourceMessage, recipients, note: note);

  /// Gửi tin nhắn tới peer hoặc kênh đang chọn (hỗ trợ trích dẫn tin nhắn và chỉ định người nhận)
  Future<bool> sendMessage(
    String text, {
    MessageModel? replyTo,
    PeerModel? recipient,
  }) => _sendMessageImpl(text, replyTo: replyTo, recipient: recipient);

  // Public instance API: coordinator_outbox_part.dart.
  /// Ghi nhận một tin nhắn vào Outbox chờ gửi lại khi peer online
  @visibleForTesting
  void recordPendingOfflineMessage(String targetKey, String messageId) =>
      _recordPendingOfflineMessageImpl(targetKey, messageId);

  bool canRetryMessage(MessageModel msg) => _canRetryMessageImpl(msg);

  /// Tự động gửi lại các tin nhắn tồn đọng trong Outbox khi một peer online
  @visibleForTesting
  Future<void> flushPendingOutgoingMessagesForPeer(PeerModel peer) =>
      _flushPendingOutgoingMessagesForPeerImpl(peer);

  /// Thử gửi lại một tin nhắn bị lỗi (thủ công từ UI hoặc gọi trực tiếp)
  Future<bool> retrySendMessage(MessageModel msg, {String? conversationId}) =>
      _retrySendMessageImpl(msg, conversationId: conversationId);

  // Public instance API: coordinator_presence_and_nic_part.dart.
  Future<void> saveNetworkAdapters(Set<String> disabled) =>
      _saveNetworkAdaptersImpl(disabled);

  /// Kiểm tra một peer có đang được chọn làm cuộc hội thoại hiện tại không
  bool isPeerSelected(PeerModel peer) => _isPeerSelectedImpl(peer);

  /// Same presence rule as the Online tab, including away/busy peers.
  /// Uses the deduplicated, search-filtered contact list (including enabled AI).
  List<PeerModel> get onlinePeers => _onlinePeersImpl;

  List<PeerModel> get peers => _peersImpl;

  @visibleForTesting
  Map<String, PeerModel> get peersMap => _peersMapImpl;

  @visibleForTesting
  Map<String, List<MessageModel>> get conversationsMap => _conversationsMapImpl;

  PeerModel? get selectedPeer => _selectedPeerImpl;

  String get searchQuery => _searchQueryImpl;

  List<MessageModel> get currentMessages => _currentMessagesImpl;

  List<FileTransferTask> get fileTasks => _fileTasksImpl;

  DiscoveryScanState get scanState => _scanStateImpl;

  bool get isScanning => _isScanningImpl;

  double get scanProgress => _scanProgressImpl;

  String get scanStatus => _scanStatusImpl;

  List<NetworkInterfaceDetails> get activeAdapters => _activeAdaptersImpl;

  List<NetworkInterfaceDetails> get enabledAdapters => _enabledAdaptersImpl;

  /// Gợi ý các tiền tố 2 số đầu tiên (ví dụ 172.21. hoặc 192.168.) dựa trên các card mạng đang dùng
  List<String> get suggestedIpPrefixes => _suggestedIpPrefixesImpl;

  bool isNewlyAddedPeer(String peerId) => _isNewlyAddedPeerImpl(peerId);

  void markNewlyAddedPeer(String peerId) => _markNewlyAddedPeerImpl(peerId);

  void dismissNewlyAddedPeer(String peerId) =>
      _dismissNewlyAddedPeerImpl(peerId);

  String getLocalizedScanStatus(LanguageProvider lang) =>
      _getLocalizedScanStatusImpl(lang);

  void resetFilterAndSelectLatest() => _resetFilterAndSelectLatestImpl();

  int get totalUnreadCount => _totalUnreadCountImpl;

  void markAllAsRead() => _markAllAsReadImpl();

  int get activeTransfersCount => _activeTransfersCountImpl;

  /// Chuyển đổi giữa chế độ chuẩn (Standard Mode) và chế độ thu nhỏ (Compact Mode)
  Future<void> toggleCompactMode() => _toggleCompactModeImpl();

  /// Cài đặt ghim cửa sổ trên cùng (Always on Top)
  Future<void> setAlwaysOnTop(bool value) => _setAlwaysOnTopImpl(value);

  /// Bật/tắt ghim trên cùng
  Future<void> toggleAlwaysOnTop() => _toggleAlwaysOnTopImpl();

  @visibleForTesting
  void setCompactModeForTesting(bool value) =>
      _setCompactModeForTestingImpl(value);

  @visibleForTesting
  void setAlwaysOnTopForTesting(bool value) =>
      _setAlwaysOnTopForTestingImpl(value);

  /// Kích hoạt quét lại mạng LAN chủ động tức thì
  Future<void> rescanNetwork({Set<String>? adapterIps}) =>
      _rescanNetworkImpl(adapterIps: adapterIps);

  /// Ảnh tùy chỉnh cũ chỉ lưu đường dẫn. Sinh Base64 một lần để HELLO gửi được ảnh.
  @visibleForTesting
  Future<void> migratePersonalAvatarIfNeeded() =>
      _migratePersonalAvatarIfNeededImpl();

  /// Xử lý khi nhận được gói tin BEE-CIAO từ peer
  @visibleForTesting
  void handlePeerHandshake(
    String senderIp,
    Map<String, dynamic> data,
    Socket socket,
  ) => _handlePeerHandshakeImpl(senderIp, data, socket);

  @visibleForTesting
  void triggerPendingBuzzIfNeededForTesting(PeerModel peer, String senderIp) =>
      _triggerPendingBuzzIfNeededForTestingImpl(peer, senderIp);

  @visibleForTesting
  Future<void> probeKnownAndRestoredPeersForTesting() =>
      _probeKnownAndRestoredPeersForTestingImpl();

  @visibleForTesting
  void handlePeerStatus(String endpoint, Map<String, dynamic> message) =>
      _handlePeerStatusImpl(endpoint, message);

  @visibleForTesting
  void handlePeerActivity(String endpoint) => _handlePeerActivityImpl(endpoint);

  @visibleForTesting
  void handlePeerDisconnected(String endpoint) =>
      _handlePeerDisconnectedImpl(endpoint);

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
    _tcpServer.onUserStatus = handlePeerStatus;
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
    _tcpServer.onActivity = handlePeerActivity;
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
      final peer = _incomingPeer(id) ?? _peers[id];
      if (peer != null) {
        final sessionIp = _peerSessions.sessions[id]?.remote.ip;
        final resolvedIp = (sessionIp != null && sessionIp.isNotEmpty)
            ? sessionIp
            : (peer.ip.isNotEmpty
                  ? peer.ip
                  : (id.contains(':') ? id.split(':').first : id));
        unawaited(_fileEngine.receiveOffer(id, resolvedIp, peer.name, message));
      }
    };
    await _fileEngine.startServer(port: localFilePort);
    localFilePort = _fileEngine.port;

    // 3. Khởi động UDP Discovery với cổng TCP thực tế
    _discovery.connectCandidate = (ip, port, sourceIp) => _connectPeer(
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

    // Chủ động thăm dò TCP trực tiếp tới các thiết bị/liên hệ đã biết ngay khi khởi động
    unawaited(_probeKnownAndRestoredPeers());
    unawaited(historyLoaded.then((_) => _probeKnownAndRestoredPeers()));

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

    // Tự động kiểm tra cập nhật OTA ngay khi khởi động và định kỳ mỗi 30 phút (nếu không tắt)
    unawaited(checkOtaUpdates(isManual: false, isStartup: true));
    _otaCheckTimer?.cancel();
    _otaCheckTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => unawaited(checkOtaUpdates(isManual: false, isStartup: true)),
    );

    notifyListeners();
  }

  /// Gửi file đính kèm tới peer hoặc kênh đang chọn
  Future<void> sendFile(
    File file, {
    String? caption,
    PeerModel? recipient,
    String? attachmentBatchId,
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
        attachmentBatchId: attachmentBatchId,
        id: 'file_multi_${DateTime.now().microsecondsSinceEpoch}',
        senderId: 'me',
        senderName: localUsername,
        recipientId: selected.id,
        text: msgText,
        isMine: true,
        status: MessageStatus.sending,
        attachmentTransfers: {for (final target in targets) target.id: ''},
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
        attachmentBatchId: attachmentBatchId,
      );
      if (_disposed) return;
      if (multiMsg != null) {
        multiMsg.attachmentTransfers[peer.id] = task.id;
        multiMsg.updateAttachmentRecipient(
          peer.id,
          task.status == TransferStatus.failed
              ? MessageStatus.failed
              : MessageStatus.sending,
        );
      }
      if (task.status != TransferStatus.failed) {
        anySuccess = true;
      }
      if (!isMultiRecipient) {
        final msgText = hasCaption
            ? caption.trim()
            : '📁 ${task.fileName} → ${peer.displayName}';
        final msg = MessageModel(
          attachmentBatchId: attachmentBatchId,
          id: 'file_${task.id}',
          attachmentTransfers: {peer.id: task.id},
          attachmentRecipientStatuses: {
            peer.id: task.status == TransferStatus.failed
                ? MessageStatus.failed
                : MessageStatus.sending,
          },
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
      if (!anySuccess) multiMsg.status = MessageStatus.failed;
      chatHistory.scheduleSave(selected.id, _conversations[selected.id]!);
      notifyListeners();
      if (!anySuccess) throw StateError('No file offer was accepted');
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
    final now = DateTime.now().microsecondsSinceEpoch;
    _lastAttachmentBatchId = now > _lastAttachmentBatchId
        ? now
        : _lastAttachmentBatchId + 1;
    final batchId = files.length > 1 ? 'batch_$_lastAttachmentBatchId' : null;

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
          attachmentBatchId: batchId,
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
      chatHistory.scheduleSave(_aiPeer.id, _conversations[_aiPeer.id]!);
      notifyListeners();
      _dispatchAiResponse(
        plainText,
        images: base64Images.isNotEmpty ? base64Images : null,
      );
      return;
    }

    if (hasText && replyTo != null) {
      await sendMessage(trimmedText, replyTo: replyTo);
    }
    var failedCount = 0;
    for (var i = 0; i < files.length; i++) {
      if (_disposed) return;
      final before = Set<MessageModel>.of(_conversations[selected.id] ?? []);
      try {
        await sendFile(
          files[i],
          caption: i == 0 && hasText && replyTo == null ? trimmedText : null,
          recipient: selected,
          attachmentBatchId: batchId,
        );
      } catch (_) {
        if (_disposed) return;
        failedCount++;
        final recorded = (_conversations[selected.id] ?? <MessageModel>[])
            .where(
              (m) =>
                  !before.contains(m) &&
                  m.isMine &&
                  m.fileAttachment?.localPath == files[i].path &&
                  m.attachmentBatchId == batchId,
            )
            .firstOrNull;
        if (recorded != null) {
          for (final recipient in recorded.attachmentTransfers.entries) {
            if (recipient.value.isEmpty) {
              recorded.attachmentRecipientStatuses[recipient.key] =
                  MessageStatus.failed;
            }
          }
          recorded.status = MessageStatus.failed;
          chatHistory.scheduleSave(selected.id, _conversations[selected.id]!);
          notifyListeners();
        } else {
          final file = files[i];
          _conversations
              .putIfAbsent(selected.id, () => [])
              .add(
                MessageModel(
                  id: 'file_failed_${DateTime.now().microsecondsSinceEpoch}_$i',
                  senderId: 'me',
                  senderName: localUsername,
                  recipientId: selected.id,
                  text: i == 0 && hasText && replyTo == null ? trimmedText : '',
                  isMine: true,
                  status: MessageStatus.failed,
                  attachmentBatchId: batchId,
                  fileAttachment: FileAttachmentInfo(
                    fileName: file.path.split(Platform.pathSeparator).last,
                    fileSize: 0,
                    localPath: file.path,
                  ),
                ),
              );
          chatHistory.scheduleSave(selected.id, _conversations[selected.id]!);
          notifyListeners();
        }
      }
    }
    if (failedCount > 0) throw StateError('$failedCount/${files.length}');
  }

  Future<void> flushHistoryBeforeExit() async {
    aiQueueManager.clearQueue();
    try {
      _tcpServer.sendToAll(
        ProtocolBeebeep.buildUserStatusPacket(status: PeerStatus.offline),
      );
      _discovery.stop();
      await _tcpServer.stop();
    } catch (_) {}
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
    _otaCheckTimer?.cancel();
    _outboxRetryTimer?.cancel();
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
