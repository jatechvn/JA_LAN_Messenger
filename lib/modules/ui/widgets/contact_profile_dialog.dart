import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/peer_model.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import 'glass_dialog.dart';
import 'glass_components.dart';
import 'bounce_marquee_text.dart';

/// Hộp thoại đổi nhanh biệt danh (Quick Nickname Dialog)
void showQuickNicknameDialog({
  required BuildContext context,
  required MessengerCoordinator coordinator,
  required PeerModel peer,
  required LanguageProvider lang,
}) {
  final controller = TextEditingController(
    text: peer.customNickname ?? peer.name,
  );

  showGlassDialog(
    context: context,
    builder: (ctx) {
      final theme = ThemeProvider.of(ctx);
      final isDark = theme.isDark;

      return GlassDialog(
        title: lang.tr('quickRename'),
        icon: Icons.edit_rounded,
        width: 350,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          if (peer.customNickname != null && peer.customNickname!.isNotEmpty)
            TextButton(
              style: TextButton.styleFrom(
                foregroundColor: theme.colors.accentRose,
              ),
              onPressed: () {
                coordinator.setPeerNickname(peer.id, null);
                Navigator.of(ctx).pop();
              },
              child: Text(lang.tr('resetDefaultName')),
            ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colors.accentBlue,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              final newName = controller.text.trim();
              coordinator.setPeerNickname(
                peer.id,
                newName.isEmpty ? null : newName,
              );
              Navigator.of(ctx).pop();
            },
            child: Text(lang.tr('save')),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              peer.displayName,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.white : Colors.black87,
              ),
              decoration: InputDecoration(
                hintText: lang.tr('nicknameHint'),
                prefixIcon: const Icon(Icons.badge_rounded, size: 18),
                isDense: true,
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: theme.colors.accentBlue,
                    width: 1.5,
                  ),
                ),
              ),
              onSubmitted: (val) {
                final newName = val.trim();
                coordinator.setPeerNickname(
                  peer.id,
                  newName.isEmpty ? null : newName,
                );
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      );
    },
  );
}

/// Hộp thoại thông tin máy trạm / đồng nghiệp (Bento Contact Profile Dialog)
class ContactProfileDialog extends StatelessWidget {
  final PeerModel peer;
  final VoidCallback? onBuzz;

  const ContactProfileDialog({super.key, required this.peer, this.onBuzz});

