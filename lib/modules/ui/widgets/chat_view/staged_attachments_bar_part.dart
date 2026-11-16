part of '../chat_view_panel.dart';

class StagedAttachmentsBar extends StatelessWidget {
  final List<File> files;
  final ValueChanged<int>? onRemove;
  final VoidCallback? onClear;

  const StagedAttachmentsBar({
    super.key,
    required this.files,
    this.onRemove,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isDark = theme.isDark;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF0F172A) : Colors.black).withValues(
          alpha: isDark ? 0.60 : 0.04,
        ),
        border: Border(
          bottom: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.08,
            ),
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.attachment_rounded,
                size: 14,
                color: theme.colors.accentBlue,
              ),
              const SizedBox(width: 5),
              Text(
                lang.tr('stagedFilesCount', [files.length]),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.accentBlue,
                ),
              ),
              const Spacer(),
              if (files.length > 1)
                InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    child: Text(
                      lang.tr('clearAllAttachments'),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w500,
                        color: theme.colors.accentRose,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: files.length,
              separatorBuilder: (context, index) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final file = files[index];
                final fileName = file.path.split(Platform.pathSeparator).last;
                final isImg = MessengerCoordinator.isImageFile(file.path);
                int fileSize = 0;
                try {
                  fileSize = file.lengthSync();
                } catch (_) {}

                final sizeStr = _formatSize(fileSize);

                if (isImg) {
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      InkWell(
                        onTap: () => showGlassFilePreview(
                          context: context,
                          filePath: file.path,
                          fileName: fileName,
                        ),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.12),
                              width: 1,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.35 : 0.08,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  file,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Center(
                                        child: Icon(
                                          Icons.broken_image_rounded,
                                          size: 24,
                                          color: isDark
                                              ? Colors.white38
                                              : Colors.black38,
                                        ),
                                      ),
                                ),
                                Positioned(
                                  bottom: 0,
                                  left: 0,
                                  right: 0,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                      horizontal: 4,
                                    ),
                                    color: Colors.black54,
                                    child: Text(
                                      sizeStr,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: -5,
                        right: -5,
                        child: InkWell(
                          onTap: () => onRemove?.call(index),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF334155)
                                  : Colors.grey.shade300,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isDark ? Colors.white24 : Colors.black12,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 2,
                                  offset: Offset(0, 1),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    InkWell(
                      onTap: () => showGlassFilePreview(
                        context: context,
                        filePath: file.path,
                        fileName: fileName,
                      ),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 170,
                        height: 72,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color:
                              (isDark ? const Color(0xFF1E293B) : Colors.white)
                                  .withValues(alpha: isDark ? 0.75 : 0.85),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.12),
                            width: 1,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.30 : 0.06,
                              ),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: theme.colors.accentBlue.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                _getFileIcon(file.path),
                                size: 20,
                                color: theme.colors.accentBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    fileName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    sizeStr,
                                    style: TextStyle(
                                      fontSize: 9.5,
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
                      ),
                    ),
                    Positioned(
                      top: -5,
                      right: -5,
                      child: InkWell(
                        onTap: () => onRemove?.call(index),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF334155)
                                : Colors.grey.shade300,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark ? Colors.white24 : Colors.black12,
                              width: 1,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static IconData _getFileIcon(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
      case 'txt':
      case 'md':
        return Icons.description_rounded;
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return Icons.folder_zip_rounded;
      case 'mp3':
      case 'wav':
      case 'm4a':
      case 'ogg':
        return Icons.audio_file_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.video_file_rounded;
      case 'xls':
      case 'xlsx':
      case 'csv':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'exe':
      case 'msi':
      case 'bat':
      case 'cmd':
        return Icons.terminal_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}
