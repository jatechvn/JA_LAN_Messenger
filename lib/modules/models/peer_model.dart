import 'package:flutter/material.dart';
import 'group_model.dart';
import '../localization/app_locale.dart';

enum PeerStatus {
  online('Online', Color(0xFF10B981)), // Emerald
  away('Away', Color(0xFFF59E0B)), // Amber
  busy('Busy', Color(0xFFEF4444)), // Red
  offline('Offline', Color(0xFF6B7280)); // Gray

  final String label;
  final Color color;
  const PeerStatus(this.label, this.color);
}

class PeerModel {
  final String id; // IP:Port hoặc user hash hoặc '__ALL_USERS__' hoặc group ID
  String name;
  String ip;
  int port;
  PeerStatus status;
  String statusDescription;
  Color avatarColor;
  String workgroup;
  bool isBeebeep;
  DateTime lastSeen;
  int unreadCount;
  String? lastMessage;
  DateTime? lastMessageTime;
  bool isGroup;
  bool isAllUsers;
  List<String> memberIds;
  bool isPinned;
  bool isMuted;
  String? customNickname;
  String? accountName;
  String? hostname;
  Set<String> knownIps;

  PeerModel({
    required this.id,
    required this.name,
    required this.ip,
    this.port = 6475,
    this.status = PeerStatus.online,
    this.statusDescription = '',
    Color? avatarColor,
    this.workgroup = '',
    this.isBeebeep = false,
    DateTime? lastSeen,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageTime,
    this.isGroup = false,
    this.isAllUsers = false,
    this.memberIds = const [],
    this.isPinned = false,
    this.isMuted = false,
    this.customNickname,
    this.accountName,
    this.hostname,
    Set<String>? knownIps,
  }) : avatarColor = avatarColor ?? _generateColor(id),
       lastSeen = lastSeen ?? DateTime.now(),
       knownIps = knownIps ?? {if (ip.isNotEmpty) ip};

  bool get isAiAssistant => id == '__AI_ASSISTANT__';

  /// Định danh duy nhất chuẩn tắc của thiết bị (để hợp nhất nhiều card mạng của cùng 1 máy)
  String get canonicalIdentity {
    if (isAiAssistant) return '__AI_ASSISTANT__';
    if (isAllUsers) return '__ALL_USERS__';
    if (isGroup) return id;

    final cleanUser = name.trim();
    final cleanAccount = (accountName ?? '').trim();
    final cleanHost = (hostname ?? '').trim();

    // 1. Tên máy (hostname) là định danh vật lý chuẩn nhất trong mạng LAN
    if (cleanHost.isNotEmpty &&
        cleanHost.toLowerCase() != 'localhost' &&
        cleanHost != '???') {
      if (cleanAccount.isNotEmpty) {
        return '$cleanAccount@$cleanHost'.toLowerCase();
      }
      return '$cleanUser@$cleanHost'.toLowerCase();
    }

    // 2. Tên người dùng / Nickname nếu không phải tên giữ chỗ mặc định
    if (cleanUser.isNotEmpty &&
        cleanUser != '???' &&
        cleanUser.toLowerCase() != 'user' &&
        cleanUser.toLowerCase() != 'administrator' &&
        cleanUser.toLowerCase() != 'admin') {
      if (cleanAccount.isNotEmpty &&
          cleanAccount.toLowerCase() != cleanUser.toLowerCase()) {
        return '$cleanAccount@$cleanUser'.toLowerCase();
      }
      return cleanUser.toLowerCase();
    }

    // 3. Fallback theo endpoint IP nếu là máy ẩn danh hoặc tên giữ chỗ
    return id.isNotEmpty ? id : ip;
  }

  String get displayName {
    if (customNickname != null && customNickname!.trim().isNotEmpty) {
      return customNickname!;
    }
    if (isAiAssistant) return 'Trợ lý JA-AI';

    final cleanName = name.trim();
    if (cleanName.isNotEmpty && cleanName != '???') {
      return cleanName;
    }

    // Fallback thông minh khi name là ??? hoặc rỗng
    final cleanHost = (hostname ?? '').trim();
    final cleanAccount = (accountName ?? '').trim();
    if (cleanHost.isNotEmpty &&
        cleanHost != '???' &&
        cleanHost.toLowerCase() != 'localhost') {
      if (cleanAccount.isNotEmpty &&
          cleanAccount != '???' &&
          cleanAccount.toLowerCase() != 'user' &&
          cleanAccount.toLowerCase() != 'administrator' &&
          cleanAccount.toLowerCase() != 'admin') {
        return '$cleanAccount@$cleanHost';
      }
      return cleanHost;
    }
    if (cleanAccount.isNotEmpty &&
        cleanAccount != '???' &&
        cleanAccount.toLowerCase() != 'user') {
      return '$cleanAccount ($ip)';
    }
    return ip.isNotEmpty ? ip : id;
  }

  String effectiveDisplayName([LanguageProvider? lang]) {
    if (isAiAssistant) {
      return lang != null ? lang.tr('aiAssistant') : displayName;
    }
    if (isAllUsers) {
      return lang != null ? lang.tr('allUsersTitle') : displayName;
    }
    return displayName;
  }

