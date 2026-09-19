import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../models/peer_model.dart';
import '../../models/group_model.dart';
import 'glass_components.dart';
import 'glass_dialog.dart';
import 'glass_search_history_field.dart';
import 'bounce_marquee_text.dart';

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
    final groups = coordinator.groups;
    final onlinePeers = allPeers
        .where((p) => p.status != PeerStatus.offline)
        .toList();

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

          // Danh sách Nhóm & Thiết bị
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
              children: [
                // Section: Nhóm trò chuyện
                if (showGroups && groups.isNotEmpty) ...[
                  Padding(
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
                            color: theme.colors.accentBlue.withValues(
                              alpha: 0.15,
                            ),
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
                          onTap: () => _showCreateGroupDialog(context),
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
                  ),
                  for (final group in groups)
                    _GroupListTile(
                      group: group,
                      isSelected: coordinator.selectedPeer?.id == group.id,
                      onTap: () => coordinator.selectPeer(
                        coordinator.getPeerForGroup(group),
                      ),
                      onDelete: () => coordinator.deleteGroup(group.id),
                    ),
                  const SizedBox(height: 6),
                ],

                // Section: Thiết bị LAN
                if (_activeCategory != _PeerCategory.groups) ...[
                  Padding(
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
                            color: (theme.isDark ? Colors.white : Colors.black)
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
                  ),
                  for (final peer in displayPeers)
                    _PeerListTile(
                      peer: peer,
                      isSelected: coordinator.selectedPeer?.id == peer.id,
                      onTap: () => coordinator.selectPeer(peer),
                    ),
                ],

                if (displayPeers.isEmpty && (!showGroups || groups.isEmpty))
                  _EmptyPeerState(),
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
}

class _CategoryTabItem extends StatelessWidget {
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryTabItem({
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colors.accentBlue.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: isSelected
                ? Border.all(
                    color: theme.colors.accentBlue.withValues(alpha: 0.3),
                    width: 1,
                  )
                : null,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected
                        ? FontWeight.w600
                        : FontWeight.normal,
                    color: isSelected
                        ? theme.colors.accentBlue
                        : (theme.isDark ? Colors.white60 : Colors.black54),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 2),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    color: isSelected
                        ? theme.colors.accentBlue
                        : (theme.isDark ? Colors.white38 : Colors.black38),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchAndActionHeader extends StatefulWidget {
  const _SearchAndActionHeader();

  @override
  State<_SearchAndActionHeader> createState() => _SearchAndActionHeaderState();
}

class _SearchAndActionHeaderState extends State<_SearchAndActionHeader> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    // Synchronize if coordinator reset search query externally (e.g. sidebar chat icon clicked)
    if (coordinator.searchQuery.isEmpty && _searchController.text.isNotEmpty) {
      _searchController.clear();
    } else if (coordinator.searchQuery.isNotEmpty &&
        _searchController.text != coordinator.searchQuery) {
      _searchController.text = coordinator.searchQuery;
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 12, 8, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color:
                (ThemeProvider.of(context).isDark ? Colors.white : Colors.black)
                    .withValues(
                      alpha: ThemeProvider.of(context).isDark ? 0.08 : 0.06,
                    ),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: GlassSearchHistoryField(
              controller: _searchController,
              category: 'peers',
              hintText: lang.tr('searchHint'),
              onChanged: (val) => coordinator.setSearchQuery(val),
              onClear: () => coordinator.setSearchQuery(''),
              onSubmitted: (val) => coordinator.setSearchQuery(val),
            ),
          ),
          const SizedBox(width: 4),
          GlassIconButton(
            icon: Icons.group_add_rounded,
            tooltip: lang.tr('createGroupTooltip'),
            size: 30,
            onPressed: () => _showCreateGroupDialog(context),
          ),
          const SizedBox(width: 3),
          GlassIconButton(
            icon: Icons.person_add_alt_1_rounded,
            tooltip: lang.tr('addIpTooltip'),
            size: 30,
            onPressed: () => _showAddIpDialog(context),
          ),
        ],
      ),
    );
  }
}

