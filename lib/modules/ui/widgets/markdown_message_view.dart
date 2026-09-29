import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/quick_action_helper.dart';
import '../../services/image_clipboard_helper.dart';
import 'glass_image_lightbox.dart';
import 'package:provider/provider.dart';

/// Widget chuyên biệt để render nội dung tin nhắn dạng Markdown chuẩn
/// Hỗ trợ in đậm, in nghiêng, danh sách, và khối code lập trình với nút Copy 1-click.
class MarkdownMessageView extends StatelessWidget {
  final String text;
  final bool isMine;
  final bool isStreaming;
  final TextStyle? baseTextStyle;

  const MarkdownMessageView({
    super.key,
    required this.text,
    this.isMine = false,
    this.isStreaming = false,
    this.baseTextStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;

    // Khi AI đang stream, nếu khối code chưa đóng (số lượng ``` lẻ)
    // tự động đóng tạm thời để parser render trơn tru không bị vỡ giao diện.
    String renderedText = text;
    if (isStreaming && renderedText.isNotEmpty) {
      final codeFenceMatches = RegExp(r'```').allMatches(renderedText).length;
      if (codeFenceMatches.isOdd) {
        renderedText += '\n```';
      }
    }

    final defaultTextColor = isMine
        ? Colors.white
        : (isDark ? const Color(0xFFF8FAFC) : Colors.black87);

    final style =
        baseTextStyle ??
        TextStyle(color: defaultTextColor, fontSize: 13, height: 1.4);

    final markdownStyle = MarkdownStyleSheet.fromTheme(Theme.of(context))
        .copyWith(
          p: style,
          h1: style.copyWith(fontSize: 18, fontWeight: FontWeight.bold),
          h2: style.copyWith(fontSize: 16, fontWeight: FontWeight.bold),
          h3: style.copyWith(fontSize: 14.5, fontWeight: FontWeight.w700),
          h4: style.copyWith(fontSize: 13.5, fontWeight: FontWeight.w700),
          strong: style.copyWith(fontWeight: FontWeight.bold),
          em: style.copyWith(fontStyle: FontStyle.italic),
          listBullet: style.copyWith(fontWeight: FontWeight.bold),
          blockquote: style.copyWith(
            color: isMine
                ? Colors.white70
                : (isDark ? const Color(0xFF94A3B8) : Colors.black54),
            fontStyle: FontStyle.italic,
          ),
          blockquoteDecoration: BoxDecoration(
            color: (isDark ? const Color(0xFF0F172A) : Colors.black).withValues(
              alpha: isDark ? 0.60 : 0.05,
            ),
            borderRadius: BorderRadius.circular(4),
            border: Border(
              left: BorderSide(
                color: isDark
                    ? const Color(0xFF38BDF8)
                    : theme.colors.accentBlue,
                width: 3,
              ),
            ),
          ),
          code: TextStyle(
            fontFamily: 'Consolas',
            fontFamilyFallback: const [
              'Cascadia Code',
              'Courier New',
              'monospace',
            ],
            fontSize: 12,
            fontWeight: FontWeight.w600,
            backgroundColor: (isDark ? Colors.white : Colors.black).withValues(
              alpha: isDark ? 0.12 : 0.07,
            ),
            color: isMine
                ? Colors.white
                : (isDark ? Colors.cyanAccent.shade100 : Colors.blue.shade900),
          ),
          codeblockDecoration:
              const BoxDecoration(), // Được tùy biến qua CodeBlockBuilder
          a: style.copyWith(
            color: isMine
                ? Colors.cyanAccent.shade100
                : (isDark ? const Color(0xFF38BDF8) : theme.colors.accentBlue),
            decoration: TextDecoration.underline,
            decorationColor: isMine
                ? Colors.cyanAccent.shade100.withValues(alpha: 0.6)
                : (isDark
                      ? const Color(0xFF38BDF8).withValues(alpha: 0.6)
                      : theme.colors.accentBlue.withValues(alpha: 0.6)),
          ),
          tableHead: style.copyWith(fontWeight: FontWeight.bold),
          tableBody: style,
          tableBorder: TableBorder.all(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.15,
            ),
            width: 0.8,
          ),
        );

    return MarkdownBody(
      data: renderedText,
      selectable: true,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      styleSheet: markdownStyle,
      onTapLink: (text, href, title) {
        QuickActionHelper.handleActionUrl(
          context,
          href,
          lang: context.read<LanguageProvider>(),
        );
      },
      builders: {'pre': CodeBlockBuilder(isDark: isDark)},
      imageBuilder: (uri, title, alt) {
        final lang = context.read<LanguageProvider>();
        final isNetwork = uri.scheme == 'http' || uri.scheme == 'https';
        final isFile = uri.scheme == 'file' || uri.scheme.isEmpty;
        final filePath = isFile
            ? (uri.scheme == 'file' ? uri.toFilePath() : uri.path)
            : null;
        final file = filePath != null ? File(filePath) : null;
        final fileExists = file != null && file.existsSync();

        Widget imgWidget;
        if (isNetwork) {
          imgWidget = Image.network(
            uri.toString(),
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image_rounded, size: 40),
          );
        } else if (fileExists) {
          imgWidget = Image.file(
            file,
            errorBuilder: (context, error, stackTrace) =>
                const Icon(Icons.broken_image_rounded, size: 40),
          );
        } else {
          imgWidget = const Icon(Icons.image_not_supported_rounded, size: 40);
        }

        return Stack(
          alignment: Alignment.topRight,
          children: [
            InkWell(
              onTap: fileExists
                  ? () => showGlassImageLightbox(
                      context: context,
                      filePath: file.path,
                      fileName: alt ?? file.uri.pathSegments.last,
                    )
                  : null,
              borderRadius: BorderRadius.circular(8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: imgWidget,
              ),
            ),
            if (fileExists)
              Positioned(
                top: 6,
                right: 6,
                child: Tooltip(
                  message: lang.tr('copyImage'),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => ImageClipboardHelper.copyImageToClipboard(
                        context,
                        filePath: file.path,
                        lang: lang,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white30, width: 0.8),
                        ),
                        child: const Icon(
                          Icons.copy_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Builder tùy biến cho thẻ <pre> (khối mã nguồn fenced code blocks)
class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;

  CodeBlockBuilder({required this.isDark});

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    String language = '';
    String codeContent = element.textContent;

    // Trích xuất class language (ví dụ: language-python)
    if (element.children != null && element.children!.isNotEmpty) {
      final firstChild = element.children!.first;
      if (firstChild is md.Element) {
        final classAttr = firstChild.attributes['class'];
        if (classAttr != null && classAttr.startsWith('language-')) {
          language = classAttr.replaceFirst('language-', '').trim();
        }
      }
    }

    if (codeContent.endsWith('\n')) {
      codeContent = codeContent.substring(0, codeContent.length - 1);
    }

    return CodeBlockCard(code: codeContent, language: language, isDark: isDark);
  }
}

/// Widget hiển thị hộp Code Block với header ngôn ngữ và nút Copy mã
class CodeBlockCard extends StatefulWidget {
  final String code;
  final String language;
  final bool isDark;

  const CodeBlockCard({
    super.key,
    required this.code,
    this.language = '',
    required this.isDark,
  });

  @override
  State<CodeBlockCard> createState() => _CodeBlockCardState();
}

class _CodeBlockCardState extends State<CodeBlockCard> {
  bool _isCopied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _copyCode(LanguageProvider lang) {
    Clipboard.setData(ClipboardData(text: widget.code));
    setState(() {
      _isCopied = true;
    });
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _isCopied = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.watch<LanguageProvider>();
    final displayLang = widget.language.trim().isNotEmpty
        ? widget.language.trim()
        : 'code';

    // Nền tối thanh lịch cho hộp code (chuẩn developer trên cả Light & Dark theme)
    final blockBg = widget.isDark
        ? const Color(0xFF0B101B)
        : const Color(0xFF1E222B);
    final headerBg = widget.isDark
        ? const Color(0xFF0F172A)
        : Colors.black.withValues(alpha: 0.28);
    final borderColor = widget.isDark
        ? const Color(0x26FFFFFF)
        : Colors.black.withValues(alpha: 0.18);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: blockBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor, width: 0.8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.3 : 0.1),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header: Ngôn ngữ & Nút Copy mã
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: headerBg,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.code_rounded,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      displayLang.toLowerCase(),
                      style: TextStyle(
                        fontFamily: 'Consolas',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.75),
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
                InkWell(
                  onTap: () => _copyCode(lang),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 13,
                          color: _isCopied
                              ? Colors.greenAccent
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isCopied
                              ? lang.tr('codeCopied')
                              : lang.tr('copyCode'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: _isCopied
                                ? Colors.greenAccent
                                : Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.6,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          // Body: Nội dung mã nguồn với cuộn ngang
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(12),
            child: SelectableText(
              widget.code,
              style: const TextStyle(
                fontFamily: 'Consolas',
                fontFamilyFallback: [
                  'Cascadia Code',
                  'Courier New',
                  'monospace',
                ],
                fontSize: 12.5,
                height: 1.45,
                color: Color(0xFFE2E8F0),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