  String? get avatarAsset {
    if (isAiAssistant) return 'assets/ai_avatar.png';
    return null;
  }

  String effectiveStatusDescription(
    LanguageProvider? lang, {
    bool isAiBusy = false,
    int queueLen = 0,
    String? selectedModel,
  }) {
    if (isAiAssistant) {
      final model =
          selectedModel ??
          (statusDescription.contains('•')
              ? statusDescription.split('•').last.trim()
              : 'qwen2.5-vl:3b');
      if (lang == null) {
        if (isAiBusy) return 'Processing ($model)';
        if (queueLen > 0) return 'Queue: $queueLen';
        return 'Ready • $model';
      }
      if (isAiBusy) return '${lang.tr('aiProcessing')} ($model)';
      if (queueLen > 0) return '${lang.tr('aiQueue')}: $queueLen';
      return '${lang.tr('ready')} • $model';
    }
    if (isAllUsers && lang != null) {
      return lang.tr('allUsersDesc');
    }
    return statusDescription;
  }

  static PeerModel createAiAssistantPeer({
    String statusDescription = 'Sẵn sàng • Qwen 2.5 VL',
    PeerStatus status = PeerStatus.online,
  }) {
    return PeerModel(
      id: '__AI_ASSISTANT__',
      name: 'Trợ lý JA-AI',
      ip: '172.21.175.20',
      port: 11434,
      status: status,
      statusDescription: statusDescription,
      isGroup: false,
      isAllUsers: false,
      isPinned: true,
      avatarColor: const Color(0xFF8B5CF6), // Purple AI
    );
  }

  static PeerModel createAllUsersPeer() {
    return PeerModel(
      id: '__ALL_USERS__',
      name: 'Toàn thể (All Users)',
      ip: '255.255.255.255',
      port: 0,
      status: PeerStatus.online,
      statusDescription: 'Kênh thông báo & chat toàn bộ thành viên',
      isGroup: true,
      isAllUsers: true,
      avatarColor: const Color(0xFF6366F1), // Indigo
    );
  }

  static PeerModel fromGroup(GroupModel group) {
    return PeerModel(
      id: group.id,
      name: group.name,
      ip: '',
      port: 0,
      status: PeerStatus.online,
      statusDescription: '${group.memberIds.length} thành viên',
      isGroup: true,
      isAllUsers: false,
      memberIds: group.memberIds,
      avatarColor: group.color,
    );
  }

  static Color _generateColor(String key) {
    final colors = [
      const Color(0xFF3B82F6), // Blue
      const Color(0xFF8B5CF6), // Purple
      const Color(0xFFEC4899), // Pink
      const Color(0xFF10B981), // Green
      const Color(0xFFF59E0B), // Amber
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF6366F1), // Indigo
    ];
    final hash = key.hashCode.abs();
    return colors[hash % colors.length];
  }

  String get initials {
    if (isAiAssistant) return '🤖';
    if (isAllUsers) return '📢';
    if (isGroup) return '👥';
    final targetName = displayName;
    if (targetName.trim().isEmpty) return '?';
    final parts = targetName.trim().split(RegExp(r'[\s@\._-]+'));
    final validParts = parts.where((p) => p.isNotEmpty).toList();
    if (validParts.length >= 2) {
      return (validParts[0][0] + validParts[1][0]).toUpperCase();
    }
    return targetName
        .substring(0, targetName.length >= 2 ? 2 : 1)
        .toUpperCase();
  }

  PeerModel copyWith({
    String? name,
    String? ip,
    int? port,
    PeerStatus? status,
    String? statusDescription,
    Color? avatarColor,
    String? workgroup,
    bool? isBeebeep,
    DateTime? lastSeen,
    int? unreadCount,
    String? lastMessage,
    DateTime? lastMessageTime,
    bool? isGroup,
    bool? isAllUsers,
    List<String>? memberIds,
    bool? isPinned,
    bool? isMuted,
    String? customNickname,
    String? accountName,
    String? hostname,
    Set<String>? knownIps,
  }) {
    return PeerModel(
      id: id,
      name: name ?? this.name,
      ip: ip ?? this.ip,
      port: port ?? this.port,
      status: status ?? this.status,
      statusDescription: statusDescription ?? this.statusDescription,
      avatarColor: avatarColor ?? this.avatarColor,
      workgroup: workgroup ?? this.workgroup,
      isBeebeep: isBeebeep ?? this.isBeebeep,
      lastSeen: lastSeen ?? this.lastSeen,
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      isGroup: isGroup ?? this.isGroup,
      isAllUsers: isAllUsers ?? this.isAllUsers,
      memberIds: memberIds ?? this.memberIds,
      isPinned: isPinned ?? this.isPinned,
      isMuted: isMuted ?? this.isMuted,
      customNickname: customNickname ?? this.customNickname,
      accountName: accountName ?? this.accountName,
      hostname: hostname ?? this.hostname,
      knownIps: knownIps ?? this.knownIps,
    );
  }
}
