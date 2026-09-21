import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/theme_provider.dart';

/// Item definition for [GlassDropdown].
/// Inherited from the JA_Mini_Showcase design system.
class GlassDropdownItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  final String? subtitle;
  final Color? accentColor;
  final String? badge;

  const GlassDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.subtitle,
    this.accentColor,
    this.badge,
  });
}

/// A modern Liquid Glass Dropdown / Popup Menu selector.
/// Adheres strictly to the JA_Mini_Showcase Frosted Glassmorphism design system:
/// - Custom glass popup with BackdropFilter blur and highlight edge.
/// - High-opacity surface (88% - 98%) to eliminate background bleed-through.
/// - Fast-path zero-blur support for HardwareTier.lite (Mini PC / Intel N100).
/// - Selected item displays active pill background with accent border and checkmark.
class GlassDropdown<T> extends StatefulWidget {
  final List<GlassDropdownItem<T>> items;
  final T? value;
  final ValueChanged<T> onChanged;
  final String hintText;
  final double maxHeight;
  final bool enableSearch;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final Widget? customTrigger;
  final Offset? menuOffset;
  final double? menuWidth;
  final String? tooltip;

  const GlassDropdown({
    super.key,
    required this.items,
    required this.value,
    required this.onChanged,
    this.hintText = 'Chọn một mục…',
    this.maxHeight = 280,
    this.enableSearch = false,
    this.borderRadius = 12,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    this.customTrigger,
    this.menuOffset,
    this.menuWidth,
    this.tooltip,
  });

  @override
  State<GlassDropdown<T>> createState() => _GlassDropdownState<T>();
}

