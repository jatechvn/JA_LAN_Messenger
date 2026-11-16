part of '../chat_view_panel.dart';

/// Presentation aggregate only. Each attachment retains its own read receipt.
class _AttachmentBatchFooter extends StatelessWidget {
  final List<MessageModel> messages;
  const _AttachmentBatchFooter({required this.messages});

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final theme = ThemeProvider.of(context);
    final first = messages.first;
    final statuses = messages.map((m) => m.status).toList();
    final status = statuses.every((s) => s == MessageStatus.read)
        ? MessageStatus.read
        : statuses.every(
            (s) => s == MessageStatus.delivered || s == MessageStatus.read,
          )
        ? MessageStatus.delivered
        : statuses.contains(MessageStatus.failed)
        ? MessageStatus.failed
        : statuses.contains(MessageStatus.sending)
        ? MessageStatus.sending
        : MessageStatus.sent;
    final time = first.timestamp.toLocal();
    final timeText =
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    final color = first.isMine ? Colors.white70 : theme.colors.textMuted;
    final stateColor = status == MessageStatus.read
        ? const Color(0xFF67E8F9)
        : status == MessageStatus.failed
        ? const Color(0xFFF87171)
        : color;
    final label = status == MessageStatus.read
        ? lang.tr('seen')
        : status == MessageStatus.delivered
        ? lang.tr('attachmentReceived')
        : status == MessageStatus.failed
        ? '${lang.tr('transferFailed')} (${statuses.where((s) => s == MessageStatus.failed).length}/${messages.length})'
        : null;
    return Padding(
      key: ValueKey('attachment-batch-footer-${first.id}'),
      padding: const EdgeInsets.fromLTRB(10, 3, 10, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(timeText, style: TextStyle(fontSize: 10, color: color)),
          if (first.isMine) ...[
            const SizedBox(width: 5),
            Icon(
              status == MessageStatus.read || status == MessageStatus.delivered
                  ? Icons.done_all_rounded
                  : status == MessageStatus.failed
                  ? Icons.error_outline_rounded
                  : status == MessageStatus.sent
                  ? Icons.done_rounded
                  : Icons.schedule_rounded,
              size: 13,
              color: stateColor,
            ),
            if (label != null) ...[
              const SizedBox(width: 3),
              Text(label, style: TextStyle(fontSize: 10, color: stateColor)),
            ],
          ],
        ],
      ),
    );
  }
}

class _MessageQuickActionChips extends StatelessWidget {
  final List<MessageEntity> entities;
  final bool isMine;

  const _MessageQuickActionChips({
    required this.entities,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: entities.map((entity) {
          final IconData icon;
          final String actionTooltip;
          final String copyTooltip;
          final String copiedToast;

          switch (entity.type) {
            case MessageEntityType.url:
              icon = Icons.language_rounded;
              actionTooltip = '${lang.tr('openLink')}: ${entity.value}';
              copyTooltip = lang.tr('copyLink');
              copiedToast = lang.tr('linkCopiedToast');
              break;
            case MessageEntityType.phone:
              icon = Icons.phone_rounded;
              actionTooltip = '${lang.tr('callPhone')}: ${entity.value}';
              copyTooltip = lang.tr('copyPhone');
              copiedToast = lang.tr('phoneCopiedToast');
              break;
            case MessageEntityType.email:
              icon = Icons.mail_outline_rounded;
              actionTooltip = '${lang.tr('sendEmail')}: ${entity.value}';
              copyTooltip = lang.tr('copyEmail');
              copiedToast = lang.tr('emailCopiedToast');
              break;
            case MessageEntityType.path:
              icon = Icons.folder_open_rounded;
              actionTooltip = '${lang.tr('openPath')}: ${entity.value}';
              copyTooltip = lang.tr('copyPath');
              copiedToast = lang.tr('pathCopiedToast');
              break;
          }

          final chipBg = isMine
              ? Colors.white.withValues(alpha: 0.16)
              : (theme.isDark
                    ? const Color(0xFF334155).withValues(alpha: 0.70)
                    : const Color(0xFFF1F5F9));
          final chipBorder = isMine
              ? Colors.white.withValues(alpha: 0.28)
              : (theme.isDark
                    ? const Color(0x33FFFFFF)
                    : Colors.black.withValues(alpha: 0.08));
          final textColor = isMine
              ? Colors.white
              : (theme.isDark
                    ? const Color(0xFFE2E8F0)
                    : const Color(0xFF334155));
          final iconColor = isMine
              ? Colors.cyanAccent.shade100
              : theme.colors.accentBlue;

          return Material(
            color: Colors.transparent,
            child: Container(
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: chipBorder, width: 0.8),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => QuickActionHelper.handleEntityClick(
                  context,
                  entity,
                  lang: lang,
                ),
                onSecondaryTap: () => QuickActionHelper.copyToClipboard(
                  context,
                  entity.value,
                  message: copiedToast,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3.5,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: actionTooltip,
                        child: Icon(icon, size: 12.5, color: iconColor),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Tooltip(
                          message: actionTooltip,
                          child: Text(
                            entity.label,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Tooltip(
                        message: copyTooltip,
                        child: InkResponse(
                          radius: 12,
                          onTap: () => QuickActionHelper.copyToClipboard(
                            context,
                            entity.value,
                            message: copiedToast,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.copy_rounded,
                              size: 11,
                              color: textColor.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
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
  final double? thumbnailExtent;

  const _AttachmentPreview({
    required this.attachment,
    required this.isMine,
    this.thumbnailExtent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isImg = MessengerCoordinator.isImageFile(attachment.fileName);
    final file = attachment.localPath != null
        ? File(attachment.localPath!)
        : null;
    final fileExists = file != null && file.existsSync();

    if (isImg && !fileExists && thumbnailExtent != null) {
      return SizedBox.square(
        dimension: thumbnailExtent!,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.image_outlined,
              color: isMine ? Colors.white70 : theme.colors.textSecondary,
            ),
            const SizedBox(height: 6),
            Text(
              attachment.fileName,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                color: isMine ? Colors.white70 : theme.colors.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    // 1. Image Preview with Thumbnail & Lightbox Zoom Viewer
    if (isImg && fileExists) {
      return InkWell(
        onTap: () =>
            _showAttachmentLightbox(context, file.path, attachment.fileName),
        borderRadius: BorderRadius.circular(10),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            constraints: thumbnailExtent != null
                ? BoxConstraints.tightFor(
                    width: thumbnailExtent,
                    height: thumbnailExtent,
                  )
                : const BoxConstraints(
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
                  cacheWidth:
                      ((thumbnailExtent ?? 280) *
                              MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
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
                Positioned(
                  top: 6,
                  right: 6,
                  child: Tooltip(
                    message: lang.tr('copyImage'),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => ImageClipboardHelper.copyImageToClipboard(
                          context,
                          filePath: file.path,
                          lang: lang,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.all(5),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white30,
                              width: 0.8,
                            ),
                          ),
                          child: const Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
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
