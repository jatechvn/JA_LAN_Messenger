import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'app_colors.dart';
import 'styles_win10.dart';
import 'styles_win11.dart';
import '../services/app_preferences.dart';

/// Performance Tier Mode for Graphic & Hardware Tuning.
enum PerfTierMode {
  auto('auto', 'Auto'),
  ultra('ultra', 'Ultra'),
  balanced('balanced', 'Balanced'),
  lite('lite', 'Lite');

  final String id;
  final String label;
  const PerfTierMode(this.id, this.label);
}

/// Effective Hardware Graphic Tier
enum HardwareTier {
  ultra('Ultra', '120 FPS • Max Glass', Icons.bolt_rounded, Color(0xFF0066FF)),
  balanced(
    'Balanced',
    '60 FPS • Laptop Opt',
    Icons.balance_rounded,
    Color(0xFF10B981),
  ),
  lite('Lite', 'Low Power • Zero Lag', Icons.eco_rounded, Color(0xFFF59E0B));

  final String label;
  final String desc;
  final IconData icon;
  final Color color;
  const HardwareTier(this.label, this.desc, this.icon, this.color);
}

class ThemeProvider extends ChangeNotifier {
  String _themeMode = 'system';
  bool _isWin11 = false;

  // Performance & Graphic Tier Profiling
  PerfTierMode _perfMode = PerfTierMode.auto;
  late HardwareTier _detectedTier;
  int _cpuCores = 4;
  int _hardwareScore = 50;
  String? _cpuModel;
  String? _gpuModel;

  /// Hook for unit testing registry-based hardware detection
  @visibleForTesting
  static String? Function(String keyPath, String valueName)?
  registryQueryOverride;

  // Glassmorphism live tuning parameters
  double _cardBlur = 24.0;
  double _cardOpacity = 0.28;
  double _dialogBlur = 20.0;
  double _dialogOpacity = 0.88;
  double _dropdownBlur = 20.0;
  double _dropdownOpacity = 0.88;

  static ThemeProvider of(BuildContext context, {bool listen = true}) {
    return listen
        ? context.watch<ThemeProvider>()
        : context.read<ThemeProvider>();
  }

  void updateGlassTuning({
    double? cardBlur,
    double? cardOpacity,
    double? dialogBlur,
    double? dialogOpacity,
  }) => saveGlassTuning(
    cardBlur: cardBlur,
    cardOpacity: cardOpacity,
    dialogBlur: dialogBlur,
    dialogOpacity: dialogOpacity,
  );

  ThemeProvider({String initialMode = 'system'}) {
    _themeMode = initialMode;
    _loadSavedPerfMode();
    _detectWindowsVersion();
    _profileHardware();
    _loadCustomGlassTuning();
  }

  void _loadSavedPerfMode() {
    try {
      final savedModeId = AppPreferences().perfTierMode;
      _perfMode = PerfTierMode.values.firstWhere(
        (e) => e.id == savedModeId,
        orElse: () => PerfTierMode.auto,
      );
    } catch (_) {
      _perfMode = PerfTierMode.auto;
    }
  }

  void _loadCustomGlassTuning() {
    try {
      final prefs = AppPreferences();
      if (prefs.cardBlur != null) _cardBlur = prefs.cardBlur!;
      if (prefs.cardOpacity != null) _cardOpacity = prefs.cardOpacity!;
      if (prefs.dialogBlur != null) _dialogBlur = prefs.dialogBlur!;
      if (prefs.dialogOpacity != null) _dialogOpacity = prefs.dialogOpacity!;
    } catch (_) {}
  }

  Future<void> saveGlassTuning({
    double? cardBlur,
    double? cardOpacity,
    double? dialogBlur,
    double? dialogOpacity,
  }) async {
    setLiveGlassmorphism(
      cardBlur: cardBlur,
      cardOpacity: cardOpacity,
      dialogBlur: dialogBlur,
      dialogOpacity: dialogOpacity,
    );
    try {
      final prefs = AppPreferences();
      await prefs.setGlassTuning(
        cardBlur: _cardBlur,
        cardOpacity: _cardOpacity,
        dialogBlur: _dialogBlur,
        dialogOpacity: _dialogOpacity,
      );
    } catch (_) {}
  }

