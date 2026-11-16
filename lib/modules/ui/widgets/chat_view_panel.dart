import 'dart:async';
import 'dart:io';
import 'package:window_manager/window_manager.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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
import '../../services/conversation_scroll_store.dart';
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
import '../../services/message_entity_detector.dart';
import '../../services/quick_action_helper.dart';
import '../../services/image_clipboard_helper.dart';
import '../../services/sticker_service.dart';
import 'sprite_sticker_widget.dart';
import 'sticker_picker_popover.dart';
import '../../services/app_power_manager.dart';
import '../../services/folder_archive_helper.dart';
import 'forward_message_dialog.dart';

part 'chat_view/chat_header_part.dart';
part 'chat_view/chat_pinned_and_quote_part.dart';
part 'chat_view/chat_message_bubble_part.dart';
part 'chat_view/chat_message_accessories_part.dart';
part 'chat_view/chat_input_dock_part.dart';
part 'chat_view/staged_attachments_bar_part.dart';
part 'chat_view/chat_scroll_and_search_part.dart';

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

class _ChatViewPanelState extends State<ChatViewPanel> with WindowListener {
  final _readKeys = <MessageModel, GlobalKey>{};
  final _visibleSince = <MessageModel, DateTime>{};
  Timer? _readTimer;
  bool _checkingRead = false;
  int _readEpoch = 0;

  void _resetReadExposure() {
    _readEpoch++;
    _visibleSince.clear();
  }

  @override
  void onWindowBlur() => _resetReadExposure();
  @override
  void onWindowMinimize() => _resetReadExposure();

  Future<void> _checkVisibleRead() async {
    if (!mounted ||
        _checkingRead ||
        !AppPowerManager.instance.shouldAnimateIndicators) {
      return;
    }
    _readKeys.removeWhere((_, key) => key.currentContext == null);
    _visibleSince.removeWhere((m, _) => !_readKeys.containsKey(m));
    if (_readKeys.isEmpty) return;
    _checkingRead = true;
    final epoch = _readEpoch;
    try {
      final active =
          await windowManager.isFocused() &&
          await windowManager.isVisible() &&
          !await windowManager.isMinimized();
      if (!mounted) return;
      if (!active ||
          epoch != _readEpoch ||
          ModalRoute.of(context)?.isCurrent != true ||
          !_scrollController.hasClients ||
          _scrollController.position.isScrollingNotifier.value) {
        _visibleSince.clear();
        return;
      }
      final coordinator = context.read<MessengerCoordinator>();
      final peer = coordinator.selectedPeer;
      if (peer == null || peer.id != _lastPeerId) return;
      final now = DateTime.now();
      final read = <MessageModel>{};
      for (final entry in _readKeys.entries) {
        final box = entry.value.currentContext?.findRenderObject();
        var visible = false;
        if (box is RenderBox && box.attached && box.hasSize) {
          final viewport = RenderAbstractViewport.maybeOf(box);
          if (viewport != null &&
              viewport is RenderBox &&
              (viewport as RenderBox).hasSize) {
            final viewportBox = viewport as RenderBox;
            final bounds = box.localToGlobal(Offset.zero) & box.size;
            final clip =
                viewportBox.localToGlobal(Offset.zero) & viewportBox.size;
            final intersection = bounds.intersect(clip);
            if (!intersection.isEmpty &&
                intersection.height >=
                    math.min(bounds.height, clip.height) * 0.5) {
              final hits = HitTestResult();
              WidgetsBinding.instance.hitTestInView(
                hits,
                intersection.center,
                View.of(context).viewId,
              );
              visible = hits.path.any((hit) => identical(hit.target, box));
            }
          }
        }
        if (!visible) {
          _visibleSince.remove(entry.key);
        } else {
          final since = _visibleSince.putIfAbsent(entry.key, () => now);
          if (now.difference(since) >= const Duration(milliseconds: 500)) {
            read.add(entry.key);
          }
        }
      }
      if (read.isNotEmpty) coordinator.markMessagesAsRead(peer.id, read);
    } catch (_) {
      _visibleSince
          .clear(); // Missing/failed native focus checks must not imply read.
    } finally {
      _checkingRead = false;
    }
  }

  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late final FocusNode _inputFocusNode;
  Timer? _typingDebounceTimer;
  MessageModel? _replyingToMessage;
  String? _highlightedMessageId;
  Timer? _highlightTimer;
  int _currentPinnedIndex = 0;
  int _prevMessageCount = 0;
  int _prevReactionRevision = 0;
  bool _prevPeerTyping = false;
  String? _lastPeerId;
  String? _lastScrollKey;
  late final ConversationScrollStore _scrollStore;
  Timer? _scrollSaveTimer;
  final _savedScrollPositions =
      <String, ({double offset, bool atBottom, String? separator})>{};

