part of '../settings_dialog.dart';

mixin _SettingsOtaTabMixin on _SettingsDialogStateBase {
  Future<void> _testServerConnection() async {
    setState(() {
      _isTestingServerConnection = true;
      _serverConnectionResult = null;
      _serverConnectionSuccess = null;
    });

    final lang = context.read<LanguageProvider>();

    try {
      if (_localOtaSource == 'github') {
        final ghRes = await OtaUpdateService().testGitHubConnection(
          repo: _otaGithubRepoController.text.trim(),
          token: _otaGithubTokenController.text.trim(),
        );
        if (mounted) {
          final success = ghRes['success'] as bool? ?? false;
          setState(() {
            _isTestingServerConnection = false;
            _serverConnectionSuccess = success;
            _serverConnectionResult = ghRes['message'] as String? ?? '';
          });
        }
      } else if (_localOtaSource == 'lan') {
        final path = _otaServerPathController.text.trim();
        final user = _otaUsernameController.text.trim();
        final pass = _otaPasswordController.text.trim();
        final success = await OtaUpdateService().connectSmbShare(
          path: path,
          username: user,
          password: pass,
        );
        if (mounted) {
          setState(() {
            _isTestingServerConnection = false;
            _serverConnectionSuccess = success;
            _serverConnectionResult = success
                ? lang.tr('serverConnectionSuccess')
                : lang.tr('serverConnectionFailed', [
                    'Không thể truy cập thư mục',
                  ]);
          });
        }
      } else {
        // 'auto' mode: kiểm tra cả LAN và GitHub
        final path = _otaServerPathController.text.trim();
        final user = _otaUsernameController.text.trim();
        final pass = _otaPasswordController.text.trim();
        final lanSuccess = await OtaUpdateService().connectSmbShare(
          path: path,
          username: user,
          password: pass,
        );
        final ghRes = await OtaUpdateService().testGitHubConnection(
          repo: _otaGithubRepoController.text.trim(),
          token: _otaGithubTokenController.text.trim(),
        );
        final ghSuccess = ghRes['success'] as bool? ?? false;

        if (mounted) {
          final isOk = lanSuccess || ghSuccess;
          final lanMsg = lanSuccess ? 'LAN: OK' : 'LAN: Fail';
          final ghMsg = ghSuccess
              ? 'GitHub: OK (${ghRes['latestTag'] ?? ''})'
              : 'GitHub: Fail (${ghRes['message'] ?? ''})';
          setState(() {
            _isTestingServerConnection = false;
            _serverConnectionSuccess = isOk;
            _serverConnectionResult = '$lanMsg | $ghMsg';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTestingServerConnection = false;
          _serverConnectionSuccess = false;
          _serverConnectionResult = e.toString();
        });
      }
    }
  }

  Future<void> _checkForUpdatesManually() async {
    setState(() {
      _isCheckingForUpdates = true;
      _manualUpdateCheckResult = null;
    });

    final path = _otaServerPathController.text.trim();
    final repo = _otaGithubRepoController.text.trim();
    final token = _otaGithubTokenController.text.trim();

    try {
      final result = await OtaUpdateService().checkForUpdates(
        overrideServerPath: path,
        overrideSource: _localOtaSource,
        overrideRepo: repo,
        overrideToken: token,
        isManual: true,
      );
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
          _manualUpdateCheckResult = result;
        });
        if (result.hasUpdate && result.packageInfo != null) {
          showGlassUpdateDialog(
            context: context,
            packageInfo: result.packageInfo!,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingForUpdates = false;
          _manualUpdateCheckResult = UpdateCheckResult(
            hasUpdate: false,
            currentVersion: appVersion,
            isConnectionSuccess: false,
            errorMessage: e.toString(),
          );
        });
      }
    }
  }

  void _openConfigFolder() {
    final file = OtaUpdateService().getConfigFile();
    if (Platform.isWindows) {
      if (file.existsSync()) {
        Process.run('explorer.exe', ['/select,', file.path]);
      } else {
        Process.run('explorer.exe', [file.parent.path]);
      }
    }
  }

  Widget _buildOtaUpdateTab(ThemeProvider theme, LanguageProvider lang) {
    final prefs = AppPreferences();
    final isDark = theme.isDark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Version Status Card
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.05 : 0.03,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            theme.colors.accentBlue,
                            theme.colors.accentCyan,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.system_update_alt_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${lang.tr('currentVersion')}: v$appVersion',
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            prefs.otaLastCheckTime != null
                                ? '${lang.tr('lastChecked')}: ${prefs.otaLastCheckTime!.hour.toString().padLeft(2, '0')}:${prefs.otaLastCheckTime!.minute.toString().padLeft(2, '0')} ${prefs.otaLastCheckTime!.day}/${prefs.otaLastCheckTime!.month}/${prefs.otaLastCheckTime!.year}'
                                : lang.tr('neverChecked'),
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    FilledButton.icon(
                      key: const ValueKey('ota-check-button'),
                      onPressed: _isCheckingForUpdates
                          ? null
                          : _checkForUpdatesManually,
                      icon: _isCheckingForUpdates
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Icon(Icons.refresh_rounded, size: 15),
                      label: Text(
                        _isCheckingForUpdates
                            ? lang.tr('checkingUpdates')
                            : lang.tr('checkUpdatesNow'),
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.colors.accentBlue,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        textStyle: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_manualUpdateCheckResult != null) ...[
                  const SizedBox(height: 10),
                  if (_manualUpdateCheckResult!.hasUpdate) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colors.accentEmerald.withValues(
                          alpha: 0.12,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colors.accentEmerald.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: theme.colors.accentEmerald,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              lang.tr('updateAvailable', [
                                _manualUpdateCheckResult!
                                        .packageInfo
                                        ?.version
                                        .displayVersion ??
                                    '',
                              ]),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: theme.colors.accentEmerald,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              if (_manualUpdateCheckResult?.packageInfo !=
                                  null) {
                                showGlassUpdateDialog(
                                  context: context,
                                  packageInfo:
                                      _manualUpdateCheckResult!.packageInfo!,
                                );
                              }
                            },
                            child: Text(lang.tr('updateNow')),
                          ),
                        ],
                      ),
                    ),
                  ] else if (_manualUpdateCheckResult!.errorMessage !=
                      null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colors.accentRose.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colors.accentRose.withValues(
                            alpha: 0.35,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: theme.colors.accentRose,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _manualUpdateCheckResult!.errorMessage!,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: theme.colors.accentRose,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: theme.colors.accentBlue.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: theme.colors.accentBlue.withValues(
                            alpha: 0.25,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 16,
                            color: theme.colors.accentBlue,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              lang.tr('noUpdatesAvailable', ['v$appVersion']),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          const SizedBox(height: 18),

          // 2. OTA Source / Channel Selector
          Row(
            children: [
              Icon(
                Icons.alt_route_rounded,
                size: 16,
                color: theme.colors.accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                lang.tr('otaSource'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: theme.colors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(
                alpha: isDark ? 0.05 : 0.04,
              ),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('ota-source-dropdown'),
                value: _localOtaSource,
                isExpanded: true,
                dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                items: [
                  DropdownMenuItem(
                    value: 'auto',
                    child: Text(
                      lang.tr('otaSourceAuto'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'github',
                    child: Text(
                      lang.tr('otaSourceGithub'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'lan',
                    child: Text(
                      lang.tr('otaSourceLan'),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _localOtaSource = val);
                },
              ),
            ),
          ),

          // 3. GitHub Releases Configuration (Hiển thị nếu source là 'github' hoặc 'auto')
          if (_localOtaSource == 'github' || _localOtaSource == 'auto') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.hub_rounded,
                  size: 16,
                  color: theme.colors.accentBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  lang.tr('githubRepo'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('ota-github-repo-input'),
              controller: _otaGithubRepoController,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas, monospace',
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: lang.tr('githubRepoHint'),
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                filled: true,
                fillColor: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: isDark ? 0.05 : 0.04,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.12,
                    ),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              lang.tr('githubToken'),
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              key: const ValueKey('ota-github-token-input'),
              controller: _otaGithubTokenController,
              obscureText: _obscureOtaGithubToken,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas, monospace',
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: lang.tr('githubTokenHint'),
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                filled: true,
                fillColor: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: isDark ? 0.05 : 0.04,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.12,
                    ),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureOtaGithubToken
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 16,
                  ),
                  splashRadius: 14,
                  onPressed: () => setState(
                    () => _obscureOtaGithubToken = !_obscureOtaGithubToken,
                  ),
                ),
              ),
            ),
          ],

          // 4. LAN SMB Configuration (Hiển thị nếu source là 'lan' hoặc 'auto')
          if (_localOtaSource == 'lan' || _localOtaSource == 'auto') ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  Icons.dns_rounded,
                  size: 16,
                  color: theme.colors.accentBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  lang.tr('otaServerPath'),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: theme.colors.accentBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('ota-server-path-input'),
              controller: _otaServerPathController,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'Consolas, monospace',
              ),
              decoration: InputDecoration(
                isDense: true,
                hintText: lang.tr('otaServerPathHint'),
                hintStyle: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.white30 : Colors.black26,
                ),
                filled: true,
                fillColor: (isDark ? Colors.white : Colors.black).withValues(
                  alpha: isDark ? 0.05 : 0.04,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(
                    color: (isDark ? Colors.white : Colors.black).withValues(
                      alpha: 0.12,
                    ),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lang.tr('otaUsername'),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _otaUsernameController,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: isDark ? 0.05 : 0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.12),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lang.tr('otaPassword'),
                        style: TextStyle(
                          fontSize: 10.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _otaPasswordController,
                        obscureText: _obscureOtaPassword,
                        style: const TextStyle(fontSize: 12),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: isDark ? 0.05 : 0.04),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: (isDark ? Colors.white : Colors.black)
                                  .withValues(alpha: 0.12),
                            ),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureOtaPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                              size: 16,
                            ),
                            splashRadius: 14,
                            onPressed: () => setState(
                              () => _obscureOtaPassword = !_obscureOtaPassword,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),

          // 5. Check Interval Setting
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 16,
                color: theme.colors.accentBlue,
              ),
              const SizedBox(width: 6),
              Text(
                lang.tr('otaCheckInterval'),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: theme.colors.accentBlue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Quick selection buttons (nút chọn nhanh thay vì droplist)
          Wrap(
            key: const ValueKey('ota-interval-dropdown'),
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildOtaIntervalChip(
                value: 'daily',
                label: lang.tr('intervalDaily'),
                icon: Icons.today_rounded,
                theme: theme,
                isDark: isDark,
              ),
              _buildOtaIntervalChip(
                value: 'weekly',
                label: lang.tr('intervalWeekly'),
                icon: Icons.date_range_rounded,
                theme: theme,
                isDark: isDark,
              ),
              _buildOtaIntervalChip(
                value: 'monthly',
                label: lang.tr('intervalMonthly'),
                icon: Icons.calendar_month_rounded,
                theme: theme,
                isDark: isDark,
              ),
              _buildOtaIntervalChip(
                value: 'off',
                label: lang.tr('intervalOff'),
                icon: Icons.cancel_outlined,
                theme: theme,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Action buttons: Test connection & Open config folder
          Row(
            children: [
              OutlinedButton.icon(
                key: const ValueKey('ota-test-connection-button'),
                onPressed: _isTestingServerConnection
                    ? null
                    : _testServerConnection,
                icon: _isTestingServerConnection
                    ? const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find_rounded, size: 14),
                label: Text(lang.tr('testServerConnection')),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _openConfigFolder,
                icon: const Icon(Icons.folder_open_rounded, size: 14),
                label: Text(lang.tr('openConfigFolder')),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  textStyle: const TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),

          if (_serverConnectionResult != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    (_serverConnectionSuccess == true
                            ? theme.colors.accentEmerald
                            : theme.colors.accentRose)
                        .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color:
                      (_serverConnectionSuccess == true
                              ? theme.colors.accentEmerald
                              : theme.colors.accentRose)
                          .withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _serverConnectionSuccess == true
                        ? Icons.check_circle_outline
                        : Icons.error_outline,
                    size: 14,
                    color: _serverConnectionSuccess == true
                        ? theme.colors.accentEmerald
                        : theme.colors.accentRose,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _serverConnectionResult!,
                      style: TextStyle(
                        fontSize: 11,
                        color: _serverConnectionSuccess == true
                            ? theme.colors.accentEmerald
                            : theme.colors.accentRose,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
