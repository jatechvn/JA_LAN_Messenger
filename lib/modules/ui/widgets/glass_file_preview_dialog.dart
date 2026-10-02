import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import 'bounce_marquee_text.dart';
import '../../services/file_preview_inspector.dart';
export '../../services/file_preview_inspector.dart'
    show ZipArchiveEntry, readZipCentralDirectory, readXlsxSheetNames;
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

/// Formats first N bytes into classic monospace Hex Dump (Offset, Hex, ASCII)
String generateHexDump(List<int> bytes, {int maxBytes = 2048}) {
  final buffer = StringBuffer();
  final takeCount = bytes.length < maxBytes ? bytes.length : maxBytes;
  for (int i = 0; i < takeCount; i += 16) {
    final offsetStr = i.toRadixString(16).padLeft(8, '0');
    final rowEnd = (i + 16 < takeCount) ? i + 16 : takeCount;
    final rowBytes = bytes.sublist(i, rowEnd);

    final hexParts = <String>[];
    for (int j = 0; j < 16; j++) {
      if (j < rowBytes.length) {
        hexParts.add(
          rowBytes[j].toRadixString(16).padLeft(2, '0').toUpperCase(),
        );
      } else {
        hexParts.add('  ');
      }
    }

    final hex1 = hexParts.sublist(0, 8).join(' ');
    final hex2 = hexParts.sublist(8, 16).join(' ');

    final asciiChars = rowBytes.map((b) {
      if (b >= 32 && b <= 126) {
        return String.fromCharCode(b);
      }
      return '.';
    }).join();

    buffer.writeln('$offsetStr  $hex1  $hex2  |$asciiChars|');
  }
  return buffer.toString();
}

