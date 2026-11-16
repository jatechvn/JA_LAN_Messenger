part of '../chat_view_panel.dart';

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
    );
    AppPowerManager.instance.indicatorsAnimationNotifier.addListener(
      _onPowerStateChanged,
    );
    if (AppPowerManager.instance.shouldAnimateIndicators) {
      _animController.repeat();
    }
  }

  void _onPowerStateChanged() {
    if (!mounted) return;
    if (AppPowerManager.instance.shouldAnimateIndicators) {
      if (!_animController.isAnimating) _animController.repeat();
    } else {
      if (_animController.isAnimating) _animController.stop();
    }
  }

  @override
  void dispose() {
    AppPowerManager.instance.indicatorsAnimationNotifier.removeListener(
      _onPowerStateChanged,
    );
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
    final lang = context.watch<LanguageProvider>();
    final displaySnippet = StickerService.isSticker(snippet)
        ? '[${lang.tr('stickers')}]'
        : snippet;

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
                        displaySnippet,
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
