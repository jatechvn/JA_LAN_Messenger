import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../ime/ime_service.dart';
import '../../theme/theme_provider.dart';

class PinyinCandidateBar extends StatelessWidget {
  final TextEditingController textController;

  const PinyinCandidateBar({super.key, required this.textController});

  @override
  Widget build(BuildContext context) {
    final ime = ImeService.of(context, listen: true);
    final engine = ime.pinyinEngine;
    if (!engine.hasCandidates && engine.buffer.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = context.watch<ThemeProvider>();
    final candidates = engine.getCurrentPageCandidates();
    final isDark = theme.isDark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF1E293B).withValues(alpha: 0.88)
                  : Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colors.accentBlue.withValues(alpha: 0.35),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Chuỗi Pinyin đang gõ
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colors.accentBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    engine.buffer,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colors.accentBlue,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // 2. Danh sách ứng viên (1-5)
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: candidates.map((c) {
                        return InkWell(
                          onTap: () {
                            final committed = ime.selectPinyinCandidate(
                              c.index,
                            );
                            if (committed != null) {
                              _insertText(textController, committed);
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.index == 1
                                  ? theme.colors.accentBlue.withValues(
                                      alpha: 0.12,
                                    )
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: c.index == 1
                                  ? Border.all(
                                      color: theme.colors.accentBlue.withValues(
                                        alpha: 0.25,
                                      ),
                                    )
                                  : null,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${c.index}.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: c.index == 1
                                        ? theme.colors.accentBlue
                                        : (isDark
                                              ? Colors.white60
                                              : Colors.black45),
                                  ),
                                ),
                                const SizedBox(width: 3),
                                Text(
                                  c.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: c.index == 1
                                        ? FontWeight.w600
                                        : FontWeight.normal,
                                    color: isDark
                                        ? const Color(0xFFF1F5F9)
                                        : const Color(0xFF0F172A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const SizedBox(width: 6),

                // 3. Nút phân trang (Trang trước / sau)
                if (engine.totalPages > 1) ...[
                  InkWell(
                    onTap: engine.pageIndex > 0
                        ? () => ime.pinyinPrevPage()
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.chevron_left_rounded,
                        size: 18,
                        color: engine.pageIndex > 0
                            ? (isDark ? Colors.white70 : Colors.black87)
                            : (isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: engine.pageIndex + 1 < engine.totalPages
                        ? () => ime.pinyinNextPage()
                        : null,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: engine.pageIndex + 1 < engine.totalPages
                            ? (isDark ? Colors.white70 : Colors.black87)
                            : (isDark ? Colors.white24 : Colors.black26),
                      ),
                    ),
                  ),
                ],

                const SizedBox(width: 4),

                // 4. Nút hủy Esc
                InkWell(
                  onTap: () => ime.clearPinyin(),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _insertText(TextEditingController controller, String text) {
    final val = controller.value;
    final start = val.selection.start.clamp(0, val.text.length);
    final end = val.selection.end.clamp(0, val.text.length);

    final newText = val.text.replaceRange(start, end, text);
    final newOffset = start + text.length;
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
  }
}