  // In-chat search state (F1)
  bool _isSearchBarVisible = false;
  String _inChatSearchQuery = '';
  int _inChatSearchMatchIndex = 0;
  int _lastHandledChatSearchFocusId = -1;
  final TextEditingController _inChatSearchController = TextEditingController();
  final FocusNode _inChatSearchFocusNode = FocusNode();

  void _saveConversationScroll() {
    final id = _lastPeerId;
    if (id == null ||
        !_scrollController.hasClients ||
        _isProgrammaticScroll ||
        _pendingJumpToBottom ||
        _pendingJumpToUnread) {
      return;
    }
    final position = _scrollController.position;
    _savedScrollPositions[id] = (
      offset: position.pixels,
      atBottom: position.maxScrollExtent - position.pixels <= 50,
      separator: _activeUnreadSeparatorMessageId,
    );
    final key = _lastScrollKey;
    if (key != null) _scrollStore.save(key, _savedScrollPositions[id]!);
  }

  @override
  void onWindowClose() => _saveConversationScroll();

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

  // Manual scroll detection & focus handling
  int _lastHandledFocusRequestId = -1;
  bool _isManualScrolling = false;
  bool _isProgrammaticScroll = false;
  Timer? _manualScrollHideTimer;

  Timer? _focusTimer;