  void _detectWindowsVersion() {
    if (!Platform.isWindows) return;
    try {
      final versionStr = Platform.operatingSystemVersion;
      final match = RegExp(r'Build\s+(\d+)').firstMatch(versionStr);
      if (match != null) {
        final buildNumber = int.tryParse(match.group(1) ?? '') ?? 0;
        _isWin11 = buildNumber >= 22000;
      }
    } catch (_) {}
  }

  /// Fast registry query for Windows hardware specifications (< 15ms)
  static String? queryWindowsRegistryValue(String keyPath, String valueName) {
    if (registryQueryOverride != null) {
      return registryQueryOverride!(keyPath, valueName);
    }
    if (!Platform.isWindows) return null;
    try {
      final res = Process.runSync('reg', [
        'query',
        keyPath,
        '/v',
        valueName,
      ], runInShell: false);
      if (res.exitCode == 0) {
        final out = res.stdout.toString();
        final lines = out.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith(valueName)) {
            final regMatch = RegExp(r'REG_\w+\s+(.*)$').firstMatch(trimmed);
            if (regMatch != null) {
              return regMatch.group(1)?.trim();
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  /// Computes hardware performance score (10 - 100) based on CPU, GPU, and Cores.
  static int calculateHardwareScore({
    String? cpu,
    String? gpu,
    required int cores,
    required bool isWin11,
  }) {
    int score = 50;

    // 1. Core count scoring
    if (cores >= 16) {
      score += 25;
    } else if (cores >= 12) {
      score += 20;
    } else if (cores >= 8) {
      score += 15;
    } else if (cores >= 6) {
      score += 5;
    } else if (cores == 4) {
      score += 0;
    } else {
      score -= 20;
    }

    // 2. CPU architecture / low-power SoC evaluation
    final cpuLower = (cpu ?? '').toLowerCase();
    if (cpuLower.contains('n100') ||
        cpuLower.contains('n95') ||
        cpuLower.contains('n97') ||
        cpuLower.contains('n5105') ||
        cpuLower.contains('n5095') ||
        cpuLower.contains('j4125') ||
        cpuLower.contains('j4105') ||
        cpuLower.contains('celeron') ||
        cpuLower.contains('pentium') ||
        cpuLower.contains('atom')) {
      score -= 35;
    } else if (cpuLower.contains('i9') ||
        cpuLower.contains('ryzen 9') ||
        cpuLower.contains('threadripper') ||
        cpuLower.contains('ultra 9') ||
        cpuLower.contains('xeon')) {
      score += 25;
    } else if (cpuLower.contains('i7') ||
        cpuLower.contains('ryzen 7') ||
        cpuLower.contains('ultra 7')) {
      score += 15;
    } else if (cpuLower.contains('i5') ||
        cpuLower.contains('ryzen 5') ||
        cpuLower.contains('ultra 5')) {
      score += 8;
    }

    // 3. GPU architecture / performance evaluation
    final gpuLower = (gpu ?? '').toLowerCase();
    if (gpuLower.contains('nvidia') ||
        gpuLower.contains('geforce') ||
        gpuLower.contains('rtx') ||
        gpuLower.contains('gtx') ||
        gpuLower.contains('radeon rx') ||
        gpuLower.contains('arc a7') ||
        gpuLower.contains('arc a5') ||
        gpuLower.contains('arc b5') ||
        gpuLower.contains('quadro')) {
      score += 25;
    } else if (gpuLower.contains('radeon 780m') ||
        gpuLower.contains('radeon 890m') ||
        gpuLower.contains('radeon 680m') ||
        gpuLower.contains('iris xe') ||
        gpuLower.contains('iris(r) xe') ||
        gpuLower.contains('arc graphics') ||
        gpuLower.contains('uhd graphics 770') ||
        gpuLower.contains('uhd graphics 750')) {
      score += 10;
    } else if (gpuLower.contains('basic display') ||
        gpuLower.contains('vga') ||
        gpuLower.contains('virtualbox') ||
        gpuLower.contains('vmware') ||
        gpuLower.contains('remote display')) {
      score -= 30;
    } else if (gpuLower.contains('uhd graphics')) {
      score -= 15;
    }

    // 4. Windows 11 DWM composition optimization
    if (isWin11) score += 5;

    return score.clamp(10, 100);
  }

  /// Maps a hardware score (10 - 100) to an appropriate HardwareTier.
  static HardwareTier calculateTierFromScore(int score) {
    if (score < 45) {
      return HardwareTier.lite;
    } else if (score < 75) {
      return HardwareTier.balanced;
    } else {
      return HardwareTier.ultra;
    }
  }

  void _profileHardware() {
    try {
      _cpuCores = Platform.numberOfProcessors;
    } catch (_) {
      _cpuCores = 4;
    }

    if (Platform.isWindows || registryQueryOverride != null) {
      _cpuModel = queryWindowsRegistryValue(
        r'HKLM\HARDWARE\DESCRIPTION\System\CentralProcessor\0',
        'ProcessorNameString',
      );
      _gpuModel = queryWindowsRegistryValue(
        r'HKLM\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}\0000',
        'DriverDesc',
      );
    }

    _hardwareScore = calculateHardwareScore(
      cpu: _cpuModel,
      gpu: _gpuModel,
      cores: _cpuCores,
      isWin11: _isWin11,
    );

    _detectedTier = calculateTierFromScore(_hardwareScore);

    // Always initialize every tier parameter, including unsaved dropdown values.
    // Custom card/dialog tuning is restored separately by the constructor.
    _applyTierParameters(effectiveTier, notify: false);
  }

  PerfTierMode get perfMode => _perfMode;
  HardwareTier get detectedTier => _detectedTier;
  HardwareTier get effectiveTier {
    switch (_perfMode) {
      case PerfTierMode.auto:
        return _detectedTier;
      case PerfTierMode.ultra:
        return HardwareTier.ultra;
      case PerfTierMode.balanced:
        return HardwareTier.balanced;
      case PerfTierMode.lite:
        return HardwareTier.lite;
    }
  }

  String get perfLabel {
    if (_perfMode == PerfTierMode.auto) {
      return 'Auto (${effectiveTier.label})';
    }
    return _perfMode.label;
  }

  int get cpuCores => _cpuCores;
  int get hardwareScore => _hardwareScore;
  String? get cpuModel => _cpuModel;
  String? get gpuModel => _gpuModel;

  /// Cycles through: auto -> ultra -> balanced -> lite -> auto
  void cyclePerfTier() {
    switch (_perfMode) {
      case PerfTierMode.auto:
        _perfMode = PerfTierMode.ultra;
        break;
      case PerfTierMode.ultra:
        _perfMode = PerfTierMode.balanced;
        break;
      case PerfTierMode.balanced:
        _perfMode = PerfTierMode.lite;
        break;
      case PerfTierMode.lite:
        _perfMode = PerfTierMode.auto;
        break;
    }
    try {
      AppPreferences().setPerfTierMode(_perfMode.id);
    } catch (_) {}
    _applyTierParameters(effectiveTier, notify: true);
  }

  Future<void> setPerfTierMode(PerfTierMode mode) async {
    if (_perfMode != mode) {
      _perfMode = mode;
      _applyTierParameters(effectiveTier, notify: true);
      try {
        await AppPreferences().setPerfTierMode(mode.id);
      } catch (_) {}
    }
  }

  void _applyTierParameters(HardwareTier tier, {bool notify = true}) {
    switch (tier) {
      case HardwareTier.ultra:
        _cardBlur = 24.0;
        _cardOpacity = 0.28;
        _dialogBlur = 20.0;
        _dialogOpacity = 0.88;
        _dropdownBlur = 20.0;
        _dropdownOpacity = 0.88;
        break;
      case HardwareTier.balanced:
        _cardBlur = 12.0;
        _cardOpacity = 0.40;
        _dialogBlur = 12.0;
        _dialogOpacity = 0.90;
        _dropdownBlur = 12.0;
        _dropdownOpacity = 0.94;
        break;
      case HardwareTier.lite:
        _cardBlur = 0.0;
        _cardOpacity = 0.88;
        _dialogBlur = 0.0;
        _dialogOpacity = 0.96;
        _dropdownBlur = 0.0;
        _dropdownOpacity = 0.98;
        break;
    }
    if (notify) notifyListeners();
  }

  String get themeMode => _themeMode;

  bool get isDark {
    if (_themeMode == 'dark') return true;
    if (_themeMode == 'light') return false;
    final brightness =
        SchedulerBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark;
  }

  bool get isWin11 => _isWin11;

  double get cardBlur => effectiveTier == HardwareTier.lite ? 0 : _cardBlur;
  double get cardOpacity {
    if (!isDark && _cardOpacity < 0.28) {
      return 0.28;
    }
    return _cardOpacity;
  }

  double get dialogBlur => effectiveTier == HardwareTier.lite ? 0 : _dialogBlur;
  double get dialogOpacity => _dialogOpacity;
  double get dropdownBlur =>
      effectiveTier == HardwareTier.lite ? 0 : _dropdownBlur;
  double get dropdownOpacity => _dropdownOpacity;

  AppColors get colors {
    if (isDark) {
      return _isWin11 ? win11DarkColors : win10DarkColors;
    } else {
      return _isWin11 ? win11LightColors : win10LightColors;
    }
  }

  Color get baseBg => colors.bgPrimary;
  Color get sidebarBg => colors.sidebarBg;
  Color get cardBg => colors.cardBg;

  /// 1-Click Direct Toggle between Light and Dark
  void toggleTheme() {
    _themeMode = isDark ? 'light' : 'dark';
    notifyListeners();
  }

  void setThemeMode(String mode) {
    _themeMode = mode;
    notifyListeners();
  }

  /// Real-time live tuning for Glassmorphism sliders
  void setLiveGlassmorphism({
    double? cardBlur,
    double? cardOpacity,
    double? dialogBlur,
    double? dialogOpacity,
    double? dropdownBlur,
    double? dropdownOpacity,
  }) {
    if (cardBlur != null) _cardBlur = cardBlur;
    if (cardOpacity != null) _cardOpacity = cardOpacity;
    if (dialogBlur != null) _dialogBlur = dialogBlur;
    if (dialogOpacity != null) _dialogOpacity = dialogOpacity;
    if (dropdownBlur != null) _dropdownBlur = dropdownBlur;
    if (dropdownOpacity != null) _dropdownOpacity = dropdownOpacity;
    notifyListeners();
  }

  void setCardBlur(double blur) {
    _cardBlur = blur;
    notifyListeners();
  }

  void setCardOpacity(double opacity) {
    _cardOpacity = opacity;
    notifyListeners();
  }

  void setDialogBlur(double blur) {
    _dialogBlur = blur;
    notifyListeners();
  }

  void setDialogOpacity(double opacity) {
    _dialogOpacity = opacity;
    notifyListeners();
  }

  void setDropdownBlur(double blur) {
    _dropdownBlur = blur;
    notifyListeners();
  }

  void setDropdownOpacity(double opacity) {
    _dropdownOpacity = opacity;
    notifyListeners();
  }

  void resetToDefaults() {
    _perfMode = PerfTierMode.auto;
    _profileHardware();
    try {
      AppPreferences().setPerfTierMode('auto');
      AppPreferences().clearGlassTuning();
    } catch (_) {}
    _applyTierParameters(effectiveTier, notify: false);
    notifyListeners();
  }
}

extension ThemeExtension on BuildContext {
  AppColors get appColors => watch<ThemeProvider>().colors;
}
