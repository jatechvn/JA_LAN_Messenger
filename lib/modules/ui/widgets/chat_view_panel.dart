import 'dart:async';
import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
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
import 'glass_file_preview_dialog.dart';
import 'markdown_message_view.dart';
import 'bounce_marquee_text.dart';
import 'contact_profile_dialog.dart';
import 'app_avatar.dart';
import 'group_members_dialog.dart';
import 'group_mention_picker.dart';
import '../../ime/ime_service.dart';
import 'pinyin_candidate_bar.dart';
import 'ime_toggle_button.dart';

class ChatViewPanel extends StatefulWidget {
  final bool isDetailsOpen;
  final VoidCallback? onToggleDetails;
  final bool isCompact;
  final VoidCallback? onBackToList;

  const ChatViewPanel({
    super.key,
    this.isDetailsOpen = false,
    this.onToggleDetails,
    this.isCompact = false,
    this.onBackToList,
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
  bool _prevPeerTyping = false;
  String? _lastPeerId;

  // Scroll tracking state
  bool _hasScrollableContent = false;
  bool _showScrollToTop = false;
  bool _showScrollToBottom = false;
  bool _isNearBottom = true;
  int _unreadBelowCount = 0;
  bool _pendingJumpToBottom = false;
  bool _pendingJumpToUnread = false;
  String? _activeUnreadSeparatorMessageId;
  final GlobalKey _unreadSeparatorKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _inputFocusNode = FocusNode();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _typingDebounceTimer?.cancel();
    _highlightTimer?.cancel();
    _inputFocusNode.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    _updateScrollState();
  }

  void _updateScrollState() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final max = pos.maxScrollExtent;
    final current = pos.pixels;

    final hasScrollableContent = max > 50.0;
    final isAtTop = current <= 40.0;
    final isAtBottom = (max - current) <= 40.0;
    final isNearBottom = (max - current) <= 140.0;

    final showScrollToTop = hasScrollableContent && !isAtTop;
    final showScrollToBottom = hasScrollableContent && !isAtBottom;
    final newUnreadCount = isAtBottom ? 0 : _unreadBelowCount;

    if (isAtBottom && _unreadBelowCount > 0) {
      try {
        final coord = context.read<MessengerCoordinator>();
        final p = coord.selectedPeer;
        if (p != null) {
          coord.markConversationAsRead(p.id);
        }
      } catch (_) {}
    }

    if (_hasScrollableContent != hasScrollableContent ||
        _showScrollToTop != showScrollToTop ||
        _showScrollToBottom != showScrollToBottom ||
        _isNearBottom != isNearBottom ||
        _unreadBelowCount != newUnreadCount) {
      _hasScrollableContent = hasScrollableContent;
      _showScrollToTop = showScrollToTop;
      _showScrollToBottom = showScrollToBottom;
      _isNearBottom = isNearBottom;
      _unreadBelowCount = newUnreadCount;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  void _scrollToTop({bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (smooth) {
        _scrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(0.0);
      }
    });
  }

  void _scrollToBottom({bool force = false, bool smooth = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final isNearBottom = (pos.maxScrollExtent - pos.pixels) <= 140.0;
      if (!force && !isNearBottom) return;

      if (smooth) {
        _scrollController
            .animateTo(
              pos.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (mounted && _scrollController.hasClients) {
                final p = _scrollController.position;
                if ((p.maxScrollExtent - p.pixels) > 5.0) {
                  _scrollController.jumpTo(p.maxScrollExtent);
                }
                _updateScrollState();
              }
            });
      } else {
        _performJumpToBottom();
      }
    });
  }

  void _performJumpToBottom({int remainingAttempts = 6}) {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final diff = pos.maxScrollExtent - pos.pixels;
    if (diff.abs() > 2.0 && remainingAttempts > 0) {
      _scrollController.jumpTo(pos.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performJumpToBottom(remainingAttempts: remainingAttempts - 1);
      });
    } else {
      if (diff.abs() > 2.0) {
        _scrollController.jumpTo(pos.maxScrollExtent);
      }
      _updateScrollState();
    }
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

  final List<File> _stagedAttachments = [];
  bool _draggingFiles = false;

  Future<void> _stageDroppedFiles(DropDoneDetails details) async {
    final coordinator = context.read<MessengerCoordinator>();
    final peerId = coordinator.selectedPeer?.id;
    setState(() => _draggingFiles = false);
    final files = <File>[];
    for (final item in details.files) {
      final file = File(item.path);
      if (await file.exists()) files.add(file);
    }
    if (!mounted || peerId == null || coordinator.selectedPeer?.id != peerId) {
      return;
    }
    setState(() => _stagedAttachments.addAll(files));
    _inputFocusNode.requestFocus();
  }

  void _removeStagedAttachment(int index) {
    if (index >= 0 && index < _stagedAttachments.length) {
      setState(() {
        _stagedAttachments.removeAt(index);
      });
    }
  }

  void _clearStagedAttachments() {
    setState(() {
      _stagedAttachments.clear();
    });
  }

  void _handleSend(MessengerCoordinator coordinator) {
    _typingDebounceTimer?.cancel();
    coordinator.sendTypingStatus(false);
    final text = _inputController.text;
    final hasText = text.trim().isNotEmpty;
    final hasAttachments = _stagedAttachments.isNotEmpty;

    if (!hasText && !hasAttachments) return;

    _inputController.clear();
    final replying = _replyingToMessage;
    final peer = coordinator.selectedPeer;
    if (peer != null) {
      coordinator.markConversationAsRead(peer.id);
    }

    final filesToSend = List<File>.from(_stagedAttachments);

    setState(() {
      _stagedAttachments.clear();
      _replyingToMessage = null;
      _unreadBelowCount = 0;
      _activeUnreadSeparatorMessageId = null;
      _isNearBottom = true;
    });

    if (filesToSend.isNotEmpty) {
      coordinator.sendFiles(filesToSend, text: text, replyTo: replying);
    } else {
      coordinator.sendMessage(text, replyTo: replying);
    }

    _scrollToBottom(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _inputFocusNode.canRequestFocus) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  Future<void> _handlePickFile() async {
    final peerId = context.read<MessengerCoordinator>().selectedPeer?.id;
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (!mounted ||
        context.read<MessengerCoordinator>().selectedPeer?.id != peerId) {
      return;
    }
    if (result != null && result.files.isNotEmpty) {
      final newFiles = <File>[];
      for (final pf in result.files) {
        if (pf.path != null) {
          final f = File(pf.path!);
          if (f.existsSync()) {
            newFiles.add(f);
          }
        }
      }
      if (newFiles.isNotEmpty) {
        setState(() {
          _stagedAttachments.addAll(newFiles);
        });
        _inputFocusNode.requestFocus();
      }
    }
  }

  Future<void> _handlePasteClipboard(MessengerCoordinator coordinator) async {
    final peerId = coordinator.selectedPeer?.id;
    final files = await coordinator.getClipboardAttachments();
    if (!mounted || coordinator.selectedPeer?.id != peerId) return;
    if (files.isNotEmpty) {
      setState(() {
        _stagedAttachments.addAll(files);
      });
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

    final messages = coordinator.currentMessages;
    final isPeerTyping =
        (!peer.isAllUsers &&
        ((!peer.isGroup && coordinator.isPeerTyping(peer.id)) ||
            (peer.isGroup && coordinator.isGroupTyping(peer.id))));
    final totalItems = messages.length + (isPeerTyping ? 1 : 0);

    // Reset replying state & determine scroll target if active peer changed
    final isPeerChanged = _lastPeerId != peer.id;
    if (isPeerChanged) {
      _lastPeerId = peer.id;
      _stagedAttachments.clear();
      _replyingToMessage = null;
      _currentPinnedIndex = 0;
      _prevMessageCount = messages.length;
      _prevPeerTyping = isPeerTyping;

      // Telegram-style: Check if there are unread messages in this conversation
      final firstUnreadId =
          coordinator.getFirstUnreadMessageId(peer.id) ??
          coordinator.getInitialUnreadMessageId(peer.id);

      if (firstUnreadId != null) {
        final unreadIdx = messages.indexWhere((m) => m.id == firstUnreadId);
        if (unreadIdx != -1) {
          _activeUnreadSeparatorMessageId = firstUnreadId;
          _unreadBelowCount = messages.length - unreadIdx;
          _isNearBottom = false;
          _pendingJumpToUnread = true;
          _pendingJumpToBottom = false;
        } else {
          _activeUnreadSeparatorMessageId = null;
          _unreadBelowCount = 0;
          _isNearBottom = true;
          _pendingJumpToBottom = true;
          _pendingJumpToUnread = false;
        }
      } else {
        _activeUnreadSeparatorMessageId = null;
        _unreadBelowCount = 0;
        _isNearBottom = true;
        _pendingJumpToBottom = true;
        _pendingJumpToUnread = false;
      }
    }

    if (_pendingJumpToBottom) {
      _pendingJumpToBottom = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performJumpToBottom();
      });
    } else if (_pendingJumpToUnread &&
        _activeUnreadSeparatorMessageId != null) {
      _pendingJumpToUnread = false;
      final targetId = _activeUnreadSeparatorMessageId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final index = messages.indexWhere((m) => m.id == targetId);
        if (index == -1) return;
        final total = messages.length;
        if (total == 0) return;

        // Frame 1: Approximate jump to target area to materialize widgets in ListView viewport
        final targetFraction = (index / total).clamp(0.0, 1.0);
        final targetOffset =
            targetFraction * _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(targetOffset);

        // Frame 2: Ensure pixel-perfect visible alignment with unread separator at ~8% from top
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final ctx = _unreadSeparatorKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.08,
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOutQuad,
            );
          }
          _updateScrollState();
        });
      });
    }

    // Auto-scroll logic: instant jump during AI stream (prevents 200ms animation conflicts),
    // and smooth scroll when a new message arrives or peer starts typing while user is near bottom.
    final isStreaming = messages.isNotEmpty && messages.last.isStreaming;
    if (isStreaming) {
      _scrollToBottom(force: false, smooth: false);
    } else if (!isPeerChanged) {
      if (messages.length != _prevMessageCount) {
        final delta = messages.length - _prevMessageCount;
        _prevMessageCount = messages.length;
        if (delta > 0) {
          if (_isNearBottom) {
            _unreadBelowCount = 0;
            _scrollToBottom(force: true, smooth: true);
          } else {
            _unreadBelowCount += delta;
            _updateScrollState();
          }
        } else {
          _unreadBelowCount = 0;
          _updateScrollState();
        }
      } else if (isPeerTyping != _prevPeerTyping) {
        final startedTyping = isPeerTyping && !_prevPeerTyping;
        if (startedTyping && _isNearBottom) {
          _scrollToBottom(force: true, smooth: true);
        }
      }
    }
    _prevPeerTyping = isPeerTyping;

    final pinnedMessages = coordinator.getPinnedMessages(peer.id);

    return DropTarget(
      onDragEntered: (_) => setState(() => _draggingFiles = true),
      onDragExited: (_) => setState(() => _draggingFiles = false),
      onDragDone: _stageDroppedFiles,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxDockHeight = (constraints.maxHeight * 0.50).clamp(
            100.0,
            500.0,
          );
          return Container(
            foregroundDecoration: _draggingFiles
                ? BoxDecoration(
                    color: ThemeProvider.of(
                      context,
                    ).colors.accentBlue.withValues(alpha: 0.08),
                    border: Border.all(
                      color: ThemeProvider.of(context).colors.accentBlue,
                      width: 2,
                    ),
                  )
                : null,
            color: Colors.transparent,
            child: Column(
              children: [
                // Chat Header
                _ChatHeader(
                  peer: peer,
                  onBuzz: () => coordinator.sendBuzz(),
                  onSendFile: _handlePickFile,
                  isDetailsOpen: widget.isDetailsOpen,
                  onToggleDetails: widget.onToggleDetails,
                  isCompact: widget.isCompact,
                  onBackToList: widget.onBackToList,
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
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          _updateScrollState();
                          return false;
                        },
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
                                    final isFirstUnread =
                                        msg.id ==
                                        _activeUnreadSeparatorMessageId;
                                    final bubble = _MessageBubble(
                                      message: msg,
                                      isHighlighted:
                                          msg.id == _highlightedMessageId,
                                      onReply: (m) {
                                        setState(() {
                                          _replyingToMessage = m;
                                        });
                                        _inputFocusNode.requestFocus();
                                      },
                                      onScrollToMessage: (id) =>
                                          _scrollToMessage(id, messages),
                                    );

                                    if (isFirstUnread) {
                                      return Column(
                                        key: _unreadSeparatorKey,
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          const _UnreadSeparatorBanner(),
                                          bubble,
                                        ],
                                      );
                                    }
                                    return bubble;
                                  } else {
                                    return _TypingIndicatorBubble(peer: peer);
                                  }
                                },
                              ),
                      ),
                      if (_hasScrollableContent &&
                          (_showScrollToTop || _showScrollToBottom))
                        Positioned(
                          right: 18,
                          bottom: 12,
                          child: _ChatScrollControls(
                            showScrollToTop: _showScrollToTop,
                            showScrollToBottom: _showScrollToBottom,
                            unreadBelowCount: _unreadBelowCount,
                            onScrollToTop: () => _scrollToTop(smooth: true),
                            onScrollToBottom: () {
                              setState(() {
                                _unreadBelowCount = 0;
                              });
                              coordinator.markConversationAsRead(peer.id);
                              _scrollToBottom(force: true, smooth: true);
                            },
                          ),
                        ),
                    ],
                  ),
                ),

                // Input Dock
                _ChatInputDock(
                  controller: _inputController,
                  focusNode: _inputFocusNode,
                  maxInputHeight: maxDockHeight,
                  replyingTo: _replyingToMessage,
                  isCompact: widget.isCompact,
                  stagedAttachments: _stagedAttachments,
                  onRemoveStagedAttachment: _removeStagedAttachment,
                  onClearStagedAttachments: _clearStagedAttachments,
                  onCancelReply: () {
                    setState(() {
                      _replyingToMessage = null;
                    });
                  },
                  onChanged: (text) => _onTextChanged(text, coordinator),
                  onSend: () => _handleSend(coordinator),
                  onAttachFile: _handlePickFile,
                  onPasteClipboard: () => _handlePasteClipboard(coordinator),
                  onBuzz: () => coordinator.sendBuzz(),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final PeerModel peer;
  final VoidCallback onBuzz;
  final VoidCallback onSendFile;
  final bool isDetailsOpen;
  final VoidCallback? onToggleDetails;
  final bool isCompact;
  final VoidCallback? onBackToList;

  const _ChatHeader({
    required this.peer,
    required this.onBuzz,
    required this.onSendFile,
    this.isDetailsOpen = false,
    this.onToggleDetails,
    this.isCompact = false,
    this.onBackToList,
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
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 10 : 16),
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
                        isCompact && !peer.isAllUsers && !peer.isGroup && !isAi,
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
                                child: isCompact
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
                                  !peer.isGroup) ...[
                                const SizedBox(width: 4),
                                Tooltip(
                                  message: lang.tr('editNickname'),
                                  child: Icon(
                                    Icons.edit_rounded,
                                    size: 12,
                                    color: theme.colors.accentBlue.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              ],
                              if (!isCompact &&
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
          if (!isCompact) ...[
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
              _BuzzActionButton(
                onPressed: onBuzz,
                tooltip: lang.tr('nudge'),
                size: 34,
                defaultColor: theme.colors.accentAmber,
              ),
            ],
            const SizedBox(width: 4),
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
              size: 34,
              onPressed: () => coordinator.togglePinPeer(peer.id),
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
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.0, end: 1.0),
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        builder: (context, animValue, child) {
          return Opacity(
            opacity: animValue.clamp(0.0, 1.0),
            child: Transform.translate(
              offset: Offset(0, (1.0 - animValue) * 8.0),
              child: child,
            ),
          );
        },
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
                (widget.peer.isGroup
                        ? context
                              .watch<MessengerCoordinator>()
                              .getGroupTypingText(widget.peer.id, lang)
                        : null) ??
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
                      final phase =
                          (_animController.value + index * 0.25) % 1.0;
                      final scale =
                          0.5 +
                          0.5 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2);
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

  void _showQuickReactionPicker(
    BuildContext context,
    MessengerCoordinator coordinator,
  ) {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '👏', '🔥', '🎉'];
    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox != null
        ? renderBox.localToGlobal(Offset.zero)
        : const Offset(100, 100);

    showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        math.max(40.0, offset.dy - 48),
        offset.dx + 280,
        offset.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 6,
      items: [
        PopupMenuItem<String>(
          enabled: false,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: emojis.map((emoji) {
              final hasReacted = widget.message.hasUserReacted(
                emoji,
                coordinator.localUsername,
              );
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).pop();
                  coordinator.toggleMessageReaction(
                    widget.message.conversationId,
                    widget.message.id,
                    emoji,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 3,
                  ),
                  decoration: hasReacted
                      ? BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: Text(emoji, style: const TextStyle(fontSize: 18)),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _showMessageMenu(
    BuildContext context,
    Offset position,
    MessengerCoordinator coordinator,
    LanguageProvider lang,
  ) async {
    const emojis = ['👍', '❤️', '😂', '😮', '😢', '👏', '🔥', '🎉'];
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
          enabled: false,
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: emojis.map((emoji) {
              final hasReacted = widget.message.hasUserReacted(
                emoji,
                coordinator.localUsername,
              );
              return InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.of(context).pop();
                  coordinator.toggleMessageReaction(
                    widget.message.conversationId,
                    widget.message.id,
                    emoji,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: hasReacted
                      ? BoxDecoration(
                          color: Theme.of(
                            context,
                          ).primaryColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: Text(emoji, style: const TextStyle(fontSize: 16)),
                ),
              );
            }).toList(),
          ),
        ),
        const PopupMenuDivider(height: 1),
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
        if (coordinator.canRetryMessage(widget.message))
          PopupMenuItem<String>(
            value: 'retry',
            height: 36,
            child: Row(
              children: [
                const Icon(
                  Icons.refresh_rounded,
                  size: 15,
                  color: Color(0xFFF87171),
                ),
                const SizedBox(width: 8),
                Text(
                  lang.tr('retrySend'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: Color(0xFFF87171),
                    fontWeight: FontWeight.w600,
                  ),
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

    if (value == 'retry') {
      coordinator.retrySendMessage(widget.message);
    } else if (value == 'reply') {
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
              icon: Icons.add_reaction_outlined,
              tooltip: lang.tr('addReaction'),
              color: theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87,
              onTap: () => _showQuickReactionPicker(context, coordinator),
            ),
            const SizedBox(width: 2),
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
    if (message.senderId == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 28),
        child: Center(
          child: Text(
            message.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              fontWeight: FontWeight.w500,
              color: theme.isDark ? Colors.white54 : Colors.black54,
            ),
          ),
        ),
      );
    }
    final isMine = message.isMine;

    final isGroupOrBroadcast =
        !isMine &&
        (message.recipientId == '__ALL_USERS__' ||
            coordinator.groupsMap.containsKey(message.recipientId) ||
            (coordinator.selectedPeer?.isGroup ?? false));

    final senderPeer = isGroupOrBroadcast
        ? coordinator.peers.cast<PeerModel?>().firstWhere(
            (p) =>
                p != null &&
                (p.id == message.senderId ||
                    p.ip == message.senderId ||
                    p.name == message.senderName),
            orElse: () => PeerModel(
              id: message.senderId,
              name: message.senderName,
              ip: '',
            ),
          )
        : null;

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

    final showHoverBar = !message.isRevoked;

    // 2. Full-bleed Photo Bubble (Telegram/Discord style)
    if (isPureImage) {
      Widget photoContent = Column(
        crossAxisAlignment: isMine
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGroupOrBroadcast) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                message.senderName,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: PeerModel.generateColor(
                    message.senderId.isNotEmpty
                        ? message.senderId
                        : message.senderName,
                  ),
                ),
              ),
            ),
          ],
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
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
                      color: (theme.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: theme.isDark ? 0.12 : 0.08),
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
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                    color: Colors.black12,
                                    child: const Center(
                                      child: Icon(
                                        Icons.broken_image_rounded,
                                        size: 40,
                                      ),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        attachment.fileName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
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
                                      if (coordinator.canRetryMessage(message))
                                        InkWell(
                                          onTap: () => coordinator
                                              .retrySendMessage(message),
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                          child: Tooltip(
                                            message: lang.tr(
                                              'messageFailedTooltip',
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.error_outline_rounded,
                                                  size: 13,
                                                  color: Color(0xFFF87171),
                                                ),
                                                const SizedBox(width: 2),
                                                Text(
                                                  lang.tr('retrySend'),
                                                  style: const TextStyle(
                                                    fontSize: 9.5,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFFF87171),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      else ...[
                                        Icon(
                                          message.status == MessageStatus.read
                                              ? Icons.done_all_rounded
                                              : (message.status ==
                                                        MessageStatus.delivered
                                                    ? Icons.done_all_rounded
                                                    : (message.status ==
                                                              MessageStatus.sent
                                                          ? Icons.done_rounded
                                                          : Icons
                                                                .schedule_rounded)),
                                          size: 13,
                                          color:
                                              message.status ==
                                                  MessageStatus.read
                                              ? const Color(0xFF67E8F9)
                                              : Colors.white70,
                                        ),
                                        if (message.status ==
                                            MessageStatus.read) ...[
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
                        canCopy: false,
                        canRegenerate: false,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (message.reactions.isNotEmpty) ...[
            const SizedBox(height: 3),
            _MessageReactionsBar(
              reactions: message.reactions,
              localUsername: coordinator.localUsername,
              isMine: isMine,
              onToggleReaction: (emoji) => coordinator.toggleMessageReaction(
                message.conversationId,
                message.id,
                emoji,
              ),
              onAddReaction: () =>
                  _showQuickReactionPicker(context, coordinator),
            ),
          ],
        ],
      );

      if (isGroupOrBroadcast && senderPeer != null) {
        photoContent = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: AppAvatar(peer: senderPeer, size: 28, showStatus: false),
            ),
            Flexible(child: photoContent),
          ],
        );
      }

      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: photoContent,
        ),
      );
    }

    // 3. Standard Text / Mixed Message Bubble (Responsive width & Markdown)
    final isAi = message.aiModelTag != null;
    final canCopy = message.text.isNotEmpty;
    final canRegenerate = isAi && !isMine && !message.isStreaming;

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

        Widget bubbleColumn = Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
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
                        if (isGroupOrBroadcast) ...[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              message.senderName,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: PeerModel.generateColor(
                                  message.senderId.isNotEmpty
                                      ? message.senderId
                                      : message.senderName,
                                ),
                              ),
                            ),
                          ),
                        ],
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
                              if (coordinator.canRetryMessage(message))
                                InkWell(
                                  onTap: () =>
                                      coordinator.retrySendMessage(message),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Tooltip(
                                    message: lang.tr('messageFailedTooltip'),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.error_outline_rounded,
                                          size: 12.5,
                                          color: Color(0xFFF87171),
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          lang.tr('retrySend'),
                                          style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFF87171),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else ...[
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
            if (message.reactions.isNotEmpty) ...[
              const SizedBox(height: 2),
              _MessageReactionsBar(
                reactions: message.reactions,
                localUsername: coordinator.localUsername,
                isMine: isMine,
                onToggleReaction: (emoji) => coordinator.toggleMessageReaction(
                  message.conversationId,
                  message.id,
                  emoji,
                ),
                onAddReaction: () =>
                    _showQuickReactionPicker(context, coordinator),
              ),
            ],
          ],
        );

        if (isGroupOrBroadcast && senderPeer != null) {
          bubbleColumn = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, right: 8),
                child: AppAvatar(peer: senderPeer, size: 28, showStatus: false),
              ),
              Flexible(child: bubbleColumn),
            ],
          );
        }

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: bubbleColumn,
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