void _showCreateGroupDialog(BuildContext context) {
  final theme = ThemeProvider.of(context);
  final lang = context.read<LanguageProvider>();
  final coordinator = context.read<MessengerCoordinator>();
  final nameController = TextEditingController();
  final availablePeers = coordinator.peers;
  final Set<String> selectedMemberIds = {};

  showGlassDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => GlassDialog(
        title: lang.tr('createGroupTitle'),
        icon: Icons.groups_rounded,
        width: 380,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(lang.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colors.accentBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                coordinator.createGroup(name, selectedMemberIds.toList());
                Navigator.pop(ctx);
              }
            },
            child: Text(lang.tr('create')),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: lang.tr('groupNameHint'),
                hintStyle: const TextStyle(fontSize: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              lang.tr('selectMembers'),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.04,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (theme.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                ),
              ),
              child: availablePeers.isEmpty
                  ? Center(
                      child: Text(
                        lang.tr('noAvailableMembers'),
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: availablePeers.length,
                      itemBuilder: (context, i) {
                        final p = availablePeers[i];
                        final isChecked = selectedMemberIds.contains(p.id);
                        return CheckboxListTile(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          value: isChecked,
                          title: Text(
                            p.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                          subtitle: Text(
                            p.ip,
                            style: const TextStyle(fontSize: 10),
                          ),
                          onChanged: (val) {
                            setState(() {
                              if (val == true) {
                                selectedMemberIds.add(p.id);
                              } else {
                                selectedMemberIds.remove(p.id);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showAddIpDialog(BuildContext context) {
  final theme = ThemeProvider.of(context);
  final lang = context.read<LanguageProvider>();
  final coordinator = context.read<MessengerCoordinator>();
  final controller = TextEditingController(text: '192.168.1.');

  showGlassDialog(
    context: context,
    builder: (ctx) => GlassDialog(
      title: lang.tr('addIpTitle'),
      icon: Icons.person_add_alt_1_rounded,
      width: 380,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(lang.tr('cancel')),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colors.accentBlue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            final ip = controller.text.trim();
            if (ip.isNotEmpty) {
              coordinator.addManualPeer(ip);
              Navigator.pop(ctx);
            }
          },
          child: Text(lang.tr('connect')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lang.tr('addIpDesc'), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: '192.168.1.100',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

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
                      allUsers.lastMessage ?? lang.tr('allUsersDesc'),
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
  final VoidCallback onDelete;

  const _GroupListTile({
    required this.group,
    required this.isSelected,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
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
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: group.color.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: group.color.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.groups_rounded,
                    color: group.color,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        group.name,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? theme.colors.accentBlue
                              : (theme.isDark ? Colors.white : Colors.black87),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 1),
                      Text(
                        '${group.memberIds.length} ${lang.tr('groupMembersCount')}',
                        style: TextStyle(
                          fontSize: 10,
                          color: theme.isDark ? Colors.white38 : Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  color: theme.isDark ? Colors.white24 : Colors.black26,
                  hoverColor: theme.colors.accentRose.withValues(alpha: 0.2),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeerListTile extends StatelessWidget {
  final PeerModel peer;
  final bool isSelected;
  final VoidCallback onTap;

  const _PeerListTile({
    required this.peer,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
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
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: peer.avatarColor.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: peer.avatarColor.withValues(alpha: 0.5),
                          width: 1.2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: peer.avatarAsset != null
                          ? ClipOval(
                              child: Image.asset(
                                peer.avatarAsset!,
                                width: 38,
                                height: 38,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(
                                  peer.initials,
                                  style: TextStyle(
                                    color: peer.avatarColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              peer.initials,
                              style: TextStyle(
                                color: peer.avatarColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                    ),
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
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        peer.lastMessage ?? peer.ip,
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

    if (selected == 'pin') {
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

class _ScanStatusBanner extends StatelessWidget {
  const _ScanStatusBanner();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final isScanning = coordinator.isScanning;
    final scanState = coordinator.scanState;
    final subnetText = scanState.activeSubnets.isNotEmpty
        ? scanState.activeSubnets.first
        : 'LAN';
    final adapterCount = scanState.activeAdaptersCount;

    return Container(
      decoration: BoxDecoration(
        color: (theme.isDark ? Colors.white : Colors.black).withValues(
          alpha: theme.isDark ? 0.03 : 0.02,
        ),
        border: Border(
          bottom: BorderSide(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: theme.isDark ? 0.07 : 0.05,
            ),
            width: 1,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                _RadarBeacon(isScanning: isScanning, size: 8),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BounceMarqueeText(
                        text: '$subnetText • $adapterCount ${lang.tr('cardAdapters')}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'Consolas',
                          color: theme.isDark
                              ? Colors.white.withValues(alpha: 0.9)
                              : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 1.5),
                      BounceMarqueeText(
                        text: coordinator.getLocalizedScanStatus(lang),
                        style: TextStyle(
                          fontSize: 10,
                          color: isScanning
                              ? theme.colors.accentBlue
                              : (theme.isDark
                                    ? Colors.white38
                                    : Colors.black45),
                          fontWeight: isScanning
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                _ScanActionButton(
                  isScanning: isScanning,
                  tooltip: lang.tr('rescanTooltip'),
                  onPressed: () => coordinator.rescanNetwork(),
                ),
              ],
            ),
          ),
          // Micro progress bar when scanning
          if (isScanning)
            LinearProgressIndicator(
              value: coordinator.scanProgress > 0
                  ? coordinator.scanProgress
                  : null,
              minHeight: 2,
              backgroundColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.05),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colors.accentBlue,
              ),
            ),
        ],
      ),
    );
  }
}

class _ScanActionButton extends StatefulWidget {
  final bool isScanning;
  final String tooltip;
  final VoidCallback onPressed;

  const _ScanActionButton({
    required this.isScanning,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_ScanActionButton> createState() => _ScanActionButtonState();
}

class _ScanActionButtonState extends State<_ScanActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.isScanning) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant _ScanActionButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.isScanning && _controller.isAnimating) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: widget.isScanning
                    ? theme.colors.accentBlue.withValues(alpha: 0.16)
                    : (_isHovered
                        ? (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.08)
                        : (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.03)),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isScanning
                      ? theme.colors.accentBlue.withValues(alpha: 0.35)
                      : (_isHovered
                          ? (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.15)
                          : (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.07)),
                  width: 1,
                ),
              ),
              child: Center(
                child: RotationTransition(
                  turns: _controller,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 16,
                    color: widget.isScanning
                        ? theme.colors.accentBlue
                        : (_isHovered
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.white70 : Colors.black54)),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RadarBeacon extends StatefulWidget {
  final bool isScanning;
  final double size;

  const _RadarBeacon({required this.isScanning, this.size = 14});

  @override
  State<_RadarBeacon> createState() => _RadarBeaconState();
}

class _RadarBeaconState extends State<_RadarBeacon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant _RadarBeacon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning != oldWidget.isScanning) {
      _controller.duration = Duration(
        milliseconds: widget.isScanning ? 700 : 1600,
      );
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final color = widget.isScanning
        ? theme.colors.accentBlue
        : theme.colors.accentEmerald;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1.0 + (_controller.value * 0.8);
        final opacity = (1.0 - _controller.value).clamp(0.0, 1.0);

        return SizedBox(
          width: widget.size * 2,
          height: widget.size * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Outer ripple wave
              Transform.scale(
                scale: scale,
                child: Container(
                  width: widget.size * 1.4,
                  height: widget.size * 1.4,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color.withValues(alpha: opacity * 0.7),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              // Inner glowing core
              Container(
                width: widget.size * 0.75,
                height: widget.size * 0.75,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyPeerState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final isScanning = coordinator.isScanning;
    final subnetText = coordinator.scanState.activeSubnets.isNotEmpty
        ? coordinator.scanState.activeSubnets.join(', ')
        : 'LAN';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _RadarBeacon(isScanning: true, size: 20),
            const SizedBox(height: 16),
            Text(
              isScanning ? lang.tr('scanning') : lang.tr('readyDiscover'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.isDark ? Colors.white70 : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${lang.tr('listeningOn')} $subnetText.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: theme.isDark ? Colors.white38 : Colors.black45,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(
                      color: (theme.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: 0.15),
                    ),
                  ),
                  onPressed: () => coordinator.rescanNetwork(),
                  icon: const Icon(Icons.refresh_rounded, size: 14),
                  label: Text(
                    lang.tr('rescan'),
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
