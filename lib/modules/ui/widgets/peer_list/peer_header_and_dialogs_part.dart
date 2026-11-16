part of '../peer_list_view.dart';

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
  late final FocusNode _searchFocusNode;
  int _lastHandledFocusRequestId = 0;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    if (coordinator.sidebarSearchFocusRequestId != _lastHandledFocusRequestId) {
      _lastHandledFocusRequestId = coordinator.sidebarSearchFocusRequestId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _searchFocusNode.canRequestFocus) {
          _searchFocusNode.requestFocus();
          _searchController.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _searchController.text.length,
          );
        }
      });
    }

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
              focusNode: _searchFocusNode,
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
