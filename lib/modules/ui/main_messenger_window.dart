import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';
import '../theme/theme_provider.dart';
import '../localization/app_locale.dart';
import '../services/messenger_coordinator.dart';
import '../services/app_preferences.dart';
import '../constants.dart';
import '../build_info.dart';
import 'widgets/compact_sidebar.dart';
import 'widgets/peer_list_view.dart';
import 'widgets/chat_view_panel.dart';
import 'widgets/transfer_list_view.dart';
import 'widgets/conversation_details_panel.dart';
import 'widgets/close_action_dialog.dart';
import 'widgets/glass_background.dart';

class MainMessengerWindow extends StatefulWidget {
  const MainMessengerWindow({super.key});

  @override
  State<MainMessengerWindow> createState() => _MainMessengerWindowState();
}

class _MainMessengerWindowState extends State<MainMessengerWindow>
    with WindowListener, TrayListener {
  MainViewTab _activeTab = MainViewTab.chats;
  bool _showDetailsPanel = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    trayManager.addListener(this);

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      windowManager.setPreventClose(true);
      _initSystemTray();
    }

    // Khởi tạo dịch vụ mạng P2P
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MessengerCoordinator>().initialize();
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    super.dispose();
  }

  Future<void> _initSystemTray() async {
    final lang = context.read<LanguageProvider>();
    try {
      await trayManager.setIcon('assets/app_icon.ico');
      final Menu menu = Menu(
        items: [
          MenuItem(key: 'show_window', label: lang.tr('trayOpen')),
          MenuItem.separator(),
          MenuItem(key: 'rescan_lan', label: lang.tr('trayRescan')),
          MenuItem.separator(),
          MenuItem(key: 'exit_app', label: lang.tr('trayExit')),
        ],
      );
      await trayManager.setContextMenu(menu);
      await trayManager.setToolTip(appName);
    } catch (e) {
      debugPrint('[Tray] Failed to initialize system tray: $e');
    }
  }

  @override
  void onTrayIconMouseDown() async {
    final isVisible = await windowManager.isVisible();
    if (isVisible) {
      await windowManager.restore();
      await windowManager.focus();
    } else {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    }
  }

  @override
  void onTrayIconRightMouseDown() async {
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    if (menuItem.key == 'show_window') {
      await windowManager.show();
      await windowManager.restore();
      await windowManager.focus();
    } else if (menuItem.key == 'rescan_lan') {
      if (mounted) {
        context.read<MessengerCoordinator>().rescanNetwork();
      }
    } else if (menuItem.key == 'exit_app') {
      await _exitSafely();
    }
  }

  bool _exiting = false;
  Future<void> _exitSafely() async {
    if (_exiting || !mounted) return;
    _exiting = true;
    final coordinator = context.read<MessengerCoordinator>();
    try {
      await coordinator.flushHistoryBeforeExit();
      await windowManager.destroy();
      exit(0);
    } catch (_) {
      _exiting = false;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Không lưu được lịch sử. Hãy kiểm tra dung lượng và quyền ghi rồi thử thoát lại.',
            ),
          ),
        );
      }
    }
  }

  @override
  void onWindowClose() async {
    final prefs = AppPreferences();

    if (prefs.rememberCloseBehavior) {
      if (prefs.closeBehavior == 'minimize') {
        await windowManager.hide();
        return;
      } else if (prefs.closeBehavior == 'exit') {
        await _exitSafely();
      }
    }

    if (!mounted) return;
    final result = await CloseActionDialog.show(context);
    if (result != null) {
      final action = result['action'] as String;
      final remember = result['remember'] as bool;
      if (remember) {
        await prefs.setCloseBehavior(action, remember: true);
      }
      if (action == 'minimize') {
        await windowManager.hide();
      } else {
        await _exitSafely();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();
    final coordinator = context.watch<MessengerCoordinator>();
    coordinator.languageProvider = lang;

    final String? toastMsg = coordinator.currentToast != null
        ? coordinator.currentToast!.format(lang)
        : coordinator.lastToastMessage;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(theme.isWin11 ? 12 : 0),
          border: Border.all(
            color: (theme.isDark ? Colors.white : Colors.black).withValues(
              alpha: theme.isDark ? 0.12 : 0.08,
            ),
            width: 1,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(theme.isWin11 ? 12 : 0),
          child: Stack(
            children: [
              // 1. Mesh Gradient Base Tint (Translucent)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        theme.colors.bgSecondary,
                        theme.colors.bgSecondary.withValues(alpha: 0.5),
                        theme.colors.bgSecondary.withValues(alpha: 0.2),
                      ],
                    ),
                  ),
                ),
              ),

              // 2. GPU-Composited Floating Ambient Mesh Orbs
              Positioned.fill(
                child: RepaintBoundary(
                  child: MeshBackground(
                    colors: theme.colors,
                    enableAnimation: theme.effectiveTier != HardwareTier.lite,
                  ),
                ),
              ),

              // 3. Foreground Window Layout
              Column(
                children: [
                  // Custom Window Subheader
                  _CustomTitleBar(
                    onlinePeersCount: coordinator.peers.length,
                    localIdentity: coordinator.localUsername,
                    isScanning: coordinator.isScanning,
                  ),

                  // Main Messenger Workspace with Floating Toast Pill overlay
                  Expanded(
                    child: Stack(
                      children: [
                        Row(
                          children: [
                            // Column 1: Compact Sidebar Rail (58px)
                            CompactSidebar(
                              activeTab: _activeTab,
                              onTabChanged: (tab) =>
                                  setState(() => _activeTab = tab),
                            ),

                            // Column 2, 3 & 4: Views based on active tab
                            if (_activeTab == MainViewTab.chats) ...[
                              // Column 2: Peer List (260px)
                              const PeerListView(),

                              // Column 3: Active Chat Conversation
                              Expanded(
                                child: ChatViewPanel(
                                  isDetailsOpen: _showDetailsPanel,
                                  onToggleDetails: () {
                                    setState(() {
                                      _showDetailsPanel = !_showDetailsPanel;
                                    });
                                  },
                                ),
                              ),

                              // Column 4: Right Conversation Details Panel
                              if (_showDetailsPanel &&
                                  coordinator.selectedPeer != null)
                                ConversationDetailsPanel(
                                  onClose: () {
                                    setState(() {
                                      _showDetailsPanel = false;
                                    });
                                  },
                                ),
                            ] else ...[
                              // Transfers Manager View
                              const Expanded(child: TransferListView()),
                            ],
                          ],
                        ),

                        // Floating Glass Toast Pill
                        if (toastMsg != null && toastMsg.isNotEmpty)
                          Positioned(
                            top: 14,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: _FloatingToastPill(
                                key: ValueKey(toastMsg),
                                message: toastMsg,
                                onDismiss: () {
                                  coordinator.clearToast();
                                  coordinator.lastToastMessage = null;
                                },
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CustomTitleBar extends StatelessWidget {
  final int onlinePeersCount;
  final String localIdentity;
  final bool isScanning;

  const _CustomTitleBar({
    required this.onlinePeersCount,
    required this.localIdentity,
    required this.isScanning,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: theme.colors.headerBg,
        border: Border(
          bottom: BorderSide(color: theme.colors.headerBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.wifi_tethering_rounded,
            size: 16,
            color: isScanning
                ? theme.colors.accentBlue
                : theme.colors.accentEmerald,
          ),
          const SizedBox(width: 8),
          Text(
            appName,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: theme.isDark ? const Color(0xFFF8FAFC) : Colors.black87,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color:
                  (isScanning
                          ? theme.colors.accentBlue
                          : theme.colors.accentEmerald)
                      .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 5),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isScanning
                        ? theme.colors.accentBlue
                        : theme.colors.accentEmerald,
                  ),
                ),
                Text(
                  isScanning
                      ? lang.tr('scanning')
                      : '$onlinePeersCount ${lang.tr('devicesOnline')}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isScanning
                        ? theme.colors.accentBlue
                        : theme.colors.accentEmerald,
                  ),
                ),
              ],
            ),
          ),
          if (BuildInfo.isDebug) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: Colors.amber.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.bug_report_rounded,
                    size: 11,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'DEBUG · v${BuildInfo.version} (${BuildInfo.debugTimestamp})',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Consolas',
                      color: Colors.amber,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const Spacer(),

          // Định danh máy trạm hiện tại: user@hostname
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: (theme.isDark ? const Color(0xFF1E293B) : Colors.black)
                  .withValues(alpha: theme.isDark ? 0.75 : 0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: theme.isDark ? 0.12 : 0.08,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.laptop_chromebook_rounded,
                  size: 13,
                  color: theme.colors.accentBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  localIdentity,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'Consolas',
                    color: theme.isDark
                        ? const Color(0xFFF8FAFC)
                        : Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloatingToastPill extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _FloatingToastPill({
    super.key,
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_FloatingToastPill> createState() => _FloatingToastPillState();
}

class _FloatingToastPillState extends State<_FloatingToastPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, -0.45), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
        );

    _animController.forward();

    _dismissTimer = Timer(const Duration(milliseconds: 3800), () {
      if (mounted) {
        _handleDismiss();
      }
    });
  }

  void _handleDismiss() {
    _dismissTimer?.cancel();
    _animController.reverse().then((_) {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);

    return SlideTransition(
      position: _slideAnim,
      child: FadeTransition(
        opacity: _fadeAnim,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: (theme.isDark ? const Color(0xFF1E2028) : Colors.white)
                    .withValues(alpha: theme.isDark ? 0.88 : 0.94),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: theme.colors.accentAmber.withValues(alpha: 0.45),
                  width: 1.2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: theme.isDark ? 0.4 : 0.12,
                    ),
                    blurRadius: 18,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.notifications_active_rounded,
                    size: 16,
                    color: theme.colors.accentAmber,
                  ),
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Text(
                      widget.message,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: theme.isDark ? Colors.white : Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _handleDismiss,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: theme.isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
