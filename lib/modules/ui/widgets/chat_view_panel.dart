import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../models/peer_model.dart';
import '../../models/message_model.dart';
import '../../models/ai_config_model.dart';
import '../../services/app_preferences.dart';
import 'glass_components.dart';
import 'glass_dialog.dart';
import 'glass_image_lightbox.dart';
import 'markdown_message_view.dart';

class ChatViewPanel extends StatefulWidget {
  final bool isDetailsOpen;
  final VoidCallback? onToggleDetails;

  const ChatViewPanel({
    super.key,
    this.isDetailsOpen = false,
    this.onToggleDetails,
  });

  @override
  State<ChatViewPanel> createState() => _ChatViewPanelState();
}

class _ChatViewPanelState extends State<ChatViewPanel> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _inputFocusNode;
  Timer? _typingDebounceTimer;
  MessageModel? _replyingToMessage;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  int _currentPinnedIndex = 0;
  int _prevMessageCount = 0;
  String? _lastPeerId;

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _typingDebounceTimer?.cancel();
    _highlightTimer?.cancel();
    _inputFocusNode.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool force = false, bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final isNearBottom = (pos.maxScrollExtent - pos.pixels) <= 140.0;
      if (!force && !isNearBottom) return;

      if (smooth) {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(pos.maxScrollExtent);
      }
    });
  }

  void _scrollToMessage(String? messageId, List<MessageModel> messages) {
    if (messageId == null || !_scrollController.hasClients) return;
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final total = messages.length;
    if (total == 0) return;
    final targetFraction = (index / total).clamp(0.0, 1.0);
    final targetOffset =
        targetFraction * _scrollController.position.maxScrollExtent;

    _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOutCubic,
    );

    setState(() {
      _highlightedMessageId = messageId;
    });
    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightedMessageId = null;
        });
      }
    });
  }

  void _onTextChanged(String text, MessengerCoordinator coordinator) {
    if (text.trim().isNotEmpty) {
      coordinator.sendTypingStatus(true);
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(milliseconds: 2500), () {
        coordinator.sendTypingStatus(false);
      });
    } else {
      _typingDebounceTimer?.cancel();
      coordinator.sendTypingStatus(false);
    }
  }

  void _handleSend(MessengerCoordinator coordinator) {
    _typingDebounceTimer?.cancel();
    coordinator.sendTypingStatus(false);
    final text = _inputController.text;
    if (text.trim().isEmpty) return;
    _inputController.clear();
    final replying = _replyingToMessage;
    setState(() {
      _replyingToMessage = null;
    });
    coordinator.sendMessage(text, replyTo: replying);
    _scrollToBottom(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inputFocusNode.canRequestFocus) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  Future<void> _handlePickFile(MessengerCoordinator coordinator) async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      await coordinator.sendFile(file);
      _scrollToBottom(force: true);
      _inputFocusNode.requestFocus();
    }
  }

  Future<void> _handlePasteClipboard(MessengerCoordinator coordinator) async {
    final hasPasted = await coordinator.pasteFromClipboard();
    if (hasPasted) {
      _scrollToBottom(force: true);
      _inputFocusNode.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = context.watch<MessengerCoordinator>();
    final lang = context.watch<LanguageProvider>();
    final peer = coordinator.selectedPeer;

    if (peer == null) {
      return const _EmptyChatView();
    }

    // Reset replying state if active peer changed
    if (_lastPeerId != peer.id) {
      _lastPeerId = peer.id;
      _replyingToMessage = null;
      _currentPinnedIndex = 0;
      _prevMessageCount = 0;
    }

    final messages = coordinator.currentMessages;
    final isPeerTyping =
        !peer.isAllUsers && !peer.isGroup && coordinator.isPeerTyping(peer.id);
    final totalItems = messages.length + (isPeerTyping ? 1 : 0);

    // Auto-scroll logic: instant jump during AI stream (prevents 200ms animation conflicts),
    // and smooth scroll only when a new message arrives and user is already near bottom.
    final isStreaming = messages.isNotEmpty && messages.last.isStreaming;
    if (isStreaming) {
      _scrollToBottom(force: false, smooth: false);
    } else if (messages.length != _prevMessageCount) {
      _prevMessageCount = messages.length;
      _scrollToBottom(force: false, smooth: true);
    }

    final pinnedMessages = coordinator.getPinnedMessages(peer.id);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDockHeight = (constraints.maxHeight * 0.50).clamp(
          100.0,
          500.0,
        );
        return Container(
          color: Colors.transparent,
          child: Column(
            children: [
              // Chat Header
              _ChatHeader(
                peer: peer,
                onBuzz: () => coordinator.sendBuzz(),
                onSendFile: () => _handlePickFile(coordinator),
                isDetailsOpen: widget.isDetailsOpen,
                onToggleDetails: widget.onToggleDetails,
              ),

              // Pinned Messages Banner
              if (pinnedMessages.isNotEmpty)
                _PinnedMessagesBanner(
                  pinnedMessages: pinnedMessages,
                  currentIndex: _currentPinnedIndex.clamp(
                    0,
                    pinnedMessages.length - 1,
                  ),
                  onSelectIndex: (idx) {
                    setState(() => _currentPinnedIndex = idx);
                    _scrollToMessage(pinnedMessages[idx].id, messages);
                  },
                  onUnpin: (msg) {
                    coordinator.togglePinMessage(peer.id, msg.id);
                  },
                  onTap: (msg) {
                    _scrollToMessage(msg.id, messages);
                  },
                ),

              // Messages List
              Expanded(
                child: messages.isEmpty && !isPeerTyping
                    ? _NoMessagesState(
                        peerName: peer.effectiveDisplayName(lang),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: totalItems,
                        itemBuilder: (context, index) {
                          if (index < messages.length) {
                            final msg = messages[index];
                            return _MessageBubble(
                              message: msg,
                              isHighlighted: msg.id == _highlightedMessageId,
                              onReply: (m) {
                                setState(() {
                                  _replyingToMessage = m;
                                });
                                _inputFocusNode.requestFocus();
                              },
                              onScrollToMessage: (id) =>
                                  _scrollToMessage(id, messages),
                            );
                          } else {
                            return _TypingIndicatorBubble(peer: peer);
                          }
                        },
                      ),
              ),

              // Input Dock
              _ChatInputDock(
                controller: _inputController,
                focusNode: _inputFocusNode,
                maxInputHeight: maxDockHeight,
                replyingTo: _replyingToMessage,
                onCancelReply: () {
                  setState(() {
                    _replyingToMessage = null;
                  });
                },
                onChanged: (text) => _onTextChanged(text, coordinator),
                onSend: () => _handleSend(coordinator),
                onAttachFile: () => _handlePickFile(coordinator),
                onPasteClipboard: () => _handlePasteClipboard(coordinator),
                onBuzz: () => coordinator.sendBuzz(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final PeerModel peer;
  final VoidCallback onBuzz;
  final VoidCallback onSendFile;
  final bool isDetailsOpen;
  final VoidCallback? onToggleDetails;

  const _ChatHeader({
    required this.peer,
    required this.onBuzz,
    required this.onSendFile,
    this.isDetailsOpen = false,
    this.onToggleDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    final effectiveName = peer.effectiveDisplayName(lang);

    final isTyping =
        !peer.isAllUsers && !peer.isGroup && coordinator.isPeerTyping(peer.id);

    final isAi = peer.isAiAssistant;
    final selectedAiModel = AppPreferences().aiSelectedModel;
    final currentModelInfo = AiModelInfo.findById(selectedAiModel);
    final isThinkingOn = AppPreferences().aiThinkingEnabled;
    final isAiBusy = coordinator.isAiActive;
    final queueLen = coordinator.aiQueueLength;

    final String effectiveSubtitle;
    if (isTyping) {
      effectiveSubtitle = lang.tr('typing');
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
          '${peer.memberIds.length} ${lang.tr('groupMembersCount')}';
    } else {
      effectiveSubtitle =
          'IP: ${peer.ip}:${peer.port} ${peer.workgroup.isNotEmpty ? "• ${peer.workgroup}" : ""}';
    }

    final effectiveOpacity = (theme.cardOpacity * (theme.isDark ? 0.95 : 0.85))
        .clamp(0.15, 0.95);
    final effectiveBlur = theme.cardBlur;
    final headerBg = (theme.isDark ? const Color(0xFF0F172A) : Colors.white)
        .withValues(alpha: effectiveOpacity);

    Widget content = Container(
      height: 54,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: headerBg,
        border: Border(
          bottom: BorderSide(color: theme.colors.headerBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 34,
            height: 34,
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
          const SizedBox(width: 10),

          // Name, IP & Status / AI Controls
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
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
                    if (!peer.isGroup && !peer.isAllUsers && !isAi) ...[
                      const SizedBox(width: 8),
                      StatusBadge(status: peer.status, showLabel: true),
                    ],
                    if (isAi) ...[
                      const SizedBox(width: 8),
                      // Model Selector Dropdown
                      PopupMenuButton<String>(
                        tooltip: lang.tr('aiModel'),
                        initialValue: selectedAiModel,
                        onSelected: (modelId) async {
                          if (modelId == '__refresh__') {
                            final models = await coordinator.refreshAiModels();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    models.isEmpty
                                        ? lang.tr('noModelsOnServer')
                                        : lang
                                              .tr('aiModelsRefreshed')
                                              .replaceFirst(
                                                '%d',
                                                models.length.toString(),
                                              ),
                                  ),
                                  duration: const Duration(seconds: 2),
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
                              color: theme.colors.accentBlue.withValues(
                                alpha: 0.35,
                              ),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                currentModelInfo.supportsVision
                                    ? Icons.visibility_rounded
                                    : (currentModelInfo.supportsThinking
                                          ? Icons.psychology_rounded
                                          : (currentModelInfo.id
                                                        .toLowerCase()
                                                        .contains('coder') ||
                                                    currentModelInfo.id
                                                        .toLowerCase()
                                                        .contains('code')
                                                ? Icons.code_rounded
                                                : Icons.smart_toy_outlined)),
                                size: 12,
                                color: theme.colors.accentBlue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                currentModelInfo.displayName.split(' ').length >
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
                          for (final m in coordinator.availableAiModels) {
                            final isCurrent = m.id == selectedAiModel;
                            IconData icon = Icons.smart_toy_outlined;
                            Color iconCol = isCurrent
                                ? theme.colors.accentBlue
                                : (theme.isDark
                                      ? Colors.white70
                                      : Colors.black87);
                            if (m.supportsVision) {
                              icon = Icons.visibility_rounded;
                              if (!isCurrent) iconCol = Colors.orangeAccent;
                            } else if (m.supportsThinking) {
                              icon = Icons.psychology_rounded;
                              if (!isCurrent) iconCol = Colors.purpleAccent;
                            } else if (m.id.toLowerCase().contains('coder') ||
                                m.id.toLowerCase().contains('code')) {
                              icon = Icons.code_rounded;
                              if (!isCurrent) iconCol = Colors.tealAccent;
                            }
                            items.add(
                              PopupMenuItem<String>(
                                value: m.id,
                                height: 38,
                                child: Row(
                                  children: [
                                    Icon(icon, size: 15, color: iconCol),
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
                                              ? theme.colors.accentBlue
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
                                        color: theme.colors.accentBlue,
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }
                          items.add(const PopupMenuDivider(height: 1));
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
                                        color: theme.colors.accentBlue,
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
                          onTap: () => coordinator.setAiThinking(!isThinkingOn),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isThinkingOn
                                  ? Colors.purpleAccent.withValues(
                                      alpha: theme.isDark ? 0.25 : 0.15,
                                    )
                                  : (theme.isDark
                                        ? Colors.white.withValues(alpha: 0.06)
                                        : Colors.black.withValues(alpha: 0.05)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isThinkingOn
                                    ? Colors.purpleAccent.withValues(alpha: 0.5)
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
                                              ? Colors.purpleAccent.shade100
                                              : Colors.purple.shade700)
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
                            color: Colors.amber.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.4),
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

          // Action Buttons
          if (isAi) ...[
            GlassIconButton(
              icon: Icons.cleaning_services_rounded,
              tooltip: lang.tr('clearAiChat'),
              color: theme.colors.accentRose,
              size: 34,
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
            GlassIconButton(
              icon: Icons.notifications_active_rounded,
              tooltip: lang.tr('nudge'),
              color: theme.colors.accentAmber,
              size: 34,
              onPressed: onBuzz,
            ),
          ],
          const SizedBox(width: 4),
          GlassIconButton(
            icon: peer.isPinned
                ? Icons.push_pin_rounded
                : Icons.push_pin_outlined,
            tooltip: peer.isPinned ? lang.tr('unpinChat') : lang.tr('pinChat'),
            color: peer.isPinned
                ? theme.colors.accentAmber
                : (theme.isDark ? Colors.white70 : Colors.black87),
            size: 34,
            onPressed: () => coordinator.togglePinPeer(peer.id),
          ),
          const SizedBox(width: 4),
          GlassIconButton(
            icon: Icons.attach_file_rounded,
            tooltip: lang.tr('attachFile'),
            color: theme.colors.accentBlue,
            size: 34,
            onPressed: onSendFile,
          ),
          if (onToggleDetails != null && !isAi) ...[
            const SizedBox(width: 4),
            GlassIconButton(
              icon: Icons.dock_rounded,
              tooltip: lang.tr('toggleDetails'),
              color: isDetailsOpen
                  ? theme.colors.accentBlue
                  : (theme.isDark ? Colors.white70 : Colors.black87),
              size: 34,
              onPressed: onToggleDetails,
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

class _PinnedMessagesBanner extends StatelessWidget {
  final List<MessageModel> pinnedMessages;
  final int currentIndex;
  final ValueChanged<int> onSelectIndex;
  final ValueChanged<MessageModel> onUnpin;
  final ValueChanged<MessageModel> onTap;

  const _PinnedMessagesBanner({
    required this.pinnedMessages,
    required this.currentIndex,
    required this.onSelectIndex,
    required this.onUnpin,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (pinnedMessages.isEmpty) return const SizedBox.shrink();
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final safeIndex = currentIndex.clamp(0, pinnedMessages.length - 1);
    final currentMsg = pinnedMessages[safeIndex];

    final previewText = currentMsg.text.isNotEmpty
        ? currentMsg.text.replaceAll('\n', ' ')
        : (currentMsg.fileAttachment?.fileName ?? lang.tr('pinnedMessage'));

    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color:
            (theme.isDark ? const Color(0xFF1E293B) : const Color(0xFFF3F4F8))
                .withValues(alpha: theme.isDark ? 0.75 : 0.95),
        border: Border(
          bottom: BorderSide(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: theme.isDark ? 0.10 : 0.08,
            ),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin_rounded, size: 16, color: Colors.amber.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () => onTap(currentMsg),
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Text(
                          pinnedMessages.length > 1
                              ? '${lang.tr('pinnedMessage')} (${safeIndex + 1}/${pinnedMessages.length})'
                              : lang.tr('pinnedMessage'),
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade700,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '• ${currentMsg.senderName}',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.isDark
                                ? const Color(0xFF94A3B8)
                                : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      previewText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: theme.isDark
                            ? const Color(0xFFF8FAFC)
                            : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (pinnedMessages.length > 1) ...[
            InkWell(
              onTap: () {
                final nextIdx =
                    (safeIndex - 1 + pinnedMessages.length) %
                    pinnedMessages.length;
                onSelectIndex(nextIdx);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: theme.isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                final nextIdx = (safeIndex + 1) % pinnedMessages.length;
                onSelectIndex(nextIdx);
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: theme.isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            const SizedBox(width: 4),
          ],
          InkWell(
            onTap: () => onUnpin(currentMsg),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 16,
                color: theme.isDark ? Colors.white54 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicatorBubble extends StatefulWidget {
  final PeerModel peer;
  const _TypingIndicatorBubble({required this.peer});

  @override
  State<_TypingIndicatorBubble> createState() => _TypingIndicatorBubbleState();
}

class _TypingIndicatorBubbleState extends State<_TypingIndicatorBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: (theme.isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.white),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
            bottomLeft: Radius.circular(2),
            bottomRight: Radius.circular(14),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.peer.effectiveDisplayName(lang)} ${lang.tr('typing')}',
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: theme.colors.accentBlue,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 8),
            AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(3, (index) {
                    final phase = (_animController.value + index * 0.25) % 1.0;
                    final scale =
                        0.5 + 0.5 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      width: 5 * scale,
                      height: 5 * scale,
                      decoration: BoxDecoration(
                        color: theme.colors.accentBlue.withValues(
                          alpha: 0.4 + 0.6 * scale,
                        ),
                        shape: BoxShape.circle,
                      ),
                    );
                  }),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _QuoteCard extends StatelessWidget {
  final String senderName;
  final String snippet;
  final bool isMine;
  final VoidCallback? onTap;

  const _QuoteCard({
    required this.senderName,
    required this.snippet,
    required this.isMine,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final accentColor = isMine
        ? const Color(0xFF67E8F9)
        : theme.colors.accentBlue;
    final bg = isMine
        ? Colors.black.withValues(alpha: 0.18)
        : (theme.isDark
              ? const Color(0xFF0F172A).withValues(alpha: 0.60)
              : Colors.black.withValues(alpha: 0.05));

    final textColor = isMine
        ? Colors.white.withValues(alpha: 0.9)
        : (theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3.5, color: accentColor),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.reply_rounded,
                            size: 11,
                            color: accentColor,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              senderName.isNotEmpty ? senderName : 'Quote',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        snippet,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.25,
                          color: textColor,
                        ),
                      ),
                    ],
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

class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isHighlighted;
  final ValueChanged<MessageModel>? onReply;
  final ValueChanged<String>? onScrollToMessage;

  const _MessageBubble({
    required this.message,
    this.isHighlighted = false,
    this.onReply,
    this.onScrollToMessage,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  bool _isHovered = false;
  bool _isCopied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  void _copyMessage(LanguageProvider lang) {
    if (widget.message.text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: widget.message.text));
    setState(() => _isCopied = true);
    _copyTimer?.cancel();
    _copyTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isCopied = false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.tr('messageCopied')),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _showMessageMenu(
    BuildContext context,
    Offset position,
    MessengerCoordinator coordinator,
    LanguageProvider lang,
  ) async {
    final isPinned = widget.message.isPinned;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      items: [
        PopupMenuItem<String>(
          value: 'reply',
          height: 36,
          child: Row(
            children: [
              const Icon(Icons.reply_rounded, size: 15),
              const SizedBox(width: 8),
              Text(lang.tr('quote'), style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'pin',
          height: 36,
          child: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
                size: 15,
                color: isPinned ? Colors.amber : null,
              ),
              const SizedBox(width: 8),
              Text(
                isPinned ? lang.tr('unpinMessage') : lang.tr('pinMessage'),
                style: const TextStyle(fontSize: 12.5),
              ),
            ],
          ),
        ),
        if (widget.message.text.isNotEmpty)
          PopupMenuItem<String>(
            value: 'copy',
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.copy_rounded, size: 15),
                const SizedBox(width: 8),
                Text(lang.tr('copy'), style: const TextStyle(fontSize: 12.5)),
              ],
            ),
          ),
        if (widget.message.isMine && !widget.message.isRevoked)
          PopupMenuItem<String>(
            value: 'revoke',
            height: 36,
            child: Row(
              children: [
                const Icon(
                  Icons.undo_rounded,
                  size: 15,
                  color: Colors.redAccent,
                ),
                const SizedBox(width: 8),
                Text(
                  lang.tr('revokeMessage'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Colors.redAccent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    if (!context.mounted) return;

    if (value == 'reply') {
      widget.onReply?.call(widget.message);
    } else if (value == 'pin') {
      coordinator.togglePinMessage(
        widget.message.conversationId,
        widget.message.id,
      );
      final wasPinned = widget.message.isPinned;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            wasPinned
                ? lang.tr('messageUnpinnedToast')
                : lang.tr('messagePinnedToast'),
          ),
          duration: const Duration(milliseconds: 1200),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else if (value == 'copy') {
      Clipboard.setData(ClipboardData(text: widget.message.text));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.tr('copiedToClipboard')),
          duration: const Duration(seconds: 1),
        ),
      );
    } else if (value == 'revoke') {
      _confirmRevoke(context, coordinator, lang);
    }
  }

  void _confirmRevoke(
    BuildContext context,
    MessengerCoordinator coordinator,
    LanguageProvider lang,
  ) {
    showGlassDialog(
      context: context,
      builder: (ctx) => GlassDialog(
        title: lang.tr('revokeMessage'),
        icon: Icons.undo_rounded,
        width: 380,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.of(ctx).pop();
              coordinator.revokeMessage(widget.message.id);
            },
            child: Text(lang.tr('revokeMessage')),
          ),
        ],
        child: Text(
          lang.tr('revokeConfirm'),
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildHoverActions(
    BuildContext context,
    ThemeProvider theme,
    LanguageProvider lang,
    MessengerCoordinator coordinator, {
    required bool canCopy,
    required bool canRegenerate,
  }) {
    final barBg = theme.isDark
        ? const Color(0xFF1E293B).withValues(alpha: 0.96)
        : Colors.white.withValues(alpha: 0.96);
    final borderColor = theme.isDark
        ? const Color(0x26FFFFFF)
        : Colors.black.withValues(alpha: 0.12);
    final isPinned = widget.message.isPinned;

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: barBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 0.8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: theme.isDark ? 0.4 : 0.12),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HoverActionButton(
              icon: Icons.reply_rounded,
              tooltip: lang.tr('quote'),
              color: theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87,
              onTap: () => widget.onReply?.call(widget.message),
            ),
            const SizedBox(width: 2),
            _HoverActionButton(
              icon: isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              tooltip: isPinned
                  ? lang.tr('unpinMessage')
                  : lang.tr('pinMessage'),
              color: isPinned
                  ? Colors.amber
                  : (theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87),
              onTap: () {
                coordinator.togglePinMessage(
                  widget.message.conversationId,
                  widget.message.id,
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      isPinned
                          ? lang.tr('messageUnpinnedToast')
                          : lang.tr('messagePinnedToast'),
                    ),
                    duration: const Duration(milliseconds: 1200),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
            ),
            if (canCopy) ...[
              const SizedBox(width: 2),
              _HoverActionButton(
                icon: _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                tooltip: _isCopied
                    ? lang.tr('messageCopied')
                    : lang.tr('copyMessage'),
                color: _isCopied
                    ? Colors.greenAccent
                    : (theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87),
                onTap: () => _copyMessage(lang),
              ),
            ],
            if (canRegenerate) ...[
              const SizedBox(width: 2),
              _HoverActionButton(
                icon: Icons.refresh_rounded,
                tooltip: lang.tr('regenerateAi'),
                color: theme.colors.accentBlue,
                onTap: () =>
                    coordinator.regenerateAiResponse(widget.message.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.read<MessengerCoordinator>();
    final message = widget.message;
    final isMine = message.isMine;

    final timeStr =
        '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}';

    final attachment = message.fileAttachment;
    final file = attachment?.localPath != null
        ? File(attachment!.localPath!)
        : null;
    final fileExists = file != null && file.existsSync();
    final isImg =
        attachment != null &&
        MessengerCoordinator.isImageFile(attachment.fileName);
    final isPureImage =
        isImg &&
        fileExists &&
        message.replyToText == null &&
        (message.text.trim().isEmpty ||
            message.text.trim() == attachment.fileName ||
            message.text.trim().startsWith(attachment.fileName));

    // 1. Trạng thái tin nhắn đã thu hồi
    if (message.isRevoked) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.05,
            ),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(14),
              topRight: const Radius.circular(14),
              bottomLeft: Radius.circular(isMine ? 14 : 2),
              bottomRight: Radius.circular(isMine ? 2 : 14),
            ),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.1,
              ),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.undo_rounded,
                size: 14,
                color: theme.isDark ? Colors.white38 : Colors.black38,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  lang.tr('messageRevoked'),
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: theme.isDark ? Colors.white38 : Colors.black45,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeStr,
                style: TextStyle(
                  fontSize: 10,
                  color: theme.isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // 2. Full-bleed Photo Bubble (Telegram/Discord style)
    if (isPureImage) {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onSecondaryTapDown: (details) => _showMessageMenu(
            context,
            details.globalPosition,
            coordinator,
            lang,
          ),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            constraints: const BoxConstraints(
              maxWidth: 340,
              maxHeight: 240,
              minWidth: 160,
              minHeight: 110,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: theme.isDark ? 0.12 : 0.08,
                ),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: theme.isDark ? 0.35 : 0.08,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  Positioned.fill(
                    child: InkWell(
                      onTap: () => showGlassImageLightbox(
                        context: context,
                        filePath: file.path,
                        fileName: attachment.fileName,
                      ),
                      child: Image.file(
                        file,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          color: Colors.black12,
                          child: const Center(
                            child: Icon(Icons.broken_image_rounded, size: 40),
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 18, 10, 6),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  attachment.fileName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  attachment.formattedSize,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                timeStr,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.white70,
                                ),
                              ),
                              if (isMine) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  message.status == MessageStatus.read
                                      ? Icons.done_all_rounded
                                      : (message.status ==
                                                MessageStatus.delivered
                                            ? Icons.done_all_rounded
                                            : (message.status ==
                                                      MessageStatus.sent
                                                  ? Icons.done_rounded
                                                  : Icons.schedule_rounded)),
                                  size: 13,
                                  color: message.status == MessageStatus.read
                                      ? const Color(0xFF67E8F9)
                                      : Colors.white70,
                                ),
                                if (message.status == MessageStatus.read) ...[
                                  const SizedBox(width: 3),
                                  Text(
                                    lang.tr('seen'),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF67E8F9),
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ],
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

    // 3. Standard Text / Mixed Message Bubble (Responsive width & Markdown)
    final isAi = message.aiModelTag != null;
    final canCopy = message.text.isNotEmpty;
    final canRegenerate = isAi && !isMine && !message.isStreaming;
    final showHoverBar = !message.isRevoked;

    final Color bubbleBg;
    if (isMine) {
      bubbleBg = theme.colors.accentBlue;
    } else if (isAi) {
      bubbleBg = theme.isDark
          ? const Color(0xFF192233)
          : const Color(0xFFF8FAFC);
    } else {
      bubbleBg = theme.isDark ? const Color(0xFF1E293B) : Colors.white;
    }

    final textColor = isMine
        ? Colors.white
        : (theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87);

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final isWide =
            message.aiModelTag != null ||
            message.text.contains('```') ||
            message.text.length > 200;

        final targetWidth = isWide
            ? (availableWidth * 0.85).clamp(420.0, 950.0)
            : (availableWidth * 0.68).clamp(320.0, 620.0);
        final maxBubbleWidth = math.min(
          targetWidth,
          math.max(260.0, availableWidth - 32.0),
        );

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                GestureDetector(
                  onSecondaryTapDown: (details) => _showMessageMenu(
                    context,
                    details.globalPosition,
                    coordinator,
                    lang,
                  ),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isMine ? 14 : 2),
                        bottomRight: Radius.circular(isMine ? 2 : 14),
                      ),
                      border: widget.isHighlighted
                          ? Border.all(color: Colors.amberAccent, width: 2.0)
                          : (isMine
                                ? null
                                : (isAi
                                      ? Border.all(
                                          color:
                                              (theme.isDark
                                                      ? const Color(0xFF38BDF8)
                                                      : const Color(0xFF0066FF))
                                                  .withValues(
                                                    alpha: theme.isDark
                                                        ? 0.35
                                                        : 0.20,
                                                  ),
                                          width: 1.2,
                                        )
                                      : (theme.isDark
                                            ? Border.all(
                                                color: const Color(0x1FFFFFFF),
                                                width: 1.0,
                                              )
                                            : null))),
                      boxShadow: [
                        if (widget.isHighlighted)
                          BoxShadow(
                            color: Colors.amberAccent.withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        else
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: theme.isDark ? 0.30 : 0.04,
                            ),
                            blurRadius: theme.isDark ? 8 : 4,
                            offset: const Offset(0, 2),
                          ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: isMine
                          ? CrossAxisAlignment.end
                          : CrossAxisAlignment.start,
                      children: [
                        // Quote / Reply Banner
                        if (message.replyToText != null) ...[
                          _QuoteCard(
                            senderName: message.replyToSender ?? '',
                            snippet: message.replyToText!,
                            isMine: isMine,
                            onTap: message.replyToId != null
                                ? () => widget.onScrollToMessage?.call(
                                    message.replyToId!,
                                  )
                                : null,
                          ),
                          const SizedBox(height: 6),
                        ],
                        // Khối suy nghĩ AI (nếu có thinkingContent)
                        if (message.thinkingContent != null &&
                            message.thinkingContent!.isNotEmpty) ...[
                          _AiThinkingBox(message: message),
                        ],

                        // Trạng thái AI đang chuẩn bị phản hồi ban đầu
                        if (message.isStreaming &&
                            message.text.isEmpty &&
                            (message.thinkingContent == null ||
                                message.thinkingContent!.isEmpty)) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: theme.colors.accentBlue,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  lang.tr('aiThinkingRunning'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: theme.isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],

                        // Nội dung tin nhắn với Markdown & Code Blocks
                        if (message.text.trim().isNotEmpty &&
                            (!message.hasAttachment ||
                                !message.text.contains(
                                  attachment?.fileName ?? '',
                                ))) ...[
                          MarkdownMessageView(
                            text: message.text,
                            isMine: isMine,
                            isStreaming: message.isStreaming,
                            baseTextStyle: TextStyle(
                              color: textColor,
                              fontSize: 13,
                              height: 1.38,
                            ),
                          ),
                          if (message.isStreaming) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 8,
                                  height: 8,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: isMine
                                        ? Colors.white70
                                        : theme.colors.accentBlue,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  lang.tr('aiGenerating'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontStyle: FontStyle.italic,
                                    color: isMine
                                        ? Colors.white70
                                        : (theme.isDark
                                              ? Colors.white54
                                              : Colors.black45),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],

                        // Nếu có đính kèm file
                        if (message.hasAttachment) ...[
                          if (message.text.trim().isNotEmpty &&
                              !message.text.contains(
                                attachment?.fileName ?? '',
                              ))
                            const SizedBox(height: 6),
                          _AttachmentPreview(
                            attachment: message.fileAttachment!,
                            isMine: isMine,
                          ),
                        ],

                        const SizedBox(height: 3),
                        // Timestamp & Delivery/Read Status
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: isMine
                                    ? Colors.white70
                                    : (theme.isDark
                                          ? const Color(0xFF94A3B8)
                                          : Colors.black38),
                              ),
                            ),
                            if (message.aiModelTag != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      (theme.isDark
                                              ? Colors.purple.shade900
                                              : Colors.purple.shade50)
                                          .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color:
                                        (theme.isDark
                                                ? Colors.purple.shade400
                                                : Colors.purple.shade300)
                                            .withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  message.aiModelTag!,
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: theme.isDark
                                        ? const Color(0xFFD8B4FE)
                                        : const Color(0xFF7E22CE),
                                  ),
                                ),
                              ),
                            ],
                            if (isMine) ...[
                              const SizedBox(width: 4),
                              Icon(
                                message.status == MessageStatus.read
                                    ? Icons.done_all_rounded
                                    : (message.status == MessageStatus.delivered
                                          ? Icons.done_all_rounded
                                          : (message.status ==
                                                    MessageStatus.sent
                                                ? Icons.done_rounded
                                                : Icons.schedule_rounded)),
                                size: 12.5,
                                color: message.status == MessageStatus.read
                                    ? const Color(0xFF67E8F9)
                                    : Colors.white70,
                              ),
                              if (message.status == MessageStatus.read) ...[
                                const SizedBox(width: 3),
                                Text(
                                  lang.tr('seen'),
                                  style: const TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF67E8F9),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Hover Quick Actions Toolbar
                if (showHoverBar)
                  Positioned(
                    top: -6,
                    right: isMine ? null : 6,
                    left: isMine ? 6 : null,
                    child: AnimatedOpacity(
                      opacity: _isHovered ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !_isHovered,
                        child: _buildHoverActions(
                          context,
                          theme,
                          lang,
                          coordinator,
                          canCopy: canCopy,
                          canRegenerate: canRegenerate,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HoverActionButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onTap;

  const _HoverActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: color.withValues(alpha: 0.15),
        child: Padding(
          padding: const EdgeInsets.all(4.5),
          child: Icon(icon, size: 13.5, color: color),
        ),
      ),
    );
  }
}

class _AiThinkingBox extends StatefulWidget {
  final MessageModel message;

  const _AiThinkingBox({required this.message});

  @override
  State<_AiThinkingBox> createState() => _AiThinkingBoxState();
}

class _AiThinkingBoxState extends State<_AiThinkingBox> {
  late bool _isExpanded;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.message.isThinkingExpanded;
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isStreamingThinking =
        widget.message.isStreaming && (widget.message.text.trim().isEmpty);
    final thinkingText = widget.message.thinkingContent ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: (theme.isDark ? Colors.purple.shade900 : Colors.purple.shade50)
            .withValues(alpha: theme.isDark ? 0.35 : 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              (theme.isDark ? Colors.purple.shade400 : Colors.purple.shade300)
                  .withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () {
              setState(() {
                _isExpanded = !_isExpanded;
                widget.message.isThinkingExpanded = _isExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🧠', style: TextStyle(fontSize: 13)),
                  const SizedBox(width: 6),
                  Text(
                    isStreamingThinking
                        ? lang.tr('aiThinkingRunning')
                        : lang.tr('aiThinkingHeader'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.isDark
                          ? const Color(0xFFD8B4FE)
                          : const Color(0xFF7E22CE),
                    ),
                  ),
                  if (isStreamingThinking) ...[
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: theme.isDark
                            ? const Color(0xFFD8B4FE)
                            : const Color(0xFF7E22CE),
                      ),
                    ),
                  ],
                  const SizedBox(width: 6),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 16,
                    color: theme.isDark ? Colors.white54 : Colors.black45,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded && thinkingText.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
              child: Text(
                thinkingText,
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 11.5,
                  height: 1.35,
                  color: theme.isDark
                      ? Colors.white.withValues(alpha: 0.7)
                      : Colors.black.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

void _openAttachmentFile(String path) {
  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', path]);
  } else {
    Process.run('open', [path]);
  }
}

void _openAttachmentFolder(String path) {
  if (Platform.isWindows) {
    Process.run('explorer.exe', ['/select,', path]);
  }
}

void _showAttachmentLightbox(
  BuildContext context,
  String filePath,
  String fileName,
) {
  showGlassImageLightbox(
    context: context,
    filePath: filePath,
    fileName: fileName,
  );
}

class _AttachmentPreview extends StatelessWidget {
  final FileAttachmentInfo attachment;
  final bool isMine;

  const _AttachmentPreview({required this.attachment, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isImg = MessengerCoordinator.isImageFile(attachment.fileName);
    final file = attachment.localPath != null
        ? File(attachment.localPath!)
        : null;
    final fileExists = file != null && file.existsSync();

    // 1. Image Preview with Thumbnail & Lightbox Zoom Viewer
    if (isImg && fileExists) {
      return InkWell(
        onTap: () =>
            _showAttachmentLightbox(context, file.path, attachment.fileName),
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 280,
              maxHeight: 200,
              minWidth: 140,
              minHeight: 90,
            ),
            decoration: BoxDecoration(
              color: (isMine ? Colors.black : Colors.white).withValues(
                alpha: 0.15,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 100,
                    color: Colors.black12,
                    child: const Center(
                      child: Icon(Icons.broken_image_rounded, size: 36),
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, Colors.black87],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          attachment.fileName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        attachment.formattedSize,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 9.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // 2. Non-Image Document / File Card with Direct Windows Execution
    return InkWell(
      onTap: () {
        if (fileExists) {
          _openAttachmentFile(file.path);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${lang.tr('sharedFiles')}: File not found'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (isMine ? Colors.black : Colors.white).withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: (isMine ? Colors.white : Colors.black).withValues(
              alpha: 0.1,
            ),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isImg ? Icons.image_rounded : Icons.insert_drive_file_rounded,
              size: 28,
              color: isMine ? Colors.white : theme.colors.accentBlue,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    attachment.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isMine
                          ? Colors.white
                          : (theme.isDark ? Colors.white : Colors.black87),
                    ),
                  ),
                  Text(
                    attachment.formattedSize,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isMine ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            if (fileExists) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                tooltip: lang.tr('openFolder'),
                color: isMine ? Colors.white70 : Colors.black54,
                onPressed: () => _openAttachmentFolder(file.path),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChatInputDock extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final VoidCallback onSend;
  final VoidCallback onAttachFile;
  final VoidCallback onPasteClipboard;
  final VoidCallback onBuzz;
  final double? maxInputHeight;
  final MessageModel? replyingTo;
  final VoidCallback? onCancelReply;

  const _ChatInputDock({
    required this.controller,
    this.focusNode,
    this.onChanged,
    required this.onSend,
    required this.onAttachFile,
    required this.onPasteClipboard,
    required this.onBuzz,
    this.maxInputHeight,
    this.replyingTo,
    this.onCancelReply,
  });

  @override
  State<_ChatInputDock> createState() => _ChatInputDockState();
}

class _ChatInputDockState extends State<_ChatInputDock> {
  bool _showEmojiPicker = false;
  final ScrollController _inputScrollController = ScrollController();

  @override
  void dispose() {
    _inputScrollController.dispose();
    super.dispose();
  }

  static const List<String> _commonEmojis = [
    '😀',
    '😃',
    '😄',
    '😁',
    '😆',
    '😅',
    '😂',
    '🤣',
    '😊',
    '😇',
    '🙂',
    '😉',
    '😍',
    '🥰',
    '😘',
    '😋',
    '😎',
    '🥳',
    '🤔',
    '🤫',
    '🤐',
    '😴',
    '😷',
    '🤒',
    '👍',
    '👎',
    '👌',
    '✌️',
    '🤞',
    '👏',
    '🙌',
    '🤝',
    '🙏',
    '💪',
    '❤️',
    '🧡',
    '💛',
    '💚',
    '💙',
    '💜',
    '🔥',
    '🎉',
    '✨',
    '⭐',
    '💡',
    '🚀',
    '✅',
    '💯',
  ];

  void _insertEmoji(String emoji) {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.start;
    final end = selection.end;
    final newText = (start >= 0 && end >= 0)
        ? text.replaceRange(start, end, emoji)
        : text + emoji;
    final newSelectionIndex = (start >= 0)
        ? start + emoji.length
        : newText.length;

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newSelectionIndex),
    );
    widget.onChanged?.call(newText);
    if (widget.focusNode != null && widget.focusNode!.canRequestFocus) {
      widget.focusNode!.requestFocus();
    }
  }

  void _insertNewline() {
    final text = widget.controller.text;
    final selection = widget.controller.selection;
    final start = selection.start >= 0 ? selection.start : text.length;
    final end = selection.end >= 0 ? selection.end : text.length;
    final newText = text.replaceRange(start, end, '\n');
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
    widget.onChanged?.call(newText);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_inputScrollController.hasClients) {
        _inputScrollController.animateTo(
          _inputScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 80),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _triggerSend() {
    widget.onSend();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.focusNode != null && widget.focusNode!.canRequestFocus) {
        widget.focusNode!.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final isAiChat = coordinator.selectedPeer?.isAiAssistant == true;
    final isAiBusy = isAiChat && coordinator.isAiActive;

    final dockOpacity = theme.isDark
        ? (0.35 + theme.cardOpacity * 0.55).clamp(0.35, 0.96)
        : (0.60 + theme.cardOpacity * 0.36).clamp(0.60, 0.98);
    final dockBlur = math.max(theme.cardBlur, 0.0);

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      decoration: BoxDecoration(
        color: (theme.isDark ? const Color(0xFF1E293B) : Colors.white)
            .withValues(alpha: dockOpacity),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (theme.isDark ? const Color(0x26FFFFFF) : Colors.black)
              .withValues(alpha: theme.isDark ? 0.8 : 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: theme.isDark ? 0.25 : 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: dockBlur, sigmaY: dockBlur),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. Emoji Popover (Compact 340px x 220px, high-density 22px icons)
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                child: _showEmojiPicker
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 340,
                            height: 220,
                            decoration: BoxDecoration(
                              color:
                                  (theme.isDark
                                          ? const Color(0xFF1E293B)
                                          : const Color(0xFFF7F8FA))
                                      .withValues(alpha: 0.98),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color:
                                    (theme.isDark
                                            ? const Color(0x1FFFFFFF)
                                            : Colors.black)
                                        .withValues(
                                          alpha: theme.isDark ? 0.8 : 0.08,
                                        ),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: theme.isDark ? 0.35 : 0.08,
                                  ),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    12,
                                    8,
                                    8,
                                    6,
                                  ),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        lang.tr('emojis'),
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: theme.isDark
                                              ? Colors.white70
                                              : Colors.black87,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: () => setState(
                                          () => _showEmojiPicker = false,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        child: Padding(
                                          padding: const EdgeInsets.all(3),
                                          child: Icon(
                                            Icons.close_rounded,
                                            size: 15,
                                            color: theme.isDark
                                                ? Colors.white54
                                                : Colors.black45,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Divider(
                                  height: 1,
                                  thickness: 0.8,
                                  color:
                                      (theme.isDark
                                              ? Colors.white
                                              : Colors.black)
                                          .withValues(
                                            alpha: theme.isDark ? 0.08 : 0.06,
                                          ),
                                ),
                                Expanded(
                                  child: Scrollbar(
                                    child: GridView.builder(
                                      padding: const EdgeInsets.all(6),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: 8,
                                            mainAxisSpacing: 3,
                                            crossAxisSpacing: 3,
                                            childAspectRatio: 1.0,
                                          ),
                                      itemCount: _commonEmojis.length,
                                      itemBuilder: (context, idx) {
                                        final emoji = _commonEmojis[idx];
                                        return Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                            hoverColor:
                                                (theme.isDark
                                                        ? Colors.white
                                                        : Colors.black)
                                                    .withValues(alpha: 0.08),
                                            onTap: () => _insertEmoji(emoji),
                                            child: Center(
                                              child: Text(
                                                emoji,
                                                style: const TextStyle(
                                                  fontSize: 22,
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),

              // 1.5 Quote / Replying Preview Bar
              if (widget.replyingTo != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        (theme.isDark ? const Color(0xFF0F172A) : Colors.black)
                            .withValues(alpha: theme.isDark ? 0.60 : 0.04),
                    border: Border(
                      bottom: BorderSide(
                        color: (theme.isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.08),
                        width: 0.8,
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 3.5,
                        height: 32,
                        decoration: BoxDecoration(
                          color: theme.colors.accentBlue,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.reply_rounded,
                                  size: 13,
                                  color: theme.colors.accentBlue,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${lang.tr('replyingTo')} ${widget.replyingTo!.senderName}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: theme.colors.accentBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.replyingTo!.text.isNotEmpty
                                  ? widget.replyingTo!.text.replaceAll(
                                      '\n',
                                      ' ',
                                    )
                                  : (widget
                                            .replyingTo!
                                            .fileAttachment
                                            ?.fileName ??
                                        ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.isDark
                                    ? const Color(0xFFF8FAFC)
                                    : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: widget.onCancelReply,
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: theme.isDark
                                ? Colors.white54
                                : Colors.black45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // 2. Chat Input Area (Spans 100% full width of card, no white flanks)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                child: Focus(
                  onKeyEvent: (node, event) {
                    if (event is KeyDownEvent) {
                      if (event.logicalKey == LogicalKeyboardKey.escape &&
                          widget.replyingTo != null) {
                        widget.onCancelReply?.call();
                        return KeyEventResult.handled;
                      }
                      final isEnter =
                          event.logicalKey == LogicalKeyboardKey.enter ||
                          event.logicalKey == LogicalKeyboardKey.numpadEnter;
                      if (isEnter) {
                        if (HardwareKeyboard.instance.isShiftPressed) {
                          _insertNewline();
                          return KeyEventResult.handled;
                        } else if (!HardwareKeyboard
                                .instance
                                .isControlPressed &&
                            !HardwareKeyboard.instance.isAltPressed) {
                          _triggerSend();
                          return KeyEventResult.handled;
                        }
                      } else if (event.logicalKey == LogicalKeyboardKey.keyV &&
                          HardwareKeyboard.instance.isControlPressed) {
                        widget.onPasteClipboard();
                        return KeyEventResult.ignored;
                      }
                    }
                    return KeyEventResult.ignored;
                  },
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: 28,
                      maxHeight: widget.maxInputHeight ?? 240,
                    ),
                    child: Scrollbar(
                      controller: _inputScrollController,
                      thumbVisibility: false,
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        scrollController: _inputScrollController,
                        onChanged: widget.onChanged,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        minLines: 1,
                        maxLines: null,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.isDark
                              ? const Color(0xFFF8FAFC)
                              : Colors.black87,
                        ),
                        decoration: InputDecoration(
                          hintText: lang.tr('inputHint'),
                          hintStyle: TextStyle(
                            fontSize: 12.5,
                            color: theme.isDark
                                ? const Color(0xFF64748B)
                                : Colors.black38,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // 3. Action Toolbar Row (Fixed height ~38px, hugging buttons only)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 2, 10, 8),
                child: Row(
                  children: [
                    GlassIconButton(
                      icon: Icons.attach_file_rounded,
                      tooltip: lang.tr('attachFile'),
                      size: 32,
                      onPressed: widget.onAttachFile,
                    ),
                    const SizedBox(width: 2),
                    GlassIconButton(
                      icon: Icons.sentiment_satisfied_alt_rounded,
                      tooltip: lang.tr('emojis'),
                      size: 32,
                      color: _showEmojiPicker ? theme.colors.accentBlue : null,
                      onPressed: () {
                        setState(() {
                          _showEmojiPicker = !_showEmojiPicker;
                        });
                      },
                    ),
                    if (!isAiChat) ...[
                      const SizedBox(width: 2),
                      GlassIconButton(
                        icon: Icons.notifications_none_rounded,
                        tooltip: lang.tr('nudge'),
                        size: 32,
                        onPressed: widget.onBuzz,
                      ),
                    ],
                    const Spacer(),
                    if (isAiBusy) ...[
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent.shade400,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(36, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () => coordinator.stopAiGeneration(),
                        icon: const Icon(Icons.stop_circle_rounded, size: 14),
                        label: Text(
                          lang.tr('stopAiGeneration'),
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.colors.accentBlue,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(40, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        elevation: 0,
                      ),
                      onPressed: _triggerSend,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            lang.tr('send'),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.send_rounded, size: 13),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChatView extends StatelessWidget {
  const _EmptyChatView();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: theme.colors.accentBlue.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 32,
              color: theme.colors.accentBlue,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            lang.tr('emptySelectChat'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: theme.isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              lang.tr('emptySelectChatDesc'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: theme.isDark ? Colors.white38 : Colors.black45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMessagesState extends StatelessWidget {
  final String peerName;

  const _NoMessagesState({required this.peerName});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.waving_hand_rounded,
            size: 36,
            color: Colors.amber.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 10),
          Text(
            lang.tr('noMessages'),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: theme.isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lang.tr('noMessagesDesc'),
            style: TextStyle(
              fontSize: 12,
              color: theme.isDark ? Colors.white38 : Colors.black45,
            ),
          ),
        ],
      ),
    );
  }
}
