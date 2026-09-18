import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../search_history_repository.dart';

/// Bento Glassmorphic Search Field with live search history suggestions.
/// Pattern adapted from JA_Mini_Showcase.
class GlassSearchHistoryField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String category;
  final String? hintText;
  final double height;
  final double minOverlayWidth;
  final double borderRadius;
  final double fontSize;
  final double hintFontSize;
  final Widget? suffixBadge;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;
  final bool openOverlayOnFocus;

  const GlassSearchHistoryField({
    super.key,
    required this.controller,
    this.category = 'peers',
    this.hintText,
    this.focusNode,
    this.height = 34,
    this.fontSize = 12,
    this.hintFontSize = 11.5,
    this.minOverlayWidth = 260,
    this.borderRadius = 8,
    this.suffixBadge,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.openOverlayOnFocus = false,
  });

  @override
  State<GlassSearchHistoryField> createState() =>
      _GlassSearchHistoryFieldState();
}

class _GlassSearchHistoryFieldState extends State<GlassSearchHistoryField> {
  final LayerLink _layerLink = LayerLink();
  late final FocusNode _internalFocusNode;
  final SearchHistoryRepository _historyRepo = SearchHistoryRepository();

  OverlayEntry? _overlayEntry;
  List<String> _cachedHistory = [];
  bool _isOpen = false;

  FocusNode get _effectiveFocusNode => widget.focusNode ?? _internalFocusNode;