/// Bento Frosted Glass File Preview Dialog with Smart Binary Inspection & Tap-Outside Dismissal
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
  DateTime? _createdTime;

  // Smart Inspector state
  int _selectedBinaryTab = 0; // 0: Overview, 1: Contents / Sheets, 2: Hex View
  List<ZipArchiveEntry> _zipEntries = [];
  List<String> _officeSheets = [];
  String? _sha256Hash;
  bool _hashFailed = false;
  String? _defaultApp;
  String? _hexDump;

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
      _createdTime = stat.changed;
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
      } else {
        // Read first 2 KB for Hex dump
        final toRead = _fileSize > 2048 ? 2048 : _fileSize;
        if (toRead > 0) {
          final raf = file.openSync();
          late List<int> bytes;
          try {
            bytes = raf.readSync(toRead);
          } finally {
            raf.closeSync();
          }
          _hexDump = generateHexDump(bytes, maxBytes: 2048);
        }

        _loadArchiveMetadata();
        _calculateSha256();
        queryDefaultFileApplication(_fileExtension).then((value) {
          if (mounted) setState(() => _defaultApp = value);
        });
      }
    } catch (_) {
      // Ignored
    } finally {
      _isLoading = false;
    }
  }

  Future<void> _loadArchiveMetadata() async {
    final path = widget.filePath;
    final ext = _fileExtension;
    if (!{'zip', 'jar', 'apk', 'xlsx', 'docx', 'pptx'}.contains(ext)) return;
    final result = await inspectFileArchive(path, ext);
    if (!mounted) return;
    setState(() {
      _zipEntries = result.entries;
      _officeSheets = result.sheets;
    });
  }

  Future<void> _calculateSha256() async {
    try {
      final hash = await calculateFileSha256(widget.filePath);
      if (mounted) setState(() => _sha256Hash = hash);
    } catch (_) {
      if (mounted) setState(() => _hashFailed = true);
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

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--:--';
    return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} ${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  String _getFileTypeDescription(String ext) {
    final lang = context.read<LanguageProvider>();
    switch (ext) {
      case 'pdf':
        return lang.tr('previewTypePdf');
      case 'doc':
      case 'docx':
        return lang.tr('previewTypeWord');
      case 'xls':
      case 'xlsx':
      case 'csv':
        return lang.tr('previewSpreadsheet');
      case 'ppt':
      case 'pptx':
        return lang.tr('previewTypePresentation');
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return lang.tr('previewTypeArchive');
      case 'txt':
      case 'log':
        return lang.tr('previewTypeText');
      case 'md':
        return lang.tr('previewTypeMarkdown');
      case 'dart':
        return lang.tr('previewTypeSource');
      case 'json':
      case 'yaml':
      case 'yml':
      case 'xml':
        return lang.tr('previewTypeConfig');
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
        return lang.tr('previewTypeSource');
      case 'bat':
      case 'cmd':
      case 'ps1':
      case 'sh':
        return lang.tr('previewTypeScript');
      case 'mp3':
      case 'wav':
      case 'flac':
      case 'aac':
        return lang.tr('previewTypeAudio');
      case 'mp4':
      case 'mkv':
      case 'avi':
      case 'mov':
        return lang.tr('previewTypeVideo');
      case 'exe':
      case 'msi':
        return lang.tr('previewTypeExecutable');
      default:
        return ext.isNotEmpty
            ? '.${ext.toUpperCase()}'
            : lang.tr('previewTypeFile');
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

  Future<void> _copyFileToClipboard(LanguageProvider lang) async {
    try {
      final ok = await Pasteboard.writeFiles([widget.filePath]);
      if (!mounted) return;
      if (!ok) {
        _copyPathToClipboard(lang);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(lang.tr('fileCopied')),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (mounted) _copyPathToClipboard(lang);
    }
  }

  void _copyHashToClipboard(LanguageProvider lang) {
    if (_sha256Hash == null || _sha256Hash!.isEmpty) return;
    Clipboard.setData(ClipboardData(text: _sha256Hash!));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(lang.tr('hashCopied')),
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
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.enter ||
              event.logicalKey == LogicalKeyboardKey.numpadEnter) {
            _openSystemFile(widget.filePath);
            return KeyEventResult.handled;
          }
          final isCtrlOrCmd =
              HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed;
          final isShift = HardwareKeyboard.instance.isShiftPressed;
          if (isCtrlOrCmd) {
            if (event.logicalKey == LogicalKeyboardKey.keyO) {
              if (widget.onOpenFolder != null) {
                widget.onOpenFolder!();
              } else {
                _openSystemFolder(widget.filePath);
              }
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.keyC) {
              if (isShift) {
                _copyPathToClipboard(lang);
              } else {
                _copyFileToClipboard(lang);
              }
              return KeyEventResult.handled;
            }
          }
        }
        return KeyEventResult.ignored;
      },
      // Outer GestureDetector: Clicking anywhere on the backdrop closes the dialog
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.of(context).pop(),
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final dialogWidth = math.min(
                  680.0,
                  math.max(260.0, constraints.maxWidth - 24.0),
                );
                final dialogHeight = math.min(
                  540.0,
                  math.max(300.0, constraints.maxHeight - 24.0),
                );
                return GestureDetector(
                  // Inner GestureDetector: Prevent clicks inside the dialog card from closing
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Container(
                    width: dialogWidth,
                    height: dialogHeight,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0F172A).withValues(alpha: 0.92)
                          : Colors.white.withValues(alpha: 0.97),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: (isDark ? Colors.white : Colors.black)
                            .withValues(alpha: isDark ? 0.14 : 0.09),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.55 : 0.18,
                          ),
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
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                12,
                                12,
                              ),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: isDark ? 0.04 : 0.03),
                                border: Border(
                                  bottom: BorderSide(
                                    color:
                                        (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.08),
                                    width: 0.8,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 34,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: extColor.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      extIcon,
                                      size: 19,
                                      color: extColor,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
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
                                    icon: const Icon(
                                      Icons.close_rounded,
                                      size: 18,
                                    ),
                                    tooltip: lang.tr('closeDialog'),
                                    splashRadius: 18,
                                    color: isDark
                                        ? Colors.white70
                                        : Colors.black54,
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                  ),
                                ],
                              ),
                            ),

                            // File Path strip with quick copy path
                            Container(
                              height: 30,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              color:
                                  (isDark ? Colors.black : Colors.grey.shade100)
                                      .withValues(alpha: isDark ? 0.35 : 0.6),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.folder_outlined,
                                    size: 13,
                                    color: isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      widget.filePath,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontFamily: 'Consolas, monospace',
                                        color: isDark
                                            ? Colors.white60
                                            : Colors.black54,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  // Copy Path Chip
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
                                  : _buildSmartBinaryInspector(
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
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                10,
                                16,
                                10,
                              ),
                              decoration: BoxDecoration(
                                color: (isDark ? Colors.white : Colors.black)
                                    .withValues(alpha: isDark ? 0.03 : 0.02),
                                border: Border(
                                  top: BorderSide(
                                    color:
                                        (isDark ? Colors.white : Colors.black)
                                            .withValues(alpha: 0.08),
                                    width: 0.8,
                                  ),
                                ),
                              ),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                alignment: WrapAlignment.end,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (_modifiedTime != null)
                                    Text(
                                      '${lang.tr('modifiedTime')}: ${_formatDateTime(_modifiedTime)}',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: isDark
                                            ? Colors.white38
                                            : Colors.black38,
                                      ),
                                    ),
                                  const SizedBox(width: 8),
                                  // Copy File Button
                                  OutlinedButton.icon(
                                    onPressed: () => _copyFileToClipboard(lang),
                                    icon: const Icon(
                                      Icons.copy_rounded,
                                      size: 14,
                                    ),
                                    label: Text(lang.tr('copyFile')),
                                    style: OutlinedButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 6,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 11.5,
                                      ),
                                      foregroundColor: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      side: BorderSide(
                                        color:
                                            (isDark
                                                    ? Colors.white
                                                    : Colors.black)
                                                .withValues(alpha: 0.16),
                                      ),
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
                                      textStyle: const TextStyle(
                                        fontSize: 11.5,
                                      ),
                                      foregroundColor: isDark
                                          ? Colors.white70
                                          : Colors.black87,
                                      side: BorderSide(
                                        color:
                                            (isDark
                                                    ? Colors.white
                                                    : Colors.black)
                                                .withValues(alpha: 0.16),
                                      ),
                                    ),
                                  ),
                                  // Open File Button (Primary)
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
                );
              },
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

  /// Modern Bento Smart Inspector for binary, office, archives and unsupported preview formats
  Widget _buildSmartBinaryInspector(
    bool isDark,
    ThemeProvider theme,
    LanguageProvider lang,
    Color extColor,
    IconData extIcon,
    String ext,
  ) {
    final hasArchiveOrOfficeEntries =
        _zipEntries.isNotEmpty || _officeSheets.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab Header selector
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: BoxDecoration(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: isDark ? 0.03 : 0.02,
            ),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.07,
                ),
                width: 0.8,
              ),
            ),
          ),
          child: Row(
            children: [
              _buildTabButton(
                title: lang.tr('tabOverview'),
                icon: Icons.dashboard_outlined,
                index: 0,
                isDark: isDark,
                theme: theme,
              ),
              const SizedBox(width: 8),
              if (hasArchiveOrOfficeEntries) ...[
                _buildTabButton(
                  title: ext == 'xlsx'
                      ? lang.tr('sheetsFound', [_officeSheets.length])
                      : lang.tr('tabContents'),
                  icon: ext == 'xlsx'
                      ? Icons.table_chart_outlined
                      : Icons.folder_zip_outlined,
                  index: 1,
                  isDark: isDark,
                  theme: theme,
                ),
                const SizedBox(width: 8),
              ],
              _buildTabButton(
                title: lang.tr('tabHexView'),
                icon: Icons.data_object_rounded,
                index: 2,
                isDark: isDark,
                theme: theme,
              ),
            ],
          ),
        ),

        // Tab Content Area
        Expanded(
          child: _selectedBinaryTab == 0
              ? _buildOverviewTab(isDark, theme, lang, extColor, extIcon, ext)
              : _selectedBinaryTab == 1 && hasArchiveOrOfficeEntries
              ? _buildContentsTab(isDark, theme, lang, extColor, ext)
              : _buildHexViewTab(isDark, theme, lang),
        ),
      ],
    );
  }

  Widget _buildTabButton({
    required String title,
    required IconData icon,
    required int index,
    required bool isDark,
    required ThemeProvider theme,
  }) {
    final isSelected = _selectedBinaryTab == index;
    return InkWell(
      onTap: () => setState(() => _selectedBinaryTab = index),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colors.accentBlue.withValues(alpha: isDark ? 0.22 : 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? theme.colors.accentBlue.withValues(alpha: 0.4)
                : Colors.transparent,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected
                  ? theme.colors.accentBlue
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(width: 5),
            Text(
              title,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? theme.colors.accentBlue
                    : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tab 0: Overview & Bento Grid
  Widget _buildOverviewTab(
    bool isDark,
    ThemeProvider theme,
    LanguageProvider lang,
    Color extColor,
    IconData extIcon,
    String ext,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Hero File Card with double-click action
          InkWell(
            onDoubleTap: () => _openSystemFile(widget.filePath),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: extColor.withValues(alpha: isDark ? 0.08 : 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: extColor.withValues(alpha: 0.22),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: extColor.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: extColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(extIcon, size: 28, color: extColor),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.fileName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_formatSize(_fileSize)} • ${_getFileTypeDescription(ext)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          lang.tr('pressEnterToOpen'),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: extColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Notice banner for binary/document files
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
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
                  size: 15,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    lang.tr('binaryNoPreview'),
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark ? Colors.white70 : Colors.black87,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Responsive Bento Tiles Grid
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 460;
              final tile1 = _buildBentoCard(
                isDark: isDark,
                icon: Icons.launch_rounded,
                iconColor: theme.colors.accentBlue,
                title: lang.tr('openWithAppHint'),
                content: _defaultApp ?? lang.tr('previewDefaultAppUnknown'),
                subtitle: ext.isNotEmpty
                    ? lang.tr('previewAssociation', [ext])
                    : null,
              );
              final tile2 = _buildBentoCard(
                isDark: isDark,
                icon: Icons.security_rounded,
                iconColor: theme.colors.accentEmerald,
                title: lang.tr('sha256Hash'),
                content: _sha256Hash != null
                    ? (_sha256Hash!.length > 20
                          ? '${_sha256Hash!.substring(0, 16)}...${_sha256Hash!.substring(_sha256Hash!.length - 8)}'
                          : _sha256Hash!)
                    : lang.tr(
                        _hashFailed ? 'previewHashError' : 'previewHashLoading',
                      ),
                trailing: _sha256Hash != null && _sha256Hash!.length > 20
                    ? IconButton(
                        icon: const Icon(Icons.copy_rounded, size: 14),
                        tooltip: lang.tr('hashCopied'),
                        onPressed: () => _copyHashToClipboard(lang),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      )
                    : null,
              );
              final tile3 = _buildBentoCard(
                isDark: isDark,
                icon: Icons.access_time_rounded,
                iconColor: const Color(0xFFF97316),
                title: '${lang.tr('createdTime')} / ${lang.tr('modifiedTime')}',
                content: _formatDateTime(_modifiedTime),
                subtitle: _createdTime != null
                    ? lang.tr('previewCreated', [_formatDateTime(_createdTime)])
                    : null,
              );
              final tile4 = _buildBentoCard(
                isDark: isDark,
                icon: ext == 'xlsx'
                    ? Icons.table_chart_rounded
                    : ext == 'zip'
                    ? Icons.folder_zip_rounded
                    : Icons.info_outline_rounded,
                iconColor: extColor,
                title: lang.tr('previewFormatInfo'),
                content: ext == 'xlsx'
                    ? (_officeSheets.isNotEmpty
                          ? lang.tr('sheetsFound', [
                              _officeSheets.length.toString(),
                            ])
                          : lang.tr('previewSpreadsheet'))
                    : ext == 'zip'
                    ? lang.tr('archiveFilesCount', [
                        _zipEntries.length > 100
                            ? '100+'
                            : _zipEntries.length.toString(),
                      ])
                    : lang.tr('previewReady'),
                subtitle: ext == 'xlsx' || ext == 'zip'
                    ? lang.tr('previewContentsHint')
                    : null,
              );

              if (isNarrow) {
                return Column(
                  children: [
                    tile1,
                    const SizedBox(height: 8),
                    tile2,
                    const SizedBox(height: 8),
                    tile3,
                    const SizedBox(height: 8),
                    tile4,
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: tile1),
                      const SizedBox(width: 10),
                      Expanded(child: tile2),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: tile3),
                      const SizedBox(width: 10),
                      Expanded(child: tile4),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBentoCard({
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String content,
    String? subtitle,
    Widget? trailing,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(
          alpha: isDark ? 0.04 : 0.03,
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(
            alpha: isDark ? 0.08 : 0.06,
          ),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            content,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9.5,
                color: isDark ? Colors.white38 : Colors.black38,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  /// Tab 1: Contents / Sheets
  Widget _buildContentsTab(
    bool isDark,
    ThemeProvider theme,
    LanguageProvider lang,
    Color extColor,
    String ext,
  ) {
    if (ext == 'xlsx' && _officeSheets.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _officeSheets.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final sheet = _officeSheets[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.04 : 0.03,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colors.accentEmerald.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.table_chart_rounded,
                  size: 16,
                  color: theme.colors.accentEmerald,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sheet,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
                Text(
                  lang.tr('previewSheetIndex', ['${index + 1}']),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white38 : Colors.black38,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    if (_zipEntries.isNotEmpty) {
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: math.min(100, _zipEntries.length),
        separatorBuilder: (_, _) => const SizedBox(height: 4),
        itemBuilder: (context, index) {
          final entry = _zipEntries[index];
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.03 : 0.02,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                Icon(
                  entry.isDirectory
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 15,
                  color: entry.isDirectory
                      ? theme.colors.accentAmber
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    entry.name,
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'Consolas, monospace',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  lang.tr('previewArchiveSizes', [
                    _formatSize(entry.uncompressedSize),
                    _formatSize(entry.compressedSize),
                  ]),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? Colors.white54 : Colors.black45,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    return Center(
      child: Text(
        lang.tr('binaryNoPreview'),
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
      ),
    );
  }

  /// Tab 2: Hex Dump View
  Widget _buildHexViewTab(
    bool isDark,
    ThemeProvider theme,
    LanguageProvider lang,
  ) {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF030712) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.vertical,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SelectableText(
              _hexDump ?? lang.tr('previewEmptyData'),
              style: TextStyle(
                fontFamily: 'Consolas, monospace',
                fontSize: 11,
                height: 1.42,
                color: isDark
                    ? const Color(0xFF94A3B8)
                    : const Color(0xFF334155),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