  void _requestInputFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_inputFocusNode.canRequestFocus) {
        _inputFocusNode.requestFocus();
      }
    });
    _focusTimer?.cancel();
    _focusTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted &&
          _inputFocusNode.canRequestFocus &&
          !_inputFocusNode.hasFocus) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  void _onManualScrollTriggered() {
    if (!mounted || _isProgrammaticScroll) return;
    _manualScrollHideTimer?.cancel();
    if (!_isManualScrolling) {
      _isManualScrolling = true;
    }
    _updateScrollState();

    _manualScrollHideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        _isManualScrolling = false;
        _updateScrollState();
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _scrollStore = ConversationScrollStore(
      File(
        '${AppPreferences().preferencesFile.parent.path}${Platform.pathSeparator}conversation_scroll.json',
      ),
    );
    _inputFocusNode = FocusNode();
    _scrollController.addListener(_onScroll);
    windowManager.addListener(this);
    AppPowerManager.instance.indicatorsAnimationNotifier.addListener(
      _syncReadPolling,
    );
    _syncReadPolling();
    _requestInputFocus();
  }

  void _syncReadPolling() {
    _resetReadExposure();
    _readTimer?.cancel();
    _readTimer = null;
    if (AppPowerManager.instance.shouldAnimateIndicators) {
      _readTimer = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _checkVisibleRead(),
      );
    }
  }

  @override
  void dispose() {
    _saveConversationScroll();
    _scrollSaveTimer?.cancel();
    _readTimer?.cancel();
    AppPowerManager.instance.indicatorsAnimationNotifier.removeListener(
      _syncReadPolling,
    );
    windowManager.removeListener(this);
    _focusTimer?.cancel();
    _manualScrollHideTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _typingDebounceTimer?.cancel();
    _highlightTimer?.cancel();
    _inChatSearchFocusNode.dispose();
    _inChatSearchController.dispose();
    _inputFocusNode.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<MessageModel> _computeSearchMatches(List<MessageModel> messages) {
    final q = _inChatSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return const <MessageModel>[];
    return [
      for (final msg in messages)
        if (!msg.isRevoked &&
            (msg.text.toLowerCase().contains(q) ||
                (msg.fileAttachment?.fileName.toLowerCase().contains(q) ??
                    false)))
          msg,
    ];
  }

  void _toggleInChatSearch() {
    setState(() {
      _isSearchBarVisible = !_isSearchBarVisible;
      if (!_isSearchBarVisible) {
        _inChatSearchQuery = '';
        _inChatSearchController.clear();
        _inChatSearchMatchIndex = 0;
        _highlightedMessageId = null;
      }
    });
    if (_isSearchBarVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inChatSearchFocusNode.canRequestFocus) {
          _inChatSearchFocusNode.requestFocus();
        }
      });
    } else {
      _requestInputFocus();
    }
  }

  void _closeInChatSearch() {
    if (!_isSearchBarVisible) return;
    setState(() {
      _isSearchBarVisible = false;
      _inChatSearchQuery = '';
      _inChatSearchController.clear();
      _inChatSearchMatchIndex = 0;
      _highlightedMessageId = null;
    });
    _requestInputFocus();
  }

  void _navigateSearchMatch(int delta, List<MessageModel> messages) {
    final matches = _computeSearchMatches(messages);
    if (matches.isEmpty) return;
    final nextIdx =
        (_inChatSearchMatchIndex + delta + matches.length) % matches.length;
    setState(() {
      _inChatSearchMatchIndex = nextIdx;
    });
    _scrollToMessage(matches[nextIdx].id, messages);
  }

  void _onScroll() {
    _resetReadExposure();
    _updateScrollState();
    _scrollSaveTimer?.cancel();
    _scrollSaveTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) _saveConversationScroll();
    });
  }

  void _updateScrollState() {
    if (!mounted || !_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final max = pos.maxScrollExtent;
    final current = pos.pixels;

    final hasScrollableContent = max > 50.0;
    final isAtTop = current <= 50.0;
    final isAtBottom = (max - current) <= 50.0;
    final isNearBottom = (max - current) <= 140.0;

    // Both buttons hide when sát đầu (isAtTop) or sát cuối (isAtBottom)!
    // They only appear when the user is scrolling manually in the middle of the chat history,
    // or if there is an unread badge below and not at bottom.
    final isMiddle = !isAtTop && !isAtBottom;

    final showScrollToTop =
        hasScrollableContent && _isManualScrolling && isMiddle;
    final showScrollToBottom =
        hasScrollableContent &&
        ((_isManualScrolling && isMiddle) ||
            (_unreadBelowCount > 0 && !isAtBottom));
    final newUnreadCount = isAtBottom ? 0 : _unreadBelowCount;

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
    _isProgrammaticScroll = true;
    _manualScrollHideTimer?.cancel();
    _isManualScrolling = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        _isProgrammaticScroll = false;
        return;
      }
      if (smooth) {
        _scrollController
            .animateTo(
              0.0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (mounted) {
                _isProgrammaticScroll = false;
                _updateScrollState();
              }
            });
      } else {
        _scrollController.jumpTo(0.0);
        _isProgrammaticScroll = false;
        _updateScrollState();
      }
    });
  }

  void _scrollToBottom({bool force = false, bool smooth = true}) {
    final conversationId = _lastPeerId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _lastPeerId != conversationId ||
          !_scrollController.hasClients) {
        return;
      }
      final pos = _scrollController.position;
      final isNearBottom = (pos.maxScrollExtent - pos.pixels) <= 140.0;
      if (!force && !isNearBottom) return;

      _isProgrammaticScroll = true;
      _manualScrollHideTimer?.cancel();
      _isManualScrolling = false;

      if (smooth) {
        _scrollController
            .animateTo(
              pos.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
            )
            .then((_) {
              if (mounted &&
                  _lastPeerId == conversationId &&
                  _scrollController.hasClients) {
                final p = _scrollController.position;
                if ((p.maxScrollExtent - p.pixels) > 5.0) {
                  _scrollController.jumpTo(p.maxScrollExtent);
                }
                _isProgrammaticScroll = false;
                _updateScrollState();
              }
            });
      } else {
        _performJumpToBottom();
      }
    });
  }

  void _performJumpToBottom({int remainingAttempts = 6}) {
    final conversationId = _lastPeerId;
    if (!mounted || !_scrollController.hasClients) {
      _isProgrammaticScroll = false;
      return;
    }
    _isProgrammaticScroll = true;
    _manualScrollHideTimer?.cancel();
    _isManualScrolling = false;

    final pos = _scrollController.position;
    final diff = pos.maxScrollExtent - pos.pixels;
    if (diff.abs() > 2.0 && remainingAttempts > 0) {
      _scrollController.jumpTo(pos.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _lastPeerId != conversationId) return;
        _performJumpToBottom(remainingAttempts: remainingAttempts - 1);
      });
    } else {
      if (diff.abs() > 2.0) {
        _scrollController.jumpTo(pos.maxScrollExtent);
      }
      _isProgrammaticScroll = false;
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

    _isProgrammaticScroll = true;
    _scrollController
        .animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
        )
        .then((_) {
          if (mounted) {
            _isProgrammaticScroll = false;
            _updateScrollState();
          }
        });

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
    final activePeerId = coordinator.selectedPeer?.id;
    if (activePeerId != null) {
      coordinator.setDraft(activePeerId, text);
    }
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
    final lang = context.read<LanguageProvider>();
    final peerId = coordinator.selectedPeer?.id;
    setState(() => _draggingFiles = false);
    final files = <File>[];
    for (final item in details.files) {
      final file = File(item.path);
      if (await file.exists()) {
        files.add(file);
      } else if (FolderArchiveHelper.isDirectory(item.path)) {
        final rawName = item.path
            .replaceAll(RegExp(r'[\\/]+$'), '')
            .split(RegExp(r'[\\/]'))
            .last;
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lang.tr('zippingFolder', [rawName])),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
        final zipPath = await FolderArchiveHelper.zipDirectory(item.path);
        if (zipPath != null) {
          final zippedFile = File(zipPath);
          if (await zippedFile.exists()) {
            files.add(zippedFile);
            if (mounted) {
              final zipName = zippedFile.path.split(RegExp(r'[\\/]')).last;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(lang.tr('folderZippedReady', [zipName])),
                  behavior: SnackBarBehavior.floating,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(lang.tr('folderZipFailed')),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    }
    if (!mounted || peerId == null || coordinator.selectedPeer?.id != peerId) {
      return;
    }
    if (files.isNotEmpty) {
      setState(() => _stagedAttachments.addAll(files));
    }
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
    if (coordinator.selectedPeer != null) {
      coordinator.setDraft(coordinator.selectedPeer!.id, '');
    }
    final replying = _replyingToMessage;

    final filesToSend = List<File>.from(_stagedAttachments);

    setState(() {
      _stagedAttachments.clear();
      _replyingToMessage = null;
      _unreadBelowCount = 0;
      _activeUnreadSeparatorMessageId = null;
      _isNearBottom = true;
    });

    if (filesToSend.isNotEmpty) {
      unawaited(_sendAttachments(coordinator, filesToSend, text, replying));
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

  Future<void> _sendAttachments(
    MessengerCoordinator coordinator,
    List<File> files,
    String text,
    MessageModel? replying,
  ) async {
    try {
      await coordinator.sendFiles(files, text: text, replyTo: replying);
    } catch (error) {
      if (!mounted) return;
      final lang = context.read<LanguageProvider>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${lang.tr('transferFailed')}: $error')),
      );
    }
  }

  void _handleSendSticker(
    StickerItem sticker,
    MessengerCoordinator coordinator,
  ) {
    _typingDebounceTimer?.cancel();
    coordinator.sendTypingStatus(false);
    final replying = _replyingToMessage;
    setState(() {
      _replyingToMessage = null;
      _unreadBelowCount = 0;
      _activeUnreadSeparatorMessageId = null;
      _isNearBottom = true;
    });

    coordinator.sendMessage(sticker.token, replyTo: replying);
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
      _saveConversationScroll();
      _lastPeerId = null;
      _resetReadExposure();
      _readKeys.clear();
      return const _EmptyChatView();
    }

    if (coordinator.chatFocusRequestId != _lastHandledFocusRequestId) {
      _lastHandledFocusRequestId = coordinator.chatFocusRequestId;
      _requestInputFocus();
    }

    if (coordinator.chatSearchFocusRequestId != _lastHandledChatSearchFocusId) {
      _lastHandledChatSearchFocusId = coordinator.chatSearchFocusRequestId;
      if (!_isSearchBarVisible) {
        _isSearchBarVisible = true;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _inChatSearchFocusNode.canRequestFocus) {
          _inChatSearchFocusNode.requestFocus();
        }
      });
    }

    final messages = coordinator.currentMessages;
    if (_lastPeerId != peer.id) {
      _resetReadExposure();
      _readKeys.clear();
    }
    _readKeys.removeWhere(
      (m, _) => !messages.contains(m) || m.status == MessageStatus.read,
    );
    _visibleSince.removeWhere((m, _) => !_readKeys.containsKey(m));
    final isPeerTyping =
        (!peer.isAllUsers &&
        ((!peer.isGroup && coordinator.isPeerTyping(peer.id)) ||
            (peer.isGroup && coordinator.isGroupTyping(peer.id))));
    final totalItems = messages.length + (isPeerTyping ? 1 : 0);

    // Reset replying state & determine scroll target if active peer changed
    final isPeerChanged = _lastPeerId != peer.id;
    // O(1) reaction change check via coordinator.reactionRevision
    final currentReactionRev = coordinator.reactionRevision;
    final reactionsChanged = currentReactionRev != _prevReactionRevision;
    _prevReactionRevision = currentReactionRev;
    final wasAtBottom =
        _scrollController.hasClients &&
        _scrollController.position.extentAfter <= 50;
    if (isPeerChanged) {
      _saveConversationScroll();
      _lastPeerId = peer.id;
      _lastScrollKey = peer.canonicalIdentity;
      _isManualScrolling = false;
      _manualScrollHideTimer?.cancel();
      _requestInputFocus();
      _stagedAttachments.clear();
      _replyingToMessage = null;
      _currentPinnedIndex = 0;
      _prevMessageCount = messages.length;
      _prevPeerTyping = isPeerTyping;
      _isSearchBarVisible = false;
      _inChatSearchQuery = '';
      _inChatSearchController.clear();
      _inChatSearchMatchIndex = 0;

      // Restore per-peer draft (F2)
      final restoredDraft = coordinator.getDraft(peer.id);
      if (_inputController.text != restoredDraft) {
        _inputController.value = TextEditingValue(
          text: restoredDraft,
          selection: TextSelection.collapsed(offset: restoredDraft.length),
        );
      }

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

      final saved =
          _savedScrollPositions[peer.id] ?? _scrollStore.read(_lastScrollKey!);
      if (saved != null) {
        _pendingJumpToUnread = false;
        _pendingJumpToBottom = saved.atBottom;
        _isNearBottom = saved.atBottom;
        _activeUnreadSeparatorMessageId = saved.separator;
        _unreadBelowCount = saved.atBottom
            ? 0
            : coordinator.countUnreadMessages(peer.id);
        if (!saved.atBottom) {
          _isProgrammaticScroll = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted ||
                _lastPeerId != peer.id ||
                !_scrollController.hasClients) {
              return;
            }
            _scrollController.jumpTo(
              saved.offset.clamp(
                0.0,
                _scrollController.position.maxScrollExtent,
              ),
            );
            _isProgrammaticScroll = false;
            _updateScrollState();
          });
        }
      }
    }

    if (_pendingJumpToBottom) {
      _pendingJumpToBottom = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _lastPeerId != peer.id) return;
        _performJumpToBottom();
      });
    } else if (_pendingJumpToUnread &&
        _activeUnreadSeparatorMessageId != null) {
      _pendingJumpToUnread = false;
      _isProgrammaticScroll = true;
      _isManualScrolling = false;
      final targetId = _activeUnreadSeparatorMessageId!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            _lastPeerId != peer.id ||
            !_scrollController.hasClients) {
          _isProgrammaticScroll = false;
          return;
        }
        final index = messages.indexWhere((m) => m.id == targetId);
        if (index == -1) {
          _isProgrammaticScroll = false;
          return;
        }
        final total = messages.length;
        if (total == 0) {
          _isProgrammaticScroll = false;
          return;
        }

        // Frame 1: Approximate jump to target area to materialize widgets in ListView viewport
        final targetFraction = (index / total).clamp(0.0, 1.0);
        final targetOffset =
            targetFraction * _scrollController.position.maxScrollExtent;
        _scrollController.jumpTo(targetOffset);

        // Frame 2: Ensure pixel-perfect visible alignment with unread separator at ~8% from top
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _lastPeerId != peer.id) {
            _isProgrammaticScroll = false;
            return;
          }
          final ctx = _unreadSeparatorKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              alignment: 0.08,
              duration: const Duration(milliseconds: 80),
              curve: Curves.easeOutQuad,
            ).then((_) {
              if (mounted) {
                _isProgrammaticScroll = false;
                _updateScrollState();
              }
            });
          } else {
            _isProgrammaticScroll = false;
            _updateScrollState();
          }
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
    if (!isPeerChanged && reactionsChanged && wasAtBottom) {
      _scrollToBottom(force: true, smooth: true);
    }

    final pinnedMessages = coordinator.getPinnedMessages(peer.id);
    final searchMatches = _isSearchBarVisible
        ? _computeSearchMatches(messages)
        : const <MessageModel>[];
    final safeSearchIndex = searchMatches.isEmpty
        ? 0
        : _inChatSearchMatchIndex.clamp(0, searchMatches.length - 1);

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
                  isSearchOpen: _isSearchBarVisible,
                  onToggleSearch: _toggleInChatSearch,
                ),

                // In-Chat Message Search Bar (F1)
                if (_isSearchBarVisible)
                  _InChatSearchBar(
                    controller: _inChatSearchController,
                    focusNode: _inChatSearchFocusNode,
                    query: _inChatSearchQuery,
                    matchCount: searchMatches.length,
                    currentMatchIndex: safeSearchIndex,
                    onQueryChanged: (val) {
                      setState(() {
                        _inChatSearchQuery = val;
                        _inChatSearchMatchIndex = 0;
                      });
                      final matches = _computeSearchMatches(messages);
                      if (matches.isNotEmpty) {
                        final newestIdx = matches.length - 1;
                        setState(() => _inChatSearchMatchIndex = newestIdx);
                        _scrollToMessage(matches[newestIdx].id, messages);
                      } else {
                        setState(() => _highlightedMessageId = null);
                      }
                    },
                    onPrevMatch: () => _navigateSearchMatch(-1, messages),
                    onNextMatch: () => _navigateSearchMatch(1, messages),
                    onClose: _closeInChatSearch,
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
                      Listener(
                        onPointerSignal: (pointerSignal) {
                          if (pointerSignal is PointerScrollEvent &&
                              pointerSignal.scrollDelta.dy.abs() > 0.1) {
                            _onManualScrollTriggered();
                          }
                        },
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (!_isProgrammaticScroll) {
                              if (notification is UserScrollNotification &&
                                  notification.direction !=
                                      ScrollDirection.idle) {
                                _onManualScrollTriggered();
                              } else if (notification
                                      is ScrollUpdateNotification &&
                                  notification.dragDetails != null) {
                                _onManualScrollTriggered();
                              } else if (notification
                                      is ScrollStartNotification &&
                                  notification.dragDetails != null) {
                                _onManualScrollTriggered();
                              }
                            }
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
                                      final separatorId =
                                          _activeUnreadSeparatorMessageId;
                                      if (index > 0 &&
                                          msg.id != separatorId &&
                                          messages[index - 1]
                                              .sharesAttachmentBatch(msg)) {
                                        return const SizedBox.shrink();
                                      }
                                      final batch = <MessageModel>[msg];
                                      for (
                                        var j = index + 1;
                                        j < messages.length;
                                        j++
                                      ) {
                                        if (messages[j].id == separatorId ||
                                            !msg.sharesAttachmentBatch(
                                              messages[j],
                                            )) {
                                          break;
                                        }
                                        batch.add(messages[j]);
                                      }
                                      final isFirstUnread =
                                          msg.id ==
                                          _activeUnreadSeparatorMessageId;
                                      final localTs = msg.timestamp.toLocal();
                                      final prevLocalTs = index > 0
                                          ? messages[index - 1].timestamp
                                                .toLocal()
                                          : null;
                                      final showDateSeparator =
                                          prevLocalTs == null ||
                                          prevLocalTs.year != localTs.year ||
                                          prevLocalTs.month != localTs.month ||
                                          prevLocalTs.day != localTs.day;
                                      final isGroupedWithPrev =
                                          !showDateSeparator &&
                                          !isFirstUnread &&
                                          index > 0 &&
                                          messages[index - 1].isMine ==
                                              msg.isMine &&
                                          messages[index - 1].senderId ==
                                              msg.senderId &&
                                          messages[index - 1].senderName ==
                                              msg.senderName &&
                                          localTs
                                                  .difference(prevLocalTs)
                                                  .inMinutes
                                                  .abs() <
                                              2;
                                      final batchImageCount = batch
                                          .where(
                                            (m) =>
                                                MessengerCoordinator.isImageFile(
                                                  m.fileAttachment?.fileName ??
                                                      '',
                                                ),
                                          )
                                          .length;
                                      final bubble = Listener(
                                        key:
                                            batch.length == 1 &&
                                                !msg.isMine &&
                                                msg.status != MessageStatus.read
                                            ? _readKeys.putIfAbsent(
                                                msg,
                                                () => GlobalKey(),
                                              )
                                            : null,
                                        behavior: HitTestBehavior.translucent,
                                        child: batch.length > 1
                                            ? Align(
                                                alignment: msg.isMine
                                                    ? Alignment.centerRight
                                                    : Alignment.centerLeft,
                                                child: Container(
                                                  key: ValueKey(
                                                    'attachment-batch-${msg.id}',
                                                  ),
                                                  width:
                                                      batchImageCount >= 3 &&
                                                          batchImageCount != 4
                                                      ? 420
                                                      : 360,
                                                  margin:
                                                      const EdgeInsets.symmetric(
                                                        vertical: 6,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: msg.isMine
                                                        ? ThemeProvider.of(
                                                            context,
                                                          ).colors.accentBlue
                                                        : ThemeProvider.of(
                                                            context,
                                                          ).colors.cardBg,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          14,
                                                        ),
                                                  ),
                                                  child: LayoutBuilder(
                                                    builder: (context, constraints) {
                                                      final columns =
                                                          batchImageCount >=
                                                                  3 &&
                                                              batchImageCount !=
                                                                  4 &&
                                                              constraints
                                                                      .maxWidth >=
                                                                  400
                                                          ? 3
                                                          : 2;
                                                      final tileWidth =
                                                          (constraints
                                                                  .maxWidth -
                                                              6 *
                                                                  (columns -
                                                                      1)) /
                                                          columns;
                                                      return Column(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .stretch,
                                                        children: [
                                                          Wrap(
                                                            key: ValueKey(
                                                              'attachment-grid-${msg.id}',
                                                            ),
                                                            spacing: 6,
                                                            runSpacing: 6,
                                                            children: [
                                                              for (final member
                                                                  in batch)
                                                                SizedBox(
                                                                  key: ValueKey(
                                                                    'attachment-tile-${member.id}',
                                                                  ),
                                                                  width:
                                                                      MessengerCoordinator.isImageFile(
                                                                        member
                                                                            .fileAttachment!
                                                                            .fileName,
                                                                      )
                                                                      ? tileWidth
                                                                      : constraints
                                                                            .maxWidth,
                                                                  child: Listener(
                                                                    behavior:
                                                                        HitTestBehavior
                                                                            .translucent,
                                                                    key:
                                                                        !member.isMine &&
                                                                            member.status !=
                                                                                MessageStatus.read
                                                                        ? _readKeys.putIfAbsent(
                                                                            member,
                                                                            () =>
                                                                                GlobalKey(),
                                                                          )
                                                                        : null,
                                                                    child: _MessageBubble(
                                                                      message:
                                                                          member,
                                                                      embedded:
                                                                          true,
                                                                      thumbnailExtent:
                                                                          MessengerCoordinator.isImageFile(
                                                                            member.fileAttachment!.fileName,
                                                                          )
                                                                          ? tileWidth -
                                                                                12
                                                                          : null,
                                                                      isHighlighted:
                                                                          member
                                                                              .id ==
                                                                          _highlightedMessageId,
                                                                      onReply: (m) {
                                                                        setState(
                                                                          () => _replyingToMessage =
                                                                              m,
                                                                        );
                                                                        _inputFocusNode
                                                                            .requestFocus();
                                                                      },
                                                                      onScrollToMessage:
                                                                          (
                                                                            id,
                                                                          ) => _scrollToMessage(
                                                                            id,
                                                                            messages,
                                                                          ),
                                                                    ),
                                                                  ),
                                                                ),
                                                            ],
                                                          ),
                                                          _AttachmentBatchFooter(
                                                            messages: batch,
                                                          ),
                                                        ],
                                                      );
                                                    },
                                                  ),
                                                ),
                                              )
                                            : _MessageBubble(
                                                message: msg,
                                                isCompactTopSpacing:
                                                    isGroupedWithPrev,
                                                isHighlighted:
                                                    msg.id ==
                                                    _highlightedMessageId,
                                                onReply: (m) {
                                                  setState(() {
                                                    _replyingToMessage = m;
                                                  });
                                                  _inputFocusNode
                                                      .requestFocus();
                                                },
                                                onScrollToMessage: (id) =>
                                                    _scrollToMessage(
                                                      id,
                                                      messages,
                                                    ),
                                              ),
                                      );

                                      if (showDateSeparator || isFirstUnread) {
                                        return Column(
                                          key: isFirstUnread
                                              ? _unreadSeparatorKey
                                              : null,
                                          mainAxisSize: MainAxisSize.min,
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (showDateSeparator)
                                              _DateSeparatorChip(date: localTs),
                                            if (isFirstUnread)
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
                      ),
                      Positioned(
                        right: 18,
                        bottom: 12,
                        child: AnimatedOpacity(
                          opacity:
                              (_hasScrollableContent &&
                                  (_showScrollToTop || _showScrollToBottom))
                              ? 1.0
                              : 0.0,
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          child: IgnorePointer(
                            ignoring:
                                !(_hasScrollableContent &&
                                    (_showScrollToTop || _showScrollToBottom)),
                            child: _ChatScrollControls(
                              showScrollToTop: _showScrollToTop,
                              showScrollToBottom: _showScrollToBottom,
                              unreadBelowCount: _unreadBelowCount,
                              onScrollToTop: () => _scrollToTop(smooth: true),
                              onScrollToBottom: () {
                                setState(() {
                                  _unreadBelowCount = 0;
                                });
                                _scrollToBottom(force: true, smooth: true);
                              },
                            ),
                          ),
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
                  onSendSticker: (sticker) =>
                      _handleSendSticker(sticker, coordinator),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