  static Future<void> show(
    BuildContext context, {
    required PeerModel peer,
    VoidCallback? onBuzz,
  }) {
    return showGlassDialog(
      context: context,
      builder: (ctx) => ContactProfileDialog(peer: peer, onBuzz: onBuzz),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();

    final effectiveName = peer.effectiveDisplayName(lang);
    final isDark = theme.isDark;

    return GlassDialog(
      title: lang.tr('contactInfo'),
      icon: Icons.badge_rounded,
      width: 350,
      actions: [
        if (!peer.isAllUsers && !peer.isGroup && !peer.isAiAssistant) ...[
          if (onBuzz != null)
            TextButton.icon(
              icon: const Icon(Icons.notifications_active_rounded, size: 16),
              label: Text(lang.tr('nudge')),
              style: TextButton.styleFrom(
                foregroundColor: theme.colors.accentAmber,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                onBuzz!();
              },
            ),
          TextButton.icon(
            icon: Icon(
              peer.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              size: 16,
            ),
            label: Text(
              peer.isPinned ? lang.tr('unpinChat') : lang.tr('pinChat'),
            ),
            style: TextButton.styleFrom(
              foregroundColor: peer.isPinned
                  ? theme.colors.accentAmber
                  : (isDark ? Colors.white70 : Colors.black87),
            ),
            onPressed: () {
              coordinator.togglePinPeer(peer.id);
              Navigator.of(context).pop();
            },
          ),
        ],
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colors.accentBlue,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(lang.tr('closeDialog')),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Profile Header with Large Avatar & Status
          Center(
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: peer.avatarColor.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: peer.avatarColor.withValues(alpha: 0.6),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: peer.avatarColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: peer.avatarAsset != null
                          ? ClipOval(
                              child: Image.asset(
                                peer.avatarAsset!,
                                width: 58,
                                height: 58,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Text(
                                  peer.initials,
                                  style: TextStyle(
                                    color: peer.avatarColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              peer.initials,
                              style: TextStyle(
                                color: peer.avatarColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 20,
                              ),
                            ),
                    ),
                    if (!peer.isAllUsers &&
                        !peer.isGroup &&
                        !peer.isAiAssistant)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: peer.status.color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isDark
                                  ? const Color(0xFF0F172A)
                                  : Colors.white,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: peer.status.color.withValues(alpha: 0.5),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        effectiveName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? const Color(0xFFF8FAFC)
                              : Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!peer.isAllUsers &&
                        !peer.isGroup &&
                        !peer.isAiAssistant) ...[
                      const SizedBox(width: 6),
                      Tooltip(
                        message: lang.tr('editNickname'),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            Navigator.of(context).pop();
                            showQuickNicknameDialog(
                              context: context,
                              coordinator: coordinator,
                              peer: peer,
                              lang: lang,
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.edit_rounded,
                              size: 14,
                              color: theme.colors.accentBlue,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (!peer.isAllUsers &&
                    !peer.isGroup &&
                    !peer.isAiAssistant) ...[
                  const SizedBox(height: 6),
                  StatusBadge(status: peer.status, showLabel: true),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 2. Bento Info Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xFF1E293B) : Colors.black)
                  .withValues(alpha: isDark ? 0.6 : 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: isDark ? 0.10 : 0.07,
                ),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                _buildInfoRow(
                  context: context,
                  theme: theme,
                  lang: lang,
                  icon: Icons.wifi_rounded,
                  label: lang.tr('ipAddress'),
                  value: '${peer.ip}:${peer.port}',
                  canCopy: true,
                ),
                if (!peer.isAllUsers && !peer.isGroup) ...[
                  const Divider(height: 14, thickness: 0.6),
                  _buildInfoRow(
                    context: context,
                    theme: theme,
                    lang: lang,
                    icon: Icons.computer_rounded,
                    label: lang.tr('hostname'),
                    value: (peer.hostname != null && peer.hostname!.isNotEmpty)
                        ? peer.hostname!
                        : (peer.name.isNotEmpty ? peer.name : '—'),
                    canCopy: true,
                  ),
                ],
                if (peer.workgroup.isNotEmpty) ...[
                  const Divider(height: 14, thickness: 0.6),
                  _buildInfoRow(
                    context: context,
                    theme: theme,
                    lang: lang,
                    icon: Icons.workspaces_rounded,
                    label: lang.tr('workgroup'),
                    value: peer.workgroup,
                  ),
                ],
                if (peer.statusDescription.isNotEmpty) ...[
                  const Divider(height: 14, thickness: 0.6),
                  _buildInfoRow(
                    context: context,
                    theme: theme,
                    lang: lang,
                    icon: Icons.info_outline_rounded,
                    label: lang.tr('status'),
                    value: peer.statusDescription,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow({
    required BuildContext context,
    required ThemeProvider theme,
    required LanguageProvider lang,
    required IconData icon,
    required String label,
    required String value,
    bool canCopy = false,
  }) {
    final isDark = theme.isDark;

    return Row(
      children: [
        Icon(
          icon,
          size: 15,
          color: theme.colors.accentBlue.withValues(alpha: 0.85),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? const Color(0xFF94A3B8) : Colors.black54,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: BounceMarqueeText(
              text: value,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                fontFamily: canCopy ? 'Consolas' : null,
                color: isDark ? const Color(0xFFF1F5F9) : Colors.black87,
              ),
            ),
          ),
        ),
        if (canCopy) ...[
          const SizedBox(width: 6),
          InkWell(
            borderRadius: BorderRadius.circular(4),
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(lang.tr('copiedToClipboard')),
                  duration: const Duration(milliseconds: 1000),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.copy_rounded,
                size: 13,
                color: theme.colors.accentBlue,
              ),
            ),
          ),
        ],
      ],
    );
  }
}
