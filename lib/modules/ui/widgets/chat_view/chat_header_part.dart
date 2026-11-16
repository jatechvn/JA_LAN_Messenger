part of '../chat_view_panel.dart';

class _ChatHeader extends StatelessWidget {
  final PeerModel peer;
  final VoidCallback onBuzz;
  final VoidCallback onSendFile;
  final bool isDetailsOpen;
  final VoidCallback? onToggleDetails;
  final bool isCompact;
  final VoidCallback? onBackToList;
  final bool isSearchOpen;
  final VoidCallback? onToggleSearch;

  const _ChatHeader({
    required this.peer,
    required this.onBuzz,
    required this.onSendFile,
    this.isDetailsOpen = false,
    this.onToggleDetails,
    this.isCompact = false,
    this.onBackToList,
    this.isSearchOpen = false,
    this.onToggleSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    final effectiveName = peer.effectiveDisplayName(lang);

    final isTyping =
        !peer.isAllUsers && !peer.isGroup && coordinator.isPeerTyping(peer.id);
    final isGroupTyping = peer.isGroup && coordinator.isGroupTyping(peer.id);

    final isAi = peer.isAiAssistant;
    final isHeaderCompact = isCompact || isDetailsOpen;
    final selectedAiModel = AppPreferences().aiSelectedModel;
    final currentModelInfo = AiModelInfo.findById(selectedAiModel);
    final isThinkingOn = AppPreferences().aiThinkingEnabled;
    final isAiBusy = coordinator.isAiActive;
    final queueLen = coordinator.aiQueueLength;

    final String effectiveSubtitle;
    if (isTyping) {
      effectiveSubtitle = lang.tr('typing');
    } else if (isGroupTyping) {
      effectiveSubtitle =
          coordinator.getGroupTypingText(peer.id, lang) ?? lang.tr('typing');
    } else if (isAi) {
      effectiveSubtitle = peer.effectiveStatusDescription(
        lang,
        isAiBusy: isAiBusy,
        queueLen: queueLen,
        selectedModel: selectedAiModel,
      );
    } else if (peer.isAllUsers) {
      final onlineCount = coordinator.peers
          .where((p) => p.status != PeerStatus.offline)
          .length;
      effectiveSubtitle =
          '$onlineCount ${lang.tr('devicesOnline')} • ${lang.tr('allUsersDesc')}';
    } else if (peer.isGroup) {
      effectiveSubtitle =
          '${coordinator.groupMembers(peer.id).length} ${lang.tr('groupMembersCount')}';
    } else {
      effectiveSubtitle = isHeaderCompact
          ? 'IP: ${peer.ip}'
          : 'IP: ${peer.ip}:${peer.port} ${peer.workgroup.isNotEmpty ? "• ${peer.workgroup}" : ""}';
    }

    final effectiveOpacity = (theme.cardOpacity * (theme.isDark ? 0.95 : 0.85))
        .clamp(0.15, 0.95);
    final effectiveBlur = theme.cardBlur;
    final headerBg = (theme.isDark ? const Color(0xFF0F172A) : Colors.white)
        .withValues(alpha: effectiveOpacity);

    final btnSize = isHeaderCompact ? 30.0 : 34.0;
    final btnGap = isHeaderCompact ? 2.0 : 4.0;

    Widget content = Container(
      height: 54,
      padding: EdgeInsets.symmetric(horizontal: isHeaderCompact ? 10 : 16),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(color: theme.colors.headerBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          if (isCompact && onBackToList != null) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              tooltip: lang.tr('backToChats'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: onBackToList,
            ),
            const SizedBox(width: 4),
          ],
          // Avatar + Name interactive area (Avatar -> Profile, Name -> Quick Rename)
          Expanded(
            child: Row(
              children: [
                // Avatar (Click to view ContactProfileDialog or GroupMembersDialog)
                InkWell(
                  onTap: peer.isGroup && !peer.isAllUsers
                      ? () => GroupMembersDialog.show(context, peer)
                      : !isAi
                      ? () => ContactProfileDialog.show(
                          context,
                          peer: peer,
                          onBuzz: onBuzz,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(20),
                  child: AppAvatar(
                    peer: peer,
                    size: 34,
                    showStatus:
                        isHeaderCompact &&
                        !peer.isAllUsers &&
                        !peer.isGroup &&
                        !isAi,
                  ),
                ),
                const SizedBox(width: 8),

                // Name, IP & Status / AI Controls (Click Name to Quick Rename or view Group Members)
                Expanded(
                  child: InkWell(
                    onTap: peer.isGroup && !peer.isAllUsers
                        ? () => GroupMembersDialog.show(context, peer)
                        : (!isAi && !peer.isAllUsers)
                        ? () => showQuickNicknameDialog(
                            context: context,
                            coordinator: coordinator,
                            peer: peer,
                            lang: lang,
                          )
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 2,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: isHeaderCompact
                                    ? BounceMarqueeText(
                                        text: effectiveName,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: theme.isDark
                                              ? const Color(0xFFF8FAFC)
                                              : Colors.black87,
                                        ),
                                      )
                                    : Text(
                                        effectiveName,
                                        style: TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: theme.isDark
                                              ? const Color(0xFFF8FAFC)
                                              : Colors.black87,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                              ),
                              if (!isAi &&
                                  !peer.isAllUsers &&
                                  (!peer.isGroup ||
                                      coordinator.isGroupAdmin(peer.id))) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: peer.isGroup
                                      ? lang.tr('renameGroup')
                                      : lang.tr('editNickname'),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      showQuickNicknameDialog(
                                        context: context,
                                        coordinator: coordinator,
                                        peer: peer,
                                        lang: lang,
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.edit_rounded,
                                        size: 12,
                                        color: theme.colors.accentBlue
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              if (!isHeaderCompact &&
                                  !peer.isGroup &&
                                  !peer.isAllUsers &&
                                  !isAi) ...[
                                const SizedBox(width: 8),
                                StatusBadge(
                                  status: peer.status,
                                  showLabel: true,
                                ),
                              ],
                              if (isAi) ...[
                                const SizedBox(width: 8),
                                // Model Selector Dropdown
                                PopupMenuButton<String>(
                                  tooltip: lang.tr('aiModel'),
                                  initialValue: selectedAiModel,
                                  onSelected: (modelId) async {
                                    if (modelId == '__refresh__') {
                                      final models = await coordinator
                                          .refreshAiModels();
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              models.isEmpty
                                                  ? lang.tr('noModelsOnServer')
                                                  : lang
                                                        .tr('aiModelsRefreshed')
                                                        .replaceFirst(
                                                          '%d',
                                                          models.length
                                                              .toString(),
                                                        ),
                                            ),
                                            duration: const Duration(
                                              seconds: 2,
                                            ),
                                            behavior: SnackBarBehavior.floating,
                                          ),
                                        );
                                      }
                                    } else {
                                      coordinator.setAiModel(modelId);
                                    }
                                  },
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  color: theme.isDark
                                      ? const Color(0xFF1E293B)
                                      : Colors.white,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme.colors.accentBlue.withValues(
                                        alpha: theme.isDark ? 0.2 : 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: theme.colors.accentBlue
                                            .withValues(alpha: 0.35),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          currentModelInfo.supportsVision
                                              ? Icons.visibility_rounded
                                              : (currentModelInfo
                                                        .supportsThinking
                                                    ? Icons.psychology_rounded
                                                    : (currentModelInfo.id
                                                                  .toLowerCase()
                                                                  .contains(
                                                                    'coder',
                                                                  ) ||
                                                              currentModelInfo
                                                                  .id
                                                                  .toLowerCase()
                                                                  .contains(
                                                                    'code',
                                                                  )
                                                          ? Icons.code_rounded
                                                          : Icons
                                                                .smart_toy_outlined)),
                                          size: 12,
                                          color: theme.colors.accentBlue,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          currentModelInfo.displayName
                                                      .split(' ')
                                                      .length >
                                                  1
                                              ? '${currentModelInfo.displayName.split(' ')[0]} ${currentModelInfo.displayName.split(' ')[1]}'
                                              : currentModelInfo.displayName,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: theme.colors.accentBlue,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.arrow_drop_down_rounded,
                                          size: 14,
                                          color: theme.colors.accentBlue,
                                        ),
                                      ],
                                    ),
                                  ),
                                  itemBuilder: (ctx) {
                                    final items = <PopupMenuEntry<String>>[];
                                    for (final m
                                        in coordinator.availableAiModels) {
                                      final isCurrent = m.id == selectedAiModel;
                                      IconData icon = Icons.smart_toy_outlined;
                                      Color iconCol = isCurrent
                                          ? theme.colors.accentBlue
                                          : (theme.isDark
                                                ? Colors.white70
                                                : Colors.black87);
                                      if (m.supportsVision) {
                                        icon = Icons.visibility_rounded;
                                        if (!isCurrent) {
                                          iconCol = Colors.orangeAccent;
                                        }
                                      } else if (m.supportsThinking) {
                                        icon = Icons.psychology_rounded;
                                        if (!isCurrent) {
                                          iconCol = Colors.purpleAccent;
                                        }
                                      } else if (m.id.toLowerCase().contains(
                                            'coder',
                                          ) ||
                                          m.id.toLowerCase().contains('code')) {
                                        icon = Icons.code_rounded;
                                        if (!isCurrent) {
                                          iconCol = Colors.tealAccent;
                                        }
                                      }
                                      items.add(
                                        PopupMenuItem<String>(
                                          value: m.id,
                                          height: 38,
                                          child: Row(
                                            children: [
                                              Icon(
                                                icon,
                                                size: 15,
                                                color: iconCol,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  m.displayName,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: isCurrent
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                    color: isCurrent
                                                        ? theme
                                                              .colors
                                                              .accentBlue
                                                        : (theme.isDark
                                                              ? Colors.white
                                                              : Colors.black87),
                                                  ),
                                                ),
                                              ),
                                              if (isCurrent)
                                                Icon(
                                                  Icons.check_rounded,
                                                  size: 14,
                                                  color:
                                                      theme.colors.accentBlue,
                                                ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }
                                    items.add(
                                      const PopupMenuDivider(height: 1),
                                    );
                                    items.add(
                                      PopupMenuItem<String>(
                                        value: '__refresh__',
                                        height: 36,
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.refresh_rounded,
                                              size: 15,
                                              color: theme.colors.accentBlue,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                lang.tr('refreshAiModels'),
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w500,
                                                  color:
                                                      theme.colors.accentBlue,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    return items;
                                  },
                                ),
                                // Thinking Toggle Pill Button (Active only when Qwen 3.5 is selected)
                                if (currentModelInfo.supportsThinking) ...[
                                  const SizedBox(width: 6),
                                  InkWell(
                                    onTap: () => coordinator.setAiThinking(
                                      !isThinkingOn,
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isThinkingOn
                                            ? Colors.purpleAccent.withValues(
                                                alpha: theme.isDark
                                                    ? 0.25
                                                    : 0.15,
                                              )
                                            : (theme.isDark
                                                  ? Colors.white.withValues(
                                                      alpha: 0.06,
                                                    )
                                                  : Colors.black.withValues(
                                                      alpha: 0.05,
                                                    )),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: isThinkingOn
                                              ? Colors.purpleAccent.withValues(
                                                  alpha: 0.5,
                                                )
                                              : (theme.isDark
                                                    ? Colors.white12
                                                    : Colors.black12),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Text(
                                            '🧠',
                                            style: TextStyle(fontSize: 11),
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            isThinkingOn
                                                ? lang.tr('thinkingOn')
                                                : lang.tr('thinkingOff'),
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.w600,
                                              color: isThinkingOn
                                                  ? (theme.isDark
                                                        ? Colors
                                                              .purpleAccent
                                                              .shade100
                                                        : Colors
                                                              .purple
                                                              .shade700)
                                                  : (theme.isDark
                                                        ? Colors.white54
                                                        : Colors.black54),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                // Queue status indicator
                                if (isAiBusy || queueLen > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(
                                        alpha: 0.18,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.amber.withValues(
                                          alpha: 0.4,
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      queueLen > 0
                                          ? '⏳ #$queueLen'
                                          : '⏳ ${lang.tr('aiGenerating')}',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              if (isTyping) ...[
                                Icon(
                                  Icons.edit_note_rounded,
                                  size: 13,
                                  color: theme.colors.accentBlue,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  effectiveSubtitle,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isTyping
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isTyping
                                        ? theme.colors.accentBlue
                                        : (theme.isDark
                                              ? const Color(0xFF94A3B8)
                                              : Colors.black45),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Action Buttons
          if (onToggleSearch != null) ...[
            GlassIconButton(
              icon: Icons.search_rounded,
              tooltip: lang.tr('searchInChat'),
              color: isSearchOpen
                  ? theme.colors.accentBlue
                  : (theme.isDark ? Colors.white70 : Colors.black87),
              size: isCompact ? 28 : btnSize,
              onPressed: onToggleSearch!,
            ),
            SizedBox(width: isCompact ? 3 : btnGap),
          ],
          if (!isCompact) ...[
            if (isAi) ...[
              GlassIconButton(
                icon: Icons.cleaning_services_rounded,
                tooltip: lang.tr('clearAiChat'),
                color: theme.colors.accentRose,
                size: btnSize,
                onPressed: () {
                  showGlassDialog(
                    context: context,
                    builder: (ctx) => GlassDialog(
                      title: lang.tr('clearAiChat'),
                      icon: Icons.delete_sweep_rounded,
                      width: 360,
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(lang.tr('cancel')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            coordinator.clearAiConversation();
                          },
                          child: Text(lang.tr('clearAiChat')),
                        ),
                      ],
                      child: Text(
                        lang.tr('clearAiChatConfirm'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
            ] else ...[
              _BuzzActionButton(
                onPressed: onBuzz,
                tooltip:
                    (!peer.isAllUsers &&
                        !peer.isGroup &&
                        peer.status == PeerStatus.offline)
                    ? lang.tr('buzzOfflineTooltip')
                    : lang.tr('nudge'),
                size: btnSize,
                defaultColor: theme.colors.accentAmber,
              ),
            ],
            SizedBox(width: btnGap),
            GlassIconButton(
              icon: peer.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              tooltip: peer.isPinned
                  ? lang.tr('unpinChat')
                  : lang.tr('pinChat'),
              color: peer.isPinned
                  ? theme.colors.accentAmber
                  : (theme.isDark ? Colors.white70 : Colors.black87),
              size: btnSize,
              onPressed: () => coordinator.togglePinPeer(peer.id),
            ),
            if (onToggleDetails != null && !isAi) ...[
              SizedBox(width: btnGap),
              GlassIconButton(
                icon: Icons.dock_rounded,
                tooltip: lang.tr('toggleDetails'),
                color: isDetailsOpen
                    ? theme.colors.accentBlue
                    : (theme.isDark ? Colors.white70 : Colors.black87),
                size: btnSize,
                onPressed: onToggleDetails,
              ),
            ],
          ] else ...[
            // Compact Mode: Only 📌 and ↗️ (Nudge 🔔 is in the dock input below)
            if (isAi) ...[
              GlassIconButton(
                icon: Icons.cleaning_services_rounded,
                tooltip: lang.tr('clearAiChat'),
                color: theme.colors.accentRose,
                size: 28,
                onPressed: () {
                  showGlassDialog(
                    context: context,
                    builder: (ctx) => GlassDialog(
                      title: lang.tr('clearAiChat'),
                      icon: Icons.delete_sweep_rounded,
                      width: 360,
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(lang.tr('cancel')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.redAccent,
                          ),
                          onPressed: () {
                            Navigator.of(ctx).pop();
                            coordinator.clearAiConversation();
                          },
                          child: Text(lang.tr('clearAiChat')),
                        ),
                      ],
                      child: Text(
                        lang.tr('clearAiChatConfirm'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 3),
            ],
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
              size: 28,
              onPressed: () => coordinator.toggleAlwaysOnTop(),
            ),
            const SizedBox(width: 3),
            GlassIconButton(
              icon: Icons.open_in_full_rounded,
              tooltip: lang.tr('standardMode'),
              color: theme.colors.accentBlue,
              size: 28,
              onPressed: () => coordinator.toggleCompactMode(),
            ),
          ],
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