  @override
  void initState() {
    super.initState();
    _internalFocusNode = FocusNode();
    _effectiveFocusNode.addListener(_handleFocusChange);
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void didUpdateWidget(covariant GlassSearchHistoryField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleTextChange);
      widget.controller.addListener(_handleTextChange);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      (oldWidget.focusNode ?? _internalFocusNode).removeListener(
        _handleFocusChange,
      );
      _effectiveFocusNode.addListener(_handleFocusChange);
      _removeOverlay();
    }
    if (oldWidget.category != widget.category) {
      _cachedHistory = [];
      _removeOverlay();
    }
  }

  @override
  void dispose() {
    _effectiveFocusNode.removeListener(_handleFocusChange);
    widget.controller.removeListener(_handleTextChange);
    _overlayEntry?.remove();
    _overlayEntry = null;
    _isOpen = false;
    _internalFocusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_effectiveFocusNode.hasFocus) {
      if (widget.openOverlayOnFocus) {
        _showOverlay();
      }
    } else {
      _removeOverlay();
    }
  }

  void _handleTextChange() {
    if (_isOpen) {
      _overlayEntry?.markNeedsBuild();
    }
    if (mounted) setState(() {});
  }

  Future<void> _loadHistory() async {
    final category = widget.category;
    final list = await _historyRepo.getHistory(category);
    if (!mounted || widget.category != category) return;
    _cachedHistory = list;
    if (_isOpen) {
      _overlayEntry?.markNeedsBuild();
    }
  }

  List<String> _getFilteredHistory() {
    final query = widget.controller.text.trim().toLowerCase();
    if (query.isEmpty) return _cachedHistory;
    return _cachedHistory
        .where((item) => item.toLowerCase().contains(query))
        .toList();
  }

  void _showOverlay() async {
    await _loadHistory();
    if (!mounted) return;
    if (!_effectiveFocusNode.hasFocus) {
      _effectiveFocusNode.requestFocus();
    }

    _removeOverlay();

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (ctx) {
        final theme = context.read<ThemeProvider>();
        final colors = theme.colors;
        final lang = context.read<LanguageProvider>();
        final isDark = theme.isDark;

        final filtered = _getFilteredHistory();
        final overlayWidth = math.max(size.width, widget.minOverlayWidth);

        return Positioned(
          width: overlayWidth,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: Offset(0, size.height + 4),
            child: TextFieldTapRegion(
              child: Material(
                color: Colors.transparent,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 280),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xF21E293B)
                            : const Color(0xFAF8FAFC),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isDark
                              ? const Color(0x38FFFFFF)
                              : const Color(0x29000000),
                          width: 1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.45 : 0.08,
                            ),
                            blurRadius: 18,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Header: Title & Clear All
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: isDark
                                      ? const Color(0x20FFFFFF)
                                      : const Color(0x15000000),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.history_rounded,
                                  size: 13,
                                  color: colors.accentCyan,
                                ),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(
                                    lang.tr('searchHistory'),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w700,
                                      color: isDark
                                          ? Colors.white60
                                          : Colors.black54,
                                      letterSpacing: 0.3,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                if (_cachedHistory.isNotEmpty)
                                  InkWell(
                                    onTap: () async {
                                      await _historyRepo.clearHistory(
                                        widget.category,
                                      );
                                      await _loadHistory();
                                    },
                                    borderRadius: BorderRadius.circular(4),
                                    hoverColor: colors.accentRose.withValues(
                                      alpha: 0.15,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        lang.tr('clearSearchHistory'),
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: colors.accentRose,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          // Items List
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 14,
                              ),
                              child: Text(
                                lang.tr('noSearchHistory'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                  fontStyle: FontStyle.italic,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            )
                          else
                            Flexible(
                              child: ListView.builder(
                                shrinkWrap: true,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                itemCount: filtered.length,
                                itemBuilder: (ctx, index) {
                                  final item = filtered[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => _selectItem(item),
                                      hoverColor: colors.accentBlue.withValues(
                                        alpha: 0.12,
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.access_time_rounded,
                                              size: 13,
                                              color: colors.accentCyan,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                item,
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.black87,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            InkWell(
                                              onTap: () async {
                                                await _historyRepo.removeQuery(
                                                  item,
                                                  widget.category,
                                                );
                                                await _loadHistory();
                                              },
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              hoverColor: colors.accentRose
                                                  .withValues(alpha: 0.2),
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  3,
                                                ),
                                                child: Icon(
                                                  Icons.close_rounded,
                                                  size: 12,
                                                  color: isDark
                                                      ? Colors.white54
                                                      : Colors.black45,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    if (mounted) {
      final scheduler = SchedulerBinding.instance;
      if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        scheduler.addPostFrameCallback((_) {
          if (mounted) setState(() => _isOpen = true);
        });
      } else {
        setState(() => _isOpen = true);
      }
    } else {
      _isOpen = true;
    }
  }

  void _removeOverlay() {
    if (!_isOpen && _overlayEntry == null) return;
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) {
      final scheduler = SchedulerBinding.instance;
      if (scheduler.schedulerPhase == SchedulerPhase.persistentCallbacks) {
        scheduler.addPostFrameCallback((_) {
          if (mounted) setState(() => _isOpen = false);
        });
      } else {
        setState(() => _isOpen = false);
      }
    } else {
      _isOpen = false;
    }
  }

  void _selectItem(String item) {
    widget.controller.text = item;
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: item.length),
    );
    _historyRepo.addQuery(item, widget.category);
    _removeOverlay();
    widget.onChanged?.call(item);
    widget.onSubmitted?.call(item);
  }

  void _saveCurrentQuery() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      _historyRepo.addQuery(text, widget.category);
    }
    _removeOverlay();
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = theme.colors;
    final lang = context.watch<LanguageProvider>();
    final hasText = widget.controller.text.isNotEmpty;
    final isDark = theme.isDark;

    if (_isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isOpen) {
          _overlayEntry?.markNeedsBuild();
        }
      });
    }

    final borderColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.08 : 0.06,
    );

    return TextFieldTapRegion(
      child: CompositedTransformTarget(
        link: _layerLink,
        child: SizedBox(
          height: widget.height,
          child: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.escape) {
                  if (_isOpen) {
                    _removeOverlay();
                    return KeyEventResult.handled;
                  }
                } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
                  if (!_isOpen) {
                    _showOverlay();
                    return KeyEventResult.handled;
                  }
                }
              }
              return KeyEventResult.ignored;
            },
            child: TextField(
              controller: widget.controller,
              focusNode: _effectiveFocusNode,
              style: TextStyle(
                fontSize: widget.fontSize,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: widget.hintText ?? lang.tr('searchHint'),
                hintStyle: TextStyle(
                  fontSize: widget.hintFontSize,
                  color: isDark ? Colors.white38 : Colors.black38,
                ),
                filled: true,
                fillColor: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.06,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.suffixBadge != null) widget.suffixBadge!,
                    if (hasText)
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _removeOverlay();
                            widget.controller.clear();
                            widget.onChanged?.call('');
                            widget.onClear?.call();
                            if (mounted) setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 4,
                            ),
                            child: Icon(
                              Icons.clear_rounded,
                              size: 14,
                              color: isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 0,
                ),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  borderSide: BorderSide(color: borderColor),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  borderSide: BorderSide(color: borderColor),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  borderSide: BorderSide(color: colors.accentBlue, width: 1.2),
                ),
              ),
              onTapOutside: (event) {
                _removeOverlay();
              },
              onTap: () {
                if (!_isOpen) {
                  _showOverlay();
                }
              },
              onChanged: (val) {
                if (!_isOpen && val.isNotEmpty) {
                  _showOverlay();
                }
                widget.onChanged?.call(val);
                setState(() {});
              },
              onSubmitted: (val) {
                _saveCurrentQuery();
                widget.onSubmitted?.call(val);
              },
            ),
          ),
        ),
      ),
    );
  }
}
