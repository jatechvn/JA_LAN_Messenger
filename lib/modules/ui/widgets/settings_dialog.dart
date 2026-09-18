import 'dart:async';
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
import 'glass_dialog.dart';

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

class _SettingsDialogState extends State<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Local state mirrors (commit-on-save)
  late double _localCardBlur;
  late double _localCardOpacity;
  late double _localDialogBlur;
  late double _localDialogOpacity;

  // Glass tuning initial values for reverting on cancel
  late double _initialCardBlur;
  late double _initialCardOpacity;
  late double _initialDialogBlur;
  late double _initialDialogOpacity;
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _themeProvider ??= Provider.of<ThemeProvider>(context, listen: false);
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    final theme = context.read<ThemeProvider>();
    _initialCardBlur = theme.cardBlur;
    _initialCardOpacity = theme.cardOpacity;
    _initialDialogBlur = theme.dialogBlur;
    _initialDialogOpacity = theme.dialogOpacity;

    _localCardBlur = _initialCardBlur;
    _localCardOpacity = _initialCardOpacity;
    _localDialogBlur = _initialDialogBlur;
    _localDialogOpacity = _initialDialogOpacity;

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

    _localAvailableModels = List.of(coordinator.availableAiModels);
    if (!_localAvailableModels.any((m) => m.id == _localAiSelectedModel)) {
      _localAvailableModels.add(AiModelInfo.findById(_localAiSelectedModel));
    }

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
      final theme = _themeProvider;
      scheduleMicrotask(() {
        theme?.setLiveGlassmorphism(
          cardBlur: cardBlur,
          cardOpacity: cardOpacity,
          dialogBlur: dialogBlur,
          dialogOpacity: dialogOpacity,
        );
      });
    }
    _tabController.dispose();
    _nicknameController.dispose();
    _workgroupController.dispose();
    _tcpPortController.dispose();
    _filePortController.dispose();
    _passwordController.dispose();
    _aiServerUrlController.dispose();
    super.dispose();
  }

  void _resetToDefaults() {
    setState(() {
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
      _autoStartEnabled = false;
      _localAiEnabled = true;
      _aiServerUrlController.text = 'http://172.21.175.20:11434';
      _localAiSelectedModel = 'qwen3.5:4b';
      _localAiThinkingEnabled = false;
      _localChatHistoryEnabled = true;
      _aiConnectionTestResult = null;
      _aiConnectionTestSuccess = null;
    });
    _themeProvider?.setLiveGlassmorphism(
      cardBlur: 24.0,
      cardOpacity: 0.28,
      dialogBlur: 20.0,
      dialogOpacity: 0.88,
    );
  }

  Future<void> _testAiConnection() async {
    setState(() {
      _isTestingAiConnection = true;
      _aiConnectionTestResult = null;
      _aiConnectionTestSuccess = null;
    });

    final coordinator = context.read<MessengerCoordinator>();
    final result = await coordinator.aiService.testConnection(
      _aiServerUrlController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _isTestingAiConnection = false;
      _aiConnectionTestSuccess = result.success;
      if (result.success) {
        if (result.models.isNotEmpty) {
          _localAvailableModels = List.of(result.models);
          AiModelInfo.updateDiscoveredModels(result.models);
          unawaited(AppPreferences().setCachedAiModels(result.models));
          if (!_localAvailableModels.any(
            (m) => m.id == _localAiSelectedModel,
          )) {
            _localAiSelectedModel = _localAvailableModels.first.id;
          }
        }
        _aiConnectionTestResult =
            '✅ Kết nối thành công (${result.pingMs}ms) • JA-AI Engine v${result.version} • ${result.availableModels.length} models';
      } else {
        _aiConnectionTestResult = '❌ ${result.error ?? 'Kết nối thất bại'}';
      }
    });
  }

  Future<void> _refreshAiModels() async {
    if (_isRefreshingModels) return;
    setState(() => _isRefreshingModels = true);
    try {
      final coordinator = context.read<MessengerCoordinator>();
      final models = await coordinator.refreshAiModels(
        customUrl: _aiServerUrlController.text.trim(),
      );
      if (mounted) {
        setState(() {
          _localAvailableModels = List.of(coordinator.availableAiModels);
          if (!_localAvailableModels.any(
            (m) => m.id == _localAiSelectedModel,
          )) {
            _localAiSelectedModel = _localAvailableModels.isNotEmpty
                ? _localAvailableModels.first.id
                : _localAiSelectedModel;
          }
        });
        final lang = Provider.of<LanguageProvider>(context, listen: false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              models.isEmpty
                  ? lang.tr('noModelsOnServer')
                  : lang
                        .tr('aiModelsRefreshed')
                        .replaceFirst('%d', models.length.toString()),
            ),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
    } finally {
      if (mounted) {
        setState(() => _isRefreshingModels = false);
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    _isSaving = true;
    _saved = true;

    final theme = context.read<ThemeProvider>();
    final coordinator = context.read<MessengerCoordinator>();

    await theme.saveGlassTuning(
      cardBlur: _localCardBlur,
      cardOpacity: _localCardOpacity,
      dialogBlur: _localDialogBlur,
      dialogOpacity: _localDialogOpacity,
    );

    final prefs = AppPreferences();
    await prefs.setCloseBehavior(_localCloseBehavior);
    unawaited(AutostartService.setAutoStart(_autoStartEnabled));
    await prefs.setAiConfig(
      enabled: _localAiEnabled,
      serverUrl: _aiServerUrlController.text.trim(),
      selectedModel: _localAiSelectedModel,
      thinkingEnabled: _localAiThinkingEnabled,
    );
    await prefs.setChatHistoryEnabled(_localChatHistoryEnabled);

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

  @override
  Widget build(BuildContext context) {
    final theme = ThemeProvider.of(context);
    final lang = context.watch<LanguageProvider>();

    final effectiveBlur = _localDialogBlur;

    Widget dialogContent = Center(
      child: Container(
        width: 540,
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

                    // Tab Bar: 3 Tabs (Advanced Settings, About, User Guide)
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

  Widget _buildAdvancedSettingsTab(ThemeProvider theme, LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Profile Settings
          Text(
            lang.tr('myProfileOnLan'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colors.accentBlue,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nicknameController,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    labelText: lang.tr('nickname'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _workgroupController,
                  style: const TextStyle(fontSize: 12.5),
                  decoration: InputDecoration(
                    labelText: lang.tr('workgroup'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. Glassmorphism Tuning (Accordion)
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              initiallyExpanded: true,
              tilePadding: EdgeInsets.zero,
              title: Text(
                lang.tr('glassTuningTitle'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colors.accentBlue,
                ),
              ),
              children: [
                _buildGlassSlider(
                  label: lang.tr('cardBlur'),
                  value: _localCardBlur,
                  min: 0,
                  max: 40,
                  isPercent: false,
                  onChanged: (v) {
                    setState(() => _localCardBlur = v);
                    _themeProvider?.setLiveGlassmorphism(cardBlur: v);
                  },
                ),
                _buildGlassSlider(
                  label: lang.tr('cardOpacity'),
                  value: _localCardOpacity,
                  min: 0.05,
                  max: 0.95,
                  isPercent: true,
                  onChanged: (v) {
                    setState(() => _localCardOpacity = v);
                    _themeProvider?.setLiveGlassmorphism(cardOpacity: v);
                  },
                ),
                _buildGlassSlider(
                  label: lang.tr('dialogBlur'),
                  value: _localDialogBlur,
                  min: 0,
                  max: 40,
                  isPercent: false,
                  onChanged: (v) {
                    setState(() => _localDialogBlur = v);
                    _themeProvider?.setLiveGlassmorphism(dialogBlur: v);
                  },
                ),
                _buildGlassSlider(
                  label: lang.tr('dialogOpacity'),
                  value: _localDialogOpacity,
                  min: 0.30,
                  max: 0.98,
                  isPercent: true,
                  onChanged: (v) {
                    setState(() => _localDialogOpacity = v);
                    _themeProvider?.setLiveGlassmorphism(dialogOpacity: v);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(lang.tr('scanAdapters')),
          for (final adapter
              in context.watch<MessengerCoordinator>().activeAdapters)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(adapter.name),
              subtitle: Text('${adapter.ip} • ${adapter.subnet}'),
              value: !_disabledAdapters.contains(adapter.name),
              onChanged: (value) => setState(() {
                if (value == true) {
                  _disabledAdapters.remove(adapter.name);
                } else {
                  _disabledAdapters.add(adapter.name);
                }
              }),
            ),
          const SizedBox(height: 14),
          // 3. Network Ports & Encryption
          Text(
            lang.tr('networkConfigTitle'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colors.accentBlue,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('customPasswordTitle'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('customPasswordSubtitle'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _encryptionEnabled,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _encryptionEnabled = val),
          ),
          if (_encryptionEnabled) ...[
            const SizedBox(height: 6),
            TextField(
              controller: _passwordController,
              obscureText: true,
              style: const TextStyle(fontSize: 12.5),
              decoration: InputDecoration(
                labelText: lang.tr('beebeepPasswordLabel'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 4. System & Startup Settings
          Text(
            lang.tr('systemAndStartup'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colors.accentBlue,
            ),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('bootWithWindows'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('bootWithWindowsDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _autoStartEnabled,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _autoStartEnabled = val),
          ),
          const SizedBox(height: 10),
          Text(
            lang.tr('windowCloseAction'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: theme.isDark ? 0.04 : 0.03,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: RadioGroup<String>(
              groupValue: _localCloseBehavior,
              onChanged: (val) {
                if (val != null) setState(() => _localCloseBehavior = val);
              },
              child: Column(
                children: [
                  InkWell(
                    onTap: () => setState(() => _localCloseBehavior = 'ask'),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: 'ask',
                            activeColor: theme.colors.accentBlue,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lang.tr('closeActionAsk'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: (theme.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05),
                  ),
                  InkWell(
                    onTap: () =>
                        setState(() => _localCloseBehavior = 'minimize'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: 'minimize',
                            activeColor: theme.colors.accentBlue,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lang.tr('closeActionMinimize'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: (theme.isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05),
                  ),
                  InkWell(
                    onTap: () => setState(() => _localCloseBehavior = 'exit'),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Row(
                        children: [
                          Radio<String>(
                            value: 'exit',
                            activeColor: theme.colors.accentRose,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              lang.tr('closeActionExit'),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 5. AI Assistant (Ollama) Settings
          Row(
            children: [
              Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: theme.colors.accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                lang.tr('aiSettingsTitle'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('enableAiTitle'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('enableAiSubtitle'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localAiEnabled,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _localAiEnabled = val),
          ),
          if (_localAiEnabled) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _aiServerUrlController,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      labelText: lang.tr('aiServerUrlLabel'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.dns_outlined, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    icon: _isTestingAiConnection
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check_rounded, size: 16),
                    label: Text(
                      _isTestingAiConnection
                          ? lang.tr('aiConnecting')
                          : lang.tr('testAiConnection'),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: _isTestingAiConnection
                        ? null
                        : _testAiConnection,
                  ),
                ),
              ],
            ),
            if (_aiConnectionTestResult != null) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color:
                      (_aiConnectionTestSuccess == true
                              ? Colors.green
                              : Colors.red)
                          .withValues(alpha: theme.isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color:
                        (_aiConnectionTestSuccess == true
                                ? Colors.green
                                : Colors.red)
                            .withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  _aiConnectionTestResult!,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _aiConnectionTestSuccess == true
                        ? (theme.isDark
                              ? Colors.greenAccent
                              : Colors.green.shade800)
                        : (theme.isDark
                              ? Colors.redAccent
                              : Colors.red.shade800),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(
                      'ai_model_${_localAiSelectedModel}_${_localAvailableModels.length}',
                    ),
                    isExpanded: true,
                    initialValue:
                        _localAvailableModels.any(
                          (m) => m.id == _localAiSelectedModel,
                        )
                        ? _localAiSelectedModel
                        : (_localAvailableModels.isNotEmpty
                              ? _localAvailableModels.first.id
                              : null),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: theme.isDark ? Colors.white : Colors.black87,
                    ),
                    decoration: InputDecoration(
                      labelText: lang.tr('defaultAiModel'),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(
                        Icons.psychology_outlined,
                        size: 18,
                      ),
                    ),
                    items: _localAvailableModels.map((m) {
                      IconData icon = Icons.smart_toy_outlined;
                      Color iconCol = theme.colors.accentBlue;
                      if (m.supportsVision) {
                        icon = Icons.visibility_rounded;
                        iconCol = Colors.orangeAccent;
                      } else if (m.supportsThinking) {
                        icon = Icons.psychology_rounded;
                        iconCol = Colors.purpleAccent;
                      } else if (m.id.toLowerCase().contains('coder') ||
                          m.id.toLowerCase().contains('code')) {
                        icon = Icons.code_rounded;
                        iconCol = Colors.tealAccent;
                      }
                      return DropdownMenuItem<String>(
                        value: m.id,
                        child: Row(
                          children: [
                            Icon(icon, size: 16, color: iconCol),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                m.displayName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _localAiSelectedModel = val);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: lang.tr('refreshAiModels'),
                  icon: _isRefreshingModels
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh_rounded),
                  onPressed: _isRefreshingModels ? null : _refreshAiModels,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                lang.tr('thinkingMode'),
                style: const TextStyle(fontSize: 12.5),
              ),
              subtitle: Text(
                lang.tr('thinkingModeDesc'),
                style: const TextStyle(fontSize: 11),
              ),
              value: _localAiThinkingEnabled,
              activeTrackColor: theme.colors.accentBlue,
              onChanged: (val) => setState(() => _localAiThinkingEnabled = val),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: theme.isDark ? 0.04 : 0.03,
                ),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: (theme.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                ),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceAround,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    '${lang.tr('aiSpecContext')}: 4096',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  Text(
                    '•',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                  Text(
                    '${lang.tr('aiSpecQueue')}: 4',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                  Text(
                    '•',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.isDark ? Colors.white30 : Colors.black26,
                    ),
                  ),
                  Text(
                    '${lang.tr('aiSpecTimeout')}: 180s',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: theme.isDark ? Colors.white60 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 6. Chat History (Persistent Storage)
          Row(
            children: [
              Icon(
                Icons.history_rounded,
                size: 16,
                color: theme.colors.accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                lang.tr('chatHistoryTitle'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: theme.colors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('enableChatHistory'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('enableChatHistoryDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localChatHistoryEnabled,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _localChatHistoryEnabled = val),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FutureBuilder<int>(
                future: context
                    .read<MessengerCoordinator>()
                    .chatHistory
                    .getHistorySizeBytes(),
                builder: (context, snapshot) {
                  final bytes = snapshot.data ?? 0;
                  return Text(
                    '${lang.tr('chatHistorySize')}: ${ChatHistoryService.formatBytes(bytes)}',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: theme.isDark ? Colors.white60 : Colors.black54,
                    ),
                  );
                },
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colors.accentRose,
                  side: BorderSide(
                    color: theme.colors.accentRose.withValues(alpha: 0.5),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                label: Text(
                  lang.tr('clearAllChatHistory'),
                  style: const TextStyle(fontSize: 11.5),
                ),
                onPressed: () {
                  final coordinator = context.read<MessengerCoordinator>();
                  showGlassDialog(
                    context: context,
                    builder: (ctx) => GlassDialog(
                      title: lang.tr('clearAllChatHistory'),
                      icon: Icons.delete_sweep_rounded,
                      width: 400,
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: Text(lang.tr('cancel')),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colors.accentRose,
                          ),
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            await coordinator.clearAllChatHistory();
                            if (mounted) {
                              setState(() {});
                              coordinator.showToast('chatHistoryCleared');
                            }
                          },
                          child: Text(lang.tr('confirm')),
                        ),
                      ],
                      child: Text(
                        lang.tr('clearAllChatHistoryConfirm'),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab(ThemeProvider theme, LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [theme.colors.accentBlue, theme.colors.accentCyan],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.forum_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    '${lang.tr('versionLabel')} ${BuildInfo.version} (${BuildInfo.debugTimestamp})',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            lang.tr('aboutAppDesc1'),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            lang.tr('aboutAppDesc2'),
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: (theme.isDark ? Colors.white : Colors.black).withValues(
                alpha: 0.04,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lang.tr('techInfoTitle'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentBlue,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '• UDP Broadcast/Multicast Port: 36475 (224.0.64.75)',
                  style: TextStyle(fontSize: 11.5),
                ),
                const Text(
                  '• TCP Control/Chat Port: 6475',
                  style: TextStyle(fontSize: 11.5),
                ),
                const Text(
                  '• TCP File Transfer Port: 6476',
                  style: TextStyle(fontSize: 11.5),
                ),
                Text(
                  lang.tr('techInfoPureDart'),
                  style: const TextStyle(fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserGuideTab(ThemeProvider theme, LanguageProvider lang) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGuideItem(
            theme,
            step: '1',
            title: lang.tr('guideStep1Title'),
            desc: lang.tr('guideStep1Desc'),
          ),
          const SizedBox(height: 14),
          _buildGuideItem(
            theme,
            step: '2',
            title: lang.tr('guideStep2Title'),
            desc: lang.tr('guideStep2Desc'),
          ),
          const SizedBox(height: 14),
          _buildGuideItem(
            theme,
            step: '3',
            title: lang.tr('guideStep3Title'),
            desc: lang.tr('guideStep3Desc'),
          ),
          const SizedBox(height: 14),
          _buildGuideItem(
            theme,
            step: '4',
            title: lang.tr('guideStep4Title'),
            desc: lang.tr('guideStep4Desc'),
          ),
        ],
      ),
    );
  }

  Widget _buildGuideItem(
    ThemeProvider theme, {
    required String step,
    required String title,
    required String desc,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: theme.colors.accentBlue,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            step,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.isDark ? Colors.white60 : Colors.black54,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
