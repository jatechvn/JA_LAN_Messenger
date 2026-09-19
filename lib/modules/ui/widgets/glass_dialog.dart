import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../theme/theme_provider.dart';

/// Bento Glassmorphic Modal Dialog with full background backdrop blur.
/// Learned from JA_Mini_Showcase pattern for premium macOS/Windows 11 look.
class GlassDialog extends StatelessWidget {
  final Widget child;
  final String title;
  final IconData? icon;
  final double width;
  final double? height;
  final List<Widget>? actions;
  final EdgeInsetsGeometry contentPadding;
  final double? blurSigma;
  final Widget? headerTrailing;

  const GlassDialog({
    super.key,
    required this.child,
    required this.title,
    this.icon,
    this.width = 460,
    this.height,
    this.actions,
    this.contentPadding = const EdgeInsets.fromLTRB(20, 16, 20, 16),
    this.blurSigma,
    this.headerTrailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;
    final effectiveBlur = blurSigma ?? theme.dialogBlur;

    final bg = isDark
        ? const Color(0xFF0F172A).withValues(alpha: theme.dialogOpacity)
        : const Color(0xFFFFFFFF).withValues(alpha: theme.dialogOpacity);

    final borderColor = (isDark ? Colors.white : Colors.black).withValues(
      alpha: isDark ? 0.12 : 0.08,
    );

    Widget dialogBody = LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final horizontalMargin = screenWidth < 420 ? 12.0 : 24.0;
        final maxDialogWidth = math.max(260.0, screenWidth - (horizontalMargin * 2));
        final effectiveWidth = math.min(width, maxDialogWidth);

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: effectiveWidth,
              height: height,
              margin: EdgeInsets.symmetric(
                horizontal: horizontalMargin,
                vertical: 24,
              ),
              decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: height == null
                  ? MainAxisSize.min
                  : MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
                  child: Row(
                    children: [
                      if (icon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: theme.colors.accentBlue.withValues(
                              alpha: 0.12,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon,
                            size: 18,
                            color: theme.colors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (headerTrailing != null) ...[
                        headerTrailing!,
                        const SizedBox(width: 8),
                      ],
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.06),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Divider(color: borderColor, height: 1),

                // Content
                if (height != null)
                  Expanded(
                    child: Padding(padding: contentPadding, child: child),
                  )
                else
                  Padding(padding: contentPadding, child: child),

                // Actions
                if (actions != null && actions!.isNotEmpty) ...[
                  Divider(color: borderColor, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 8,
                        children: actions!,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  },
);

    if (effectiveBlur > 0) {
      dialogBody = BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: dialogBody,
      );
    }
    return RepaintBoundary(child: dialogBody);
  }
}

/// Helper function to display any dialog with buttery smooth fade/scale animation
/// and authentic backdrop blur.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget Function(BuildContext) builder,
  bool barrierDismissible = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: 'GlassDialog',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => builder(ctx),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.95,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}
