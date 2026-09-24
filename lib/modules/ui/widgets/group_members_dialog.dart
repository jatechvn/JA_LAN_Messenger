import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/peer_model.dart';
import '../../services/messenger_coordinator.dart';
import '../../localization/app_locale.dart';
import 'app_avatar.dart';
import 'avatar_picker_dialog.dart';
import 'glass_dialog.dart';
import '../../theme/theme_provider.dart';

/// Hộp thoại xem danh sách và quản lý thành viên nhóm
class GroupMembersDialog extends StatefulWidget {
  final PeerModel groupPeer;

  const GroupMembersDialog({super.key, required this.groupPeer});

  static Future<void> show(BuildContext context, PeerModel groupPeer) {
    return showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => GroupMembersDialog(groupPeer: groupPeer),
    );
  }

  @override
  State<GroupMembersDialog> createState() => _GroupMembersDialogState();
}

class _GroupMembersDialogState extends State<GroupMembersDialog> {
  String _searchQuery = '';

  void _showAddMemberPicker(BuildContext context) {
    final coordinator = context.read<MessengerCoordinator>();
    final lang = context.read<LanguageProvider>();
    final isDark = ThemeProvider.of(context, listen: false).isDark;
    final ink = isDark ? Colors.white : Colors.black87;
    final currentMemberIds = coordinator
        .groupMembers(widget.groupPeer.id)
        .map((p) => p.id)
        .toSet();

    // Lấy danh sách các peer chưa có trong nhóm
    final candidatePeers = coordinator.peers
        .where(
          (p) =>
              !p.isGroup &&
              !p.isAllUsers &&
              !p.isAi &&
              !currentMemberIds.contains(p.id),
        )
        .toList();

    final selectedToAdd = <String>{};
    var pickerSearch = '';

    showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setPickerState) {
            final filteredCandidates = candidatePeers.where((p) {
              if (pickerSearch.isEmpty) return true;
              final q = pickerSearch.toLowerCase();
              return p.name.toLowerCase().contains(q) ||
                  p.ip.contains(q) ||
                  (p.hostname?.toLowerCase().contains(q) ?? false);
            }).toList();

            return GlassDialog(
              title: lang.tr('addMembers'),
              icon: Icons.person_add_rounded,
              width: 440,
              scrollable: true,
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: Text(
                    lang.tr('cancel'),
                    style: TextStyle(color: ink.withValues(alpha: 0.7)),
                  ),
                ),
                ElevatedButton(
                  onPressed: selectedToAdd.isEmpty
                      ? null
                      : () {
                          coordinator.addGroupMembers(
                            widget.groupPeer.id,
                            selectedToAdd.toList(),
                          );
                          Navigator.of(dialogCtx).pop();
                          setState(() {});
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(lang.tr('confirm')),
                ),
              ],
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    onChanged: (val) =>
                        setPickerState(() => pickerSearch = val),
                    style: TextStyle(color: ink, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: lang.tr('searchMembers'),
                      hintStyle: TextStyle(color: ink.withValues(alpha: 0.65)),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: ink.withValues(alpha: 0.6),
                      ),
                      isDense: true,
                      filled: true,
                      fillColor: ink.withValues(alpha: 0.06),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 240,
                    child: filteredCandidates.isEmpty
                        ? Center(
                            child: Text(
                              lang.tr('noPeersFound'),
                              style: TextStyle(
                                color: ink.withValues(alpha: 0.65),
                                fontSize: 13,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredCandidates.length,
                            itemBuilder: (context, idx) {
                              final peer = filteredCandidates[idx];
                              final isSelected = selectedToAdd.contains(
                                peer.id,
                              );

                              return CheckboxListTile(
                                value: isSelected,
                                onChanged: (checked) {
                                  setPickerState(() {
                                    if (checked == true) {
                                      selectedToAdd.add(peer.id);
                                    } else {
                                      selectedToAdd.remove(peer.id);
                                    }
                                  });
                                },
                                activeColor: const Color(0xFF3B82F6),
                                secondary: AppAvatar(
                                  peer: peer,
                                  size: 32,
                                  showStatus: true,
                                ),
                                title: Text(
                                  peer.name,
                                  style: TextStyle(
                                    color: ink,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                subtitle: Text(
                                  peer.ip,
                                  style: TextStyle(
                                    color: ink.withValues(alpha: 0.65),
                                    fontSize: 11,
                                  ),
                                ),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<MessengerCoordinator>();
    final lang = context.watch<LanguageProvider>();
    final isDark = ThemeProvider.of(context).isDark;
    final ink = isDark ? Colors.white : Colors.black87;

    // Tìm lại thông tin group mới nhất từ coordinator
    final matchingGroups = coordinator.groups.where(
      (group) => group.id == widget.groupPeer.id,
    );
    final updatedPeer = matchingGroups.isEmpty
        ? widget.groupPeer
        : PeerModel.fromGroup(matchingGroups.first);

    final members = coordinator.groupMembers(updatedPeer.id);

    final filteredMembers = members.where((m) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return m.name.toLowerCase().contains(q) ||
          m.ip.contains(q) ||
          (m.hostname?.toLowerCase().contains(q) ?? false);
    }).toList();

    final isLocalAdmin = coordinator.isGroupAdmin(updatedPeer.id);

    return GlassDialog(
      title: '${updatedPeer.name} (${members.length})',
      icon: Icons.groups_rounded,
      width: 440,
      scrollable: true,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            lang.tr('confirm'),
            style: TextStyle(
              color: isDark ? const Color(0xFF60A5FA) : const Color(0xFF1D4ED8),
            ),
          ),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 0. Thông tin & Đổi Avatar nhóm
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: ink.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: ink.withValues(alpha: 0.08)),
            ),
            child: Row(
              children: [
                AppAvatar(peer: updatedPeer, size: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        updatedPeer.name,
                        style: TextStyle(
                          color: ink,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${members.length} ${lang.tr('members') != 'members' ? lang.tr('members') : 'thành viên'}',
                        style: TextStyle(
                          color: ink.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isLocalAdmin)
                  TextButton.icon(
                    onPressed: () async {
                      await AvatarPickerDialog.show(
                        context,
                        targetGroupId: updatedPeer.id,
                        groupName: updatedPeer.name,
                        initialColor: updatedPeer.avatarColor,
                        initialPreset: updatedPeer.avatarPreset,
                        initialCustomPath: updatedPeer.customAvatarPath,
                        initialCustomBase64: updatedPeer.customAvatarBase64,
                        initialGroupName: updatedPeer.name,
                        canRenameGroup: coordinator.isGroupAdmin(
                          updatedPeer.id,
                        ),
                      );
                      setState(() {});
                    },
                    icon: const Icon(Icons.edit_outlined, size: 14),
                    label: Text(
                      lang.tr('changeGroupAvatar'),
                      style: const TextStyle(fontSize: 11),
                    ),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ),

          // 1. Ô tìm kiếm thành viên
          TextField(
            onChanged: (val) => setState(() => _searchQuery = val),
            style: TextStyle(color: ink, fontSize: 13),
            decoration: InputDecoration(
              hintText: lang.tr('searchMembers'),
              hintStyle: TextStyle(color: ink.withValues(alpha: 0.65)),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 18,
                color: ink.withValues(alpha: 0.6),
              ),
              isDense: true,
              filled: true,
              fillColor: ink.withValues(alpha: 0.06),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 2. Nút Thêm thành viên. Thành viên thường không mời thêm người.
          if (isLocalAdmin)
            OutlinedButton.icon(
              onPressed: () => _showAddMemberPicker(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: (isDark
                    ? const Color(0xFF60A5FA)
                    : const Color(0xFF1D4ED8)),
                side: BorderSide(
                  color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.person_add_rounded, size: 18),
              label: Text(lang.tr('addMembers')),
            ),
          const SizedBox(height: 12),

          // 3. Danh sách thành viên
          SizedBox(
            height: 280,
            child: filteredMembers.isEmpty
                ? Center(
                    child: Text(
                      lang.tr('noPeersFound'),
                      style: TextStyle(
                        color: ink.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                  )
                : ListView.separated(
                    itemCount: filteredMembers.length,
                    separatorBuilder: (_, _) =>
                        Divider(color: ink.withValues(alpha: 0.06), height: 1),
                    itemBuilder: (context, idx) {
                      final member = filteredMembers[idx];
                      final isOnline = member.status != PeerStatus.offline;
                      final groupModel = matchingGroups.isEmpty
                          ? null
                          : matchingGroups.first;
                      final recordHash = groupModel?.memberRecords[member.id]
                          ?.elementAtOrNull(2);
                      final memberIsCreator = member.id == 'me'
                          ? coordinator.isGroupCreator(updatedPeer.id)
                          : groupModel != null &&
                                (groupModel.isCreator(member.id) ||
                                    (recordHash != null &&
                                        groupModel.isCreator(recordHash)));
                      final memberIsAdmin = member.id == 'me'
                          ? coordinator.isGroupAdmin(updatedPeer.id)
                          : groupModel != null &&
                                (groupModel.isAdmin(member.id) ||
                                    (recordHash != null &&
                                        groupModel.isAdmin(recordHash)));
                      final isCreatorView = coordinator.isGroupCreator(
                        updatedPeer.id,
                      );

                      return ListTile(
                        leading: AppAvatar(
                          peer: member,
                          isLocal: member.id == 'me',
                          size: 34,
                          showStatus: true,
                        ),
                        title: Text(
                          member.name,
                          style: TextStyle(
                            color: ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          '${memberIsCreator
                              ? '${lang.tr('groupCreatorBadge')} • '
                              : memberIsAdmin
                              ? '${lang.tr('groupAdminBadge')} • '
                              : ''}${member.ip} • ${isOnline ? lang.tr('online') : lang.tr('offline')}',
                          style: TextStyle(
                            color: isOnline
                                ? (isDark
                                      ? const Color(0xFF4ADE80)
                                      : const Color(0xFF15803D))
                                : ink.withValues(alpha: 0.65),
                            fontSize: 11,
                          ),
                        ),
                        trailing:
                            member.id == 'me' ||
                                !isLocalAdmin ||
                                memberIsCreator
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isCreatorView)
                                    PopupMenuButton<String>(
                                      tooltip: lang.tr('groupAdminBadge'),
                                      onSelected: (action) {
                                        if (action == 'promote') {
                                          coordinator.setGroupAdmin(
                                            updatedPeer.id,
                                            member.id,
                                            admin: true,
                                          );
                                        } else if (action == 'demote') {
                                          coordinator.setGroupAdmin(
                                            updatedPeer.id,
                                            member.id,
                                            admin: false,
                                          );
                                        } else if (action == 'transfer') {
                                          coordinator.transferGroupCreator(
                                            updatedPeer.id,
                                            member.id,
                                          );
                                        }
                                        setState(() {});
                                      },
                                      itemBuilder: (context) => [
                                        if (!memberIsAdmin)
                                          PopupMenuItem(
                                            value: 'promote',
                                            child: Text(
                                              lang.tr('promoteAdmin'),
                                            ),
                                          ),
                                        if (memberIsAdmin)
                                          PopupMenuItem(
                                            value: 'demote',
                                            child: Text(lang.tr('demoteAdmin')),
                                          ),
                                        PopupMenuItem(
                                          value: 'transfer',
                                          child: Text(
                                            lang.tr('transferCreator'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.remove_circle_outline_rounded,
                                      size: 18,
                                      color: Colors.red.withValues(alpha: 0.7),
                                    ),
                                    tooltip: lang.tr('removeMember'),
                                    onPressed: () {
                                      coordinator.removeGroupMember(
                                        updatedPeer.id,
                                        member.id,
                                      );
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
