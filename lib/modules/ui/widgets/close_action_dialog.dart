import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/app_power_manager.dart';

/// Glassmorphic dialog prompting user choice on window close:
/// - Minimize to tray
/// - Exit application
/// - Remember choice
class CloseActionDialog extends StatefulWidget {
  final String initialAction;

  const CloseActionDialog({super.key, this.initialAction = 'minimize'});

  static Future<Map<String, dynamic>?> show(BuildContext context) {
    return showGeneralDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'CloseActionDialog',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim1, anim2) => const CloseActionDialog(),
      transitionBuilder: (ctx, anim1, anim2, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: AppPowerManager.instance.indicatorsAnimationNotifier,
          builder: (_, active, _) {
            // A paused Navigator ticker must not leave the close prompt invisible.
            if (!active) return child;
            return FadeTransition(
              opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(
                  CurvedAnimation(parent: anim1, curve: Curves.easeOut),
                ),
                child: child,
              ),
            );
          },
        );
      },
    );
  }

  @override
  State<CloseActionDialog> createState() => _CloseActionDialogState();
}

class _CloseActionDialogState extends State<CloseActionDialog> {
  late String _selectedAction;
  bool _rememberChoice = false;

  @override
  void initState() {
    super.initState();
    _selectedAction = widget.initialAction == 'exit' ? 'exit' : 'minimize';
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final colors = theme.colors;
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    return Center(
      child: Container(
        width: 440,
        margin: const EdgeInsets.all(24),
        child: Stack(
          children: [
            // Glass backdrop filter
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18.0, sigmaY: 18.0),
                  child: Container(
                    color: (isDark ? const Color(0xFF1E293B) : Colors.white)
                        .withValues(alpha: isDark ? 0.90 : 0.92),
                  ),
                ),
              ),
            ),

            // Dialog content
            Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: isDark ? 0.14 : 0.08,
                    ),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.45 : 0.12,
                      ),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title Bar
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: colors.accentBlue.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.exit_to_app_rounded,
                            color: colors.accentBlue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                lang.tr('closeDialogTitle'),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                lang.tr('closeDialogPrompt'),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: isDark
                                      ? Colors.white60
                                      : Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // Options Container
                    Container(
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.black : Colors.white)
                            .withValues(alpha: isDark ? 0.25 : 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: isDark ? 0.08 : 0.05),
                        ),
                      ),
                      child: RadioGroup<String>(
                        groupValue: _selectedAction,
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedAction = val);
                          }
                        },
                        child: Column(
                          children: [
                            InkWell(
                              onTap: () =>
                                  setState(() => _selectedAction = 'minimize'),
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: 'minimize',
                                      activeColor: colors.accentBlue,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            lang.tr('closeActionMinimize'),
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black87,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            lang.tr('realtimeListening'),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white54
                                                  : Colors.black45,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            Divider(
                              height: 1,
                              thickness: 1,
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.06),
                            ),
                            InkWell(
                              onTap: () =>
                                  setState(() => _selectedAction = 'exit'),
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(10),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    Radio<String>(
                                      value: 'exit',
                                      activeColor: colors.accentRose,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        lang.tr('closeActionExit'),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
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

                    const SizedBox(height: 12),

                    // Remember Choice Checkbox
                    InkWell(
                      onTap: () =>
                          setState(() => _rememberChoice = !_rememberChoice),
                      borderRadius: BorderRadius.circular(6),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _rememberChoice,
                              activeColor: colors.accentBlue,
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _rememberChoice = val);
                                }
                              },
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                lang.tr('rememberChoice'),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Actions (Cancel, Confirm)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(null),
                          style: TextButton.styleFrom(
                            foregroundColor: isDark
                                ? Colors.white60
                                : Colors.black54,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                          ),
                          child: Text(
                            lang.tr('cancel'),
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop({
                              'action': _selectedAction,
                              'remember': _rememberChoice,
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _selectedAction == 'exit'
                                ? colors.accentRose
                                : colors.accentBlue,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            lang.tr('confirm'),
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
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
      ),
    );
  }
}
