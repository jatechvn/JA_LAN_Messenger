import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../models/peer_model.dart';
import '../../constants.dart';
import 'chat_view_panel.dart';
import 'glass_components.dart';

enum _CompactFilter { all, unread, online }

/// Chế độ xem thu nhỏ 1 cột (Compact Mode)
class CompactMessengerView extends StatelessWidget {
  const CompactMessengerView({super.key});

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<MessengerCoordinator>();
    final selectedPeer = coordinator.selectedPeer;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final isChat = child.key == const ValueKey('compact_chat_panel');
        final inOffset = isChat
            ? const Offset(0.2, 0.0)
            : const Offset(-0.2, 0.0);
        return SlideTransition(
          position: Tween<Offset>(
            begin: inOffset,
            end: Offset.zero,
          ).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: selectedPeer != null
          ? ChatViewPanel(
              key: const ValueKey('compact_chat_panel'),
              isCompact: true,
              onBackToList: () => coordinator.selectPeer(null),
            )
          : const _CompactConversationList(
              key: ValueKey('compact_conversation_list'),
            ),
    );
  }
}

class _CompactConversationList extends StatefulWidget {
  const _CompactConversationList({super.key});

  @override
  State<_CompactConversationList> createState() =>
      _CompactConversationListState();
}

class _CompactConversationListState extends State<_CompactConversationList> {
  _CompactFilter _activeFilter = _CompactFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    final allPeers = coordinator.peers;
    final groups = coordinator.groups;
    final allUsers = coordinator.allUsersPeer;

    // Build complete list of candidate items
    final List<PeerModel> allItems = [];
    allItems.add(allUsers);
    for (final group in groups) {
      allItems.add(coordinator.getPeerForGroup(group));
    }
    allItems.addAll(allPeers);

    // Apply Filter Tab
    List<PeerModel> filtered = allItems.where((p) {
      if (_activeFilter == _CompactFilter.unread) {
        return p.unreadCount > 0;
      } else if (_activeFilter == _CompactFilter.online) {
        if (p.isAllUsers) return true;
        if (p.isAiAssistant) return p.status != PeerStatus.offline;
        return p.status != PeerStatus.offline;
      }
      return true;
    }).toList();

