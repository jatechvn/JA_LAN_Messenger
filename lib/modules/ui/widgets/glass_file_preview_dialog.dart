import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import 'bounce_marquee_text.dart';
import 'glass_image_lightbox.dart';

/// Helper to open a file with system default handler
void _openSystemFile(String path) {
  if (Platform.isWindows) {
    Process.run('cmd', ['/c', 'start', '', path]);
  } else if (Platform.isMacOS) {
    Process.run('open', [path]);
  } else if (Platform.isLinux) {
    Process.run('xdg-open', [path]);
  }
}

/// Helper to open enclosing folder in file manager
void _openSystemFolder(String path) {
  if (Platform.isWindows) {
    Process.run('explorer.exe', ['/select,', path]);
  } else if (Platform.isMacOS) {
    Process.run('open', ['-R', path]);
  } else if (Platform.isLinux) {
    final parent = File(path).parent.path;
    Process.run('xdg-open', [parent]);
  }
}

/// Helper function to display image lightbox or file preview dialog
Future<void> showGlassFilePreview({
  required BuildContext context,
  required String filePath,
  required String fileName,
  VoidCallback? onOpenFolder,
}) {
  if (MessengerCoordinator.isImageFile(filePath)) {
    return showGlassImageLightbox(
      context: context,
      filePath: filePath,
      fileName: fileName,
      onOpenFolder: onOpenFolder,
    );
  }

  final theme = ThemeProvider.of(context, listen: false);
  final isDark = theme.isDark;

  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'GlassFilePreviewDialog',
    barrierColor: isDark
        ? Colors.black.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, anim1, anim2) => GlassFilePreviewDialog(
      filePath: filePath,
      fileName: fileName,
      onOpenFolder: onOpenFolder,
    ),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.94,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic)),
          child: child,
        ),
      );
    },
  );
}

/// Bento Frosted Glass File Preview Dialog
class GlassFilePreviewDialog extends StatefulWidget {
  final String filePath;
  final String fileName;
  final VoidCallback? onOpenFolder;

  const GlassFilePreviewDialog({
    super.key,
    required this.filePath,
    required this.fileName,
    this.onOpenFolder,
  });

  @override
  State<GlassFilePreviewDialog> createState() => _GlassFilePreviewDialogState();
}

class _GlassFilePreviewDialogState extends State<GlassFilePreviewDialog> {
  static const int _maxPreviewBytes = 49152; // 48 KB
  static const Set<String> _textFileExtensions = {
    'txt',
    'log',
    'md',
    'json',
    'dart',
    'yaml',
    'yml',
    'xml',
    'csv',
    'tsv',
    'py',
    'js',
    'ts',
    'html',
    'htm',
    'css',
    'scss',
    'c',
    'cpp',
    'h',
    'hpp',
    'cs',
    'java',
    'kt',
    'rs',
    'go',
    'sh',
    'bat',
    'cmd',
    'ps1',
    'sql',
    'ini',
    'cfg',
    'conf',
    'properties',
    'env',
  };

  bool _isLoading = true;
  String? _textContent;
  bool _isTruncated = false;
  int _fileSize = 0;
  bool _fileExists = false;
  DateTime? _modifiedTime;

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  String get _fileExtension {
    final name = widget.fileName;
    final dot = name.lastIndexOf('.');
    if (dot != -1 && dot < name.length - 1) {
      return name.substring(dot + 1).toLowerCase();
    }
    return '';
  }

  bool get _isTextFile => _textFileExtensions.contains(_fileExtension);

