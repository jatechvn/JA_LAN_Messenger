import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../theme/theme_provider.dart';
import '../../localization/app_locale.dart';
import '../../services/messenger_coordinator.dart';
import '../../services/app_preferences.dart';
import '../../services/autostart_service.dart';
import '../../services/chat_history_service.dart';
import '../../constants.dart';
import '../../build_info.dart';
import '../../models/ai_config_model.dart';
import '../../ime/ime_service.dart';
import '../../ime/ime_types.dart';
import '../../services/ota_update_service.dart';
import '../../services/app_power_manager.dart';
import 'glass_dialog.dart';
import 'glass_update_dialog.dart';
import 'app_avatar.dart';
import 'avatar_picker_dialog.dart';

part 'settings/settings_advanced_tab_part.dart';
part 'settings/settings_ota_tab_part.dart';
part 'settings/settings_about_and_guide_tab_part.dart';

void showSettingsDialog(BuildContext context) {
  showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'SettingsDialog',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, anim1, anim2) => const SettingsDialog(),
    transitionBuilder: (ctx, anim1, anim2, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: anim1, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween<double>(
            begin: 0.95,
            end: 1.0,
          ).animate(CurvedAnimation(parent: anim1, curve: Curves.easeOut)),
          child: child,
        ),
      );
    },
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({super.key});

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

