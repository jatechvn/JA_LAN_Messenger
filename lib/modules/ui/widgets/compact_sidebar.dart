import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../models/peer_model.dart';
import 'glass_components.dart';
import 'settings_dialog.dart';

enum MainViewTab { chats, transfers }

class CompactSidebar extends StatelessWidget {
  final MainViewTab activeTab;
  final ValueChanged<MainViewTab> onTabChanged;

  const CompactSidebar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final effectiveOpacity = (theme.cardOpacity * (theme.isDark ? 1.05 : 0.85))
        .clamp(0.12, 0.95);
    final effectiveBlur = theme.cardBlur;
    final sidebarColor =
        (theme.isDark ? const Color(0xFF0F172A) : const Color(0xFFF0F0F0))
            .withValues(alpha: effectiveOpacity);

    Widget content = Container(
      width: 58,
      decoration: BoxDecoration(
        color: sidebarColor,
        border: Border(
          right: BorderSide(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: theme.isDark ? 0.10 : 0.06,
            ),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          // App Logo
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colors.accentBlue, theme.colors.accentCyan],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: theme.colors.accentBlue.withValues(alpha: 0.35),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(
              Icons.forum_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(height: 24),

          // Tab 1: Chats
          _SidebarTabItem(
            icon: Icons.chat_bubble_outline_rounded,
            activeIcon: Icons.chat_bubble_rounded,
            isSelected: activeTab == MainViewTab.chats,
            tooltip: lang.tr('tabChats'),
            badgeCount: coordinator.totalUnreadCount,
            onTap: () {
              onTabChanged(MainViewTab.chats);
              coordinator.resetFilterAndSelectLatest();
            },
          ),
          const SizedBox(height: 8),

          // Tab 2: Transfers
          _SidebarTabItem(
            icon: Icons.swap_vert_rounded,
            activeIcon: Icons.swap_vertical_circle_rounded,
            isSelected: activeTab == MainViewTab.transfers,
            tooltip: lang.tr('tabTransfers'),
            badgeCount: coordinator.activeTransfersCount,
            onTap: () => onTabChanged(MainViewTab.transfers),
          ),
          const SizedBox(height: 8),

          // Quick Language Switcher
          const _LanguageSelectorButton(),

          const Spacer(),

          // Theme Toggle
          GlassIconButton(
            icon: theme.isDark
                ? Icons.light_mode_rounded
                : Icons.dark_mode_rounded,
            tooltip: theme.isDark
                ? lang.tr('themeLight')
                : lang.tr('themeDark'),
            size: 38,
            onPressed: () => theme.toggleTheme(),
          ),
          const SizedBox(height: 8),

          // Settings Button
          GlassIconButton(
            icon: Icons.settings_rounded,
            tooltip: lang.tr('tabSettings'),
            size: 38,
            onPressed: () {
              showSettingsDialog(context);
            },
          ),
          const SizedBox(height: 12),

          // User Profile & Status
          _UserStatusAvatar(),
          const SizedBox(height: 14),
        ],
      ),
    );

    if (effectiveBlur > 0) {
      content = ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: content,
        ),
      );
    }

    return RepaintBoundary(child: content);
  }
}

class _SidebarTabItem extends StatelessWidget {
  final IconData icon;
  final IconData activeIcon;
  final bool isSelected;
  final String tooltip;
  final int badgeCount;
  final VoidCallback onTap;

  const _SidebarTabItem({
    required this.icon,
    required this.activeIcon,
    required this.isSelected,
    required this.tooltip,
    this.badgeCount = 0,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final activeColor = theme.colors.accentBlue;

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.15)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected
                  ? Border.all(
                      color: activeColor.withValues(alpha: 0.35),
                      width: 1,
                    )
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  isSelected ? activeIcon : icon,
                  color: isSelected
                      ? activeColor
                      : (theme.isDark
                            ? Colors.white.withValues(alpha: 0.65)
                            : Colors.black54),
                  size: 21,
                ),
                if (badgeCount > 0)
                  Positioned(
                    top: 4,
                    right: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colors.accentRose,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      child: Text(
                        badgeCount > 99 ? '99+' : badgeCount.toString(),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserStatusAvatar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final coordinator = context.watch<MessengerCoordinator>();

    return Theme(
      data: Theme.of(context).copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: theme.cardBg,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.1,
              ),
              width: 1,
            ),
          ),
        ),
      ),
      child: PopupMenuButton<PeerStatus>(
        tooltip:
            '${coordinator.localUsername} (${coordinator.localStatus.label})',
        offset: const Offset(48, -120),
        onSelected: (status) {
          coordinator.updateProfile(status: status);
        },
        itemBuilder: (ctx) => [
          _buildPopupItem(
            ctx,
            PeerStatus.online,
            Icons.check_circle_rounded,
            coordinator.localStatus == PeerStatus.online,
          ),
          _buildPopupItem(
            ctx,
            PeerStatus.away,
            Icons.schedule_rounded,
            coordinator.localStatus == PeerStatus.away,
          ),
          _buildPopupItem(
            ctx,
            PeerStatus.busy,
            Icons.do_not_disturb_on_rounded,
            coordinator.localStatus == PeerStatus.busy,
          ),
        ],
        child: Stack(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: coordinator.localColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: coordinator.localColor.withValues(alpha: 0.6),
                  width: 1.5,
                ),
              ),
              alignment: Alignment.center,
              child: Text(
                coordinator.localUsername.isNotEmpty
                    ? coordinator.localUsername[0].toUpperCase()
                    : 'U',
                style: TextStyle(
                  color: coordinator.localColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: StatusBadge(status: coordinator.localStatus),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<PeerStatus> _buildPopupItem(
    BuildContext context,
    PeerStatus status,
    IconData icon,
    bool isSelected,
  ) {
    final theme = ThemeProvider.of(context);
    return PopupMenuItem<PeerStatus>(
      value: status,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 16, color: status.color),
          const SizedBox(width: 8),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected
                  ? theme.colors.accentBlue
                  : (theme.isDark ? Colors.white : Colors.black87),
            ),
          ),
          if (isSelected) ...[
            const Spacer(),
            Icon(Icons.check_rounded, size: 16, color: theme.colors.accentBlue),
          ],
        ],
      ),
    );
  }
}

class _LanguageSelectorButton extends StatelessWidget {
  const _LanguageSelectorButton();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final nextLang = lang.nextLanguage;
    final langCode = lang.currentLanguage.code == 'zh'
        ? 'CN'
        : lang.currentLanguage.code.toUpperCase();

    return Tooltip(
      message:
          '${lang.tr('switchLanguage')}: ${lang.currentLanguage.label} ➔ ${nextLang.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => lang.cycleLanguage(),
          borderRadius: BorderRadius.circular(19),
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: theme.isDark ? 0.08 : 0.05,
              ),
              border: Border.all(
                color: theme.colors.accentBlue.withValues(alpha: 0.35),
                width: 1.2,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.translate_rounded,
                  size: 19,
                  color: theme.isDark ? Colors.white70 : Colors.black87,
                ),
                Positioned(
                  right: 2,
                  bottom: 2,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 3,
                      vertical: 0.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colors.accentBlue,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    constraints: const BoxConstraints(minWidth: 14),
                    child: Text(
                      langCode,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 7.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
