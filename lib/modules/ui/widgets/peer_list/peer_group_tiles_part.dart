part of '../peer_list_view.dart';

class _PinnedAllUsersTile extends StatelessWidget {
  final bool isSelected;
  final VoidCallback onTap;

  const _PinnedAllUsersTile({required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final allUsers = coordinator.allUsersPeer;
    final activeBg = theme.colors.accentBlue.withValues(alpha: 0.14);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? activeBg
                : (theme.isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.04,
                  ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? theme.colors.accentBlue.withValues(alpha: 0.4)
                  : theme.colors.accentBlue.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              // Glowing Broadcast Icon
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colors.accentBlue,
                      const Color(0xFF6366F1), // Indigo
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colors.accentBlue.withValues(alpha: 0.3),
                      blurRadius: 6,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.campaign_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            lang.tr('allUsersTitle'),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? theme.colors.accentBlue
                                  : (theme.isDark
                                        ? Colors.white
                                        : Colors.black87),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colors.accentBlue.withValues(
                              alpha: 0.15,
                            ),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text(
                            'ALL',
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3B82F6),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      allUsers.lastMessage != null
                          ? StickerService.formatLastMessagePreview(
                              allUsers.lastMessage!,
                              lang.tr('stickers'),
                            )
                          : lang.tr('allUsersDesc'),
                      style: TextStyle(
                        fontSize: 10.5,
                        color: theme.isDark ? Colors.white38 : Colors.black45,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (allUsers.unreadCount > 0)
                Container(
                  margin: const EdgeInsets.only(left: 6),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1.5,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colors.accentRose,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    allUsers.unreadCount.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupListTile extends StatelessWidget {
  final GroupModel group;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _GroupListTile({
    super.key,
    required this.group,
    required this.isSelected,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final isAdmin = coordinator.isGroupAdmin(group.id);
    final groupPeer = coordinator.getPeerForGroup(group);
    final activeBg = theme.colors.accentBlue.withValues(alpha: 0.14);

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: isSelected ? activeBg : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: isSelected
            ? Border.all(
                color: theme.colors.accentBlue.withValues(alpha: 0.4),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                AppAvatar(peer: groupPeer, size: 34, isCircle: true),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              group.name,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? theme.colors.accentBlue
                                    : (theme.isDark
                                          ? Colors.white
                                          : Colors.black87),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (group.lastMessageTime != null)
                            Text(
                              _formatTime(group.lastMessageTime!),
                              style: TextStyle(
                                fontSize: 9.5,
                                color: theme.isDark
                                    ? Colors.white38
                                    : Colors.black38,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Expanded(
                            child:
                                (!isSelected &&
                                    coordinator.hasDraft(groupPeer.id))
                                ? Text.rich(
                                    TextSpan(
                                      children: [
                                        TextSpan(
                                          text: '${lang.tr('draftPrefix')} ',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w600,
                                            color: theme.colors.accentAmber,
                                          ),
                                        ),
                                        TextSpan(
                                          text: coordinator
                                              .getDraft(groupPeer.id)
                                              .replaceAll('\n', ' '),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: theme.isDark
                                                ? Colors.white70
                                                : Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Text(
                                    group.lastMessage != null
                                        ? StickerService.formatLastMessagePreview(
                                            group.lastMessage!,
                                            lang.tr('stickers'),
                                          )
                                        : '${group.memberCount} ${lang.tr('groupMembersCount')}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: group.unreadCount > 0
                                          ? (theme.isDark
                                                ? Colors.white
                                                : Colors.black87)
                                          : (theme.isDark
                                                ? Colors.white38
                                                : Colors.black45),
                                      fontWeight: group.unreadCount > 0
                                          ? FontWeight.w600
                                          : FontWeight.normal,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                          ),
                          if (group.unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colors.accentRose,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                group.unreadCount.toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Tooltip(
                  message: isAdmin
                      ? lang.tr('deleteGroup')
                      : lang.tr('leaveGroup'),
                  child: IconButton(
                    icon: Icon(
                      isAdmin ? Icons.close_rounded : Icons.logout_rounded,
                      size: 14,
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 20,
                      minHeight: 20,
                    ),
                    color: theme.isDark ? Colors.white24 : Colors.black26,
                    hoverColor:
                        (isAdmin
                                ? theme.colors.accentRose
                                : theme.colors.accentAmber)
                            .withValues(alpha: 0.2),
                    onPressed: () {
                      if (isAdmin) {
                        _confirmDisbandGroup(context, group);
                      } else {
                        _confirmLeaveGroup(context, group);
                      }
                    },
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
    final isAdmin = coordinator.isGroupAdmin(group.id);
    final groupPeer = coordinator.getPeerForGroup(group);

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
        if (isAdmin) ...[
          PopupMenuItem<String>(
            value: 'rename',
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: theme.isDark ? Colors.white70 : Colors.black87,
                ),
                const SizedBox(width: 10),
                Text(
                  lang.tr('renameGroup'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'avatar',
            height: 38,
            child: Row(
              children: [
                Icon(
                  Icons.image_outlined,
                  size: 16,
                  color: theme.isDark ? Colors.white70 : Colors.black87,
                ),
                const SizedBox(width: 10),
                Text(
                  lang.tr('changeGroupAvatar'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
        PopupMenuItem<String>(
          value: 'members',
          height: 38,
          child: Row(
            children: [
              Icon(
                Icons.people_outline_rounded,
                size: 16,
                color: theme.isDark ? Colors.white70 : Colors.black87,
              ),
              const SizedBox(width: 10),
              Text(
                lang.tr('groupMembers'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'leave_or_disband',
          height: 38,
          child: Row(
            children: [
              Icon(
                isAdmin ? Icons.delete_outline_rounded : Icons.logout_rounded,
                size: 16,
                color: Colors.redAccent.shade200,
              ),
              const SizedBox(width: 10),
              Text(
                isAdmin ? lang.tr('deleteGroup') : lang.tr('leaveGroup'),
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.redAccent.shade200,
                ),
              ),
            ],
          ),
        ),
      ],
    );

    if (!context.mounted) return;

    if (selected == 'rename') {
      showQuickNicknameDialog(
        context: context,
        coordinator: coordinator,
        peer: groupPeer,
        lang: lang,
      );
    } else if (selected == 'avatar') {
      await AvatarPickerDialog.show(
        context,
        targetGroupId: groupPeer.id,
        groupName: groupPeer.name,
        initialColor: groupPeer.avatarColor,
        initialPreset: groupPeer.avatarPreset,
        initialCustomPath: groupPeer.customAvatarPath,
        initialCustomBase64: groupPeer.customAvatarBase64,
        initialGroupName: groupPeer.name,
        canRenameGroup: isAdmin,
      );
    } else if (selected == 'members') {
      GroupMembersDialog.show(context, groupPeer);
    } else if (selected == 'leave_or_disband') {
      if (isAdmin) {
        _confirmDisbandGroup(context, group);
      } else {
        _confirmLeaveGroup(context, group);
      }
    }
  }

  static String _formatTime(DateTime dt) {
    final localDt = dt.toLocal();
    final now = DateTime.now();
    if (now.year == localDt.year &&
        now.month == localDt.month &&
        now.day == localDt.day) {
      final h = localDt.hour.toString().padLeft(2, '0');
      final m = localDt.minute.toString().padLeft(2, '0');
      return '$h:$m';
    }
    return '${localDt.day}/${localDt.month}';
  }
}
