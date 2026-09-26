import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../models/peer_model.dart';
import 'glass_components.dart';
import 'glass_dialog.dart';
import 'glass_image_lightbox.dart';
import 'app_avatar.dart';
import 'avatar_picker_dialog.dart';
import 'group_members_dialog.dart';
import 'create_group_dialog.dart';

class ConversationDetailsPanel extends StatelessWidget {
  final VoidCallback onClose;

  const ConversationDetailsPanel({super.key, required this.onClose});

  void _openFile(String path) {
    if (Platform.isWindows) {
      Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      Process.run('open', [path]);
    }
  }

  void _openFolder(String path) {
    if (Platform.isWindows) {
      Process.run('explorer.exe', ['/select,', path]);
    }
  }

  void _showZoomDialog(
    BuildContext context,
    String imagePath,
    String fileName,
  ) {
    showGlassImageLightbox(
      context: context,
      filePath: imagePath,
      fileName: fileName,
      onOpenFolder: () => _openFolder(imagePath),
    );
  }

  void _showEditNicknameDialog(
    BuildContext context,
    MessengerCoordinator coordinator,
    PeerModel peer,
  ) {
    final lang = context.read<LanguageProvider>();
    final controller = TextEditingController(
      text: peer.isGroup ? peer.name : peer.displayName,
    );

    showGlassDialog(
      context: context,
      builder: (ctx) => GlassDialog(
        title: peer.isGroup ? lang.tr('renameGroup') : lang.tr('editName'),
        icon: Icons.edit_note_rounded,
        width: 380,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final newName = controller.text.trim();
              if (peer.isGroup) {
                if (newName.isNotEmpty) {
                  coordinator.renameGroup(peer.id, newName);
                }
              } else {
                coordinator.setPeerNickname(
                  peer.id,
                  newName.isEmpty ? null : newName,
                );
              }
              Navigator.of(ctx).pop();
            },
            child: Text(lang.tr('save')),
          ),
        ],
        child: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 256,
          decoration: InputDecoration(
            hintText: peer.isGroup
                ? lang.tr('groupNameHint')
                : lang.tr('nickname'),
            border: const OutlineInputBorder(),
          ),
        ),
      ),
    );
  }

  void _showClearHistoryConfirm(
    BuildContext context,
    MessengerCoordinator coordinator,
    PeerModel peer,
  ) {
    final lang = context.read<LanguageProvider>();

    showGlassDialog(
      context: context,
      builder: (ctx) => GlassDialog(
        title: lang.tr('clearHistory'),
        icon: Icons.delete_sweep_rounded,
        width: 380,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              coordinator.clearConversation(peer.id);
              Navigator.of(ctx).pop();
            },
            child: Text(lang.tr('clearHistory')),
          ),
        ],
        child: Text(
          lang.tr('clearHistoryConfirm'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  void _showDisbandGroupConfirm(
    BuildContext context,
    MessengerCoordinator coordinator,
    PeerModel peer,
  ) {
    final lang = context.read<LanguageProvider>();
    showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => GlassDialog(
        title: lang.tr('deleteGroup'),
        icon: Icons.warning_amber_rounded,
        width: 380,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              coordinator.deleteGroup(peer.id, notifyPeers: true);
              Navigator.of(ctx).pop();
            },
            child: Text(lang.tr('confirm')),
          ),
        ],
        child: Text(
          lang.tr('disbandGroupConfirm'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  void _showLeaveGroupConfirm(
    BuildContext context,
    MessengerCoordinator coordinator,
    PeerModel peer,
  ) {
    final lang = context.read<LanguageProvider>();
    showGlassDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => GlassDialog(
        title: lang.tr('leaveGroup'),
        icon: Icons.logout_rounded,
        width: 380,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              coordinator.leaveGroup(peer.id);
              Navigator.of(ctx).pop();
            },
            child: Text(lang.tr('confirm')),
          ),
        ],
        child: Text(
          lang.tr('leaveGroupConfirm'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final peer = coordinator.selectedPeer;

    if (peer == null) return const SizedBox.shrink();

    final mediaMessages = coordinator.getMediaMessages(peer.id);
    final fileMessages = coordinator.getFileMessages(peer.id);

    final effectiveName = peer.effectiveDisplayName(lang);

    final effectiveOpacity = theme.isDark
        ? (theme.cardOpacity * 1.1).clamp(0.08, 0.95)
        : (theme.cardOpacity * 0.95).clamp(0.12, 0.95);
    final effectiveBlur = theme.cardBlur;
    final panelBg = (theme.isDark ? const Color(0xFF1E293B) : Colors.white)
        .withValues(alpha: effectiveOpacity);

    Widget content = Container(
      width: 290,
      decoration: BoxDecoration(
        color: panelBg,
        border: Border(
          left: BorderSide(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: theme.isDark ? 0.10 : 0.06,
            ),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Header
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: theme.colors.headerBg,
              border: Border(
                bottom: BorderSide(color: theme.colors.headerBorder, width: 1),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  lang.tr('conversationInfo'),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: theme.isDark
                        ? const Color(0xFFF8FAFC)
                        : Colors.black87,
                  ),
                ),
                GlassIconButton(
                  icon: Icons.close_rounded,
                  size: 30,
                  tooltip: lang.tr('cancel'),
                  onPressed: onClose,
                ),
              ],
            ),
          ),

          // Body (Scrollable)
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              children: [
                // Profile Avatar & Name
                Center(
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          AppAvatar(
                            peer: peer,
                            size: 68,
                            showStatus: !peer.isGroup && !peer.isAllUsers,
                            onTap: peer.isGroup
                                ? () => AvatarPickerDialog.show(
                                    context,
                                    targetGroupId: peer.id,
                                    groupName: peer.name,
                                    initialColor: peer.avatarColor,
                                    initialPreset: peer.avatarPreset,
                                    initialCustomPath: peer.customAvatarPath,
                                    initialCustomBase64:
                                        peer.customAvatarBase64,
                                    initialGroupName: peer.name,
                                    canRenameGroup: coordinator.isGroupAdmin(
                                      peer.id,
                                    ),
                                  )
                                : null,
                          ),
                          if (peer.isGroup)
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: InkWell(
                                onTap: () => AvatarPickerDialog.show(
                                  context,
                                  targetGroupId: peer.id,
                                  groupName: peer.name,
                                  initialColor: peer.avatarColor,
                                  initialPreset: peer.avatarPreset,
                                  initialCustomPath: peer.customAvatarPath,
                                  initialCustomBase64: peer.customAvatarBase64,
                                  initialGroupName: peer.name,
                                  canRenameGroup: coordinator.isGroupAdmin(
                                    peer.id,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: theme.colors.accentBlue,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: theme.isDark
                                          ? const Color(0xFF1E293B)
                                          : Colors.white,
                                      width: 2,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              effectiveName,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: theme.isDark
                                    ? const Color(0xFFF8FAFC)
                                    : Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!peer.isAllUsers &&
                              !peer.isAiAssistant &&
                              (!peer.isGroup ||
                                  coordinator.isGroupAdmin(peer.id))) ...[
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => _showEditNicknameDialog(
                                context,
                                coordinator,
                                peer,
                              ),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  Icons.edit_outlined,
                                  size: 15,
                                  color: theme.colors.accentBlue,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (peer.customNickname != null &&
                          peer.customNickname!.isNotEmpty)
                        Text(
                          '(${peer.name})',
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.isDark
                                ? Colors.white54
                                : Colors.black54,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // 3 Action Buttons Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionButton(
                      icon: peer.isMuted
                          ? Icons.notifications_off_rounded
                          : Icons.notifications_none_rounded,
                      label: peer.isMuted ? lang.tr('unmute') : lang.tr('mute'),
                      isActive: peer.isMuted,
                      onTap: () => coordinator.toggleMutePeer(peer.id),
                    ),
                    _ActionButton(
                      icon: peer.isPinned
                          ? Icons.push_pin_rounded
                          : Icons.push_pin_outlined,
                      label: peer.isPinned ? lang.tr('unpin') : lang.tr('pin'),
                      isActive: peer.isPinned,
                      onTap: () => coordinator.togglePinPeer(peer.id),
                    ),
                    if (!peer.isAllUsers &&
                        (!peer.isGroup || coordinator.isGroupAdmin(peer.id)))
                      _ActionButton(
                        icon: peer.isGroup
                            ? Icons.group_add_rounded
                            : Icons.add_circle_outline_rounded,
                        label: peer.isGroup
                            ? lang.tr('addMember')
                            : lang.tr('createGroup'),
                        isActive: false,
                        onTap: () {
                          if (peer.isGroup) {
                            GroupMembersDialog.show(context, peer);
                          } else {
                            CreateGroupDialog.show(
                              context,
                              initialSelectedPeer: peer,
                            );
                          }
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Group Members Section
                if (peer.isGroup && !peer.isAllUsers) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _SectionHeader(
                        title:
                            '${lang.tr('groupMembers')} (${coordinator.groupMembers(peer.id).length})',
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => GroupMembersDialog.show(context, peer),
                        icon: const Icon(Icons.people_alt_rounded, size: 14),
                        label: Text(
                          lang.tr('viewAll'),
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildGroupMembersList(
                    context,
                    coordinator,
                    peer,
                    theme,
                    lang,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                ],

                // LAN Network Details
                if (!peer.isGroup && !peer.isAllUsers) ...[
                  _SectionHeader(title: lang.tr('networkDetails')),
                  const SizedBox(height: 6),
                  _DetailRow(
                    icon: Icons.lan_rounded,
                    label: lang.tr('ipAddress'),
                    value: peer.ip,
                    canCopy: true,
                  ),
                  _DetailRow(
                    icon: Icons.settings_ethernet_rounded,
                    label: lang.tr('port'),
                    value: '${peer.port}',
                  ),
                  if (peer.workgroup.isNotEmpty)
                    _DetailRow(
                      icon: Icons.workspaces_rounded,
                      label: lang.tr('workgroup'),
                      value: peer.workgroup,
                    ),
                  _DetailRow(
                    icon: Icons.wifi_tethering_rounded,
                    label: lang.tr('status'),
                    value: peer.status.label,
                    valueColor: peer.status.color,
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                ],

                // Photos & Videos Gallery
                _SectionHeader(
                  title: '${lang.tr('mediaPhotos')} (${mediaMessages.length})',
                ),
                const SizedBox(height: 8),
                if (mediaMessages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      lang.tr('noMediaShared'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.isDark ? Colors.white38 : Colors.black38,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 6,
                          mainAxisSpacing: 6,
                        ),
                    itemCount: mediaMessages.length > 9
                        ? 9
                        : mediaMessages.length,
                    itemBuilder: (context, index) {
                      final msg = mediaMessages[index];
                      final file = File(msg.fileAttachment?.localPath ?? '');
                      return InkWell(
                        onTap: () {
                          if (file.existsSync()) {
                            _showZoomDialog(
                              context,
                              file.path,
                              msg.fileAttachment!.fileName,
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: file.existsSync()
                              ? Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        color: Colors.grey.withValues(
                                          alpha: 0.2,
                                        ),
                                        child: const Icon(
                                          Icons.broken_image_rounded,
                                          size: 20,
                                        ),
                                      ),
                                )
                              : Container(
                                  color: Colors.grey.withValues(alpha: 0.2),
                                  child: const Icon(
                                    Icons.image_not_supported,
                                    size: 20,
                                  ),
                                ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Files Section
                _SectionHeader(
                  title: '${lang.tr('sharedFiles')} (${fileMessages.length})',
                ),
                const SizedBox(height: 8),
                if (fileMessages.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      lang.tr('noFilesShared'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.isDark ? Colors.white38 : Colors.black38,
                        fontStyle: FontStyle.italic,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: fileMessages.length > 5
                        ? 5
                        : fileMessages.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final msg = fileMessages[index];
                      final att = msg.fileAttachment!;
                      return InkWell(
                        onTap: () {
                          if (att.localPath != null &&
                              File(att.localPath!).existsSync()) {
                            _openFile(att.localPath!);
                          }
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (theme.isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file_rounded,
                                size: 22,
                                color: Color(0xFF3B82F6),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      att.fileName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                        color: theme.isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                    Text(
                                      att.formattedSize,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: theme.isDark
                                            ? Colors.white38
                                            : Colors.black45,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (att.localPath != null)
                                IconButton(
                                  icon: const Icon(
                                    Icons.folder_open_rounded,
                                    size: 16,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: lang.tr('openFolder'),
                                  onPressed: () => _openFolder(att.localPath!),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 18),
                const Divider(height: 1),
                const SizedBox(height: 14),

                // Management & Clear History
                InkWell(
                  onTap: () =>
                      _showClearHistoryConfirm(context, coordinator, peer),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.redAccent.withValues(alpha: 0.25),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          lang.tr('clearHistory'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.redAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (peer.isGroup && !peer.isAllUsers) ...[
                  const SizedBox(height: 8),
                  // Leave group button
                  InkWell(
                    onTap: () =>
                        _showLeaveGroupConfirm(context, coordinator, peer),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Colors.orangeAccent.withValues(alpha: 0.25),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.logout_rounded,
                            size: 16,
                            color: Colors.orangeAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            lang.tr('leaveGroup'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.orangeAccent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (coordinator.isGroupAdmin(peer.id)) ...[
                    const SizedBox(height: 8),
                    // Disband group button (Chỉ Admin/Trưởng nhóm mới có quyền giải tán nhóm)
                    InkWell(
                      onTap: () =>
                          _showDisbandGroupConfirm(context, coordinator, peer),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.25),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.group_remove_rounded,
                              size: 16,
                              color: Colors.redAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              lang.tr('deleteGroup'),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
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

  Widget _buildGroupMembersList(
    BuildContext context,
    MessengerCoordinator coordinator,
    PeerModel groupPeer,
    ThemeProvider theme,
    LanguageProvider lang,
  ) {
    final members = coordinator.groupMembers(groupPeer.id);
    final group = coordinator.groupsMap[groupPeer.id];

    if (members.isEmpty) {
      return Text(
        lang.tr('noAvailableMembers'),
        style: TextStyle(
          fontSize: 11.5,
          color: theme.isDark ? Colors.white38 : Colors.black38,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    final displayMembers = members.take(6).toList();

    return Column(
      children: [
        for (final m in displayMembers)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: InkWell(
              onTap: () => GroupMembersDialog.show(context, groupPeer),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    AppAvatar(
                      peer: m,
                      isLocal: m.id == 'me',
                      size: 28,
                      showStatus: true,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: theme.isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            m.ip,
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.isDark
                                  ? Colors.white54
                                  : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (m.id != 'me' &&
                        coordinator.isGroupAdmin(groupPeer.id) &&
                        group != null &&
                        !group.isCreator(m.id) &&
                        !group.isCreator(
                          group.memberRecords[m.id]?.elementAtOrNull(2) ?? '',
                        ))
                      IconButton(
                        icon: Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 16,
                          color: Colors.red.withValues(alpha: 0.6),
                        ),
                        tooltip: lang.tr('removeMember'),
                        onPressed: () {
                          coordinator.removeGroupMember(groupPeer.id, m.id);
                        },
                        constraints: const BoxConstraints(
                          minWidth: 28,
                          minHeight: 28,
                        ),
                        padding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
            ),
          ),
        if (members.length > 6)
          TextButton(
            onPressed: () => GroupMembersDialog.show(context, groupPeer),
            child: Text(
              '${lang.tr('viewAll')} (+${members.length - 6})',
              style: TextStyle(fontSize: 11, color: theme.colors.accentBlue),
            ),
          ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    return Text(
      title,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: theme.isDark ? Colors.white70 : Colors.black87,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool canCopy;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.canCopy = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: theme.isDark ? Colors.white38 : Colors.black45,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.isDark ? Colors.white54 : Colors.black54,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color:
                  valueColor ?? (theme.isDark ? Colors.white : Colors.black87),
            ),
          ),
          if (canCopy) ...[
            const SizedBox(width: 4),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(lang.tr('copiedToClipboard')),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.copy_rounded,
                  size: 13,
                  color: theme.colors.accentBlue,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final color = isActive
        ? theme.colors.accentBlue
        : (theme.isDark ? Colors.white60 : Colors.black54);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colors.accentBlue.withValues(alpha: 0.12)
              : (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.04,
                ),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isActive
                ? theme.colors.accentBlue.withValues(alpha: 0.3)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
