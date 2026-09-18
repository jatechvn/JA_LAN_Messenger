import 'dart:ui';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../theme/theme_provider.dart';
import '../../models/peer_model.dart';

/// Bề mặt kính mờ tái sử dụng có sàn an toàn chống nhòe chữ (legibility floor)
class GlassSurface extends StatelessWidget {
  final Widget child;
  final double? blur;
  final double? opacity;
  final BorderRadius? borderRadius;
  final Border? border;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Color? baseColor;

  const GlassSurface({
    super.key,
    required this.child,
    this.blur,
    this.opacity,
    this.borderRadius,
    this.border,
    this.padding,
    this.margin,
    this.baseColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final rawOpacity = opacity ?? theme.cardOpacity;
    final effectiveOpacity = (!theme.isDark && rawOpacity < 0.28)
        ? 0.28
        : rawOpacity;
    final rawBlur = blur ?? theme.cardBlur;

    // Sàn an toàn legibility floor: nếu trong suốt (opacity < 1.0) thì blur tối thiểu phải là 8.0
    final effectiveBlur = effectiveOpacity < 1.0 ? math.max(rawBlur, 8.0) : 0.0;

    final br = borderRadius ?? BorderRadius.circular(12);
    final bgColor = (baseColor ?? (theme.isDark ? Colors.black : Colors.white))
        .withValues(alpha: effectiveOpacity);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: br,
        border:
            border ??
            Border.all(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: theme.isDark ? 0.08 : 0.06,
              ),
              width: 1,
            ),
      ),
      child: ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: effectiveBlur,
            sigmaY: effectiveBlur,
          ),
          child: Container(padding: padding, color: bgColor, child: child),
        ),
      ),
    );
  }
}

/// Nút bấm icon mờ thanh thoát
class GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;

  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.tooltip,
    this.size = 36,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final iconColor =
        color ??
        (theme.isDark ? Colors.white.withValues(alpha: 0.85) : Colors.black87);

    final btn = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        hoverColor: (theme.isDark ? Colors.white : Colors.black).withValues(
          alpha: 0.08,
        ),
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          child: Icon(icon, size: size * 0.55, color: iconColor),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Badge trạng thái tròn hoặc pill
class StatusBadge extends StatelessWidget {
  final PeerStatus status;
  final bool showLabel;

  const StatusBadge({super.key, required this.status, this.showLabel = false});

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(
        color: status.color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: status.color.withValues(alpha: 0.45),
            blurRadius: 4,
            spreadRadius: 1,
          ),
        ],
      ),
    );

    if (!showLabel) return dot;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: status.color.withValues(alpha: 0.3),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(width: 5),
          Text(
            status.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: status.color,
            ),
          ),
        ],
      ),
    );
  }
}