  void _loadFile() {
    final file = File(widget.filePath);
    if (!file.existsSync()) {
      _fileExists = false;
      _isLoading = false;
      return;
    }

    try {
      final stat = file.statSync();
      _fileSize = stat.size;
      _modifiedTime = stat.modified;
      _fileExists = true;

      if (_isTextFile) {
        final toRead = _fileSize > _maxPreviewBytes
            ? _maxPreviewBytes
            : _fileSize;
        final raf = file.openSync();
        late List<int> bytes;
        try {
          bytes = raf.readSync(toRead);
        } finally {
          raf.closeSync();
        }
        _isTruncated = _fileSize > _maxPreviewBytes;
        try {
          _textContent = utf8.decode(bytes, allowMalformed: true);
        } catch (_) {
          _textContent = String.fromCharCodes(bytes);
        }
      }
    } catch (_) {
      // Ignored
    } finally {
      _isLoading = false;
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _getFileTypeDescription(String ext) {
    switch (ext) {
      case 'pdf':
        return 'Tài liệu PDF (.pdf)';
      case 'doc':
      case 'docx':
        return 'Tài liệu Microsoft Word (.docx)';
      case 'xls':
      case 'xlsx':
      case 'csv':
        return 'Bảng tính Excel / CSV (.xlsx)';
      case 'ppt':
      case 'pptx':
        return 'Bản trình chiếu PowerPoint (.pptx)';
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return 'Tệp tin nén lưu trữ (Archive)';
      case 'txt':
      case 'log':
        return 'Tập tin văn bản thuần (Text / Log)';
      case 'md':
        return 'Tài liệu Markdown (.md)';
      case 'dart':
        return 'Mã nguồn Dart (.dart)';
      case 'json':
      case 'yaml':
      case 'yml':
      case 'xml':
        return 'Tập tin cấu hình / Dữ liệu ($ext)';
      case 'py':
      case 'js':
      case 'ts':
      case 'cpp':
      case 'c':
      case 'h':
      case 'cs':
      case 'java':
      case 'rs':
      case 'go':
        return 'Mã nguồn lập trình (Source Code)';
      case 'bat':
      case 'cmd':
      case 'ps1':
      case 'sh':
        return 'Kịch bản lệnh (Shell Script)';
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return 'Tệp âm thanh (Audio)';
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return 'Tệp video (Video)';
      case 'exe':
      case 'msi':
        return 'Chương trình ứng dụng thực thi (Executable)';
      default:
        return ext.isNotEmpty ? 'Tệp $ext' : 'Tập tin (File)';
    }
  }

  Color _getExtensionColor(String ext, ThemeProvider theme) {
    switch (ext) {
      case 'pdf':
      case 'doc':
      case 'docx':
        return theme.colors.accentBlue;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return theme.colors.accentEmerald;
      case 'ppt':
      case 'pptx':
        return const Color(0xFFF97316);
      case 'zip':
      case 'rar':
      case '7z':
        return theme.colors.accentAmber;
      case 'dart':
      case 'py':
      case 'json':
      case 'ts':
      case 'js':
      case 'cpp':
      case 'rs':
        return const Color(0xFFA855F7);
      default:
        return theme.colors.accentBlue;
    }
  }

  IconData _getExtensionIcon(String ext) {
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      case 'txt':
      case 'log':
        return Icons.text_snippet_rounded;
      case 'md':
        return Icons.article_rounded;
      case 'dart':
      case 'py':
      case 'js':
      case 'ts':
      case 'cpp':
      case 'cs':
      case 'java':
      case 'rs':
      case 'go':
      case 'json':
      case 'yaml':
      case 'xml':
        return Icons.code_rounded;
      case 'bat':
      case 'sh':
      case 'ps1':
        return Icons.terminal_rounded;
      case 'mp3':
      case 'wav':
        return Icons.audiotrack_rounded;
      case 'mp4':
      case 'mkv':
        return Icons.video_file_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  void _copyPathToClipboard(LanguageProvider lang) {
    Clipboard.setData(ClipboardData(text: widget.filePath));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.tr('pathCopied')),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;
    final ext = _fileExtension;
    final extColor = _getExtensionColor(ext, theme);
    final extIcon = _getExtensionIcon(ext);

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
      child: Material(
        color: Colors.transparent,
        child: Center(
          child: Container(
            width: 660,
            height: 520,
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF0F172A).withValues(alpha: 0.90)
                  : Colors.white.withValues(alpha: 0.96),
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
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top Header
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
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
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: extColor.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(extIcon, size: 18, color: extColor),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BounceMarqueeText(
                                  text: widget.fileName,
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _fileExists
                                      ? '${_formatSize(_fileSize)} • ${_getFileTypeDescription(ext)}'
                                      : lang.tr('fileNotFound'),
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
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

                    // File Path strip with quick copy
                    Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      color: (isDark ? Colors.black : Colors.grey.shade100)
                          .withValues(alpha: isDark ? 0.35 : 0.6),
                      child: Row(
                        children: [
                          Icon(
                            Icons.folder_outlined,
                            size: 13,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              widget.filePath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontFamily: 'Consolas, monospace',
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _copyPathToClipboard(lang),
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.copy_rounded,
                                    size: 11,
                                    color: theme.colors.accentBlue,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    lang.tr('copyPath'),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: theme.colors.accentBlue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Body Content Area
                    Expanded(
                      child: _isLoading
                          ? const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : !_fileExists
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      size: 48,
                                      color: theme.colors.accentRose,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      lang.tr('fileNotFound'),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: isDark
                                            ? Colors.white70
                                            : Colors.black87,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : _isTextFile
                          ? _buildTextPreview(isDark, theme, lang)
                          : _buildBinaryPreview(
                              isDark,
                              theme,
                              lang,
                              extColor,
                              extIcon,
                              ext,
                            ),
                    ),

                    // Bottom Action Toolbar
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.end,
                        children: [
                          if (_modifiedTime != null)
                            Text(
                              'Sửa đổi: ${_modifiedTime!.hour.toString().padLeft(2, '0')}:${_modifiedTime!.minute.toString().padLeft(2, '0')} ${_modifiedTime!.day}/${_modifiedTime!.month}/${_modifiedTime!.year}',
                              style: TextStyle(
                                fontSize: 10.5,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          // Open Folder Button
                          OutlinedButton.icon(
                            onPressed: () {
                              if (widget.onOpenFolder != null) {
                                widget.onOpenFolder!();
                              } else {
                                _openSystemFolder(widget.filePath);
                              }
                            },
                            icon: const Icon(
                              Icons.folder_open_rounded,
                              size: 14,
                            ),
                            label: Text(lang.tr('openFolder')),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(fontSize: 11.5),
                              foregroundColor: isDark
                                  ? Colors.white70
                                  : Colors.black87,
                              side: BorderSide(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: 0.16),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Open File Button
                          FilledButton.icon(
                            onPressed: () {
                              _openSystemFile(widget.filePath);
                            },
                            icon: const Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                            ),
                            label: Text(lang.tr('openWithApp')),
                            style: FilledButton.styleFrom(
                              backgroundColor: theme.colors.accentBlue,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
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

  Widget _buildTextPreview(
    bool isDark,
    ThemeProvider theme,
    LanguageProvider lang,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_isTruncated)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: theme.colors.accentAmber.withValues(alpha: 0.12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 13,
                  color: theme.colors.accentAmber,
                ),
                const SizedBox(width: 6),
                Text(
                  lang.tr('textPreviewTruncated', ['48 KB']),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: theme.colors.accentAmber,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF030712) : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(
                    _textContent ?? '',
                    style: TextStyle(
                      fontFamily: 'Consolas, monospace',
                      fontSize: 12,
                      height: 1.45,
                      color: isDark
                          ? const Color(0xFFE2E8F0)
                          : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBinaryPreview(
    bool isDark,
    ThemeProvider theme,
    LanguageProvider lang,
    Color extColor,
    IconData extIcon,
    String ext,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: extColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(
                  color: extColor.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
              child: Icon(extIcon, size: 36, color: extColor),
            ),
            const SizedBox(height: 16),
            Text(
              widget.fileName,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_formatSize(_fileSize)} • ${_getFileTypeDescription(ext)}',
              style: TextStyle(
                fontSize: 11.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 420,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.04,
                ),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: (isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.07,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      lang.tr('binaryNoPreview'),
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
