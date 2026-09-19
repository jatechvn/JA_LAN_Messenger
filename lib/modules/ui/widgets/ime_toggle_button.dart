import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../ime/ime_service.dart';
import '../../ime/ime_types.dart';
import '../../localization/app_locale.dart';
import '../../theme/theme_provider.dart';

class ImeToggleButton extends StatelessWidget {
  final double size;
  const ImeToggleButton({super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final ime = ImeService.of(context, listen: true);
    final lang = context.watch<LanguageProvider>();
    final theme = context.watch<ThemeProvider>();
    final isDark = theme.isDark;
    final state = ime.engineState;
    final mode = ime.effectiveMode;

        Color pillColor;
        Color textColor;
        Widget iconWidget;
        String labelText;
        String tooltipText;

        if (state == ImeEngineState.bypassedExternal) {
          pillColor = theme.colors.accentAmber.withValues(alpha: 0.15);
          textColor = theme.colors.accentAmber;
          iconWidget = Icon(
            Icons.shield_outlined,
            size: 13,
            color: theme.colors.accentAmber,
          );
          labelText = ime.shortStatusLabel;
          tooltipText =
              '${lang.tr('imeBypassedDesc')}: ${ime.detectedExternalIme.imeName ?? 'External IME'}';
        } else {
          switch (mode) {
            case ImeMode.telex:
              pillColor = theme.colors.accentEmerald.withValues(alpha: 0.15);
              textColor = theme.colors.accentEmerald;
              iconWidget = const Text(
                '🇻🇳',
                style: TextStyle(fontSize: 11),
              );
              labelText = 'TELEX';
              tooltipText =
                  '${lang.tr('imeTelex')} (Ctrl+Shift)';
              break;
            case ImeMode.pinyin:
              pillColor = theme.colors.accentBlue.withValues(alpha: 0.15);
              textColor = theme.colors.accentBlue;
              iconWidget = const Text(
                '🇨🇳',
                style: TextStyle(fontSize: 11),
              );
              labelText = '拼音';
              tooltipText =
                  '${lang.tr('imePinyin')} (Ctrl+Shift)';
              break;
            case ImeMode.off:
            case ImeMode.auto:
              pillColor = isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.05);
              textColor = isDark ? Colors.white60 : Colors.black54;
              iconWidget = Icon(
                Icons.keyboard_outlined,
                size: 13,
                color: textColor,
              );
              labelText = 'EN';
              tooltipText =
                  '${lang.tr('imeOff')} (Ctrl+Shift)';
              break;
          }
        }

        return Tooltip(
          message: tooltipText,
          child: PopupMenuButton<ImeMode>(
            tooltip: '',
            offset: const Offset(0, -170),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.1),
              ),
            ),
            color: isDark ? const Color(0xFF1E293B) : Colors.white,
            onSelected: (newMode) => ime.setMode(newMode),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: ImeMode.auto,
                child: Row(
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 15,
                      color: ime.mode == ImeMode.auto
                          ? theme.colors.accentBlue
                          : (isDark ? Colors.white54 : Colors.black45),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lang.tr('imeAuto'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: ime.mode == ImeMode.auto
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: ime.mode == ImeMode.auto
                              ? theme.colors.accentBlue
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ImeMode.telex,
                child: Row(
                  children: [
                    const Text('🇻🇳', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lang.tr('imeTelex'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: ime.mode == ImeMode.telex
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: ime.mode == ImeMode.telex
                              ? theme.colors.accentEmerald
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: ImeMode.pinyin,
                child: Row(
                  children: [
                    const Text('🇨🇳', style: TextStyle(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lang.tr('imePinyin'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: ime.mode == ImeMode.pinyin
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: ime.mode == ImeMode.pinyin
                              ? theme.colors.accentBlue
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(height: 8),
              PopupMenuItem(
                value: ImeMode.off,
                child: Row(
                  children: [
                    Icon(
                      Icons.block_rounded,
                      size: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        lang.tr('imeOff'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: ime.mode == ImeMode.off
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            child: InkWell(
              onTap: () => ime.cycleMode(),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                height: size,
                padding: const EdgeInsets.symmetric(horizontal: 7),
                decoration: BoxDecoration(
                  color: pillColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: textColor.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconWidget,
                    const SizedBox(width: 4),
                    Text(
                      labelText,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                        letterSpacing: 0.3,
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
