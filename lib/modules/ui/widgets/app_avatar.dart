import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/peer_model.dart';
import '../../services/app_preferences.dart';

/// Giữ đúng một bản byte cho mỗi ảnh Base64. Quét mạng dựng lại danh sách
/// nhiều lần; giải mã lại sẽ tạo MemoryImage mới và avatar nhấp nháy.
class AvatarImageCache {
  static const int _maxEntries = 48;
  static final Map<String, Uint8List> _bytes = {};

  static Uint8List? decode(String base64) {
    final cached = _bytes.remove(base64);
    if (cached != null) {
      _bytes[base64] = cached;
      return cached;
    }
    try {
      final decoded = base64Decode(base64);
      if (_bytes.length >= _maxEntries) {
        _bytes.remove(_bytes.keys.first);
      }
      _bytes[base64] = decoded;
      return decoded;
    } catch (_) {
      return null;
    }
  }
}

/// Danh sách các preset icon phổ biến và đẹp mắt cho avatar người dùng
class AvatarPresets {
  static const Map<String, IconData> icons = {
    'robot': Icons.smart_toy_rounded,
    'rocket': Icons.rocket_launch_rounded,
    'cat': Icons.pets_rounded,
    'dog': Icons.cruelty_free_rounded,
    'game': Icons.sports_esports_rounded,
    'code': Icons.terminal_rounded,
    'star': Icons.star_rounded,
    'diamond': Icons.diamond_rounded,
    'fire': Icons.local_fire_department_rounded,
    'bolt': Icons.bolt_rounded,
    'music': Icons.music_note_rounded,
    'coffee': Icons.coffee_rounded,
    'shield': Icons.shield_rounded,
    'laptop': Icons.laptop_chromebook_rounded,
    'flight': Icons.flight_rounded,
    'palette': Icons.palette_rounded,
  };

  static const List<Color> paletteColors = [
    Color(0xFF3B82F6), // Blue
    Color(0xFF06B6D4), // Cyan
    Color(0xFF10B981), // Emerald
    Color(0xFF84CC16), // Lime
    Color(0xFFF59E0B), // Amber
    Color(0xFFF97316), // Orange
    Color(0xFFEF4444), // Red
    Color(0xFFEC4899), // Pink
    Color(0xFF8B5CF6), // Purple
    Color(0xFF6366F1), // Indigo
    Color(0xFF14B8A6), // Teal
    Color(0xFF64748B), // Slate
  ];

  static IconData getIcon(String? presetName) {
    if (presetName == null) return Icons.person_rounded;
    return icons[presetName] ?? Icons.person_rounded;
  }
}

