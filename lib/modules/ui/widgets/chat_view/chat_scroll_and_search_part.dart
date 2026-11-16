part of '../chat_view_panel.dart';

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

/// Dải phân cách ngày tháng trong lịch sử trò chuyện (Hôm nay / Hôm qua / dd/MM/yyyy)
class _DateSeparatorChip extends StatelessWidget {
  final DateTime date;

  const _DateSeparatorChip({required this.date});

  String _formatDateLabel(LanguageProvider lang) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(local.year, local.month, local.day);
    final diffDays = today.difference(msgDay).inDays;

    if (diffDays == 0) {
      return lang.tr('today');
    } else if (diffDays == 1) {
      return lang.tr('yesterday');
    }
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    final y = local.year.toString();
    return '$d/$m/$y';
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1E293B) : Colors.black).withValues(
              alpha: isDark ? 0.65 : 0.06,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.10 : 0.06,
              ),
              width: 0.8,
            ),
          ),
          child: Text(
            _formatDateLabel(lang),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? const Color(0xFF94A3B8) : Colors.black54,
            ),
          ),
        ),
      ),
    );
  }
}

/// Thanh tìm kiếm tin nhắn trong cuộc trò chuyện hiện tại (Ctrl+F)
class _InChatSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String query;
  final int matchCount;
  final int currentMatchIndex;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onPrevMatch;
  final VoidCallback onNextMatch;
  final VoidCallback onClose;

  const _InChatSearchBar({
    required this.controller,
    required this.focusNode,
    required this.query,
    required this.matchCount,
    required this.currentMatchIndex,
    required this.onQueryChanged,
    required this.onPrevMatch,
    required this.onNextMatch,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;
    final hasQuery = query.trim().isNotEmpty;

    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF1E293B) : const Color(0xFFF3F4F8))
            .withValues(alpha: isDark ? 0.85 : 0.96),
        border: Border(
          bottom: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: isDark ? 0.10 : 0.08,
            ),
            width: 0.8,
          ),
        ),
      ),
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.escape) {
              onClose();
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.numpadEnter) {
              if (HardwareKeyboard.instance.isShiftPressed) {
                onNextMatch();
              } else {
                onPrevMatch();
              }
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: 16,
              color: theme.colors.accentBlue,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onQueryChanged,
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? const Color(0xFFF8FAFC) : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: lang.tr('searchMessagesHint'),
                  hintStyle: TextStyle(
                    fontSize: 12,
                    color: isDark ? const Color(0xFF94A3B8) : Colors.black45,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 6),
                ),
              ),
            ),
            if (hasQuery) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  matchCount > 0
                      ? '${currentMatchIndex + 1}/$matchCount'
                      : lang.tr('noSearchResults'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: matchCount > 0
                        ? theme.colors.accentBlue
                        : (isDark ? Colors.white54 : Colors.black45),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
                tooltip: lang.tr('prevMatch'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: matchCount > 0 ? onPrevMatch : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                tooltip: lang.tr('nextMatch'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                onPressed: matchCount > 0 ? onNextMatch : null,
              ),
            ],
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 16),
              tooltip: lang.tr('close'),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              onPressed: onClose,
            ),
          ],
        ),
      ),
    );
  }
}
