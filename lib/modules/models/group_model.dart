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

  GroupModel({
    required this.id,
    required this.name,
    required this.memberIds,
    DateTime? createdAt,
    Color? color,
  }) : createdAt = createdAt ?? DateTime.now(),
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
  };

  factory GroupModel.fromJson(Map<String, dynamic> json) => GroupModel(
    id: json['id'] as String,
    name: json['name'] as String,
    memberIds:
        (json['memberIds'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [],
    createdAt: json['createdAt'] != null
        ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
        : DateTime.now(),
    color: json['color'] != null ? Color(json['color'] as int) : null,
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