/// Widget hiển thị Avatar thống nhất, hỗ trợ ảnh tùy chỉnh từ máy, icon preset, AI, Group và chữ cái đầu (Initials)
class AppAvatar extends StatelessWidget {
  final PeerModel? peer;
  final double size;
  final bool showStatus;
  final bool isLocal;
  final bool isCircle;
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.peer,
    this.size = 40,
    this.showStatus = false,
    this.isLocal = false,
    this.isCircle = true,
    this.onTap,
  });

  /// Factory hiển thị Avatar cho chính người dùng máy hiện tại (Local User)
  factory AppAvatar.local({
    Key? key,
    double size = 40,
    bool showStatus = false,
    bool isCircle = true,
    VoidCallback? onTap,
  }) {
    return AppAvatar(
      key: key,
      size: size,
      showStatus: showStatus,
      isLocal: true,
      isCircle: isCircle,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget avatarContent;

    if (isLocal) {
      avatarContent = _buildLocalAvatar();
    } else if (peer != null) {
      avatarContent = _buildPeerAvatar(peer!);
    } else {
      avatarContent = _buildDefaultAvatar();
    }

    final effectiveColor = _getEffectiveColor();
    final borderColor = effectiveColor.withValues(alpha: 0.5);

    final shapeDecoration = isCircle
        ? BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: borderColor, width: 1.2),
          )
        : BoxDecoration(
            borderRadius: BorderRadius.circular(size * 0.3),
            border: Border.all(color: borderColor, width: 1.2),
          );

    final avatarWidget = Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: shapeDecoration,
      child: avatarContent,
    );

    final borderRadius = isCircle
        ? BorderRadius.circular(size / 2)
        : BorderRadius.circular(size * 0.3);

    if (!showStatus) {
      return onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: borderRadius,
              child: avatarWidget,
            )
          : avatarWidget;
    }

    final statusColor = _getStatusColor();
    final badgeSize = (size * 0.28).clamp(8.0, 14.0);

    final statusStack = Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: badgeSize,
            height: badgeSize,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFF1E293B),
                width: badgeSize > 10 ? 2 : 1.5,
              ),
            ),
          ),
        ),
      ],
    );

    return onTap != null
        ? InkWell(onTap: onTap, borderRadius: borderRadius, child: statusStack)
        : statusStack;
  }

  Color _getEffectiveColor() {
    if (isLocal) {
      return _getLocalColor();
    }
    if (peer != null) {
      if (peer!.isAi) return const Color(0xFF6366F1);
      if (peer!.isAllUsers) return const Color(0xFF0EA5E9);
      return peer!.avatarColor;
    }
    return const Color(0xFF3B82F6);
  }

  Color _getLocalColor() {
    final prefs = AppPreferences();
    final colorHex = prefs.userAvatarColor.replaceFirst('#', '');
    try {
      final val = int.parse(
        colorHex.length == 6 ? 'FF$colorHex' : colorHex,
        radix: 16,
      );
      return Color(val);
    } catch (_) {
      return const Color(0xFF3B82F6);
    }
  }

  Color _getStatusColor() {
    if (isLocal) return const Color(0xFF22C55E);
    if (peer == null) return Colors.grey;
    switch (peer!.status) {
      case PeerStatus.online:
        return const Color(0xFF22C55E);
      case PeerStatus.busy:
        return const Color(0xFFEF4444);
      case PeerStatus.away:
        return const Color(0xFFF59E0B);
      case PeerStatus.offline:
        return Colors.grey.shade600;
    }
  }

  Widget _buildLocalAvatar() {
    final prefs = AppPreferences();
    final type = prefs.userAvatarType;
    final bgColor = _getLocalColor();

    if (type == 'custom') {
      final customPath = prefs.userAvatarCustomPath;
      if (customPath.isNotEmpty && File(customPath).existsSync()) {
        return Image.file(
          File(customPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildFallbackPreset(bgColor, 'robot'),
        );
      }
    }

    if (type == 'preset') {
      return _buildFallbackPreset(bgColor, prefs.userAvatarPreset);
    }

    // Initials fallback
    final name = prefs.localNickname ?? Platform.environment['USERNAME'] ?? 'U';
    return _buildInitials(bgColor, name);
  }

  Widget _buildAiFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6366F1), Color(0xFFEC4899)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.auto_awesome_rounded,
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }

  Widget _buildPeerAvatar(PeerModel p) {
    if (p.avatarAsset != null && p.avatarAsset!.isNotEmpty) {
      return Image.asset(
        p.avatarAsset!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => p.isAi
            ? _buildAiFallback()
            : _buildInitials(p.avatarColor, p.name, p),
      );
    }

    if (p.isAi) {
      return _buildAiFallback();
    }

    if (p.isAllUsers) {
      return Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0EA5E9), Color(0xFF10B981)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Icon(
            Icons.groups_rounded,
            color: Colors.white,
            size: size * 0.55,
          ),
        ),
      );
    }

    if (p.isGroup) {
      if (p.customAvatarPath != null &&
          p.customAvatarPath!.isNotEmpty &&
          File(p.customAvatarPath!).existsSync()) {
        return Image.file(
          File(p.customAvatarPath!),
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => _buildGroupFallback(p),
        );
      }

      final groupImage = _memoryImage(
        p.customAvatarBase64,
        () => _buildGroupFallback(p),
      );
      if (groupImage != null) return groupImage;

      if (p.avatarPreset != null && p.avatarPreset!.isNotEmpty) {
        return _buildFallbackPreset(p.avatarColor, p.avatarPreset!);
      }

      return _buildGroupFallback(p);
    }

    if (p.customAvatarPath != null &&
        p.customAvatarPath!.isNotEmpty &&
        File(p.customAvatarPath!).existsSync()) {
      return Image.file(
        File(p.customAvatarPath!),
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _buildInitials(p.avatarColor, p.name, p),
      );
    }

    final peerImage = _memoryImage(
      p.customAvatarBase64,
      () => _buildInitials(p.avatarColor, p.name, p),
    );
    if (peerImage != null) return peerImage;

    if (p.avatarPreset != null && p.avatarPreset!.isNotEmpty) {
      if (p.avatarPreset == 'initials') {
        return _buildInitials(p.avatarColor, p.name, p);
      }
      return _buildFallbackPreset(p.avatarColor, p.avatarPreset!);
    }

    return _buildInitials(p.avatarColor, p.name, p);
  }

  Widget? _memoryImage(String? base64, Widget Function() fallback) {
    if (base64 == null || base64.isEmpty) return null;
    final bytes = AvatarImageCache.decode(base64);
    if (bytes == null) return null;
    return Image.memory(
      bytes,
      width: size,
      height: size,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => fallback(),
    );
  }

  Widget _buildDefaultAvatar() {
    const defaultColor = Color(0xFF3B82F6);
    return Container(
      color: defaultColor.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: defaultColor,
          size: size * 0.55,
        ),
      ),
    );
  }

  Widget _buildGroupFallback(PeerModel p) {
    return Container(
      color: p.avatarColor.withValues(alpha: 0.2),
      child: Center(
        child: Icon(
          Icons.groups_rounded,
          color: p.avatarColor,
          size: size * 0.55,
        ),
      ),
    );
  }

  Widget _buildFallbackPreset(Color bgColor, String presetKey) {
    final iconData = AvatarPresets.getIcon(presetKey);
    return Container(
      color: bgColor.withValues(alpha: 0.2),
      child: Center(
        child: Icon(iconData, color: bgColor, size: size * 0.55),
      ),
    );
  }

  Widget _buildInitials(Color avatarColor, String name, [PeerModel? p]) {
    final initials = p?.initials ?? _computeInitials(name);

    return Container(
      color: avatarColor.withValues(alpha: 0.2),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: avatarColor,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  String _computeInitials(String name) {
    final clean = name.trim();
    if (clean.isEmpty) return '?';
    final parts = clean.split(RegExp(r'[\s@\._-]+'));
    final validParts = parts.where((p) => p.isNotEmpty).toList();
    if (validParts.length >= 2) {
      return (validParts[0][0] + validParts[1][0]).toUpperCase();
    }
    return clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
  }
}
