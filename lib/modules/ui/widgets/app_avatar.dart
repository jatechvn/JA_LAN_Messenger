import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/peer_model.dart';
import '../../services/app_preferences.dart';

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
  final VoidCallback? onTap;

  const AppAvatar({
    super.key,
    this.peer,
    this.size = 40,
    this.showStatus = false,
    this.isLocal = false,
    this.onTap,
  });

  /// Factory hiển thị Avatar cho chính người dùng máy hiện tại (Local User)
  factory AppAvatar.local({
    Key? key,
    double size = 40,
    bool showStatus = false,
    VoidCallback? onTap,
  }) {
    return AppAvatar(
      key: key,
      size: size,
      showStatus: showStatus,
      isLocal: true,
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

    final avatarWidget = ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.0,
          ),
        ),
        child: avatarContent,
      ),
    );

    if (!showStatus) {
      return onTap != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(size * 0.3),
              child: avatarWidget,
            )
          : avatarWidget;
    }

    final statusColor = _getStatusColor();
    final badgeSize = (size * 0.28).clamp(8.0, 14.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size * 0.3),
      child: Stack(
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
      ),
    );
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
    final colorHex = prefs.userAvatarColor.replaceFirst('#', '');
    Color bgColor;
    try {
      final val = int.parse(
        colorHex.length == 6 ? 'FF$colorHex' : colorHex,
        radix: 16,
      );
      bgColor = Color(val);
    } catch (_) {
      bgColor = const Color(0xFF3B82F6);
    }

    if (type == 'custom') {
      final customPath = prefs.userAvatarCustomPath;
      if (customPath.isNotEmpty && File(customPath).existsSync()) {
        return Image.file(
          File(customPath),
          width: size,
          height: size,
          fit: BoxFit.cover,
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

  Widget _buildPeerAvatar(PeerModel p) {
    if (p.isAi) {
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
          errorBuilder: (_, _, _) => _buildGroupFallback(p),
        );
      }

      if (p.customAvatarBase64 != null && p.customAvatarBase64!.isNotEmpty) {
        try {
          final bytes = base64Decode(p.customAvatarBase64!);
          return Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildGroupFallback(p),
          );
        } catch (_) {}
      }

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
        errorBuilder: (_, _, _) => _buildInitials(p.avatarColor, p.name),
      );
    }

    if (p.customAvatarBase64 != null && p.customAvatarBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(p.customAvatarBase64!);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _buildInitials(p.avatarColor, p.name),
        );
      } catch (_) {}
    }

    if (p.avatarPreset != null && p.avatarPreset!.isNotEmpty) {
      if (p.avatarPreset == 'initials') {
        return _buildInitials(p.avatarColor, p.name);
      }
      return _buildFallbackPreset(p.avatarColor, p.avatarPreset!);
    }

    return _buildInitials(p.avatarColor, p.name);
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFF3B82F6),
      child: Center(
        child: Icon(
          Icons.person_rounded,
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }

  Widget _buildGroupFallback(PeerModel p) {
    return Container(
      color: p.avatarColor,
      child: Center(
        child: Icon(
          Icons.forum_rounded,
          color: Colors.white,
          size: size * 0.55,
        ),
      ),
    );
  }

  Widget _buildFallbackPreset(Color bgColor, String presetKey) {
    final iconData = AvatarPresets.getIcon(presetKey);
    return Container(
      color: bgColor,
      child: Center(
        child: Icon(iconData, color: Colors.white, size: size * 0.55),
      ),
    );
  }

  Widget _buildInitials(Color bgColor, String name) {
    final clean = name.trim();
    String initials = '';
    if (clean.isNotEmpty) {
      final parts = clean.split(RegExp(r'\s+'));
      if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        initials = clean.substring(0, clean.length >= 2 ? 2 : 1).toUpperCase();
      }
    } else {
      initials = '?';
    }

    return Container(
      color: bgColor,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: Colors.white,
            fontSize: size * 0.38,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
