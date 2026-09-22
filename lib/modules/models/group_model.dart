import 'dart:convert';
import 'package:flutter/material.dart';

/// Mô hình thông tin một Nhóm trò chuyện LAN
class GroupModel {
  final String id;
  String name;
  List<String>
  memberIds; // Danh sách endpoint ID của các thành viên (e.g. "192.168.1.10:6475")
  final DateTime createdAt;
  Color color;
  DateTime updatedAt;
  // BeeBEEP records [name, account, hash, domain], keyed by remote member ID.
  Map<String, List<String>> memberRecords;
  // Explicit invitations issued locally. Preserve the original time on retry;
  // otherwise reconnecting could resurrect a group after a later departure.
  Map<String, DateTime> invitations;
  int unreadCount;
  String? lastMessage;
  DateTime? lastMessageTime;
  String? avatarPreset;
  String? customAvatarPath;
  String? customAvatarBase64;
  int get memberCount => memberIds.toSet().length + 1;

  // Distinguishes "leave this field unchanged" from an explicit null clear.
  static const Object _keep = Object();

  GroupModel({
    required this.id,
    required this.name,
    required this.memberIds,
    DateTime? createdAt,
    Color? color,
    DateTime? updatedAt,
    Map<String, List<String>>? memberRecords,
    Map<String, DateTime>? invitations,
    this.unreadCount = 0,
    this.lastMessage,
    this.lastMessageTime,
    this.avatarPreset,
    this.customAvatarPath,
    this.customAvatarBase64,
  }) : createdAt = createdAt ?? DateTime.now(),
       updatedAt = updatedAt ?? createdAt ?? DateTime.now(),
       memberRecords = memberRecords ?? {},
       invitations = invitations ?? {},
       color = color ?? _generateColor(id);

  static Color _generateColor(String key) {
    final colors = [
      const Color(0xFF6366F1), // Indigo
      const Color(0xFF8B5CF6), // Violet
      const Color(0xFFEC4899), // Pink
      const Color(0xFF06B6D4), // Cyan
      const Color(0xFF10B981), // Emerald
      const Color(0xFFF59E0B), // Amber
    ];
    final hash = key.hashCode.abs();
    return colors[hash % colors.length];
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'memberIds': memberIds,
    'createdAt': createdAt.toIso8601String(),
    'color': color.toARGB32(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'memberRecords': memberRecords,
    'invitations': invitations.map(
      (id, time) => MapEntry(id, time.toUtc().toIso8601String()),
    ),
    'unreadCount': unreadCount,
    if (lastMessage != null) 'lastMessage': lastMessage,
    if (lastMessageTime != null)
      'lastMessageTime': lastMessageTime!.toIso8601String(),
    if (avatarPreset != null) 'avatarPreset': avatarPreset,
    if (customAvatarPath != null) 'customAvatarPath': customAvatarPath,
    if (customAvatarBase64 != null) 'customAvatarBase64': customAvatarBase64,
  };

  GroupModel copyWith({
    String? name,
    List<String>? memberIds,
    Color? color,
    DateTime? updatedAt,
    Map<String, List<String>>? memberRecords,
    Map<String, DateTime>? invitations,
    int? unreadCount,
    String? lastMessage,
    DateTime? lastMessageTime,
    Object? avatarPreset = _keep,
    Object? customAvatarPath = _keep,
    Object? customAvatarBase64 = _keep,
  }) {
    return GroupModel(
      id: id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      createdAt: createdAt,
      color: color ?? this.color,
      updatedAt: updatedAt ?? this.updatedAt,
      memberRecords: memberRecords ?? this.memberRecords,
      invitations: invitations ?? Map.of(this.invitations),
      unreadCount: unreadCount ?? this.unreadCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      avatarPreset: identical(avatarPreset, _keep)
          ? this.avatarPreset
          : avatarPreset as String?,
      customAvatarPath: identical(customAvatarPath, _keep)
          ? this.customAvatarPath
          : customAvatarPath as String?,
      customAvatarBase64: identical(customAvatarBase64, _keep)
          ? this.customAvatarBase64
          : customAvatarBase64 as String?,
    );
  }

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
    id: json['id'] as String,
    name: json['name'] as String,
    updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? ''),
    invitations: (json['invitations'] as Map<String, dynamic>? ?? {}).map(
      (id, time) => MapEntry(id, DateTime.parse(time as String)),
    ),
    memberRecords: (json['memberRecords'] as Map<String, dynamic>? ?? {}).map(
      (key, value) => MapEntry(key, (value as List).cast<String>()),
    ),
    memberIds:
        (json['memberIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [],
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    color: json['color'] != null ? Color(json['color'] as int) : null,
    unreadCount: json['unreadCount'] as int? ?? 0,
    lastMessage: json['lastMessage'] as String?,
    lastMessageTime: json['lastMessageTime'] != null
        ? DateTime.tryParse(json['lastMessageTime'] as String)
        : null,
    avatarPreset: json['avatarPreset'] as String?,
    customAvatarPath: json['customAvatarPath'] as String?,
    customAvatarBase64: json['customAvatarBase64'] as String?,
  );

  static List<GroupModel> listFromJson(String source) {
    try {
      final data = jsonDecode(source) as List<dynamic>;
      return data
          .map((e) => GroupModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static String listToJson(List<GroupModel> groups) {
    return jsonEncode(groups.map((g) => g.toJson()).toList());
  }
}
