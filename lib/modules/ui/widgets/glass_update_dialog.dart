import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../constants.dart';
import '../../services/ota_update_service.dart';

/// Mở hộp thoại cập nhật Bento Frosted Glass
Future<void> showGlassUpdateDialog({
  required BuildContext context,
  required UpdatePackageInfo packageInfo,
}) {
  final theme = ThemeProvider.of(context, listen: false);
  final isDark = theme.isDark;

  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'GlassUpdateDialog',
    barrierColor: isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.40),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim1, anim2) => GlassUpdateDialog(
      packageInfo: packageInfo,
    ),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(
            CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
          ),
          child: child,
        ),
      );
    },
  );
}

/// Hộp thoại thông báo cập nhật Bento Frosted Glass
class GlassUpdateDialog extends StatefulWidget {
  final UpdatePackageInfo packageInfo;

  const GlassUpdateDialog({
    super.key,
    required this.packageInfo,
  });

  @override
  State<GlassUpdateDialog> createState() => _GlassUpdateDialogState();
}

class _GlassUpdateDialogState extends State<GlassUpdateDialog> {
  bool _isUpdating = false;
  double _progress = 0.0;
  String _statusText = '';
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _isUpdating = true;
      _errorMessage = null;
      _progress = 0.05;
      _statusText = 'Đang khởi tạo...';
    });

    try {
      await OtaUpdateService().performUpdate(
        widget.packageInfo,
        onProgress: (prog, status) {
          if (mounted) {
            setState(() {
              _progress = prog;
              _statusText = status;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _isUpdating = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!_isUpdating &&
            event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          Navigator.of(context).pop();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 520,
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.94)
                  : Colors.white.withValues(alpha: 0.97),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: isDark ? 0.14 : 0.09,
                ),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header Bar
                    Container(
                      padding: const EdgeInsets.fromLTRB(18, 14, 14, 14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: isDark ? 0.04 : 0.03),
                        border: Border(
                          bottom: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.08),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colors.accentBlue,
                                  theme.colors.accentCyan,
                                ],
                              ),
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colors.accentBlue.withValues(alpha: 0.35),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.system_update_alt_rounded,
                              size: 20,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  lang.tr('otaUpdateTitle'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: isDark ? Colors.white : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  lang.tr('updateAvailable', [
                                    widget.packageInfo.version.toString(),
                                  ]),
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: theme.colors.accentEmerald,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (!_isUpdating)
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 18),
                              tooltip: lang.tr('closeDialog'),
                              splashRadius: 18,
                              color: isDark ? Colors.white70 : Colors.black54,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                        ],
                      ),
                    ),

                    // Body
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Version Comparison & Size Cards
                          Row(
                            children: [
                              // Current Version Badge
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: (isDark ? Colors.white : Colors.black)
                                        .withValues(alpha: isDark ? 0.05 : 0.04),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: (isDark ? Colors.white : Colors.black)
                                          .withValues(alpha: 0.08),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang.tr('currentVersion'),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: isDark ? Colors.white54 : Colors.black45,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        'v$appVersion',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: isDark ? Colors.white70 : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 16,
                                color: theme.colors.accentBlue,
                              ),
                              const SizedBox(width: 8),
                              // New Version Badge
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: theme.colors.accentEmerald.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: theme.colors.accentEmerald.withValues(alpha: 0.35),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lang.tr('latestVersion'),
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: theme.colors.accentEmerald,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 3),
                                      Row(
                                        children: [
                                          Text(
                                            widget.packageInfo.version.displayVersion,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: theme.colors.accentEmerald,
                                            ),
                                          ),
                                          const Spacer(),
                                          Text(
                                            widget.packageInfo.formattedSize,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Release Notes Section
                          Row(
                            children: [
                              Icon(
                                Icons.article_outlined,
                                size: 14,
                                color: theme.colors.accentBlue,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                lang.tr('releaseNotes'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colors.accentBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 140),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.black : Colors.grey.shade100)
                                  .withValues(alpha: isDark ? 0.35 : 0.6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.08),
                              ),
                            ),
                            child: SingleChildScrollView(
                              child: Text(
                                widget.packageInfo.releaseNotes?.trim().isNotEmpty == true
                                    ? widget.packageInfo.releaseNotes!
                                    : 'Bản phát hành bao gồm các cải tiến hiệu năng, tính năng mới và các bản vá lỗi bảo mật.',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  height: 1.45,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                          ),

                          // Progress Bar & Status (while updating)
                          if (_isUpdating) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progress,
                                backgroundColor: (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.08),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  theme.colors.accentBlue,
                                ),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  _statusText,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                                Text(
                                  '${(_progress * 100).toInt()}%',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colors.accentBlue,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          // Error Message if failed
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: theme.colors.accentRose.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: theme.colors.accentRose.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline_rounded,
                                    size: 16,
                                    color: theme.colors.accentRose,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colors.accentRose,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Action Buttons Footer
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: isDark ? 0.03 : 0.02),
                        border: Border(
                          top: BorderSide(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.08),
                            width: 0.8,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (!_isUpdating)
                            OutlinedButton(
                              key: const ValueKey('btn-update-later'),
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                foregroundColor:
                                    isDark ? Colors.white70 : Colors.black87,
                                side: BorderSide(
                                  color: (isDark ? Colors.white : Colors.black)
                                      .withValues(alpha: 0.16),
                                ),
                              ),
                              child: Text(lang.tr('updateLater')),
                            ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            key: const ValueKey('btn-update-now'),
                            onPressed: _isUpdating ? null : _startUpdate,
                            icon: _isUpdating
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor:
                                          AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.download_rounded, size: 16),
                            label: Text(
                              _isUpdating
                                  ? lang.tr('downloadingUpdate')
                                  : lang.tr('updateNow'),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colors.accentEmerald,
                              foregroundColor: Colors.white,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 8,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
