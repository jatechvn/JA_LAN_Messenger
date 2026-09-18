import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../models/file_transfer_task.dart';

class TransferListView extends StatelessWidget {
  const TransferListView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    final tasks = coordinator.fileTasks;

    return Container(
      color: Colors.transparent,
      child: Column(
        children: [
          // Header
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: theme.colors.headerBg,
              border: Border(
                bottom: BorderSide(color: theme.colors.headerBorder, width: 1),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.swap_vert_rounded, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${lang.tr('transfersTitle')} (${tasks.length})',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: theme.isDark
                        ? const Color(0xFFF8FAFC)
                        : Colors.black87,
                  ),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colors.accentBlue.withValues(
                      alpha: 0.15,
                    ),
                    foregroundColor: theme.colors.accentBlue,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    // Mở thư mục Downloads
                    final downloadDir = Platform.isWindows
                        ? '${Platform.environment['USERPROFILE']}\\Downloads\\JA_LAN_Messenger'
                        : '${Platform.environment['HOME']}/Downloads/JA_LAN_Messenger';
                    if (Platform.isWindows) {
                      Process.run('explorer.exe', [downloadDir]);
                    }
                  },
                  icon: const Icon(Icons.folder_open_rounded, size: 16),
                  label: Text(
                    lang.tr('openDownloadFolder'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // List of tasks
          Expanded(
            child: tasks.isEmpty
                ? _EmptyTransferState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      final task = tasks[index];
                      return _TransferCard(task: task);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final FileTransferTask task;

  const _TransferCard({required this.task});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final isUpload = task.isUpload;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: (theme.isDark ? const Color(0xFF1E293B) : Colors.white)
            .withValues(alpha: theme.isDark ? 0.90 : 0.90),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: (theme.isDark ? const Color(0x1FFFFFFF) : Colors.black)
              .withValues(alpha: theme.isDark ? 0.8 : 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (isUpload
                              ? theme.colors.accentBlue
                              : theme.colors.accentEmerald)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isUpload
                      ? Icons.arrow_upward_rounded
                      : Icons.arrow_downward_rounded,
                  color: isUpload
                      ? theme.colors.accentBlue
                      : theme.colors.accentEmerald,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.fileName,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.isDark
                            ? const Color(0xFFF8FAFC)
                            : Colors.black87,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${lang.tr(isUpload ? 'transferTo' : 'transferFrom')}: ${task.peerName} (${task.peerIp}) • ${task.formattedFileSize}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.isDark
                            ? const Color(0xFF94A3B8)
                            : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusBadge(task, theme, lang),
            ],
          ),
          const SizedBox(height: 10),

          // Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: task.status == TransferStatus.completed
                  ? 1.0
                  : task.progress,
              backgroundColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(
                task.status == TransferStatus.completed
                    ? theme.colors.accentEmerald
                    : (task.status == TransferStatus.failed
                          ? theme.colors.accentRose
                          : theme.colors.accentBlue),
              ),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),

          // Speed & Percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                task.status == TransferStatus.transferring
                    ? '${lang.tr('transferSpeed')}: ${task.formattedSpeed}'
                    : (task.status == TransferStatus.completed
                          ? lang.tr('transferCompleted')
                          : (task.status == TransferStatus.failed
                                ? '${lang.tr('transferFailed')}: ${task.errorMessage ?? ""}'
                                      .trim()
                                : lang.tr('transferPreparing'))),
                style: TextStyle(
                  fontSize: 11,
                  color: task.status == TransferStatus.failed
                      ? theme.colors.accentRose
                      : (theme.isDark ? Colors.white54 : Colors.black54),
                ),
              ),
              Text(
                '${(task.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(
    FileTransferTask task,
    ThemeProvider theme,
    LanguageProvider lang,
  ) {
    Color badgeColor;
    String label;

    switch (task.status) {
      case TransferStatus.transferring:
        badgeColor = theme.colors.accentBlue;
        label = lang.tr('transferring');
        break;
      case TransferStatus.completed:
        badgeColor = theme.colors.accentEmerald;
        label = lang.tr('transferCompleted');
        break;
      case TransferStatus.failed:
        badgeColor = theme.colors.accentRose;
        label = lang.tr('transferFailed');
        break;
      case TransferStatus.cancelled:
        badgeColor = Colors.grey;
        label = lang.tr('transferCancelled');
        break;
      case TransferStatus.pending:
        badgeColor = theme.colors.accentAmber;
        label = lang.tr('transferPending');
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: badgeColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyTransferState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_sync_outlined,
            size: 48,
            color: theme.isDark ? Colors.white24 : Colors.black26,
          ),
          const SizedBox(height: 12),
          Text(
            lang.tr('noTransfers'),
            style: TextStyle(
              fontSize: 14,
              color: theme.isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lang.tr('noTransfersDesc'),
            style: TextStyle(
              fontSize: 11.5,
              color: theme.isDark ? Colors.white38 : Colors.black38,
            ),
          ),
        ],
      ),
    );
  }
}