abstract class _SettingsDialogStateBase extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Local state mirrors (commit-on-save)
  late double _localCardBlur;
  late double _localCardOpacity;
  late double _localDialogBlur;
  late double _localDialogOpacity;
  late PerfTierMode _localPerfMode;
  late bool _localEnableIdleSleep;
  late int _localIdleTimeoutSeconds;

  // Glass tuning initial values for reverting on cancel
  late double _initialCardBlur;
  late double _initialCardOpacity;
  late double _initialDialogBlur;
  late double _initialDialogOpacity;
  late PerfTierMode _initialPerfMode;
  bool _saved = false;
  ThemeProvider? _themeProvider;

  // Local profile & network mirrors
  late TextEditingController _nicknameController;
  late TextEditingController _workgroupController;
  late TextEditingController _tcpPortController;
  late TextEditingController _filePortController;
  late bool _encryptionEnabled;
  late Set<String> _disabledAdapters;
  late Set<String> _initialDisabledAdapters;
  bool _isSaving = false;
  late TextEditingController _passwordController;
  late String _localCloseBehavior;
  bool _autoStartEnabled = false;

  // AI mirrors
  late bool _localAiEnabled;
  late TextEditingController _aiServerUrlController;
  late String _localAiSelectedModel;
  late bool _localAiThinkingEnabled;
  late List<AiModelInfo> _localAvailableModels;
  bool _isRefreshingModels = false;
  bool _isTestingAiConnection = false;
  String? _aiConnectionTestResult;
  bool? _aiConnectionTestSuccess;

  // Chat History mirror
  late bool _localChatHistoryEnabled;

  // Buzz Alert mirrors
  late bool _localBuzzFlashScreen;
  late bool _localBuzzShakeWindow;
  late bool _localBuzzBringToFront;

  // WinRM Remote Launch mirrors
  late bool _localWinrmEnabled;
  late TextEditingController _winrmUsernameController;
  late TextEditingController _winrmPasswordController;
  late TextEditingController _winrmPortController;
  late bool _localWinrmAutoBuzzOnConnect;
  bool _obscureWinrmPassword = true;
  late TextEditingController _winrmTestIpController;
  bool _isTestingWinrmConnection = false;
  String? _winrmConnectionTestResult;
  bool? _winrmConnectionTestSuccess;

  // IME mirrors
  late String _localImeMode;
  late bool _localImeAutoBypassExternal;

  // OTA Update mirrors
  late String _localOtaSource;
  late TextEditingController _otaGithubRepoController;
  late TextEditingController _otaGithubTokenController;
  bool _obscureOtaGithubToken = true;
  late String _localOtaCheckInterval;
  late TextEditingController _otaServerPathController;
  late TextEditingController _otaUsernameController;
  late TextEditingController _otaPasswordController;
  bool _obscureOtaPassword = true;
  bool _isTestingServerConnection = false;
  String? _serverConnectionResult;
  bool? _serverConnectionSuccess;
  bool _isCheckingForUpdates = false;
  UpdateCheckResult? _manualUpdateCheckResult;

  Widget _buildPerfTierChip({
    required PerfTierMode mode,
    required String label,
    String? desc,
    required IconData icon,
    required ThemeProvider theme,
  }) {
    final isSelected = _localPerfMode == mode;
    final color = isSelected
        ? theme.colors.accentBlue
        : (theme.isDark ? Colors.white70 : Colors.black87);

    return Tooltip(
      message: desc ?? label,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: () {
          setState(() {
            _localPerfMode = mode;
          });
          // Update live tuning values to match the selected tier
          final targetTier = mode == PerfTierMode.auto
              ? theme.detectedTier
              : (mode == PerfTierMode.ultra
                    ? HardwareTier.ultra
                    : (mode == PerfTierMode.balanced
                          ? HardwareTier.balanced
                          : HardwareTier.lite));
          switch (targetTier) {
            case HardwareTier.ultra:
              _localCardBlur = 24.0;
              _localCardOpacity = 0.28;
              _localDialogBlur = 20.0;
              _localDialogOpacity = 0.88;
              break;
            case HardwareTier.balanced:
              _localCardBlur = 12.0;
              _localCardOpacity = 0.40;
              _localDialogBlur = 12.0;
              _localDialogOpacity = 0.90;
              break;
            case HardwareTier.lite:
              _localCardBlur = 0.0;
              _localCardOpacity = 0.88;
              _localDialogBlur = 0.0;
              _localDialogOpacity = 0.96;
              break;
          }
          _themeProvider?.setLiveGlassmorphism(
            cardBlur: _localCardBlur,
            cardOpacity: _localCardOpacity,
            dialogBlur: _localDialogBlur,
            dialogOpacity: _localDialogOpacity,
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colors.accentBlue.withValues(alpha: 0.15)
                : (theme.isDark ? Colors.white : Colors.black).withValues(
                    alpha: 0.04,
                  ),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? theme.colors.accentBlue
                  : (theme.isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.1,
                    ),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdleTimeoutChip(int seconds, String label, ThemeProvider theme) {
    final isSelected = _localIdleTimeoutSeconds == seconds;
    return ChoiceChip(
      key: ValueKey('idle-timeout-chip-$seconds'),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected
              ? Colors.white
              : (theme.isDark ? Colors.white70 : Colors.black87),
        ),
      ),
      selected: isSelected,
      selectedColor: theme.colors.accentEmerald,
      backgroundColor: (theme.isDark ? Colors.white : Colors.black).withValues(
        alpha: 0.05,
      ),
      showCheckmark: false,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      onSelected: (selected) {
        if (selected) {
          setState(() => _localIdleTimeoutSeconds = seconds);
        }
      },
    );
  }

  Widget _buildOtaIntervalChip({
    required String value,
    required String label,
    required IconData icon,
    required ThemeProvider theme,
    required bool isDark,
  }) {
    final isSelected = _localOtaCheckInterval == value;
    final color = isSelected
        ? theme.colors.accentBlue
        : (isDark ? Colors.white70 : Colors.black87);

    return InkWell(
      key: ValueKey('ota-interval-chip-$value'),
      onTap: () {
        setState(() => _localOtaCheckInterval = value);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colors.accentBlue.withValues(alpha: 0.15)
              : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected
                ? theme.colors.accentBlue
                : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlassSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required bool isPercent,
    required ValueChanged<double> onChanged,
  }) {
    final theme = ThemeProvider.of(context);
    final valueDisplay = isPercent
        ? '${(value * 100).toStringAsFixed(0)}%'
        : '${value.toStringAsFixed(1)}px';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.isDark ? Colors.white70 : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                valueDisplay,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: theme.colors.accentBlue,
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: theme.colors.accentBlue,
              inactiveTrackColor: (theme.isDark ? Colors.white : Colors.black)
                  .withValues(alpha: 0.1),
              thumbColor: theme.colors.accentBlue,
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsDialogState extends _SettingsDialogStateBase
    with
        _SettingsAdvancedTabMixin,
        _SettingsOtaTabMixin,
        _SettingsAboutAndGuideTabMixin {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeProvider ??= Provider.of<ThemeProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);

    final theme = context.read<ThemeProvider>();
    _initialCardBlur = theme.cardBlur;
    _initialCardOpacity = theme.cardOpacity;
    _initialDialogBlur = theme.dialogBlur;
    _initialDialogOpacity = theme.dialogOpacity;
    _initialPerfMode = theme.perfMode;

    _localCardBlur = _initialCardBlur;
    _localCardOpacity = _initialCardOpacity;
    _localDialogBlur = _initialDialogBlur;
    _localDialogOpacity = _initialDialogOpacity;
    _localPerfMode = _initialPerfMode;

    final coordinator = context.read<MessengerCoordinator>();
    _nicknameController = TextEditingController(
      text: coordinator.localUsername,
    );
    _workgroupController = TextEditingController(
      text: coordinator.localWorkgroup,
    );
    _tcpPortController = TextEditingController(
      text: coordinator.localTcpPort.toString(),
    );
    _filePortController = TextEditingController(
      text: coordinator.localFilePort.toString(),
    );
    _disabledAdapters = Set.of(coordinator.networkPreferences.disabledNames);
    _initialDisabledAdapters = Set.of(_disabledAdapters);
    _encryptionEnabled = coordinator.security.isEncryptionEnabled;
    _passwordController = TextEditingController(
      text: coordinator.security.password,
    );

    final prefs = AppPreferences();
    _localCloseBehavior = prefs.closeBehavior;
    _localAiEnabled = prefs.aiEnabled;
    _aiServerUrlController = TextEditingController(text: prefs.aiServerUrl);
    _localAiSelectedModel = prefs.aiSelectedModel;
    _localAiThinkingEnabled = prefs.aiThinkingEnabled;
    _localChatHistoryEnabled = prefs.chatHistoryEnabled;
    _localBuzzFlashScreen = prefs.buzzFlashScreen;
    _localBuzzShakeWindow = prefs.buzzShakeWindow;
    _localBuzzBringToFront = prefs.buzzBringToFront;

    _localWinrmEnabled = prefs.winrmEnabled;
    _winrmUsernameController = TextEditingController(
      text: prefs.winrmDefaultUsername,
    );
    _winrmPasswordController = TextEditingController(
      text: prefs.winrmDefaultPassword,
    );
    _winrmPortController = TextEditingController(
      text: prefs.winrmDefaultPort.toString(),
    );
    _localWinrmAutoBuzzOnConnect = prefs.winrmAutoBuzzOnConnect;
    _winrmTestIpController = TextEditingController();

    _localImeMode = prefs.imeMode;
    _localImeAutoBypassExternal = prefs.imeAutoBypassExternal;

    _localOtaSource = prefs.otaSource;
    _otaGithubRepoController = TextEditingController(text: prefs.otaGithubRepo);
    _otaGithubTokenController = TextEditingController(
      text: prefs.otaGithubToken,
    );
    _localOtaCheckInterval = prefs.otaCheckInterval;
    _otaServerPathController = TextEditingController(text: prefs.otaServerPath);
    _otaUsernameController = TextEditingController(text: prefs.otaUsername);
    _otaPasswordController = TextEditingController(text: prefs.otaPassword);

    _localAvailableModels = List.of(coordinator.availableAiModels);
    if (!_localAvailableModels.any((m) => m.id == _localAiSelectedModel)) {
      _localAvailableModels.add(AiModelInfo.findById(_localAiSelectedModel));
    }

    _localEnableIdleSleep = prefs.enableIdleSleep;
    _localIdleTimeoutSeconds = prefs.idleTimeoutSeconds;

    AutostartService.isAutoStartEnabled().then((enabled) {
      if (mounted) setState(() => _autoStartEnabled = enabled);
    });
  }

  @override
  void dispose() {
    if (!_saved && _themeProvider != null) {
      final cardBlur = _initialCardBlur;
      final cardOpacity = _initialCardOpacity;
      final dialogBlur = _initialDialogBlur;
      final dialogOpacity = _initialDialogOpacity;
      final perfMode = _initialPerfMode;
      final theme = _themeProvider;
      scheduleMicrotask(() {
        try {
          theme?.setPerfTierMode(perfMode);
          theme?.setLiveGlassmorphism(
            cardBlur: cardBlur,
            cardOpacity: cardOpacity,
            dialogBlur: dialogBlur,
            dialogOpacity: dialogOpacity,
          );
        } catch (_) {}
      });
    }
    _tabController.dispose();
    _nicknameController.dispose();
    _workgroupController.dispose();
    _tcpPortController.dispose();
    _filePortController.dispose();
    _passwordController.dispose();
    _aiServerUrlController.dispose();
    _otaGithubRepoController.dispose();
    _otaGithubTokenController.dispose();
    _otaServerPathController.dispose();
    _otaUsernameController.dispose();
    _otaPasswordController.dispose();
    _winrmUsernameController.dispose();
    _winrmPasswordController.dispose();
    _winrmPortController.dispose();
    _winrmTestIpController.dispose();
    super.dispose();
  }

  void _resetToDefaults() {
    setState(() {
      _localPerfMode = PerfTierMode.auto;
      _localCardBlur = 24.0;
      _localCardOpacity = 0.28;
      _localDialogBlur = 20.0;
      _localDialogOpacity = 0.88;
      _tcpPortController.text = defaultListenerPort.toString();
      _filePortController.text = defaultFileTransferPort.toString();
      _workgroupController.text = 'General';
      _encryptionEnabled = false;
      _disabledAdapters.clear();
      _localCloseBehavior = 'ask';
      _autoStartEnabled = Platform.isWindows;
      _localAiEnabled = true;
      _aiServerUrlController.text = 'http://172.21.175.20:11434';
      _localAiSelectedModel = 'qwen3.5:4b';
      _localAiThinkingEnabled = false;
      _localChatHistoryEnabled = true;
      _localBuzzFlashScreen = true;
      _localBuzzShakeWindow = true;
      _localBuzzBringToFront = true;
      _localWinrmEnabled = true;
      _winrmUsernameController.text = 'user';
      _winrmPasswordController.text = 'user';
      _winrmPortController.text = '5985';
      _localWinrmAutoBuzzOnConnect = true;
      _winrmTestIpController.text = '';
      _winrmConnectionTestResult = null;
      _winrmConnectionTestSuccess = null;
      _localImeMode = 'auto';
      _localImeAutoBypassExternal = true;
      _aiConnectionTestResult = null;
      _aiConnectionTestSuccess = null;
      _localOtaSource = 'auto';
      _otaGithubRepoController.text = 'jatechvn/JA_LAN_Messenger';
      _otaGithubTokenController.text = '';
      _localOtaCheckInterval = 'daily';
      _otaServerPathController.text =
          r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger';
      _otaUsernameController.text = 'user';
      _otaPasswordController.text = 'user';
      _serverConnectionResult = null;
      _serverConnectionSuccess = null;
      _manualUpdateCheckResult = null;
      _localEnableIdleSleep = true;
      _localIdleTimeoutSeconds = 12;
    });
    _themeProvider?.setPerfTierMode(PerfTierMode.auto);
    _themeProvider?.setLiveGlassmorphism(
      cardBlur: 24.0,
      cardOpacity: 0.28,
      dialogBlur: 20.0,
      dialogOpacity: 0.88,
    );
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    _isSaving = true;
    _saved = true;

    final theme = context.read<ThemeProvider>();
    final coordinator = context.read<MessengerCoordinator>();
    final ime = context.read<ImeService>();

    theme.setPerfTierMode(_localPerfMode);

    AppPowerManager.instance.configure(
      enableIdleSleep: _localEnableIdleSleep,
      idleTimeoutSeconds: _localIdleTimeoutSeconds,
    );

    final prefs = AppPreferences();
    try {
      await prefs.setPowerOptimization(
        enableIdleSleep: _localEnableIdleSleep,
        idleTimeoutSeconds: _localIdleTimeoutSeconds,
      );
    } catch (e) {
      debugPrint('[SettingsDialog] Error saving power optimization: $e');
    }

    await theme.saveGlassTuning(
      cardBlur: _localCardBlur,
      cardOpacity: _localCardOpacity,
      dialogBlur: _localDialogBlur,
      dialogOpacity: _localDialogOpacity,
    );

    await prefs.setCloseBehavior(_localCloseBehavior);
    unawaited(AutostartService.setAutoStart(_autoStartEnabled));
    await prefs.setAiConfig(
      enabled: _localAiEnabled,
      serverUrl: _aiServerUrlController.text.trim(),
      selectedModel: _localAiSelectedModel,
      thinkingEnabled: _localAiThinkingEnabled,
    );
    await prefs.setChatHistoryEnabled(_localChatHistoryEnabled);
    await prefs.setBuzzAlertSettings(
      flashScreen: _localBuzzFlashScreen,
      shakeWindow: _localBuzzShakeWindow,
      bringToFront: _localBuzzBringToFront,
    );
    await prefs.setWinrmGlobalSettings(
      enabled: _localWinrmEnabled,
      defaultUsername: _winrmUsernameController.text.trim(),
      defaultPassword: _winrmPasswordController.text,
      defaultPort: int.tryParse(_winrmPortController.text.trim()) ?? 5985,
      autoBuzzOnConnect: _localWinrmAutoBuzzOnConnect,
    );
    await prefs.setImeSettings(
      mode: _localImeMode,
      autoBypassExternal: _localImeAutoBypassExternal,
    );
    ime.setMode(ImeMode.fromId(_localImeMode));
    ime.setAutoBypassExternal(_localImeAutoBypassExternal);

    await prefs.setOtaSettings(
      source: _localOtaSource,
      githubRepo: _otaGithubRepoController.text.trim(),
      githubToken: _otaGithubTokenController.text.trim(),
      checkInterval: _localOtaCheckInterval,
      serverPath: _otaServerPathController.text.trim(),
      username: _otaUsernameController.text.trim(),
      password: _otaPasswordController.text.trim(),
    );
    unawaited(
      OtaUpdateService().saveExternalConfigFile(
        OtaUpdateConfig(
          source: _localOtaSource,
          githubRepo: _otaGithubRepoController.text.trim(),
          githubToken: _otaGithubTokenController.text.trim(),
          serverPath: _otaServerPathController.text.trim(),
          username: _otaUsernameController.text.trim(),
          password: _otaPasswordController.text.trim(),
          checkInterval: _localOtaCheckInterval,
        ),
      ),
    );

    coordinator.security.isEncryptionEnabled = _encryptionEnabled;
    coordinator.security.setPassword(_passwordController.text.trim());
    coordinator.updateProfile(
      username: _nicknameController.text.trim(),
      workgroup: _workgroupController.text.trim(),
    );

    // Chỉ cập nhật card mạng và quét lại nếu người dùng thực sự thay đổi lựa chọn card
    if (!setEquals(_initialDisabledAdapters, _disabledAdapters)) {
      unawaited(coordinator.saveNetworkAdapters(_disabledAdapters));
    }

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    final effectiveBlur = theme.effectiveTier == HardwareTier.lite
        ? 0.0
        : _localDialogBlur;

    Widget dialogContent = Center(
      child: Container(
        width: 580,
        margin: const EdgeInsets.all(24),
        child: Stack(
          children: [
            // Lớp nền Dialog đằng sau tạo hiệu ứng kính mờ
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  color: (theme.isDark ? const Color(0xFF0F172A) : Colors.white)
                      .withValues(alpha: _localDialogOpacity),
                ),
              ),
            ),

            // Lớp nội dung Dialog đằng trước
            Material(
              color: Colors.transparent,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (theme.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: theme.isDark ? 0.12 : 0.08),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header & Tab Bar
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
                      child: Row(
                        children: [
                          Icon(
                            Icons.settings_suggest_rounded,
                            color: theme.colors.accentBlue,
                            size: 22,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            lang.tr('systemSettings'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: theme.isDark
                                  ? Colors.white
                                  : Colors.black87,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),

                    // Tab Bar: 4 Tabs (Advanced Settings, OTA Update, About, User Guide)
                    TabBar(
                      controller: _tabController,
                      indicatorColor: theme.colors.accentBlue,
                      labelColor: theme.colors.accentBlue,
                      unselectedLabelColor: theme.isDark
                          ? Colors.white54
                          : Colors.black54,
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: [
                        Tab(text: lang.tr('tabAdvancedSettings')),
                        Tab(text: lang.tr('tabUpdate')),
                        Tab(text: lang.tr('tabAbout')),
                        Tab(text: lang.tr('tabUserGuide')),
                      ],
                    ),

                    // Tab Content
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 400),
                      child: TabBarView(
                        controller: _tabController,
                        children: [
                          _buildAdvancedSettingsTab(theme, lang),
                          _buildOtaUpdateTab(theme, lang),
                          _buildAboutTab(theme, lang),
                          _buildUserGuideTab(theme, lang),
                        ],
                      ),
                    ),

                    // Footer Buttons (Default, Cancel, Save)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border(
                          top: BorderSide(
                            color: (theme.isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.08),
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          TextButton.icon(
                            onPressed: _resetToDefaults,
                            icon: const Icon(Icons.restore_rounded, size: 16),
                            label: Text(
                              lang.tr('defaults'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              lang.tr('cancel'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.colors.accentBlue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: _saveSettings,
                            child: Text(
                              lang.tr('saveChanges'),
                              style: const TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (effectiveBlur > 0) {
      dialogContent = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: effectiveBlur, sigmaY: effectiveBlur),
        child: dialogContent,
      );
    }
    return RepaintBoundary(child: dialogContent);
  }
}