    // Apply Search Query
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      filtered = filtered.where((p) {
        final name = p.effectiveDisplayName(lang).toLowerCase();
        final ip = p.ip.toLowerCase();
        return name.contains(q) || ip.contains(q);
      }).toList();
    }

    final totalUnread = allItems.fold<int>(0, (sum, p) => sum + p.unreadCount);
    final onlineCount = allPeers
        .where((p) => p.status != PeerStatus.offline)
        .length;

    return Column(
      children: [
        // 1. Mini Top Header
        _CompactTopBar(
          onlineCount: onlineCount,
          onToggleAlwaysOnTop: () => coordinator.toggleAlwaysOnTop(),
          onExpandToStandard: () => coordinator.toggleCompactMode(),
        ),

        // 2. Compact Search Field
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
          child: Container(
            height: 32,
            decoration: BoxDecoration(
              color: (theme.isDark ? const Color(0xFF1E293B) : Colors.black)
                  .withValues(alpha: theme.isDark ? 0.65 : 0.05),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: theme.isDark ? 0.12 : 0.08,
                ),
                width: 1,
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: TextStyle(
                fontSize: 12,
                color: theme.isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 7),
                hintText: lang.tr('searchHint'),
                hintStyle: TextStyle(
                  fontSize: 11.5,
                  color: theme.isDark ? Colors.white38 : Colors.black38,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: theme.isDark ? Colors.white38 : Colors.black45,
                ),
                prefixIconConstraints: const BoxConstraints(minWidth: 30),
                suffixIcon: _searchQuery.isNotEmpty
                    ? InkWell(
                        onTap: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: theme.isDark ? Colors.white38 : Colors.black45,
                        ),
                      )
                    : null,
                suffixIconConstraints: const BoxConstraints(minWidth: 26),
                border: InputBorder.none,
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),

        // 3. Filter Pills Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterPill(
                  theme: theme,
                  label: lang.tr('allFilter'),
                  isSelected: _activeFilter == _CompactFilter.all,
                  count: allItems.length,
                  onTap: () =>
                      setState(() => _activeFilter = _CompactFilter.all),
                ),
                const SizedBox(width: 6),
                _buildFilterPill(
                  theme: theme,
                  label: lang.tr('unreadFilter'),
                  isSelected: _activeFilter == _CompactFilter.unread,
                  count: totalUnread,
                  isRoseCount: true,
                  onTap: () =>
                      setState(() => _activeFilter = _CompactFilter.unread),
                ),
                const SizedBox(width: 6),
                _buildFilterPill(
                  theme: theme,
                  label: lang.tr('onlineFilter'),
                  isSelected: _activeFilter == _CompactFilter.online,
                  count: onlineCount,
                  onTap: () =>
                      setState(() => _activeFilter = _CompactFilter.online),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 2),

        // 4. Conversations List
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                    lang.tr('emptyNoPeer'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final item = filtered[index];
                    return _CompactPeerItemTile(
                      peer: item,
                      onTap: () => coordinator.selectPeer(item),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterPill({
    required ThemeProvider theme,
    required String label,
    required bool isSelected,
    required int count,
    bool isRoseCount = false,
    required VoidCallback onTap,
  }) {
    final activeBg = theme.colors.accentBlue.withValues(alpha: 0.18);
    final inactiveBg = (theme.isDark ? const Color(0xFF1E293B) : Colors.black)
        .withValues(alpha: theme.isDark ? 0.50 : 0.04);

    final textColor = isSelected
        ? theme.colors.accentBlue
        : (theme.isDark ? Colors.white70 : Colors.black54);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colors.accentBlue.withValues(alpha: 0.50)
                : (theme.isDark ? Colors.white10 : Colors.black12),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: textColor,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 0.5,
                ),
                decoration: BoxDecoration(
                  color: isRoseCount && count > 0
                      ? theme.colors.accentRose
                      : (isSelected
                            ? theme.colors.accentBlue.withValues(alpha: 0.3)
                            : (theme.isDark
                                  ? Colors.white12
                                  : Colors.black.withValues(alpha: 0.06))),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  count > 99 ? '99+' : count.toString(),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: isRoseCount && count > 0
                        ? Colors.white
                        : (isSelected
                              ? theme.colors.accentBlue
                              : (theme.isDark
                                    ? Colors.white60
                                    : Colors.black54)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Thanh tiêu đề Compact Mode thu nhỏ
class _CompactTopBar extends StatelessWidget {
  final int onlineCount;
  final VoidCallback onToggleAlwaysOnTop;
  final VoidCallback onExpandToStandard;

  const _CompactTopBar({
    required this.onlineCount,
    required this.onToggleAlwaysOnTop,
    required this.onExpandToStandard,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.colors.headerBg,
        border: Border(
          bottom: BorderSide(color: theme.colors.headerBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Left section: Logo + Full App Name + Online Device Pill
          Expanded(
            child: Row(
              children: [
                // Logo Capsule
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.colors.accentBlue,
                        theme.colors.accentCyan,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.chat_bubble_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Tooltip(
                    message: appName,
                    child: Text(
                      appName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: theme.isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                // Online device pill
                Tooltip(
                  message: '$onlineCount ${lang.tr('onlineFilter')}',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colors.accentEmerald.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: theme.colors.accentEmerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$onlineCount',
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: theme.colors.accentEmerald,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),

          // 1. Always on Top 📌
          GlassIconButton(
            icon: coordinator.isAlwaysOnTop
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            tooltip: coordinator.isAlwaysOnTop
                ? lang.tr('unpinFromTop')
                : lang.tr('alwaysOnTop'),
            color: coordinator.isAlwaysOnTop
                ? theme.colors.accentAmber
                : (theme.isDark ? Colors.white70 : Colors.black87),
            size: 26,
            onPressed: onToggleAlwaysOnTop,
          ),
          const SizedBox(width: 3),

          // 2. Expand to Standard Mode ↗️
          GlassIconButton(
            icon: Icons.open_in_full_rounded,
            tooltip: lang.tr('standardMode'),
            color: theme.colors.accentBlue,
            size: 26,
            onPressed: onExpandToStandard,
          ),
          const SizedBox(width: 3),

          // 3. Minimize to Tray 🗕
          GlassIconButton(
            icon: Icons.remove_rounded,
            tooltip: lang.tr('trayExit'),
            color: theme.isDark ? Colors.white60 : Colors.black54,
            size: 26,
            onPressed: () {
              try {
                windowManager.hide();
              } catch (_) {}
            },
          ),
        ],
      ),
    );
  }
}

/// Thẻ hội thoại thu nhỏ phong cách Bento Glassmorphism
class _CompactPeerItemTile extends StatefulWidget {
  final PeerModel peer;
  final VoidCallback onTap;

  const _CompactPeerItemTile({required this.peer, required this.onTap});

  @override
  State<_CompactPeerItemTile> createState() => _CompactPeerItemTileState();
}

class _CompactPeerItemTileState extends State<_CompactPeerItemTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final peer = widget.peer;

    final isTyping =
        !peer.isAllUsers && !peer.isGroup && coordinator.isPeerTyping(peer.id);
    final isGroupTyping = peer.isGroup && coordinator.isGroupTyping(peer.id);

    final effectiveName = peer.effectiveDisplayName(lang);

    final String lastMessageSnippet;
    if (isTyping) {
      lastMessageSnippet = lang.tr('typing');
    } else if (isGroupTyping) {
      lastMessageSnippet =
          coordinator.getGroupTypingText(peer.id, lang) ?? lang.tr('typing');
    } else if (peer.lastMessage != null && peer.lastMessage!.isNotEmpty) {
      lastMessageSnippet = peer.lastMessage!;
    } else if (peer.isAllUsers) {
      lastMessageSnippet = lang.tr('allUsersDesc');
    } else {
      lastMessageSnippet = peer.ip;
    }

    final hoverBg = (theme.isDark ? Colors.white : Colors.black).withValues(
      alpha: _isHovered ? (theme.isDark ? 0.08 : 0.05) : 0.0,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: hoverBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isHovered
                ? (theme.isDark ? Colors.white12 : Colors.black12)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                // Avatar with online status dot
                Stack(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: peer.avatarColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: peer.avatarColor.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: peer.avatarAsset != null
                          ? ClipOval(
                              child: Image.asset(
                                peer.avatarAsset!,
                                width: 34,
                                height: 34,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(
                                  peer.initials,
                                  style: TextStyle(
                                    color: peer.avatarColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              peer.initials,
                              style: TextStyle(
                                color: peer.avatarColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                    ),
                    if (!peer.isAllUsers && !peer.isGroup)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: peer.status.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 9),

                // Name & Snippet
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              effectiveName,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: peer.unreadCount > 0
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: theme.isDark
                                    ? Colors.white
                                    : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (peer.isPinned) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.push_pin_rounded,
                              size: 11,
                              color: theme.colors.accentAmber,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        lastMessageSnippet,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isTyping
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isTyping
                              ? theme.colors.accentBlue
                              : (peer.unreadCount > 0
                                    ? (theme.isDark
                                          ? Colors.white70
                                          : Colors.black87)
                                    : (theme.isDark
                                          ? Colors.white38
                                          : Colors.black45)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // Unread Badge Pill
                if (peer.unreadCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colors.accentRose,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: theme.colors.accentRose.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Text(
                      peer.unreadCount > 99
                          ? '99+'
                          : peer.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