class _BuzzActionButton extends StatefulWidget {
  final VoidCallback onPressed;
  final double size;
  final String tooltip;
  final Color? defaultColor;

  const _BuzzActionButton({
    required this.onPressed,
    this.size = 32,
    required this.tooltip,
    this.defaultColor,
  });

  @override
  State<_BuzzActionButton> createState() => _BuzzActionButtonState();
}

class _BuzzActionButtonState extends State<_BuzzActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _shakeAnimation;
  bool _isBuzzing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.22), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.22, end: 0.22), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.22, end: -0.18), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.18, end: 0.18), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.18, end: -0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _trigger() {
    if (_isBuzzing) return;
    setState(() => _isBuzzing = true);
    _controller.forward(from: 0.0).then((_) {
      if (mounted) setState(() => _isBuzzing = false);
    });
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final activeColor = theme.colors.accentAmber;
    final color = _isBuzzing
        ? activeColor
        : (widget.defaultColor ??
              (theme.isDark ? Colors.white70 : Colors.black87));

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.rotate(
          angle: _shakeAnimation.value,
          child: Transform.scale(
            scale: _isBuzzing ? 1.18 : 1.0,
            child: Container(
              decoration: _isBuzzing
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.65),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    )
                  : null,
              child: GlassIconButton(
                icon: Icons.notifications_active_rounded,
                tooltip: widget.tooltip,
                color: color,
                size: widget.size,
                onPressed: _trigger,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MessageReactionsBar extends StatelessWidget {
  final Map<String, List<String>> reactions;
  final String localUsername;
  final bool isMine;
  final ValueChanged<String> onToggleReaction;
  final VoidCallback onAddReaction;

  const _MessageReactionsBar({
    required this.reactions,
    required this.localUsername,
    required this.isMine,
    required this.onToggleReaction,
    required this.onAddReaction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Wrap(
        alignment: isMine ? WrapAlignment.end : WrapAlignment.start,
        spacing: 4,
        runSpacing: 4,
        children: [
          ...reactions.entries.where((e) => e.value.isNotEmpty).map((entry) {
            final emoji = entry.key;
            final users = entry.value;
            final count = users.length;
            final hasReacted = users.contains(localUsername);

            return Tooltip(
              message: users.join(', '),
              waitDuration: const Duration(milliseconds: 300),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => onToggleReaction(emoji),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    color: hasReacted
                        ? theme.colors.accentBlue.withValues(
                            alpha: isDark ? 0.3 : 0.18,
                          )
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : Colors.black.withValues(alpha: 0.04)),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: hasReacted
                          ? theme.colors.accentBlue.withValues(alpha: 0.7)
                          : (isDark ? Colors.white12 : Colors.black12),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emoji, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: hasReacted
                              ? theme.colors.accentBlue
                              : (isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onAddReaction,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                  width: 0.8,
                ),
              ),
              child: Icon(
                Icons.add_rounded,
                size: 13,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
        ],
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

    // 2. Non-Image Document / File Card with Preview & Execution
    return InkWell(
      onTap: () {
        if (fileExists) {
          showGlassFilePreview(
            context: context,
            filePath: file.path,
            fileName: attachment.fileName,
            onOpenFolder: () => _openAttachmentFolder(file.path),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${lang.tr('sharedFiles')}: ${lang.tr('fileNotFound')}',
              ),
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
  final bool isCompact;
  final List<File> stagedAttachments;
  final ValueChanged<int>? onRemoveStagedAttachment;
  final VoidCallback? onClearStagedAttachments;

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
    this.isCompact = false,
    this.stagedAttachments = const [],
    this.onRemoveStagedAttachment,
    this.onClearStagedAttachments,
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

    final hMargin = widget.isCompact ? 8.0 : 14.0;
    final bMargin = widget.isCompact ? 8.0 : 12.0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hMargin),
          child: PinyinCandidateBar(textController: widget.controller),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: hMargin),
          child: GroupMentionPicker(
            controller: widget.controller,
            focusNode: widget.focusNode,
            onChanged: widget.onChanged,
          ),
        ),
        Container(
          margin: EdgeInsets.fromLTRB(hMargin, 0, hMargin, bMargin),
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
                color: Colors.black.withValues(
                  alpha: theme.isDark ? 0.25 : 0.06,
                ),
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
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
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
                                                alpha: theme.isDark
                                                    ? 0.08
                                                    : 0.06,
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
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                hoverColor:
                                                    (theme.isDark
                                                            ? Colors.white
                                                            : Colors.black)
                                                        .withValues(
                                                          alpha: 0.08,
                                                        ),
                                                onTap: () =>
                                                    _insertEmoji(emoji),
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
                            (theme.isDark
                                    ? const Color(0xFF0F172A)
                                    : Colors.black)
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

                  // 1.8 Staged Attachments Tray (Telegram / Zalo style)
                  if (widget.stagedAttachments.isNotEmpty)
                    StagedAttachmentsBar(
                      files: widget.stagedAttachments,
                      onRemove: widget.onRemoveStagedAttachment,
                      onClear: widget.onClearStagedAttachments,
                    ),

                  // 2. Chat Input Area (Spans 100% full width of card, no white flanks)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
                    child: Focus(
                      onKeyEvent: (node, event) {
                        final ime = ImeService.of(context, listen: false);
                        if (ime.handlePinyinKeyEvent(
                          event,
                          widget.controller,
                        )) {
                          return KeyEventResult.handled;
                        }
                        if (event is KeyDownEvent) {
                          final isCtrl =
                              HardwareKeyboard.instance.isControlPressed;
                          final isShift =
                              HardwareKeyboard.instance.isShiftPressed;
                          if (isCtrl && isShift) {
                            ime.toggleOnOff();
                            return KeyEventResult.handled;
                          }
                          if (event.logicalKey == LogicalKeyboardKey.escape &&
                              widget.replyingTo != null) {
                            widget.onCancelReply?.call();
                            return KeyEventResult.handled;
                          }
                          final isEnter =
                              event.logicalKey == LogicalKeyboardKey.enter ||
                              event.logicalKey ==
                                  LogicalKeyboardKey.numpadEnter;
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
                          } else if (event.logicalKey ==
                                  LogicalKeyboardKey.keyV &&
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
                            inputFormatters: [
                              ImeService.of(
                                context,
                                listen: false,
                              ).inputFormatter,
                            ],
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
                          color: _showEmojiPicker
                              ? theme.colors.accentBlue
                              : null,
                          onPressed: () {
                            setState(() {
                              _showEmojiPicker = !_showEmojiPicker;
                            });
                          },
                        ),
                        if (!isAiChat) ...[
                          const SizedBox(width: 2),
                          _BuzzActionButton(
                            onPressed: widget.onBuzz,
                            tooltip: lang.tr('nudge'),
                            size: 32,
                            defaultColor: theme.isDark
                                ? Colors.white70
                                : Colors.black87,
                          ),
                        ],
                        const SizedBox(width: 4),
                        const ImeToggleButton(),
                        const Spacer(),
                        if (isAiBusy) ...[
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.redAccent.shade400,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(36, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              elevation: 0,
                            ),
                            onPressed: () => coordinator.stopAiGeneration(),
                            icon: const Icon(
                              Icons.stop_circle_rounded,
                              size: 14,
                            ),
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
        ),
      ],
    );
  }
}

class StagedAttachmentsBar extends StatelessWidget {
  final List<File> files;
  final ValueChanged<int>? onRemove;
  final VoidCallback? onClear;

  const StagedAttachmentsBar({
    super.key,
    required this.files,
    this.onRemove,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF0F172A) : Colors.black).withValues(
          alpha: isDark ? 0.60 : 0.04,
        ),
        border: Border(
          bottom: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.08,
            ),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.attachment_rounded,
                size: 14,
                color: theme.colors.accentBlue,
              ),
              const SizedBox(width: 5),
              Text(
                lang.tr('stagedFilesCount', [files.length]),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.accentBlue,
                ),
              ),
              const Spacer(),
              if (files.length > 1)
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      lang.tr('clearAllAttachments'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colors.accentRose,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: files.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final file = files[index];
                final fileName = file.path.split(Platform.pathSeparator).last;
                final isImg = MessengerCoordinator.isImageFile(file.path);
                int fileSize = 0;
                try {
                  fileSize = file.lengthSync();
                } catch (_) {}

                final sizeStr = _formatSize(fileSize);

                if (isImg) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InkWell(
                        onTap: () => showGlassFilePreview(
                          context: context,
                          filePath: file.path,
                          fileName: fileName,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.12),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.35 : 0.08,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Center(
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          size: 24,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                        ),
                                      ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                      horizontal: 4,
                                    ),
                                    color: Colors.black54,
                                    child: Text(
                                      sizeStr,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -5,
                        right: -5,
                        child: InkWell(
                          onTap: () => onRemove?.call(index),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.black12,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InkWell(
                      onTap: () => showGlassFilePreview(
                        context: context,
                        filePath: file.path,
                        fileName: fileName,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 170,
                        height: 72,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              (isDark ? const Color(0xFF1E293B) : Colors.white)
                                  .withValues(alpha: isDark ? 0.75 : 0.85),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.12),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.30 : 0.06,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: theme.colors.accentBlue.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getFileIcon(file.path),
                                size: 20,
                                color: theme.colors.accentBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    sizeStr,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      top: -5,
                      right: -5,
                      child: InkWell(
                        onTap: () => onRemove?.call(index),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF334155)
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.white24 : Colors.black12,
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static IconData _getFileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'md':
        return Icons.description_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'ogg':
        return Icons.audio_file_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.video_file_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'exe':
      case 'msi':
      case 'bat':
      case 'cmd':
        return Icons.terminal_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
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

class _ChatScrollControls extends StatelessWidget {
  final bool showScrollToTop;
  final bool showScrollToBottom;
  final int unreadBelowCount;
  final VoidCallback onScrollToTop;
  final VoidCallback onScrollToBottom;

  const _ChatScrollControls({
    required this.showScrollToTop,
    required this.showScrollToBottom,
    required this.unreadBelowCount,
    required this.onScrollToTop,
    required this.onScrollToBottom,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Badge số tin nhắn mới cạnh nút cuộn xuống dưới cùng
        if (showScrollToBottom && unreadBelowCount > 0) ...[
          _NewMessagesBadgeChip(
            count: unreadBelowCount,
            onTap: onScrollToBottom,
          ),
          const SizedBox(width: 8),
        ],

        // Capsule các nút điều hướng cuộn Bento Glass
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: theme.isDark ? 0.35 : 0.08,
                ),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(22),
            blur: 16,
            opacity: theme.isDark ? 0.65 : 0.78,
            padding: const EdgeInsets.all(3),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: theme.isDark ? 0.14 : 0.08,
              ),
              width: 1,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showScrollToTop)
                  _ScrollActionButton(
                    icon: Icons.keyboard_arrow_up_rounded,
                    tooltip: lang.tr('scrollToTop'),
                    onPressed: onScrollToTop,
                  ),
                if (showScrollToTop && showScrollToBottom)
                  Container(
                    width: 20,
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: (theme.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.10),
                  ),
                if (showScrollToBottom)
                  _ScrollActionButton(
                    icon: Icons.keyboard_arrow_down_rounded,
                    tooltip: lang.tr('scrollToBottom'),
                    onPressed: onScrollToBottom,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScrollActionButton extends StatefulWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _ScrollActionButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  State<_ScrollActionButton> createState() => _ScrollActionButtonState();
}

class _ScrollActionButtonState extends State<_ScrollActionButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;

    final hoverBg = (isDark ? Colors.white : Colors.black).withValues(
      alpha: 0.10,
    );
    final iconColor = _isHovered
        ? theme.colors.accentColor
        : (isDark
              ? Colors.white.withValues(alpha: 0.90)
              : theme.colors.textPrimary);

    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: _isHovered ? hoverBg : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            onTap: widget.onPressed,
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              width: 34,
              height: 34,
              child: Center(
                child: Icon(widget.icon, size: 22, color: iconColor),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewMessagesBadgeChip extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const _NewMessagesBadgeChip({required this.count, required this.onTap});

  @override
  State<_NewMessagesBadgeChip> createState() => _NewMessagesBadgeChipState();
}

class _NewMessagesBadgeChipState extends State<_NewMessagesBadgeChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    final text = lang
        .tr('newMessagesCount')
        .replaceFirst('%d', '${widget.count}');
    final baseColor = theme.colors.accentRose;

    return Tooltip(
      message: lang.tr('scrollToBottom'),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? baseColor.withValues(alpha: _isHovered ? 0.35 : 0.22)
                  : baseColor.withValues(alpha: _isHovered ? 0.22 : 0.14),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: baseColor.withValues(alpha: _isHovered ? 0.65 : 0.40),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withValues(alpha: isDark ? 0.28 : 0.16),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: baseColor,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: baseColor.withValues(alpha: 0.6),
                        blurRadius: 4,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : baseColor,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dải phân cách tin nhắn chưa đọc phong cách Telegram kết hợp Bento Glassmorphism
class _UnreadSeparatorBanner extends StatelessWidget {
  const _UnreadSeparatorBanner();

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;
    final accent = theme.colors.accentRose;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: 0.0),
                    accent.withValues(alpha: isDark ? 0.35 : 0.25),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: GlassSurface(
              borderRadius: BorderRadius.circular(14),
              blur: 12,
              opacity: isDark ? 0.60 : 0.75,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              border: Border.all(
                color: accent.withValues(alpha: isDark ? 0.40 : 0.28),
                width: 1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: 0.7),
                          blurRadius: 5,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    lang.tr('unreadMessagesBanner'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : accent,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    accent.withValues(alpha: isDark ? 0.35 : 0.25),
                    accent.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
