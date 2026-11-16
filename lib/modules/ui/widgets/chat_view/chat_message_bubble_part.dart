part of '../chat_view_panel.dart';

class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool embedded;
  final double? thumbnailExtent;
  final bool isHighlighted;
  final bool isCompactTopSpacing;
  final ValueChanged<MessageModel>? onReply;
  final ValueChanged<String>? onScrollToMessage;

  const _MessageBubble({
    required this.message,
    this.embedded = false,
    this.thumbnailExtent,
    this.isHighlighted = false,
    this.isCompactTopSpacing = false,
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

  Future<void> _copyImage(LanguageProvider lang) async {
    final attachment = widget.message.fileAttachment;
    final path = attachment?.localPath;
    if (path == null) return;
    final ok = await ImageClipboardHelper.copyImageToClipboard(
      context,
      filePath: path,
      lang: lang,
    );
    if (ok && mounted) {
      setState(() => _isCopied = true);
      _copyTimer?.cancel();
      _copyTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _isCopied = false);
      });
    }
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
    final entities = MessageEntityDetector.extractEntities(widget.message.text);
    final attachment = widget.message.fileAttachment;
    final file = attachment?.localPath != null
        ? File(attachment!.localPath!)
        : null;
    final fileExists = file != null && file.existsSync();
    final isImg =
        attachment != null &&
        MessengerCoordinator.isImageFile(attachment.fileName);
    final isSticker = StickerService.isSticker(widget.message.text);
    final stickerItem = isSticker
        ? StickerService().findByToken(widget.message.text)
        : null;
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
        if (!widget.message.isRevoked)
          PopupMenuItem<String>(
            value: 'forward',
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.shortcut_rounded, size: 15),
                const SizedBox(width: 8),
                Text(
                  lang.tr('forwardMessage'),
                  style: const TextStyle(fontSize: 12.5),
                ),
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
        if (isImg && fileExists) ...[
          PopupMenuItem<String>(
            value: 'copy_image',
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.copy_rounded, size: 15),
                const SizedBox(width: 8),
                Text(
                  lang.tr('copyImage'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
          PopupMenuItem<String>(
            value: 'open_folder',
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.folder_open_rounded, size: 15),
                const SizedBox(width: 8),
                Text(
                  lang.tr('openFolder'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
        if (isSticker &&
            stickerItem != null &&
            stickerItem.isFromFile &&
            File(stickerItem.previewPath).existsSync())
          PopupMenuItem<String>(
            value: 'copy_sticker',
            height: 36,
            child: Row(
              children: [
                const Icon(Icons.copy_rounded, size: 15),
                const SizedBox(width: 8),
                Text(
                  lang.tr('copyImage'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
        if (widget.message.text.isNotEmpty &&
            (!isImg || widget.message.text != attachment.fileName) &&
            !isSticker)
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
        if (entities.isNotEmpty) ...[
          const PopupMenuDivider(height: 1),
          for (int i = 0; i < entities.length; i++) ...[
            PopupMenuItem<String>(
              value: 'entity_open_$i',
              height: 34,
              child: Row(
                children: [
                  Icon(
                    entities[i].type == MessageEntityType.url
                        ? Icons.language_rounded
                        : (entities[i].type == MessageEntityType.phone
                              ? Icons.phone_rounded
                              : (entities[i].type == MessageEntityType.email
                                    ? Icons.mail_outline_rounded
                                    : Icons.folder_open_rounded)),
                    size: 15,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entities[i].type == MessageEntityType.url
                          ? '${lang.tr('openLink')}: ${entities[i].label}'
                          : (entities[i].type == MessageEntityType.phone
                                ? '${lang.tr('callPhone')}: ${entities[i].value}'
                                : (entities[i].type == MessageEntityType.email
                                      ? '${lang.tr('sendEmail')}: ${entities[i].value}'
                                      : '${lang.tr('openPath')}: ${entities[i].label}')),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuItem<String>(
              value: 'entity_copy_$i',
              height: 34,
              child: Row(
                children: [
                  const Icon(Icons.copy_rounded, size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entities[i].type == MessageEntityType.url
                          ? lang.tr('copyLink')
                          : (entities[i].type == MessageEntityType.phone
                                ? lang.tr('copyPhone')
                                : (entities[i].type == MessageEntityType.email
                                      ? lang.tr('copyEmail')
                                      : lang.tr('copyPath'))),
                      style: const TextStyle(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );

    if (!context.mounted) return;

    if (value != null && value.startsWith('entity_')) {
      final parts = value.split('_');
      final action = parts[1];
      final idx = int.tryParse(parts[2]) ?? 0;
      if (idx < entities.length) {
        final ent = entities[idx];
        if (action == 'open') {
          await QuickActionHelper.handleEntityClick(context, ent, lang: lang);
        } else if (action == 'copy') {
          final toastMsg = ent.type == MessageEntityType.url
              ? lang.tr('linkCopiedToast')
              : (ent.type == MessageEntityType.phone
                    ? lang.tr('phoneCopiedToast')
                    : (ent.type == MessageEntityType.email
                          ? lang.tr('emailCopiedToast')
                          : lang.tr('pathCopiedToast')));
          await QuickActionHelper.copyToClipboard(
            context,
            ent.value,
            message: toastMsg,
          );
        }
      }
      return;
    }

    if (value == 'copy_image') {
      await _copyImage(lang);
      return;
    } else if (value == 'copy_sticker' && stickerItem != null) {
      await ImageClipboardHelper.copyImageToClipboard(
        context,
        filePath: stickerItem.previewPath,
        lang: lang,
      );
      return;
    } else if (value == 'open_folder') {
      final path = widget.message.fileAttachment?.localPath;
      if (path != null && File(path).existsSync()) {
        if (Platform.isWindows) {
          Process.run('explorer.exe', ['/select,', path]);
        } else if (Platform.isMacOS) {
          Process.run('open', ['-R', path]);
        } else if (Platform.isLinux) {
          Process.run('xdg-open', [File(path).parent.path]);
        }
      }
      return;
    } else if (value == 'retry') {
      coordinator.retrySendMessage(widget.message);
    } else if (value == 'reply') {
      widget.onReply?.call(widget.message);
    } else if (value == 'forward') {
      await ForwardMessageDialog.show(context, widget.message);
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
    VoidCallback? onCopy,
    bool isImage = false,
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
                    ? (isImage
                          ? lang.tr('imageCopiedToast')
                          : lang.tr('messageCopied'))
                    : (isImage ? lang.tr('copyImage') : lang.tr('copyMessage')),
                color: _isCopied
                    ? Colors.greenAccent
                    : (theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87),
                onTap: onCopy ?? () => _copyMessage(lang),
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

    final localTime = message.timestamp.toLocal();
    final timeStr =
        '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';

    final attachment = message.fileAttachment;
    final file = attachment?.localPath != null
        ? File(attachment!.localPath!)
        : null;
    final fileExists = file != null && file.existsSync();
    final isImg =
        attachment != null &&
        MessengerCoordinator.isImageFile(attachment.fileName);
    final isPureImage =
        !widget.embedded &&
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

    // 1.8. Animated Sticker Message (Bubble-free 60 FPS Sprite Sheet)
    final isSticker = StickerService.isSticker(message.text);
    if (isSticker) {
      final sticker = StickerService().findByToken(message.text);

      Widget stickerWidget;
      if (sticker != null) {
        stickerWidget = SpriteStickerWidget(
          filePath: sticker.isFromFile ? sticker.spritePath : null,
          assetPath: !sticker.isFromFile ? sticker.spritePath : null,
          size: 135,
          autoPlay: true,
          loop: true,
        );
      } else {
        final parsed = StickerService.parseStickerToken(message.text);
        final label = parsed != null
            ? '${parsed.$1}/${parsed.$2}'
            : message.text;
        stickerWidget = Container(
          width: 135,
          height: 90,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.06,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.1,
              ),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.sticky_note_2_outlined,
                size: 28,
                color: theme.isDark ? Colors.white54 : Colors.black45,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  color: theme.isDark ? Colors.white54 : Colors.black54,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      }

      Widget stickerContent = Column(
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    crossAxisAlignment: isMine
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      stickerWidget,
                      const SizedBox(height: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: theme.isDark ? 0.35 : 0.20,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Colors.white70,
                              ),
                            ),
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
                                size: 12,
                                color: message.status == MessageStatus.read
                                    ? const Color(0xFF67E8F9)
                                    : Colors.white70,
                              ),
                              if (message.status == MessageStatus.read) ...[
                                const SizedBox(width: 2),
                                Text(
                                  lang.tr('seen'),
                                  style: const TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF67E8F9),
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ],
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
                        canCopy:
                            sticker != null &&
                            sticker.isFromFile &&
                            File(sticker.previewPath).existsSync(),
                        canRegenerate: false,
                        isImage: true,
                        onCopy:
                            (sticker != null &&
                                sticker.isFromFile &&
                                File(sticker.previewPath).existsSync())
                            ? () => ImageClipboardHelper.copyImageToClipboard(
                                context,
                                filePath: sticker.previewPath,
                                lang: lang,
                              )
                            : null,
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
        stickerContent = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 6, right: 8),
              child: AppAvatar(peer: senderPeer, size: 28, showStatus: false),
            ),
            Flexible(child: stickerContent),
          ],
        );
      }

      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: stickerContent,
        ),
      );
    }

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
                                                MessageStatus.read ||
                                            (message.hasAttachment &&
                                                message.status ==
                                                    MessageStatus
                                                        .delivered)) ...[
                                          const SizedBox(width: 3),
                                          Text(
                                            lang.tr(
                                              message.status ==
                                                      MessageStatus.read
                                                  ? 'seen'
                                                  : 'attachmentReceived',
                                            ),
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
                        canCopy: fileExists,
                        canRegenerate: false,
                        onCopy: () => _copyImage(lang),
                        isImage: true,
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
    final detectedEntities = MessageEntityDetector.extractEntities(
      message.text,
    );

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
        final maxBubbleWidth = widget.embedded
            ? availableWidth
            : math.min(targetWidth, math.max(260.0, availableWidth - 32.0));

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
                    margin: widget.embedded
                        ? EdgeInsets.zero
                        : EdgeInsets.only(
                            top: widget.isCompactTopSpacing ? 2 : 8,
                            bottom: 4,
                          ),
                    width: widget.embedded ? double.infinity : null,
                    constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                    padding: widget.thumbnailExtent != null
                        ? const EdgeInsets.all(6)
                        : const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                    decoration: BoxDecoration(
                      color: widget.embedded ? Colors.transparent : bubbleBg,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(14),
                        topRight: const Radius.circular(14),
                        bottomLeft: Radius.circular(isMine ? 14 : 2),
                        bottomRight: Radius.circular(isMine ? 2 : 14),
                      ),
                      border: widget.embedded
                          ? null
                          : widget.isHighlighted
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
                      boxShadow: widget.embedded
                          ? []
                          : [
                              if (widget.isHighlighted)
                                BoxShadow(
                                  color: Colors.amberAccent.withValues(
                                    alpha: 0.5,
                                  ),
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
                        if (isGroupOrBroadcast &&
                            !widget.isCompactTopSpacing) ...[
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
                            thumbnailExtent: widget.thumbnailExtent,
                          ),
                        ],

                        // Smart Quick Action Chips (URLs, Phones, Emails, Paths)
                        if (detectedEntities.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _MessageQuickActionChips(
                            entities: detectedEntities,
                            isMine: isMine,
                          ),
                        ],

                        const SizedBox(height: 3),
                        // Timestamp & Delivery/Read Status
                        if (!widget.embedded)
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
                                  if (message.status == MessageStatus.read ||
                                      (message.hasAttachment &&
                                          message.status ==
                                              MessageStatus.delivered)) ...[
                                    const SizedBox(width: 3),
                                    Text(
                                      lang.tr(
                                        message.status == MessageStatus.read
                                            ? 'seen'
                                            : 'attachmentReceived',
                                      ),
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

        if (!widget.embedded && isGroupOrBroadcast && senderPeer != null) {
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
