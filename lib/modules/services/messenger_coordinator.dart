import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
import 'network_preferences.dart';
import 'chat_history_service.dart';
import 'clipboard_image.dart';
import 'ota_update_service.dart';

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
        return '🚀 ${lang.tr('updateAvailable')} (v${args.first})';
      default:
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
  final PeerModel _allUsersPeer = PeerModel.createAllUsersPeer();
  final PeerModel _aiPeer = PeerModel.createAiAssistantPeer();
  late final AiService aiService;
  late final AiQueueManager aiQueueManager;

  PeerModel get aiPeer => _aiPeer;
  bool get isAiActive => aiQueueManager.isBusy;
  int get aiQueueLength => aiQueueManager.queueLength;
  final Map<String, GroupModel> _groups = {};
  final Map<String, List<MessageModel>> _conversations = {};
  PeerModel? _selectedPeer;
  String _searchQuery = '';

  // Chế độ thu nhỏ (Compact Mode) & Ghim trên cùng (Always on Top)
  bool _isCompactMode = false;
  bool _isAlwaysOnTop = false;

  bool get isCompactMode => _isCompactMode;
  bool get isAlwaysOnTop => _isAlwaysOnTop;

  // Quản lý trạng thái đang gõ phím (typing)
  final Map<String, DateTime> _typingPeers = {};
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
  final LanTcpServer _tcpServer = LanTcpServer();
  final FileTransferEngine _fileEngine = FileTransferEngine();
  final SecurityService security = SecurityService();
  final KnownDevicesRegistry knownDevices = KnownDevicesRegistry();
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

  MessengerCoordinator() {
    final prefs = AppPreferences();
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
    _loadChatHistory();
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
  PeerModel getPeerForGroup(GroupModel group) => PeerModel.fromGroup(group);

  List<PeerModel> get peers {
    // Deduplicate peers by canonical identity
    final Map<String, PeerModel> uniqueMap = {};
    for (final p in _peers.values) {
      if (p.isGroup || p.isAllUsers) continue;
      final key = p.networkSessionIdentity;

      final existing = uniqueMap[key];
      if (existing == null) {
        uniqueMap[key] = p;
      } else {
        // If one is online and the other is offline, keep the online one
        if (existing.status == PeerStatus.offline &&
            p.status != PeerStatus.offline) {
          uniqueMap[key] = p;
        } else if ((p.status == PeerStatus.offline) ==
                (existing.status == PeerStatus.offline) &&
            p.lastSeen.isAfter(existing.lastSeen)) {
          uniqueMap[key] = p;
        }
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
    for (final p in _peers.values) {
      count += p.unreadCount;
    }
    return count;
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

    // 1. Khởi động TCP Server nhận tin nhắn (Port 6475, tự động fallback nếu bị chiếm)
    _tcpServer.helloBuilder = _buildHello;
    _tcpServer.passwordProvider = () =>
        security.isEncryptionEnabled ? security.password : '';
    _tcpServer.onUserStatus = (id, message) {
      final peer = _peers[id];
      if (_disposed || peer == null) return;
      peer.status = switch (message['data']) {
        '1' => PeerStatus.online,
        '2' => PeerStatus.busy,
        '3' => PeerStatus.away,
        _ => PeerStatus.offline,
      };
      peer.statusDescription = message['text'] as String;
      peer.lastSeen = DateTime.now();
      notifyListeners();
    };
    _tcpServer.onDisconnected = (id) {
      if (_disposed) return;
      // BeeBEEP và socket TCP ngang hàng trong mạng LAN thường tự động đóng sau khi hoàn tất
      // truyền tải hoặc hết thời gian chờ idle. Không vội đánh dấu peer thành offline ngay lập tức
      // để tránh hiện tượng thông báo và trạng thái bị chập chờn (flapping).
      // Quá trình _checkPeerLiveness định kỳ sẽ kiểm tra timeout 45s không có tín hiệu để chuyển offline.
    };
    _tcpServer.onActivity = (id) {
      _peers[id]?.lastSeen = DateTime.now();
    };
    _tcpServer.onHandshake = handlePeerHandshake;
    _tcpServer.onMessage = handleIncomingMessage;
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

  List<int> _buildHello(String publicKey) => ProtocolBeebeep.buildHelloPacket(
    localPort: localTcpPort,
    username: localUsername,
    status: localStatus,
    statusDescription: localStatusDescription,
    accountName: Platform.environment['USERNAME'] ?? localUsername,
    appVersion: appVersion,
    avatarHexColor: '#${localColor.toARGB32().toRadixString(16).substring(2)}',
    workgroup: localWorkgroup,
    password: security.isEncryptionEnabled ? security.password : '',
    publicKey: publicKey,
    hostname: Platform.localHostname,
  );

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

    // Tạo đối tượng tạm để tính canonicalIdentity chính xác theo máy vật lý
    final candidate = PeerModel(
      id: endpoint,
      name: username,
      ip: senderIp,
      port: remotePort,
      status: status,
      statusDescription: statusDesc,
      workgroup: workgroup,
      isBeebeep: true,
      accountName: account.isNotEmpty && account != '???' ? account : null,
      hostname: hostname.isNotEmpty && hostname != '???' ? hostname : null,
      knownIps: {senderIp},
    );

    final identityKey = candidate.canonicalIdentity;

    // Tìm peer đã tồn tại (qua endpoint chính xác hoặc canonicalIdentity của cùng 1 máy vật lý)
    PeerModel? existingPeer = _peers[endpoint];
    if (existingPeer == null) {
      for (final p in _peers.values) {
        if (p.isGroup || p.isAllUsers) continue;
        // Chỉ gộp khi canonicalIdentity là một khóa máy vật lý cụ thể (không phải fallback endpoint IP:Port)
        if (p.networkSessionIdentity == candidate.networkSessionIdentity) {
          existingPeer = p;
          break;
        }
      }
    }

    final now = DateTime.now();
    final peer = existingPeer ?? candidate;
    peer.isPinned = AppPreferences().isPeerPinned(identityKey);

    // Cập nhật thông tin mới nhất cho peer
    if (username.isNotEmpty && username != '???') {
      peer.name = username;
    }
    peer.ip = senderIp;
    peer.port = remotePort;
    peer.status = status;
    peer.statusDescription = statusDesc;
    peer.workgroup = workgroup;
    peer.lastSeen = now;
    if (account.isNotEmpty && account != '???') {
      peer.accountName = account;
    }
    if (hostname.isNotEmpty && hostname != '???') {
      peer.hostname = hostname;
    }
    peer.knownIps.add(senderIp);

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

    // Đảm bảo endpoint và peer.id cùng trỏ tới thực thể này
    _peers[endpoint] = peer;
    _peers[peer.id] = peer;

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

    notifyListeners();
  }

  static String _getGroupsFilePath() {
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

  Future<void> _loadChatHistory() async {
    try {
      final saved = await chatHistory.loadAllConversations();
      if (_disposed) return;
      for (final entry in saved.entries) {
        final convId = entry.key;
        final msgs = entry.value;
        if (msgs.isEmpty) continue;

        _conversations[convId] = msgs;

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
      notifyListeners();
    } catch (e) {
      debugPrint('[Coordinator] Load chat history error: $e');
    }
  }

  void createGroup(String name, List<String> memberIds) {
    final id = 'group_${DateTime.now().millisecondsSinceEpoch}';
    final group = GroupModel(id: id, name: name, memberIds: memberIds);
    _groups[id] = group;
    _saveGroups();
    selectPeer(PeerModel.fromGroup(group));
    notifyListeners();
  }

  void deleteGroup(String groupId) {
    if (_groups.containsKey(groupId)) {
      _groups.remove(groupId);
      _saveGroups();
      if (_selectedPeer?.id == groupId) {
        _selectedPeer = null;
      }
      notifyListeners();
    }
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
    if (_tcpServer.send(endpoint, packet)) return true;
    final peer = _peers[endpoint];
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
    DateTime timestamp,
  ) {
    final decryptedText = text;

    final senderPeer =
        _findPeerByIpOrId(senderIp) ??
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
    if (decryptedText.startsWith('[All Users] ')) {
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
      GroupModel? targetGroup;
      for (final g in _groups.values) {
        if (decryptedText.startsWith('[${g.name}] ')) {
          targetGroup = g;
          break;
        }
      }

      if (targetGroup != null) {
        final prefix = '[${targetGroup.name}] ';
        final actualText = decryptedText.substring(prefix.length);
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
        list.add(msg);
        chatHistory.scheduleSave(targetGroup.id, list);
        _showDesktopNotification(
          title: '[${targetGroup.name}] ${senderPeer.displayName}',
          body: quote.text,
          peer: PeerModel.fromGroup(targetGroup),
        );
      } else {
        // 3. Tin nhắn trò chuyện trực tiếp cá nhân
        final quote = _parseQuote(decryptedText);
        final isCurrentChat = _selectedPeer?.id == senderPeer.id;
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
        list.add(msg);
        chatHistory.scheduleSave(senderPeer.id, list);

        senderPeer.lastMessage = quote.text;
        senderPeer.lastMessageTime = timestamp;

        if (!isCurrentChat) {
          senderPeer.unreadCount++;
        } else {
          // Gửi ngay tín hiệu đã xem (Read receipt) về phía gửi
          _sendToPeer(
            senderPeer.id,
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
    final peer = _findPeerByIpOrId(senderIp);
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

    final peer = _findPeerByIpOrId(senderIp);
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
    if (_disposed || _typingPeers.isEmpty) return;
    final now = DateTime.now();
    final expired = _typingPeers.entries
        .where((e) => now.difference(e.value).inSeconds >= 4)
        .map((e) => e.key)
        .toList();
    if (expired.isNotEmpty) {
      for (final key in expired) {
        _typingPeers.remove(key);
      }
      notifyListeners();
    }
  }

  /// Kiểm tra xem đối phương có đang soạn tin nhắn hay không
  bool isPeerTyping(String peerId) {
    final time = _typingPeers[peerId];
    if (time == null) return false;
    return DateTime.now().difference(time).inSeconds < 4;
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

  /// Gửi tín hiệu đang soạn tin hoặc ngừng soạn tin tới peer đang chat
  void sendTypingStatus(bool isTyping) {
    final peer = _selectedPeer;
    if (peer == null || peer.isAllUsers || peer.isGroup) return;
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
    _sendToPeer(peer.id, ProtocolBeebeep.buildTypingPacket(isTyping: isTyping));
  }

  /// Đánh dấu toàn bộ tin nhắn trong cuộc trò chuyện là đã đọc
  void markConversationAsRead(String peerId) {
    final list = _conversations[peerId];
    if (list == null || list.isEmpty) return;
    var hadUnread = false;
    for (final m in list) {
      if (!m.isMine && m.status != MessageStatus.read) {
        m.status = MessageStatus.read;
        hadUnread = true;
        if (peerId != '__ALL_USERS__' && !_groups.containsKey(peerId)) {
          _sendToPeer(peerId, ProtocolBeebeep.buildReadPacket(m.id));
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
    if (hadUnread) {
      chatHistory.scheduleSave(peerId, list);
      notifyListeners();
    }
  }

  /// Xử lý tín hiệu typing nhận được
  void _handleIncomingTyping(String senderIp, bool isTyping) {
    if (_disposed) return;
    final peer =
        _findPeerByIpOrId(senderIp) ??
        PeerModel(
          id: senderIp,
          name: senderIp,
          ip: senderIp,
          knownIps: {senderIp},
        );
    if (isTyping) {
      _typingPeers[peer.id] = DateTime.now();
    } else {
      _typingPeers.remove(peer.id);
    }
    notifyListeners();
  }

  /// Xử lý tín hiệu đã xem (read receipt) nhận được
  void _handleIncomingReadReceipt(String senderIp, String messageId) {
    if (_disposed) return;
    final peer =
        _findPeerByIpOrId(senderIp) ??
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
    var found = false;
    for (final entry in _conversations.entries) {
      for (final msg in entry.value) {
        if (msg.id == messageId) {
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
    final sender = _findPeerByIpOrId(endpoint);
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
      // Nếu cuộc trò chuyện không có tin chưa đọc nào, đánh dấu đã đọc an toàn
      if (firstUnread == null) {
        markConversationAsRead(peer.id);
      }
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
      replyToId: replyTo?.id,
      replyToSender: replyTo?.senderName,
      replyToText: replyTo?.text,
    );

    final list = _conversations.putIfAbsent(_selectedPeer!.id, () => []);
    list.add(msg);
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
                !p.isGroup && !p.isAllUsers && p.status != PeerStatus.offline,
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
      }
      msg.status = (anySuccess || onlinePeers.isEmpty)
          ? MessageStatus.sent
          : MessageStatus.failed;
      notifyListeners();
      return anySuccess;
    } else if (_selectedPeer!.isGroup) {
      // Gửi tới các thành viên trong nhóm
      var anySuccess = false;
      for (final memberId in _selectedPeer!.memberIds) {
        final peer = _peers[memberId];
        if (peer != null && peer.status != PeerStatus.offline) {
          final ok = _sendToPeer(
            peer.id,
            ProtocolBeebeep.buildChatPacket(
              messageId: msgId,
              text: '[${_selectedPeer!.name}] $networkPayload',
            ),
          );
          if (ok) anySuccess = true;
        }
      }
      msg.status = anySuccess ? MessageStatus.sent : MessageStatus.failed;
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
      notifyListeners();
      return success;
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
              .map((id) => _peers[id])
              .whereType<PeerModel>()
              .where((p) => p.status != PeerStatus.offline)
              .toList()
        : [selected];
    if (targets.isEmpty) throw StateError('Không có người nhận trực tuyến');
    for (final peer in targets) {
      final task = await _fileEngine.sendFile(
        peerId: peer.id,
        peerIp: peer.ip,
        peerName: peer.name,
        file: file,
      );
      if (_disposed) return;
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
    _conversations[peerId]?.clear();
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

  /// Xử lý khi nhận hoàn tất một file truyền về từ peer
  void _handleIncomingFileCompleted(FileTransferTask task) {
    final list = _conversations.putIfAbsent(task.peerId, () => []);
    final existingIndex = list.indexWhere((m) => m.id == 'file_${task.id}');
    final completed = task.status == TransferStatus.completed;
    final failed =
        task.status == TransferStatus.failed ||
        task.status == TransferStatus.cancelled;

    final senderPeer =
        _peers[task.peerId] ??
        _peers.values.firstWhere(
          (p) => p.ip == task.peerIp,
          orElse: () =>
              PeerModel(id: task.peerIp, name: task.peerName, ip: task.peerIp),
        );
    _peers[senderPeer.id] = senderPeer;

    final msg = MessageModel(
      id: 'file_${task.id}',
      senderId: senderPeer.id,
      senderName: senderPeer.displayName,
      recipientId: 'me',
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
      chatHistory.scheduleSave(senderPeer.id, list);
      if (completed) {
        _showDesktopNotification(
          title: '📁 ${task.fileName}',
          body: 'Đã nhận thành công từ ${senderPeer.displayName}',
          peer: senderPeer,
        );
      }
      return;
    }
    list.add(msg);
    chatHistory.scheduleSave(senderPeer.id, list);
    senderPeer.lastMessage = isImageFile(task.fileName)
        ? '📷 [Ảnh] ${task.fileName}'
        : '📁 [Tệp] ${task.fileName}';
    senderPeer.lastMessageTime = DateTime.now();

    if (_selectedPeer?.id != senderPeer.id) {
      senderPeer.unreadCount++;
    }

    if (completed) {
      _showDesktopNotification(
        title: '📁 ${task.fileName}',
        body: 'Đã nhận thành công từ ${senderPeer.displayName}',
        peer: senderPeer,
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