class _GlassDropdownState<T> extends State<GlassDropdown<T>> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  final FocusNode _menuFocus = FocusNode();
  bool _isOpen = false;

  @override
  void dispose() {
    _removeOverlay();
    _menuFocus.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_isOpen) {
      _removeOverlay();
    } else {
      _showOverlay();
    }
  }

  void _removeOverlay() {
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
      if (mounted) {
        setState(() => _isOpen = false);
      }
    }
  }

  void _showOverlay() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final size = renderBox.size;
    final effectiveWidth =
        widget.menuWidth ?? (size.width < 180 ? 180 : size.width);
    final effectiveOffset = widget.menuOffset ?? Offset(0, size.height + 6);

    _overlayEntry = OverlayEntry(
      builder: (context) {
        return Stack(
          children: [
            // Barrier dismiss on tap outside
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _removeOverlay,
              ),
            ),
            Positioned(
              width: effectiveWidth,
              child: CompositedTransformFollower(
                link: _layerLink,
                showWhenUnlinked: false,
                offset: effectiveOffset,
                child: Focus(
                  focusNode: _menuFocus,
                  autofocus: true,
                  onKeyEvent: (_, event) {
                    if (event is KeyDownEvent &&
                        event.logicalKey == LogicalKeyboardKey.escape) {
                      _removeOverlay();
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: _GlassDropdownMenu<T>(
                    items: widget.items,
                    selectedValue: widget.value,
                    maxHeight: widget.maxHeight,
                    enableSearch:
                        widget.enableSearch && widget.items.length > 5,
                    menuOffset: effectiveOffset,
                    onSelected: (val) {
                      _removeOverlay();
                      widget.onChanged(val);
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(_overlayEntry!);
    _menuFocus.requestFocus();
    setState(() => _isOpen = true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final colors = theme.colors;

    final selectedItem = widget.items.cast<GlassDropdownItem<T>?>().firstWhere(
      (item) => item?.value == widget.value,
      orElse: () => null,
    );

    Widget triggerWidget;
    if (widget.customTrigger != null) {
      triggerWidget = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          hoverColor: theme.isDark ? Colors.white10 : Colors.black12,
          child: widget.customTrigger!,
        ),
      );
    } else {
      triggerWidget = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _toggleDropdown,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          hoverColor: colors.cardHoverBg.withValues(alpha: 0.15),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: widget.padding,
            decoration: BoxDecoration(
              color: colors.subCardBg,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: _isOpen
                    ? colors.accentColor.withValues(alpha: 0.5)
                    : colors.subCardBorder,
                width: 1.1,
              ),
              boxShadow: [
                if (_isOpen)
                  BoxShadow(
                    color: colors.primaryGlow.withValues(alpha: 0.18),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selectedItem?.icon != null) ...[
                  Icon(
                    selectedItem!.icon,
                    size: 16,
                    color: selectedItem.accentColor ?? colors.accentCyan,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    selectedItem?.label ?? widget.hintText,
                    style: TextStyle(
                      color: selectedItem != null
                          ? colors.textPrimary
                          : colors.textMuted,
                      fontSize: 12.5,
                      fontWeight: selectedItem != null
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _isOpen ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: _isOpen ? colors.accentColor : colors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      triggerWidget = Tooltip(message: widget.tooltip!, child: triggerWidget);
    }

    return CompositedTransformTarget(link: _layerLink, child: triggerWidget);
  }
}

class _GlassDropdownMenu<T> extends StatefulWidget {
  final List<GlassDropdownItem<T>> items;
  final T? selectedValue;
  final double maxHeight;
  final bool enableSearch;
  final Offset menuOffset;
  final ValueChanged<T> onSelected;

  const _GlassDropdownMenu({
    required this.items,
    required this.selectedValue,
    required this.maxHeight,
    required this.enableSearch,
    required this.menuOffset,
    required this.onSelected,
  });

  @override
  State<_GlassDropdownMenu<T>> createState() => _GlassDropdownMenuState<T>();
}

class _GlassDropdownMenuState<T> extends State<_GlassDropdownMenu<T>>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  late List<GlassDropdownItem<T>> _filteredItems = widget.items;
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..forward();

    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _scaleAnim = Tween<double>(
      begin: 0.94,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String query) {
    setState(() {
      if (query.trim().isEmpty) {
        _filteredItems = widget.items;
      } else {
        final q = query.toLowerCase();
        _filteredItems = widget.items.where((item) {
          final l = item.label.toLowerCase();
          final s = item.subtitle?.toLowerCase() ?? '';
          final b = item.badge?.toLowerCase() ?? '';
          return l.contains(q) || s.contains(q) || b.contains(q);
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final colors = theme.colors;
    final isDark = theme.isDark;

    final dropdownBlur = theme.dropdownBlur;
    final dropdownOpacity = theme.dropdownOpacity.clamp(0.88, 0.98);
    final isLite =
        theme.effectiveTier == HardwareTier.lite || dropdownBlur <= 0;

    // High-opacity frosted surface matching JA_Mini_Showcase
    final dropdownBg = isDark
        ? const Color(0xFF1E293B).withValues(alpha: dropdownOpacity)
        : const Color(0xFFFFFFFF).withValues(alpha: dropdownOpacity);
    final dropdownBorder = isDark
        ? const Color(0x38FFFFFF)
        : const Color(0x29000000);

    final isPoppingUpward = widget.menuOffset.dy < 0;

    Widget menuContent = Container(
      constraints: BoxConstraints(maxHeight: widget.maxHeight),
      decoration: BoxDecoration(
        color: dropdownBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dropdownBorder, width: 1.1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top highlight edge gradient
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  (isDark ? Colors.white : Colors.white).withValues(
                    alpha: isDark ? 0.25 : 0.6,
                  ),
                  (isDark ? Colors.white : Colors.white).withValues(
                    alpha: 0.05,
                  ),
                ],
              ),
            ),
          ),

          // Search field for lists > 5 items
          if (widget.enableSearch) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              child: Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0x33000000)
                      : const Color(0x0D000000),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDark
                        ? const Color(0x26FFFFFF)
                        : const Color(0x1A000000),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 15,
                      color: colors.textMuted,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        onChanged: _filter,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 12,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          hintText: 'Tìm kiếm ${widget.items.length} mục…',
                          hintStyle: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ),
                    if (_searchCtrl.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          _filter('');
                        },
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: colors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Divider(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.08,
              ),
              height: 1,
            ),
          ],

          // Scrollable item list
          Flexible(
            child: _filteredItems.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Không tìm thấy mục phù hợp',
                      style: TextStyle(color: colors.textMuted, fontSize: 12),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 6,
                    ),
                    shrinkWrap: true,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _filteredItems.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 2),
                    itemBuilder: (context, index) {
                      final item = _filteredItems[index];
                      final isSelected = item.value == widget.selectedValue;

                      return InkWell(
                        onTap: () => widget.onSelected(item.value),
                        borderRadius: BorderRadius.circular(10),
                        hoverColor: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: 0.06),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? colors.accentColor.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected
                                  ? colors.accentColor.withValues(alpha: 0.35)
                                  : Colors.transparent,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (item.icon != null) ...[
                                Icon(
                                  item.icon,
                                  size: 16,
                                  color:
                                      item.accentColor ??
                                      (isSelected
                                          ? colors.accentColor
                                          : colors.textMuted),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      item.label,
                                      style: TextStyle(
                                        color: isSelected
                                            ? colors.accentColor
                                            : colors.textPrimary,
                                        fontSize: 12.5,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                      ),
                                    ),
                                    if (item.subtitle != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        item.subtitle!,
                                        style: TextStyle(
                                          color: colors.textMuted,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (item.badge != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color:
                                        (item.accentColor ?? colors.accentColor)
                                            .withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color:
                                          (item.accentColor ??
                                                  colors.accentColor)
                                              .withValues(alpha: 0.35),
                                      width: 0.8,
                                    ),
                                  ),
                                  child: Text(
                                    item.badge!,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color:
                                          item.accentColor ??
                                          colors.accentColor,
                                    ),
                                  ),
                                ),
                              ],
                              if (isSelected) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: colors.accentColor,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );

    // Fast-path: Skip BackdropFilter if on Lite tier or blur <= 0
    if (!isLite && dropdownBlur > 0) {
      menuContent = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: dropdownBlur, sigmaY: dropdownBlur),
          child: menuContent,
        ),
      );
    } else {
      menuContent = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: menuContent,
      );
    }

    return Material(
      color: Colors.transparent,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ScaleTransition(
          scale: _scaleAnim,
          alignment: isPoppingUpward ? Alignment.bottomLeft : Alignment.topLeft,
          child: menuContent,
        ),
      ),
    );
  }
}
