import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/peer_model.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../services/app_preferences.dart';
import 'glass_dialog.dart';
import 'glass_components.dart';
import 'bounce_marquee_text.dart';
import 'app_avatar.dart';

/// Hộp thoại đổi nhanh biệt danh (Quick Nickname Dialog)
Future<void> showQuickNicknameDialog({
  required BuildContext context,
  required MessengerCoordinator coordinator,
  required PeerModel peer,
  required LanguageProvider lang,
}) {
  final controller = TextEditingController(
    text: peer.customNickname ?? peer.name,
  );

  return showGlassDialog(
    context: context,
    builder: (ctx) {
      final theme = ThemeProvider.of(ctx);
      final isDark = theme.isDark;

      return GlassDialog(
        title: peer.isGroup ? lang.tr('renameGroup') : lang.tr('quickRename'),
        icon: Icons.edit_rounded,
        width: 350,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(lang.tr('cancel')),
          ),
          if (!peer.isGroup &&
              peer.customNickname != null &&
              peer.customNickname!.isNotEmpty)
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
              if (peer.isGroup) {
                if (newName.isNotEmpty) {
                  coordinator.renameGroup(peer.id, newName);
                }
              } else {
                coordinator.setPeerNickname(
                  peer.id,
                  newName.isEmpty ? null : newName,
                );
              }
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
      scrollable: true,
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
            icon: const Icon(Icons.settings_remote_rounded, size: 16),
            label: Text(lang.tr('winrmConfigure')),
            style: TextButton.styleFrom(
              foregroundColor: theme.colors.accentCyan,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              showPeerWinrmConfigDialog(
                context: context,
                peer: peer,
                lang: lang,
              );
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
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: peer.avatarColor.withValues(alpha: 0.35),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: AppAvatar(peer: peer, size: 58, isCircle: true),
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
          if (!peer.isAllUsers && !peer.isGroup && !peer.isAiAssistant) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colors.accentCyan,
                  side: BorderSide(
                    color: theme.colors.accentCyan.withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.settings_remote_rounded, size: 15),
                label: Text(
                  lang.tr('winrmContactConfig'),
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  showPeerWinrmConfigDialog(
                    context: context,
                    peer: peer,
                    lang: lang,
                  );
                },
              ),
            ),
          ],
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

/// Hộp thoại cấu hình WinRM riêng cho liên hệ / máy trạm
void showPeerWinrmConfigDialog({
  required BuildContext context,
  required PeerModel peer,
  required LanguageProvider lang,
}) {
  showGlassDialog(
    context: context,
    builder: (ctx) => _PeerWinrmConfigDialog(peer: peer, lang: lang),
  );
}

class _PeerWinrmConfigDialog extends StatefulWidget {
  final PeerModel peer;
  final LanguageProvider lang;

  const _PeerWinrmConfigDialog({required this.peer, required this.lang});

  @override
  State<_PeerWinrmConfigDialog> createState() => _PeerWinrmConfigDialogState();
}

class _PeerWinrmConfigDialogState extends State<_PeerWinrmConfigDialog> {
  late bool _useCustom;
  late TextEditingController _userController;
  late TextEditingController _passController;
  late TextEditingController _portController;
  late TextEditingController _customPathController;
  bool _obscurePassword = true;
  bool _isTesting = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void initState() {
    super.initState();
    final prefs = AppPreferences();
    final existing =
        prefs.getWinrmConfigForPeer(widget.peer.canonicalIdentity) ??
        prefs.getWinrmConfigForPeer(widget.peer.id);
    _useCustom = existing?.useCustom ?? false;
    _userController = TextEditingController(text: existing?.username ?? '');
    _passController = TextEditingController(text: existing?.password ?? '');
    _portController = TextEditingController(
      text: (existing != null && existing.port > 0)
          ? existing.port.toString()
          : prefs.winrmDefaultPort.toString(),
    );
    _customPathController = TextEditingController(
      text: existing?.customAppPath ?? '',
    );
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _portController.dispose();
    _customPathController.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    final prefs = AppPreferences();
    final user = _userController.text.trim().isNotEmpty
        ? _userController.text.trim()
        : prefs.winrmDefaultUsername;
    final pass = _passController.text.isNotEmpty
        ? _passController.text
        : prefs.winrmDefaultPassword;
    final port =
        int.tryParse(_portController.text.trim()) ?? prefs.winrmDefaultPort;
    final ip = widget.peer.ip.isNotEmpty
        ? widget.peer.ip
        : (widget.peer.knownIps.isNotEmpty ? widget.peer.knownIps.first : '');

    if (ip.isEmpty) {
      setState(() {
        _testSuccess = false;
        _testResult = widget.lang.tr('winrmNoIp');
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
      _testSuccess = null;
    });

    final coordinator = context.read<MessengerCoordinator>();
    final result = await coordinator.winrmLauncher.testConnection(
      ip: ip,
      port: port,
      username: user,
      password: pass,
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _testSuccess = result.success;
      _testResult = result.message;
    });
  }

  Future<void> _save() async {
    final prefs = AppPreferences();
    if (!_useCustom) {
      await prefs.setWinrmConfigForPeer(widget.peer.canonicalIdentity, null);
      await prefs.setWinrmConfigForPeer(widget.peer.id, null);
    } else {
      final config = WinrmPeerConfig(
        useCustom: true,
        username: _userController.text.trim(),
        password: _passController.text,
        port: int.tryParse(_portController.text.trim()) ?? 5985,
        customAppPath: _customPathController.text.trim().isNotEmpty
            ? _customPathController.text.trim()
            : null,
      );
      await prefs.setWinrmConfigForPeer(widget.peer.canonicalIdentity, config);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final isDark = theme.isDark;
    final lang = widget.lang;

    return GlassDialog(
      title: '${lang.tr('winrmConfigure')} - ${widget.peer.displayName}',
      icon: Icons.settings_remote_rounded,
      width: 440,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(lang.tr('cancel')),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colors.accentBlue,
            foregroundColor: Colors.white,
          ),
          onPressed: _save,
          child: Text(lang.tr('save')),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                lang.tr('winrmUseCustomConfig'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                _useCustom
                    ? lang.tr('winrmUseCustomConfig')
                    : lang.tr('winrmUseDefaultConfig'),
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              value: _useCustom,
              activeTrackColor: theme.colors.accentBlue,
              onChanged: (val) => setState(() => _useCustom = val),
            ),
            const SizedBox(height: 8),
            if (_useCustom) ...[
              TextField(
                controller: _userController,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: lang.tr('winrmDefaultUser'),
                  hintText: AppPreferences().winrmDefaultUsername,
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.person_outline_rounded,
                    size: 16,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passController,
                obscureText: _obscurePassword,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: lang.tr('winrmDefaultPass'),
                  hintText: '••••••••',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.lock_outline_rounded, size: 16),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: lang.tr('winrmPort'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.numbers_rounded, size: 16),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _customPathController,
                style: const TextStyle(fontSize: 12.5),
                decoration: InputDecoration(
                  labelText: lang.tr('winrmCustomAppPath'),
                  hintText: lang.tr('winrmCustomAppPathHint'),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.folder_open_rounded, size: 16),
                ),
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: Text(
                    'IP: ${widget.peer.ip.isNotEmpty ? widget.peer.ip : (widget.peer.knownIps.isNotEmpty ? widget.peer.knownIps.first : '—')}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'Consolas',
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.colors.accentCyan,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isTesting ? null : _testConnection,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black87,
                          ),
                        )
                      : const Icon(Icons.network_check_rounded, size: 15),
                  label: Text(
                    _isTesting
                        ? lang.tr('winrmTesting')
                        : lang.tr('winrmTestConnection'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: (_testSuccess == true ? Colors.green : Colors.red)
                      .withValues(alpha: isDark ? 0.20 : 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: (_testSuccess == true ? Colors.green : Colors.red)
                        .withValues(alpha: 0.5),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess == true
                          ? Icons.check_circle_outline_rounded
                          : Icons.error_outline_rounded,
                      size: 16,
                      color: _testSuccess == true ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _testResult!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: _testSuccess == true
                              ? (isDark
                                    ? Colors.greenAccent
                                    : Colors.green.shade800)
                              : (isDark
                                    ? Colors.redAccent
                                    : Colors.red.shade800),
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
    );
  }
}
