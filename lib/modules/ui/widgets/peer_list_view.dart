import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
                      onDelete: () => _confirmDisbandGroup(context, group),
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
                      key: ValueKey(peer.id),
                      peer: peer,
                      isSelected: coordinator.isPeerSelected(peer),
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
  CreateGroupDialog.show(context);
}

void _confirmDisbandGroup(BuildContext context, GroupModel group) {
  final lang = context.read<LanguageProvider>();
  final coordinator = context.read<MessengerCoordinator>();
  showGlassDialog(
    context: context,
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
            coordinator.deleteGroup(group.id);
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

void _confirmLeaveGroup(BuildContext context, GroupModel group) {
  final lang = context.read<LanguageProvider>();
  final coordinator = context.read<MessengerCoordinator>();
  showGlassDialog(
    context: context,
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
          style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
          onPressed: () {
            coordinator.leaveGroup(group.id);
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

void _showAddIpDialog(BuildContext context) {
  showGlassDialog(context: context, builder: (ctx) => const _AddIpDialog());
}

class _AddIpDialog extends StatefulWidget {
  const _AddIpDialog();

  @override
  State<_AddIpDialog> createState() => _AddIpDialogState();
}

class _AddIpDialogState extends State<_AddIpDialog> {
  late final TextEditingController _controller;
  bool _isConnecting = false;
  String? _errorMessage;
  String? _connectingIp;

  @override
  void initState() {
    super.initState();
    final coordinator = context.read<MessengerCoordinator>();
    final prefixes = coordinator.suggestedIpPrefixes;
    final defaultPrefix = prefixes.isNotEmpty ? prefixes.first : '192.168.';
    _controller = TextEditingController(text: defaultPrefix);
    _controller.selection = TextSelection.collapsed(
      offset: defaultPrefix.length,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyPrefix(String prefix) {
    if (_isConnecting) return;
    final current = _controller.text.trim();
    final parts = current.split('.');
    String newText;
    if (parts.length >= 2) {
      final remainder = parts.sublist(2).join('.');
      newText = '$prefix$remainder';
    } else {
      newText = prefix;
    }
    setState(() {
      _errorMessage = null;
      _controller.text = newText;
      _controller.selection = TextSelection.collapsed(offset: newText.length);
    });
  }

  Future<void> _submit() async {
    final ip = _controller.text.trim();
    final lang = context.read<LanguageProvider>();
    final coordinator = context.read<MessengerCoordinator>();

    if (ip.isEmpty || !NetworkUtils.isValidIp(ip)) {
      setState(() {
        _errorMessage = lang.tr('addIpInvalid');
      });
      return;
    }

    setState(() {
      _isConnecting = true;
      _errorMessage = null;
      _connectingIp = ip;
    });

    final result = await coordinator.addManualPeer(ip);
    if (!mounted) return;

    if (result.isSuccess) {
      Navigator.of(context).pop();
      final name = result.peer?.displayName ?? ip;
      coordinator.showToast('addIpSuccessToast', ['$name ($ip)']);
      if (result.peer != null) {
        coordinator.selectPeer(result.peer);
      }
    } else if (result.isAlreadyExists) {
      Navigator.of(context).pop();
      final name = result.peer?.displayName ?? ip;
      coordinator.showToast('addIpAlreadyExists', ['$name ($ip)']);
      if (result.peer != null) {
        coordinator.selectPeer(result.peer);
      }
    } else if (result.isOwnIp) {
      setState(() {
        _isConnecting = false;
        _errorMessage = lang.tr('addIpOwnIp');
      });
    } else if (result.isInvalidIp) {
      setState(() {
        _isConnecting = false;
        _errorMessage = lang.tr('addIpInvalid');
      });
    } else {
      setState(() {
        _isConnecting = false;
        _errorMessage = lang.tr('addIpFailedToast', [ip]);
      });
    }
  }

  void _saveOffline() {
    final coordinator = context.read<MessengerCoordinator>();
    final targetIp = _connectingIp ?? _controller.text.trim();
    final peer = coordinator.addOfflineManualPeer(targetIp);
    Navigator.of(context).pop();
    coordinator.showToast('savedOfflineToast', [
      '${peer.displayName} ($targetIp)',
    ]);
    coordinator.selectPeer(peer);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final prefixes = coordinator.suggestedIpPrefixes;
    final hintPrefix = prefixes.isNotEmpty ? prefixes.first : '192.168.';

    return GlassDialog(
      title: lang.tr('addIpTitle'),
      icon: Icons.person_add_alt_1_rounded,
      width: 420,
      actions: [
        TextButton(
          onPressed: _isConnecting ? null : () => Navigator.pop(context),
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
          onPressed: _isConnecting ? null : _submit,
          child: _isConnecting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(lang.tr('connect')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(lang.tr('addIpDesc'), style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),

          // Suggestion chips
          if (prefixes.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  lang.tr('addIpSuggestedPrefix'),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    children: [
                      for (final p in prefixes)
                        ActionChip(
                          label: Text(
                            p,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: theme.colors.accentBlue,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          backgroundColor: theme.colors.accentBlue.withValues(
                            alpha: 0.12,
                          ),
                          side: BorderSide(
                            color: theme.colors.accentBlue.withValues(
                              alpha: 0.35,
                            ),
                            width: 0.8,
                          ),
                          onPressed: _isConnecting
                              ? null
                              : () => _applyPrefix(p),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          TextField(
            controller: _controller,
            autofocus: true,
            enabled: !_isConnecting,
            style: const TextStyle(fontSize: 13),
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '${hintPrefix}1.100',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
            ),
          ),

          if (_isConnecting) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.tr('addIpConnecting', [_connectingIp ?? '']),
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colors.accentBlue,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.3),
                  width: 0.8,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        size: 15,
                        color: Colors.orangeAccent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!_isConnecting &&
                      _connectingIp != null &&
                      _errorMessage ==
                          lang.tr('addIpFailedToast', [_connectingIp!])) ...[
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.bookmark_add_outlined, size: 14),
                        label: Text(
                          lang.tr('saveAsOfflineContact'),
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: _saveOffline,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
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
                            child: Text(
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
                      Text(
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
                        text:
                            '$subnetText • $adapterCount ${lang.tr('cardAdapters')}',
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
                          ? (isDark ? Colors.white : Colors.black).withValues(
                              alpha: 0.08,
                            )
                          : (isDark ? Colors.white : Colors.black).withValues(
                              alpha: 0.03,
                            )),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.isScanning
                      ? theme.colors.accentBlue.withValues(alpha: 0.35)
                      : (_isHovered
                            ? (isDark ? Colors.white : Colors.black).withValues(
                                alpha: 0.15,
                              )
                            : (isDark ? Colors.white : Colors.black).withValues(
                                alpha: 0.07,
                              )),
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
