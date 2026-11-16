import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../constants.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../services/sticker_service.dart';
import '../../models/peer_model.dart';
import '../../models/group_model.dart';
import '../../network/network_utils.dart';
import 'glass_components.dart';
import 'glass_dialog.dart';
import 'glass_search_history_field.dart';
import 'bounce_marquee_text.dart';
import 'create_group_dialog.dart';
import 'app_avatar.dart';
import 'avatar_picker_dialog.dart';
import 'contact_profile_dialog.dart';
import 'group_members_dialog.dart';
import '../../services/app_power_manager.dart';

part 'peer_list/peer_header_and_dialogs_part.dart';
part 'peer_list/peer_add_ip_dialog_part.dart';
part 'peer_list/peer_group_tiles_part.dart';
part 'peer_list/peer_tile_part.dart';
part 'peer_list/peer_scan_banner_part.dart';

enum _PeerCategory { all, online, groups }

class PeerListView extends StatefulWidget {
  const PeerListView({super.key});

  @override
  State<PeerListView> createState() => _PeerListViewState();
}

class _PeerListViewState extends State<PeerListView> {
  _PeerCategory _activeCategory = _PeerCategory.all;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final allPeers = coordinator.peers;
    final groups = List<GroupModel>.from(coordinator.groups)
      ..sort((a, b) {
        final aTime =
            a.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            b.lastMessageTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
    final onlinePeers = coordinator.onlinePeers;

    final List<PeerModel> displayPeers;
    switch (_activeCategory) {
      case _PeerCategory.all:
        displayPeers = allPeers;
        break;
      case _PeerCategory.online:
        displayPeers = onlinePeers;
        break;
      case _PeerCategory.groups:
        displayPeers = const [];
        break;
    }

    final showGroups =
        (_activeCategory == _PeerCategory.all ||
        _activeCategory == _PeerCategory.groups);

    final effectiveOpacity = theme.isDark
        ? (theme.cardOpacity * 1.1).clamp(0.08, 0.95)
        : (theme.cardOpacity * 0.75).clamp(0.12, 0.95);
    final effectiveBlur = theme.cardBlur;

    Widget content = Container(
      width: 260,
      decoration: BoxDecoration(
        color: (theme.isDark ? const Color(0xFF1E293B) : Colors.white)
            .withValues(alpha: effectiveOpacity),
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
          // Header & Search
          const _SearchAndActionHeader(),

          // Real-time Scan Status & Progress Banner
          const _ScanStatusBanner(),

          // Category Filter Tabs (All | Online | Groups)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
            child: Container(
              height: 28,
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: (theme.isDark ? const Color(0xFF1E293B) : Colors.black)
                    .withValues(alpha: theme.isDark ? 0.65 : 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (theme.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: theme.isDark ? 0.10 : 0.05),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  _CategoryTabItem(
                    label: lang.tr('categoryAll'),
                    count: allPeers.length + groups.length,
                    isSelected: _activeCategory == _PeerCategory.all,
                    onTap: () =>
                        setState(() => _activeCategory = _PeerCategory.all),
                  ),
                  _CategoryTabItem(
                    label: lang.tr('categoryOnline'),
                    count: onlinePeers.length,
                    isSelected: _activeCategory == _PeerCategory.online,
                    onTap: () =>
                        setState(() => _activeCategory = _PeerCategory.online),
                  ),
                  _CategoryTabItem(
                    label: lang.tr('categoryGroups'),
                    count: groups.length,
                    isSelected: _activeCategory == _PeerCategory.groups,
                    onTap: () =>
                        setState(() => _activeCategory = _PeerCategory.groups),
                  ),
                ],
              ),
            ),
          ),

          // Pinned Broadcast Channel: Toàn thể (All Users)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
            child: _PinnedAllUsersTile(
              isSelected:
                  coordinator.selectedPeer?.id == coordinator.allUsersPeer.id,
              onTap: () => coordinator.selectPeer(coordinator.allUsersPeer),
            ),
          ),

          const Divider(height: 10, thickness: 0.8, indent: 12, endIndent: 12),

          // Danh sách Nhóm & Thiết bị (Ảo hóa bằng ListView.builder)
          Expanded(
            child: (displayPeers.isEmpty && (!showGroups || groups.isEmpty))
                ? _EmptyPeerState()
                : Builder(
                    builder: (context) {
                      final hasGroupSection = showGroups && groups.isNotEmpty;
                      final hasPeerSection =
                          _activeCategory != _PeerCategory.groups;
                      // Cấu trúc index ảo hóa:
                      // [0]: Group Header (nếu hasGroupSection)
                      // [1..groups.length]: _GroupListTile
                      // [groups.length + 1]: Spacer 6px
                      // [peerHeaderIdx]: Peer Section Header (nếu hasPeerSection)
                      // [peerStartIdx..]: _PeerListTile
                      final groupBlockCount = hasGroupSection
                          ? (1 + groups.length + 1)
                          : 0;
                      final peerBlockCount = hasPeerSection
                          ? (1 + displayPeers.length)
                          : 0;
                      final totalCount = groupBlockCount + peerBlockCount;

                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          vertical: 2,
                          horizontal: 8,
                        ),
                        itemCount: totalCount,
                        itemBuilder: (context, index) {
                          if (hasGroupSection && index < groupBlockCount) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                child: Row(
                                  children: [
                                    Text(
                                      lang.tr('groupsSection').toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.5,
                                        color: theme.isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.colors.accentBlue
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '${groups.length}',
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: theme.colors.accentBlue,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    InkWell(
                                      onTap: () =>
                                          _showCreateGroupDialog(context),
                                      borderRadius: BorderRadius.circular(4),
                                      child: Padding(
                                        padding: const EdgeInsets.all(2),
                                        child: Icon(
                                          Icons.add_rounded,
                                          size: 16,
                                          color: theme.colors.accentBlue,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final groupIdx = index - 1;
                            if (groupIdx < groups.length) {
                              final group = groups[groupIdx];
                              return _GroupListTile(
                                key: ValueKey('group_${group.id}'),
                                group: group,
                                isSelected:
                                    coordinator.selectedPeer?.id == group.id,
                                onTap: () => coordinator.selectPeer(
                                  coordinator.getPeerForGroup(group),
                                ),
                                onDelete: () =>
                                    _confirmDisbandGroup(context, group),
                              );
                            }
                            return const SizedBox(height: 6);
                          }

                          final peerLocalIdx = index - groupBlockCount;
                          if (peerLocalIdx == 0) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              child: Row(
                                children: [
                                  Text(
                                    (_activeCategory == _PeerCategory.online
                                            ? lang.tr('categoryOnline')
                                            : lang.tr('tabChats'))
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      color: theme.isDark
                                          ? Colors.white38
                                          : Colors.black38,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          (theme.isDark
                                                  ? Colors.white
                                                  : Colors.black)
                                              .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${displayPeers.length}',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: theme.isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          final peer = displayPeers[peerLocalIdx - 1];
                          return _PeerListTile(
                            key: ValueKey(peer.id),
                            peer: peer,
                            isSelected: coordinator.isPeerSelected(peer),
                            onTap: () => coordinator.selectPeer(peer),
                          );
                        },
                      );
                    },
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
}
