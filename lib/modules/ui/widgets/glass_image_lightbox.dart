import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';

/// Bento Glassmorphic Image Preview / Lightbox.
/// Supports theme-adaptive backdrop blur (luminous frosted white in Light mode,
/// deep glass in Dark mode), tap-on-empty-space dismissal, and Esc shortcut.
class GlassImageLightbox extends StatelessWidget {
  final String filePath;
  final String fileName;
  final VoidCallback? onOpenFolder;

  const GlassImageLightbox({
    super.key,
    required this.filePath,
    required this.fileName,
    this.onOpenFolder,
  });

  void _defaultOpenFolder() {
    if (Platform.isWindows) {
      Process.run('explorer.exe', ['/select,', filePath]);
    } else if (Platform.isMacOS) {
      Process.run('open', ['-R', filePath]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [File(filePath).parent.path]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    final headerBg = isDark
        ? const Color(0xFF0F172A).withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.88);

    final headerBorder = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.08);

    final textColor = isDark ? Colors.white : Colors.black87;
    final iconColor = isDark ? Colors.white70 : Colors.black87;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: Stack(
            children: [
              // Zoomable Image & Tap-to-dismiss empty space
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return InteractiveViewer(
                      minScale: 0.5,
                      maxScale: 4.0,
                      child: SizedBox(
                        width: constraints.maxWidth,
                        height: constraints.maxHeight,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            // Tapping anywhere in the empty margins closes preview
                            Navigator.of(context).pop();
                          },
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                68,
                                20,
                                20,
                              ),
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  // Tapping the image itself does NOT close
                                },
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(
                                          alpha: isDark ? 0.45 : 0.12,
                                        ),
                                        blurRadius: 24,
                                        offset: const Offset(0, 8),
                                      ),
                                    ],
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.file(
                                      File(filePath),
                                      fit: BoxFit.contain,
                                      errorBuilder:
                                          (
                                            context,
                                            error,
                                            stackTrace,
                                          ) => Container(
                                            padding: const EdgeInsets.all(32),
                                            color: isDark
                                                ? Colors.white10
                                                : Colors.black.withValues(
                                                    alpha: 0.05,
                                                  ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.broken_image_rounded,
                                                  size: 64,
                                                  color: isDark
                                                      ? Colors.white38
                                                      : Colors.black38,
                                                ),
                                                const SizedBox(height: 8),
                                                Text(
                                                  fileName,
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.white54
                                                        : Colors.black54,
                                                    fontSize: 12,
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
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Floating Frosted Glass Action Header
              Positioned(
                top: 14,
                left: 20,
                right: 20,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        // Tapping header does not close
                      },
                      child: Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: headerBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: headerBorder, width: 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.35 : 0.06,
                              ),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.image_rounded,
                              size: 18,
                              color: theme.colors.accentBlue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                fileName,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.folder_open_rounded,
                                size: 19,
                                color: iconColor,
                              ),
                              tooltip: lang.tr('openFolder'),
                              splashRadius: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: onOpenFolder ?? _defaultOpenFolder,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                Icons.close_rounded,
                                size: 19,
                                color: iconColor,
                              ),
                              tooltip: lang.tr('cancel'),
                              splashRadius: 18,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 32,
                                minHeight: 32,
                              ),
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
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
}

/// Helper function to display the theme-adaptive image lightbox with
/// smooth fade/scale transition, frosted glass blur, and empty space dismissal.
Future<void> showGlassImageLightbox({
  required BuildContext context,
  required String filePath,
  required String fileName,
  VoidCallback? onOpenFolder,
}) {
  final theme = ThemeProvider.of(context, listen: false);
  final isDark = theme.isDark;

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'GlassImageLightbox',
    barrierColor: isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.white.withValues(alpha: 0.60),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim1, anim2) => GlassImageLightbox(
      filePath: filePath,
      fileName: fileName,
      onOpenFolder: onOpenFolder,
    ),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.96,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}
