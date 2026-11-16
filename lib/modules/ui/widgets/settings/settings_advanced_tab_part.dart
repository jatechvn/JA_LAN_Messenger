part of '../settings_dialog.dart';

mixin _SettingsAdvancedTabMixin on _SettingsDialogStateBase {
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

  Future<void> _testWinrmConnection() async {
    final ip = _winrmTestIpController.text.trim();
    if (ip.isEmpty) {
      setState(() {
        _winrmConnectionTestSuccess = false;
        _winrmConnectionTestResult =
            'Vui lòng nhập địa chỉ IP máy cần kiểm tra.';
      });
      return;
    }

    final user = _winrmUsernameController.text.trim();
    if (user.isEmpty) {
      setState(() {
        _winrmConnectionTestSuccess = false;
        _winrmConnectionTestResult = 'Vui lòng nhập tên tài khoản WinRM.';
      });
      return;
    }

    final pass = _winrmPasswordController.text;
    final port = int.tryParse(_winrmPortController.text.trim()) ?? 5985;

    setState(() {
      _isTestingWinrmConnection = true;
      _winrmConnectionTestResult = null;
      _winrmConnectionTestSuccess = null;
    });

    try {
      final coordinator = context.read<MessengerCoordinator>();
      final result = await coordinator.winrmLauncher.testConnection(
        ip: ip,
        port: port,
        username: user,
        password: pass,
      );

      if (!mounted) return;
      setState(() {
        _isTestingWinrmConnection = false;
        _winrmConnectionTestSuccess = result.success;
        _winrmConnectionTestResult = result.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isTestingWinrmConnection = false;
        _winrmConnectionTestSuccess = false;
        _winrmConnectionTestResult = 'Lỗi kiểm tra: $e';
      });
    }
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
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Tooltip(
                message: lang.tr('changeAvatar'),
                child: InkWell(
                  onTap: () async {
                    await AvatarPickerDialog.show(context);
                    if (mounted) setState(() {});
                  },
                  borderRadius: BorderRadius.circular(24),
                  child: Stack(
                    children: [
                      AppAvatar.local(size: 46),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: Color(0xFF3B82F6),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.edit_rounded,
                            size: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 14),
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

          // 2. Performance & Hardware Tier Tuning
          Text(
            lang.tr('perfTierTitle'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: theme.colors.accentBlue,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            lang.tr('perfTierSubtitle'),
            style: TextStyle(
              fontSize: 11,
              color: theme.isDark ? Colors.white60 : Colors.black54,
            ),
          ),
          const SizedBox(height: 10),

          // Hardware Profile Info Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      theme.detectedTier.icon,
                      size: 16,
                      color: theme.detectedTier.color,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${lang.tr('hardwareScoreLabel')}: ${theme.hardwareScore}/100 • ${theme.detectedTier.label} (${theme.detectedTier.desc})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: theme.detectedTier.color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${lang.tr('detectedHardwareLabel')}: ${theme.cpuModel ?? '${theme.cpuCores} Cores'} | ${theme.gpuModel ?? 'Default Display'}',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.isDark ? Colors.white70 : Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Tier Selection Chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPerfTierChip(
                mode: PerfTierMode.auto,
                label:
                    '${lang.tr('perfTierAuto')} (${theme.detectedTier.label})',
                desc: null,
                icon: Icons.auto_awesome_rounded,
                theme: theme,
              ),
              _buildPerfTierChip(
                mode: PerfTierMode.ultra,
                label: lang.tr('perfTierUltra'),
                desc: lang.tr('perfTierUltraDesc'),
                icon: Icons.bolt_rounded,
                theme: theme,
              ),
              _buildPerfTierChip(
                mode: PerfTierMode.balanced,
                label: lang.tr('perfTierBalanced'),
                desc: lang.tr('perfTierBalancedDesc'),
                icon: Icons.balance_rounded,
                theme: theme,
              ),
              _buildPerfTierChip(
                mode: PerfTierMode.lite,
                label: lang.tr('perfTierLite'),
                desc: lang.tr('perfTierLiteDesc'),
                icon: Icons.eco_rounded,
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 2.1. Power Optimizer & Idle Sleep Mode Card
          Container(
            padding: const EdgeInsets.all(12),
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
            child: Material(
              color: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.energy_savings_leaf_rounded,
                        size: 16,
                        color: theme.colors.accentEmerald,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lang.tr('powerOptimizerTitle'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: theme.colors.accentEmerald,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              lang.tr('powerOptimizerDesc'),
                              style: TextStyle(
                                fontSize: 10.5,
                                color: theme.isDark
                                    ? Colors.white60
                                    : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    key: const ValueKey('power-optimizer-switch-tile'),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      lang.tr('idleSleepTitle'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      lang.tr('idleSleepDesc'),
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                    value: _localEnableIdleSleep,
                    activeThumbColor: theme.colors.accentEmerald,
                    onChanged: (val) {
                      setState(() => _localEnableIdleSleep = val);
                    },
                  ),
                  if (_localEnableIdleSleep) ...[
                    const SizedBox(height: 8),
                    Text(
                      lang.tr('idleTimeoutLabel'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: theme.isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _buildIdleTimeoutChip(12, lang.tr('idle12s'), theme),
                        _buildIdleTimeoutChip(30, lang.tr('idle30s'), theme),
                        _buildIdleTimeoutChip(60, lang.tr('idle60s'), theme),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 3. Glassmorphism Tuning (Accordion)
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
          // 4.5. Buzz / Nudge Alert Settings
          Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                size: 16,
                color: theme.colors.accentAmber,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lang.tr('buzzAlertSettings'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentAmber,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  minimumSize: const Size(60, 26),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 14),
                label: const Text('Test Buzz', style: TextStyle(fontSize: 11)),
                onPressed: () {
                  context
                      .read<MessengerCoordinator>()
                      .triggerBuzzAlertForTesting();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('buzzFlashScreen'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('buzzFlashScreenDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localBuzzFlashScreen,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _localBuzzFlashScreen = val),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('buzzShakeWindow'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('buzzShakeWindowDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localBuzzShakeWindow,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _localBuzzShakeWindow = val),
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('buzzBringToFront'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('buzzBringToFrontDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localBuzzBringToFront,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _localBuzzBringToFront = val),
          ),
          const SizedBox(height: 16),
          // 4.6. WinRM Remote Launch Settings
          Row(
            children: [
              Icon(
                Icons.settings_remote_rounded,
                size: 16,
                color: theme.colors.accentCyan,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lang.tr('winrmSettings'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentCyan,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('winrmSettings'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('winrmEnableDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localWinrmEnabled,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) => setState(() => _localWinrmEnabled = val),
          ),
          if (_localWinrmEnabled) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (theme.isDark ? Colors.white : Colors.black).withValues(
                  alpha: theme.isDark ? 0.04 : 0.02,
                ),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: (theme.isDark ? Colors.white : Colors.black)
                      .withValues(alpha: 0.08),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _winrmUsernameController,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            labelText: lang.tr('winrmDefaultUser'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(
                              Icons.person_outline_rounded,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _winrmPasswordController,
                          obscureText: _obscureWinrmPassword,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            labelText: lang.tr('winrmDefaultPass'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 16,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscureWinrmPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                                size: 16,
                              ),
                              onPressed: () => setState(
                                () => _obscureWinrmPassword =
                                    !_obscureWinrmPassword,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      SizedBox(
                        width: 140,
                        child: TextField(
                          controller: _winrmPortController,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            labelText: lang.tr('winrmPort'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(
                              Icons.numbers_rounded,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(
                            () => _localWinrmAutoBuzzOnConnect =
                                !_localWinrmAutoBuzzOnConnect,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          child: Row(
                            children: [
                              Checkbox(
                                value: _localWinrmAutoBuzzOnConnect,
                                activeColor: theme.colors.accentBlue,
                                onChanged: (val) => setState(
                                  () => _localWinrmAutoBuzzOnConnect =
                                      val ?? true,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  lang.tr('winrmAutoBuzz'),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  Text(
                    lang.tr('winrmTestConnection'),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: theme.isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _winrmTestIpController,
                          style: const TextStyle(fontSize: 12.5),
                          decoration: InputDecoration(
                            hintText: lang.tr('winrmTestIpHint'),
                            isDense: true,
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(
                              Icons.computer_rounded,
                              size: 16,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: theme.colors.accentBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _isTestingWinrmConnection
                            ? null
                            : _testWinrmConnection,
                        icon: _isTestingWinrmConnection
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.network_check_rounded, size: 16),
                        label: Text(
                          _isTestingWinrmConnection
                              ? lang.tr('winrmTesting')
                              : lang.tr('winrmTestConnection'),
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  if (_winrmConnectionTestResult != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color:
                            (_winrmConnectionTestSuccess == true
                                    ? Colors.green
                                    : Colors.red)
                                .withValues(alpha: theme.isDark ? 0.20 : 0.08),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color:
                              (_winrmConnectionTestSuccess == true
                                      ? Colors.green
                                      : Colors.red)
                                  .withValues(alpha: 0.5),
                          width: 0.8,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _winrmConnectionTestSuccess == true
                                ? Icons.check_circle_outline_rounded
                                : Icons.error_outline_rounded,
                            size: 16,
                            color: _winrmConnectionTestSuccess == true
                                ? Colors.green
                                : Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _winrmConnectionTestResult!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: _winrmConnectionTestSuccess == true
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
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          // 4.8. Built-in Input Method (IME) Settings
          Row(
            children: [
              Icon(
                Icons.keyboard_alt_outlined,
                size: 16,
                color: theme.colors.accentEmerald,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  lang.tr('imeSettings'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentEmerald,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  lang.tr('imeMode'),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 260),
                child: DropdownButton<String>(
                  value: _localImeMode,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: theme.isDark
                      ? const Color(0xFF1E293B)
                      : Colors.white,
                  underline: const SizedBox.shrink(),
                  items: [
                    DropdownMenuItem(
                      value: 'auto',
                      child: Text(
                        lang.tr('imeAuto'),
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'telex',
                      child: Text(
                        lang.tr('imeTelex'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'pinyin',
                      child: Text(
                        lang.tr('imePinyin'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'off',
                      child: Text(
                        lang.tr('imeOff'),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _localImeMode = val);
                    }
                  },
                ),
              ),
            ],
          ),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: Text(
              lang.tr('imeAutoBypass'),
              style: const TextStyle(fontSize: 12.5),
            ),
            subtitle: Text(
              lang.tr('imeAutoBypassDesc'),
              style: const TextStyle(fontSize: 11),
            ),
            value: _localImeAutoBypassExternal,
            activeTrackColor: theme.colors.accentBlue,
            onChanged: (val) =>
                setState(() => _localImeAutoBypassExternal = val),
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
}
