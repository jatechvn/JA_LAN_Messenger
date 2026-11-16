part of '../peer_list_view.dart';

class _PeerListTile extends StatelessWidget {
  final PeerModel peer;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeerListTile({
    super.key,
    required this.peer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final activeBg = theme.isDark
        ? theme.colors.accentBlue.withValues(alpha: 0.22)
        : theme.colors.accentBlue.withValues(alpha: 0.14);

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isSelected
            ? Border.all(
                color: theme.colors.accentBlue.withValues(
                  alpha: theme.isDark ? 0.50 : 0.40,
                ),
                width: 1,
              )
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          canRequestFocus: false,
          onTap: onTap,
          onSecondaryTapDown: (details) =>
              _showContextMenu(context, details.globalPosition),
          borderRadius: BorderRadius.circular(10),
          hoverColor: (theme.isDark ? Colors.white : Colors.black).withValues(
            alpha: 0.06,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                // Avatar with Status Dot
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AppAvatar(peer: peer, size: 38, isCircle: true),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: StatusBadge(status: peer.status),
                    ),
                  ],
                ),
                const SizedBox(width: 10),

                // Name & Last message
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                if (peer.isPinned) ...[
                                  Icon(
                                    Icons.push_pin_rounded,
                                    size: 12,
                                    color: theme.colors.accentAmber,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Flexible(
                                  child: Text(
                                    peer.effectiveDisplayName(lang),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      color: theme.isDark
                                          ? const Color(0xFFF8FAFC)
                                          : Colors.black87,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (peer.isMuted) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    Icons.notifications_off_rounded,
                                    size: 11,
                                    color: theme.isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (peer.isAiAssistant)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF8B5CF6,
                                ).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(
                                    0xFF8B5CF6,
                                  ).withValues(alpha: 0.5),
                                  width: 0.8,
                                ),
                              ),
                              child: const Text(
                                'AI',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF8B5CF6),
                                ),
                              ),
                            ),
                          if (peer.isBeebeep)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Bee',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber,
                                ),
                              ),
                            ),
                          if (coordinator.isNewlyAddedPeer(peer.id))
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4.5,
                                vertical: 1,
                              ),
                              margin: const EdgeInsets.only(left: 4),
                              decoration: BoxDecoration(
                                color: theme.colors.accentEmerald.withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: theme.colors.accentEmerald.withValues(
                                    alpha: 0.45,
                                  ),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                lang.tr('badgeNewFriend'),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colors.accentEmerald,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      (!isSelected && coordinator.hasDraft(peer.id))
                          ? Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${lang.tr('draftPrefix')} ',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: theme.colors.accentAmber,
                                    ),
                                  ),
                                  TextSpan(
                                    text: coordinator
                                        .getDraft(peer.id)
                                        .replaceAll('\n', ' '),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: theme.isDark
                                          ? const Color(0xFFCBD5E1)
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : Text(
                              peer.lastMessage != null
                                  ? StickerService.formatLastMessagePreview(
                                      peer.lastMessage!,
                                      lang.tr('stickers'),
                                    )
                                  : peer.ip,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: peer.unreadCount > 0
                                    ? (theme.isDark
                                          ? const Color(0xFFF8FAFC)
                                          : Colors.black87)
                                    : (theme.isDark
                                          ? const Color(0xFF94A3B8)
                                          : Colors.black45),
                                fontWeight: peer.unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ],
                  ),
                ),

                // Unread Badge
                if (peer.unreadCount > 0)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colors.accentRose,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      peer.unreadCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
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

  void _showContextMenu(BuildContext context, Offset position) async {
    final coordinator = context.read<MessengerCoordinator>();
    final lang = context.read<LanguageProvider>();
    final theme = ThemeProvider.of(context);

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx + 1,
        position.dy + 1,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: theme.isDark ? const Color(0xFF232530) : Colors.white,
      items: [
        if (coordinator.isNewlyAddedPeer(peer.id))
          PopupMenuItem<String>(
            value: 'dismiss_new',
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.label_off_outlined,
                  size: 16,
                  color: theme.colors.accentEmerald,
                ),
                const SizedBox(width: 10),
                Text(
                  lang.tr('dismissNewFriendBadge'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'pin',
          height: 38,
          child: Row(
            children: [
              Icon(
                peer.isPinned
                    ? Icons.push_pin_rounded
                    : Icons.push_pin_outlined,
                size: 16,
                color: peer.isPinned
                    ? theme.colors.accentAmber
                    : (theme.isDark ? Colors.white70 : Colors.black87),
              ),
              const SizedBox(width: 10),
              Text(
                peer.isPinned ? lang.tr('unpinChat') : lang.tr('pinChat'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'mute',
          height: 38,
          child: Row(
            children: [
              Icon(
                peer.isMuted
                    ? Icons.notifications_rounded
                    : Icons.notifications_off_rounded,
                size: 16,
                color: theme.isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 10),
              Text(
                peer.isMuted ? lang.tr('unmute') : lang.tr('mute'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (!peer.isAllUsers) ...[
          const PopupMenuDivider(height: 8),
          PopupMenuItem<String>(
            value: 'clear',
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  size: 16,
                  color: Colors.redAccent.shade200,
                ),
                const SizedBox(width: 10),
                Text(
                  lang.tr('clearHistory'),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.redAccent.shade200,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );

    if (selected == 'dismiss_new') {
      coordinator.dismissNewlyAddedPeer(peer.id);
    } else if (selected == 'pin') {
      coordinator.togglePinPeer(peer.id);
    } else if (selected == 'mute') {
      coordinator.toggleMutePeer(peer.id);
    } else if (selected == 'clear') {
      if (context.mounted) {
        final confirm = await showGlassDialog<bool>(
          context: context,
          builder: (ctx) => GlassDialog(
            title: lang.tr('clearHistory'),
            icon: Icons.delete_outline_rounded,
            width: 360,
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(lang.tr('cancel')),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.redAccent,
                ),
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(lang.tr('clearHistory')),
              ),
            ],
            child: Text(
              lang.tr('clearHistoryConfirm'),
              style: const TextStyle(fontSize: 13),
            ),
          ),
        );
        if (confirm == true) {
          coordinator.clearConversation(peer.id);
        }
      }
    }
  }
}
