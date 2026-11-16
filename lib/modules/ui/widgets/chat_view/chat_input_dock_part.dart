part of '../chat_view_panel.dart';

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
  final void Function(StickerItem sticker)? onSendSticker;

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
    this.onSendSticker,
  });

  @override
  State<_ChatInputDock> createState() => _ChatInputDockState();
}

class _ChatInputDockState extends State<_ChatInputDock> {
  bool _showEmojiPicker = false;
  bool _showStickerPicker = false;
  final Object _pickerTapGroup = Object();

  Widget _dismissiblePicker(Widget child) => TapRegion(
    groupId: _pickerTapGroup,
    onTapOutside: (_) {
      if (_showEmojiPicker || _showStickerPicker) {
        setState(() {
          _showEmojiPicker = false;
          _showStickerPicker = false;
        });
      }
    },
    child: child,
  );
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
    final isTargetOffline =
        coordinator.selectedPeer != null &&
        !coordinator.selectedPeer!.isAllUsers &&
        !coordinator.selectedPeer!.isGroup &&
        coordinator.selectedPeer!.status == PeerStatus.offline;

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
                  // 1. Emoji Popover (Compact max 340px x 220px, high-density 22px icons)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: _showEmojiPicker
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _dismissiblePicker(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 340,
                                  ),
                                  child: Container(
                                    width: double.infinity,
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
                                                  alpha: theme.isDark
                                                      ? 0.8
                                                      : 0.08,
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                                  () =>
                                                      _showEmojiPicker = false,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                                child: Padding(
                                                  padding: const EdgeInsets.all(
                                                    3,
                                                  ),
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
                                                final emoji =
                                                    _commonEmojis[idx];
                                                return Material(
                                                  color: Colors.transparent,
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
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
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),

                  // 1.2 Sticker Popover (Bento Frosted Glass)
                  AnimatedSize(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    child: _showStickerPicker
                        ? Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: _dismissiblePicker(
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 340,
                                  ),
                                  child: StickerPickerPopover(
                                    onSelectSticker: (sticker) {
                                      setState(
                                        () => _showStickerPicker = false,
                                      );
                                      widget.onSendSticker?.call(sticker);
                                    },
                                    onClose: () => setState(
                                      () => _showStickerPicker = false,
                                    ),
                                  ),
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
                                  StickerService.isSticker(
                                        widget.replyingTo!.text,
                                      )
                                      ? '[${lang.tr('stickers')}]'
                                      : widget.replyingTo!.text.isNotEmpty
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
                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isUltraCompact = constraints.maxWidth < 310;
                        final isNarrow = constraints.maxWidth < 360;
                        final buttonSize = isUltraCompact
                            ? 26.0
                            : (isNarrow ? 28.0 : 32.0);
                        final spacing = isNarrow ? 1.0 : 2.0;
                        return Row(
                          children: [
                            GlassIconButton(
                              icon: Icons.attach_file_rounded,
                              tooltip: lang.tr('attachFile'),
                              size: buttonSize,
                              onPressed: widget.onAttachFile,
                            ),
                            SizedBox(width: spacing),
                            TapRegion(
                              groupId: _pickerTapGroup,
                              child: GlassIconButton(
                                icon: Icons.sentiment_satisfied_alt_rounded,
                                tooltip: lang.tr('emojis'),
                                size: buttonSize,
                                color: _showEmojiPicker
                                    ? theme.colors.accentBlue
                                    : null,
                                onPressed: () {
                                  setState(() {
                                    _showEmojiPicker = !_showEmojiPicker;
                                    if (_showEmojiPicker) {
                                      _showStickerPicker = false;
                                    }
                                  });
                                },
                              ),
                            ),
                            SizedBox(width: spacing),
                            TapRegion(
                              groupId: _pickerTapGroup,
                              child: GlassIconButton(
                                icon: Icons.sticky_note_2_rounded,
                                tooltip: lang.tr('stickers'),
                                size: buttonSize,
                                color: _showStickerPicker
                                    ? theme.colors.accentBlue
                                    : null,
                                onPressed: () {
                                  setState(() {
                                    _showStickerPicker = !_showStickerPicker;
                                    if (_showStickerPicker) {
                                      _showEmojiPicker = false;
                                    }
                                  });
                                },
                              ),
                            ),
                            if (!isAiChat) ...[
                              SizedBox(width: spacing),
                              _BuzzActionButton(
                                onPressed: widget.onBuzz,
                                tooltip: isTargetOffline
                                    ? lang.tr('buzzOfflineTooltip')
                                    : lang.tr('nudge'),
                                size: buttonSize,
                                defaultColor: theme.isDark
                                    ? Colors.white70
                                    : Colors.black87,
                              ),
                            ],
                            SizedBox(width: isNarrow ? 2.0 : 4.0),
                            ImeToggleButton(size: buttonSize),
                            const Spacer(),
                            if (isAiBusy) ...[
                              Tooltip(
                                message: lang.tr('stopAiGeneration'),
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.redAccent.shade400,
                                    foregroundColor: Colors.white,
                                    minimumSize: Size(
                                      isUltraCompact
                                          ? 28
                                          : (isNarrow ? 30 : 36),
                                      buttonSize,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: isUltraCompact
                                          ? 6
                                          : (isNarrow ? 6 : 10),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  onPressed: () =>
                                      coordinator.stopAiGeneration(),
                                  child: isUltraCompact
                                      ? const Icon(
                                          Icons.stop_circle_rounded,
                                          size: 14,
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                              Icons.stop_circle_rounded,
                                              size: 14,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              lang.tr('stopAiGeneration'),
                                              style: const TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                              SizedBox(width: isNarrow ? 3 : 6),
                            ],
                            Tooltip(
                              message: lang.tr('send'),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.colors.accentBlue,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size(
                                    isUltraCompact ? 32 : (isNarrow ? 36 : 40),
                                    buttonSize,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: isUltraCompact
                                        ? 8
                                        : (isNarrow ? 8 : 14),
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  elevation: 0,
                                ),
                                onPressed: _triggerSend,
                                child: isUltraCompact
                                    ? const Icon(Icons.send_rounded, size: 13)
                                    : Row(
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
                                          const Icon(
                                            Icons.send_rounded,
                                            size: 13,
                                          ),
                                        ],
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
            ),
          ),
        ),
      ],
    );
  }
}
