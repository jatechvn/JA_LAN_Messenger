import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter/foundation.dart';
import '../models/ai_config_model.dart';
import 'windows_secret.dart';

/// Cấu hình WinRM riêng cho từng máy/người dùng
class WinrmPeerConfig {
  final bool useCustom;
  final String username;
  final String password;
  final int port;
  final String? customAppPath;

  const WinrmPeerConfig({
    this.useCustom = false,
    this.username = '',
    this.password = '',
    this.port = 5985,
    this.customAppPath,
  });

  Map<String, dynamic> toJson() => {
    'useCustom': useCustom,
    'username': username,
    'password': AppPreferences.protectSecret(password),
    'port': port,
    if (customAppPath != null) 'customAppPath': customAppPath,
  };

  factory WinrmPeerConfig.fromJson(Map<String, dynamic> json) =>
      WinrmPeerConfig(
        useCustom: json['useCustom'] as bool? ?? false,
        username: json['username'] as String? ?? '',
        password: AppPreferences.unprotectSecret(
          json['password'] as String? ?? '',
        ),
        port: json['port'] as int? ?? 5985,
        customAppPath: json['customAppPath'] as String?,
      );
}

/// Manages application-wide user preferences persisted in user_preferences.json.
class AppPreferences extends ChangeNotifier {
  static final AppPreferences _instance = AppPreferences._internal();
  factory AppPreferences() => _instance;
  AppPreferences._internal() {
    load();
  }

  static const String _secretPrefixV2 = 'enc:v2:';
  static const String _secretPrefixV1 = 'enc:v1:';
  static const List<int> _legacySecretKey = [
    0x4A, 0x41, 0x5F, 0x4C, 0x41, 0x4E, 0x5F, 0x53, 0x45, 0x43, // 'JA_LAN_SEC'
    0x32, 0x30, 0x32, 0x36, 0x5F, 0x57, 0x49, 0x4E, 0x52, 0x4D, // '2026_WINRM'
  ];

  static enc.Key? _cachedAesKey;

  /// Tạo khóa AES 256-bit ràng buộc theo định danh người dùng và máy tính hiện tại
  static enc.Key _deriveUserMachineKey() {
    if (_cachedAesKey != null) return _cachedAesKey!;
    final username = Platform.environment['USERNAME'] ?? 'user';
    final userdomain = Platform.environment['USERDOMAIN'] ?? 'local';
    final computer = Platform.environment['COMPUTERNAME'] ?? 'pc';
    final userprofile = Platform.environment['USERPROFILE'] ?? '';

    final entropy =
        'JA_LAN_WINRM_V2:$username@$userdomain:$computer:$userprofile';
    final digest = sha256.convert(utf8.encode(entropy));
    _cachedAesKey = enc.Key(Uint8List.fromList(digest.bytes));
    return _cachedAesKey!;
  }

  /// Mã hoá mật khẩu với AES-256-CBC và IV ngẫu nhiên sinh mới cho mỗi lần lưu
  static String protectSecret(String secret) {
    if (secret.isEmpty) return '';
    if (Platform.isWindows) {
      final protected = WindowsSecret.transform(
        Uint8List.fromList(utf8.encode(secret)),
        protect: true,
      );
      return 'enc:dpapi:${base64.encode(protected)}';
    }
    try {
      final key = _deriveUserMachineKey();
      final iv = enc.IV.fromSecureRandom(16);
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc));
      final encrypted = encrypter.encrypt(secret, iv: iv);
      return '$_secretPrefixV2${iv.base64}:${encrypted.base64}';
    } catch (_) {
      final bytes = utf8.encode(secret);
      final masked = List<int>.generate(
        bytes.length,
        (i) => bytes[i] ^ _legacySecretKey[i % _legacySecretKey.length],
      );
      return '$_secretPrefixV1${base64.encode(masked)}';
    }
  }

  /// Giải mã mật khẩu, hỗ trợ chuẩn enc:v2: (AES-256), tương thích ngược enc:v1: và plain text
  static String unprotectSecret(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    if (raw.startsWith('enc:dpapi:')) {
      if (!Platform.isWindows) {
        throw StateError('This WinRM credential belongs to a Windows user');
      }
      return utf8.decode(
        WindowsSecret.transform(
          base64.decode(raw.substring('enc:dpapi:'.length)),
          protect: false,
        ),
      );
    }

    // Chuẩn mã hóa AES-256-CBC với random IV
    if (raw.startsWith(_secretPrefixV2)) {
      try {
        final payload = raw.substring(_secretPrefixV2.length);
        final parts = payload.split(':');
        if (parts.length == 2) {
          final iv = enc.IV.fromBase64(parts[0]);
          final encrypter = enc.Encrypter(
            enc.AES(_deriveUserMachineKey(), mode: enc.AESMode.cbc),
          );
          return encrypter.decrypt64(parts[1], iv: iv);
        }
      } catch (_) {
        return raw;
      }
    }

    // Tương thích ngược enc:v1:
    if (raw.startsWith(_secretPrefixV1)) {
      try {
        final b64 = raw.substring(_secretPrefixV1.length);
        final masked = base64.decode(b64);
        final bytes = List<int>.generate(
          masked.length,
          (i) => masked[i] ^ _legacySecretKey[i % _legacySecretKey.length],
        );
        return utf8.decode(bytes);
      } catch (_) {
        return raw;
      }
    }

    // Tương thích plain text cũ
    return raw;
  }

  File? _customFile;
  String? _localNickname;
  String? get localNickname => _localNickname;

  Future<void> setLocalNickname(String value) async {
    final nickname = value.trim();
    if (nickname.isEmpty) return;
    _localNickname = nickname;
    await _save();
  }

  String _closeBehavior = 'ask'; // 'ask', 'minimize', 'exit'
  bool _rememberCloseBehavior = false;

  bool _aiEnabled = true;
  String _aiServerUrl = 'http://172.21.175.20:11434';
  String _aiSelectedModel = 'qwen2.5-vl:3b';
  bool _aiThinkingEnabled = false;
  Set<String> _pinnedKeys = {'__AI_ASSISTANT__'};
  bool _chatHistoryEnabled = true;
  List<AiModelInfo> _cachedDiscoveredModels = [];

  double? _cardBlur;
  double? _cardOpacity;
  double? _dialogBlur;
  double? _dialogOpacity;

  bool _isCompactMode = false;
  bool _isAlwaysOnTop = false;
  double? _compactWidth;
  double? _compactHeight;
  double? _compactPosX;
  double? _compactPosY;
  double? _normalWidth;
  double? _normalHeight;
  double? _normalPosX;
  double? _normalPosY;

  // Cảnh báo rung chuông (Buzz / Nudge)
  bool _buzzFlashScreen = true;
  bool _buzzShakeWindow = true;
  bool _buzzBringToFront = true;

  // Bộ gõ tích hợp (Built-in IME)
  String _imeMode = 'auto';
  bool _imeAutoBypassExternal = true;

  // Cập nhật OTA: Hỗ trợ cả Internet GitHub Releases và Mạng nội bộ (SMB/UNC)
  String _otaSource = 'auto'; // 'auto', 'github', 'lan'
  String _otaGithubRepo = 'jatechvn/JA_LAN_Messenger';
  String _otaGithubToken = '';
  String _otaCheckInterval = 'daily'; // 'daily', 'weekly', 'monthly', 'off'
  String _otaServerPath =
      r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger';
  String _otaUsername = 'user';
  String _otaPassword = 'user';
  DateTime? _otaLastCheckTime;
  String? _otaCachedUpdateVersion;

  // Cấu hình WinRM khởi động ứng dụng từ xa
  bool _winrmEnabled = true;
  String _winrmDefaultUsername = 'FT';
  String _winrmDefaultPassword = '123';
  int _winrmDefaultPort = 5985;
  bool _winrmAutoBuzzOnConnect = true;
  Map<String, WinrmPeerConfig> _peerWinrmConfigs = {};

  // Cấu hình hiệu năng phần cứng (Hardware Graphic Tier)
  String _perfTierMode = 'auto'; // 'auto', 'ultra', 'balanced', 'lite'

  // Ảnh đại diện cá nhân (User Avatar)
  String _userAvatarType = 'initials'; // 'initials', 'preset', 'custom'
  String _userAvatarPreset = 'robot';
  String _userAvatarCustomPath = '';
  String _userAvatarColor = '#3B82F6';
  String _userAvatarBase64 = '';

  String get userAvatarType => _userAvatarType;
  String get userAvatarPreset => _userAvatarPreset;
  String get userAvatarCustomPath => _userAvatarCustomPath;
  String get userAvatarColor => _userAvatarColor;
  String get userAvatarBase64 => _userAvatarBase64;

  String get closeBehavior => _closeBehavior;
  bool get rememberCloseBehavior => _rememberCloseBehavior;

  bool get aiEnabled => _aiEnabled;
  String get aiServerUrl => _aiServerUrl;
  String get aiSelectedModel => _aiSelectedModel;
  bool get aiThinkingEnabled => _aiThinkingEnabled;
  Set<String> get pinnedKeys => Set.unmodifiable(_pinnedKeys);
  bool get chatHistoryEnabled => _chatHistoryEnabled;
  List<AiModelInfo> get cachedDiscoveredModels =>
      List.unmodifiable(_cachedDiscoveredModels);

  double? get cardBlur => _cardBlur;
  double? get cardOpacity => _cardOpacity;
  double? get dialogBlur => _dialogBlur;
  double? get dialogOpacity => _dialogOpacity;

  bool get isCompactMode => _isCompactMode;
  bool get isAlwaysOnTop => _isAlwaysOnTop;
  double? get compactWidth => _compactWidth;
  double? get compactHeight => _compactHeight;
  double? get compactPosX => _compactPosX;
  double? get compactPosY => _compactPosY;
  double? get normalWidth => _normalWidth;
  double? get normalHeight => _normalHeight;
  double? get normalPosX => _normalPosX;
  double? get normalPosY => _normalPosY;

  bool get buzzFlashScreen => _buzzFlashScreen;
  bool get buzzShakeWindow => _buzzShakeWindow;
  bool get buzzBringToFront => _buzzBringToFront;

  String get imeMode => _imeMode;
  bool get imeAutoBypassExternal => _imeAutoBypassExternal;

  String get otaSource => _otaSource;
  String get otaGithubRepo => _otaGithubRepo;
  String get otaGithubToken => _otaGithubToken;
  String get otaCheckInterval => _otaCheckInterval;
  String get otaServerPath => _otaServerPath;
  String get otaUsername => _otaUsername;
  String get otaPassword => _otaPassword;
  DateTime? get otaLastCheckTime => _otaLastCheckTime;
  String? get otaCachedUpdateVersion => _otaCachedUpdateVersion;
  String get perfTierMode => _perfTierMode;

  bool get winrmEnabled => _winrmEnabled;
  String get winrmDefaultUsername => _winrmDefaultUsername;
  String get winrmDefaultPassword => _winrmDefaultPassword;
  int get winrmDefaultPort => _winrmDefaultPort;
  bool get winrmAutoBuzzOnConnect => _winrmAutoBuzzOnConnect;
  Map<String, WinrmPeerConfig> get peerWinrmConfigs =>
      Map.unmodifiable(_peerWinrmConfigs);

  WinrmPeerConfig? getWinrmConfigForPeer(String peerKey) =>
      _peerWinrmConfigs[peerKey];

  ({String username, String password, int port, String? customAppPath})
  resolveWinrmCredentials(String? peerKey) {
    if (peerKey != null && _peerWinrmConfigs.containsKey(peerKey)) {
      final config = _peerWinrmConfigs[peerKey]!;
      if (config.useCustom) {
        return (
          username: config.username.isNotEmpty
              ? config.username
              : _winrmDefaultUsername,
          password: config.password.isNotEmpty
              ? config.password
              : _winrmDefaultPassword,
          port: config.port > 0 ? config.port : _winrmDefaultPort,
          customAppPath: config.customAppPath,
        );
      }
    }
    return (
      username: _winrmDefaultUsername,
      password: _winrmDefaultPassword,
      port: _winrmDefaultPort,
      customAppPath: null,
    );
  }

  bool isPeerPinned(String key) => _pinnedKeys.contains(key);

  int _loadGeneration = 0;

  void resetToDefaults() {
    _localNickname = null;
    _loadGeneration++;
    _closeBehavior = 'ask';
    _rememberCloseBehavior = false;
    _aiEnabled = true;
    _aiServerUrl = 'http://172.21.175.20:11434';
    _aiSelectedModel = 'qwen2.5-vl:3b';
    _aiThinkingEnabled = false;
    _pinnedKeys = {'__AI_ASSISTANT__'};
    _chatHistoryEnabled = true;
    _cachedDiscoveredModels = [];
    AiModelInfo.resetDiscoveredModels();
    _cardBlur = null;
    _perfTierMode = 'auto';
    _userAvatarType = 'initials';
    _userAvatarPreset = 'robot';
    _userAvatarCustomPath = '';
    _userAvatarColor = '#3B82F6';
    _userAvatarBase64 = '';
    _cardOpacity = null;
    _dialogBlur = null;
    _dialogOpacity = null;
    _isCompactMode = false;
    _isAlwaysOnTop = false;
    _compactWidth = null;
    _compactHeight = null;
    _compactPosX = null;
    _compactPosY = null;
    _normalWidth = null;
    _normalHeight = null;
    _normalPosX = null;
    _normalPosY = null;
    _buzzFlashScreen = true;
    _buzzShakeWindow = true;
    _buzzBringToFront = true;
    _imeMode = 'auto';
    _imeAutoBypassExternal = true;
    _otaCheckInterval = 'daily';
    _otaServerPath =
        r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger';
    _otaUsername = 'user';
    _otaPassword = 'user';
    _otaLastCheckTime = null;
    _otaCachedUpdateVersion = null;
    _winrmEnabled = true;
    _winrmDefaultUsername = 'FT';
    _winrmDefaultPassword = '123';
    _winrmDefaultPort = 5985;
    _winrmAutoBuzzOnConnect = true;
    _peerWinrmConfigs = {};
  }

  void setCustomFileForTesting(File? file) {
    _loadGeneration++;
    resetToDefaults();
    _customFile = file;
  }

  File _getPrefFile() {
    if (_customFile != null) return _customFile!;
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory('$appData\\JA_LAN_Messenger');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return File('${dir.path}\\user_preferences.json');
    }
    return File('user_preferences.json');
  }

  /// Used before startup migrations; reading this path does not save defaults.
  File get preferencesFile => _getPrefFile();

  Future<void> load() async {
    final currentGen = ++_loadGeneration;
    try {
      final file = _getPrefFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (currentGen != _loadGeneration) return;
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
          final nickname = data['localNickname'];
          _localNickname = nickname is String && nickname.trim().isNotEmpty
              ? nickname.trim()
              : null;
          if (currentGen != _loadGeneration) return;
          if (data.containsKey('closeBehavior')) {
            _closeBehavior = data['closeBehavior'] as String? ?? 'ask';
          }
          if (data.containsKey('rememberCloseBehavior')) {
            _rememberCloseBehavior =
                data['rememberCloseBehavior'] as bool? ?? false;
          }
          if (data.containsKey('aiEnabled')) {
            _aiEnabled = data['aiEnabled'] as bool? ?? true;
          }
          if (data.containsKey('aiServerUrl')) {
            _aiServerUrl =
                data['aiServerUrl'] as String? ?? 'http://172.21.175.20:11434';
          }
          if (data.containsKey('aiSelectedModel')) {
            _aiSelectedModel =
                data['aiSelectedModel'] as String? ?? 'qwen2.5-vl:3b';
          }
          if (data.containsKey('aiThinkingEnabled')) {
            _aiThinkingEnabled = data['aiThinkingEnabled'] as bool? ?? false;
          }
          if (data.containsKey('chatHistoryEnabled')) {
            _chatHistoryEnabled = data['chatHistoryEnabled'] as bool? ?? true;
          }
          if (data.containsKey('pinnedKeys')) {
            final list = data['pinnedKeys'] as List<dynamic>?;
            if (list != null) {
              _pinnedKeys = list.map((e) => e.toString()).toSet();
            }
          }
          if (data.containsKey('cachedDiscoveredModels') &&
              data['cachedDiscoveredModels'] is List) {
            final list = <AiModelInfo>[];
            for (final item in (data['cachedDiscoveredModels'] as List)) {
              if (item is Map) {
                try {
                  list.add(
                    AiModelInfo.fromJson(Map<String, dynamic>.from(item)),
                  );
                } catch (_) {}
              }
            }
            if (list.isNotEmpty) {
              _cachedDiscoveredModels = AiModelInfo.forServerSelection(list);
              AiModelInfo.updateDiscoveredModels(_cachedDiscoveredModels);
            }
          }
          if (data.containsKey('cardBlur')) {
            _cardBlur = (data['cardBlur'] as num?)?.toDouble();
          }
          if (data.containsKey('cardOpacity')) {
            _cardOpacity = (data['cardOpacity'] as num?)?.toDouble();
          }
          if (data.containsKey('dialogBlur')) {
            _dialogBlur = (data['dialogBlur'] as num?)?.toDouble();
          }
          if (data.containsKey('dialogOpacity')) {
            _dialogOpacity = (data['dialogOpacity'] as num?)?.toDouble();
          }
          if (data.containsKey('isCompactMode')) {
            _isCompactMode = data['isCompactMode'] as bool? ?? false;
          }
          if (data.containsKey('isAlwaysOnTop')) {
            _isAlwaysOnTop = data['isAlwaysOnTop'] as bool? ?? false;
          }
          if (data.containsKey('compactWidth')) {
            _compactWidth = (data['compactWidth'] as num?)?.toDouble();
          }
          if (data.containsKey('compactHeight')) {
            _compactHeight = (data['compactHeight'] as num?)?.toDouble();
          }
          if (data.containsKey('compactPosX')) {
            _compactPosX = (data['compactPosX'] as num?)?.toDouble();
          }
          if (data.containsKey('compactPosY')) {
            _compactPosY = (data['compactPosY'] as num?)?.toDouble();
          }
          if (data.containsKey('normalWidth')) {
            _normalWidth = (data['normalWidth'] as num?)?.toDouble();
          }
          if (data.containsKey('normalHeight')) {
            _normalHeight = (data['normalHeight'] as num?)?.toDouble();
          }
          if (data.containsKey('normalPosX')) {
            _normalPosX = (data['normalPosX'] as num?)?.toDouble();
          }
          if (data.containsKey('normalPosY')) {
            _normalPosY = (data['normalPosY'] as num?)?.toDouble();
          }
          if (data.containsKey('buzzFlashScreen')) {
            _buzzFlashScreen = data['buzzFlashScreen'] as bool? ?? true;
          }
          if (data.containsKey('buzzShakeWindow')) {
            _buzzShakeWindow = data['buzzShakeWindow'] as bool? ?? true;
          }
          if (data.containsKey('buzzBringToFront')) {
            _buzzBringToFront = data['buzzBringToFront'] as bool? ?? true;
          }
          if (data.containsKey('imeMode')) {
            _imeMode = data['imeMode'] as String? ?? 'auto';
          }
          if (data.containsKey('imeAutoBypassExternal')) {
            _imeAutoBypassExternal =
                data['imeAutoBypassExternal'] as bool? ?? true;
          }
          if (data.containsKey('otaSource')) {
            _otaSource = data['otaSource'] as String? ?? 'auto';
          }
          if (data.containsKey('otaGithubRepo')) {
            _otaGithubRepo =
                data['otaGithubRepo'] as String? ?? 'jatechvn/JA_LAN_Messenger';
          }
          if (data.containsKey('otaGithubToken')) {
            _otaGithubToken = data['otaGithubToken'] as String? ?? '';
          }
          if (data.containsKey('otaCheckInterval')) {
            _otaCheckInterval = data['otaCheckInterval'] as String? ?? 'daily';
          }
          if (data.containsKey('otaServerPath')) {
            _otaServerPath =
                data['otaServerPath'] as String? ??
                r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger';
          }
          if (data.containsKey('otaUsername')) {
            _otaUsername = data['otaUsername'] as String? ?? 'user';
          }
          if (data.containsKey('otaPassword')) {
            _otaPassword = data['otaPassword'] as String? ?? 'user';
          }
          if (data.containsKey('otaLastCheckTime')) {
            final str = data['otaLastCheckTime'] as String?;
            if (str != null) _otaLastCheckTime = DateTime.tryParse(str);
          }
          if (data.containsKey('otaCachedUpdateVersion')) {
            _otaCachedUpdateVersion = data['otaCachedUpdateVersion'] as String?;
          }
          if (data.containsKey('perfTierMode')) {
            _perfTierMode = data['perfTierMode'] as String? ?? 'auto';
          }
          if (data.containsKey('userAvatarType')) {
            _userAvatarType = data['userAvatarType'] as String? ?? 'initials';
          }
          if (data.containsKey('userAvatarPreset')) {
            _userAvatarPreset = data['userAvatarPreset'] as String? ?? 'robot';
          }
          if (data.containsKey('userAvatarCustomPath')) {
            _userAvatarCustomPath =
                data['userAvatarCustomPath'] as String? ?? '';
          }
          if (data.containsKey('userAvatarColor')) {
            _userAvatarColor = data['userAvatarColor'] as String? ?? '#3B82F6';
          }
          if (data.containsKey('userAvatarBase64')) {
            _userAvatarBase64 = data['userAvatarBase64'] as String? ?? '';
          }
          if (data.containsKey('winrmEnabled')) {
            _winrmEnabled = data['winrmEnabled'] as bool? ?? true;
          }
          if (data.containsKey('winrmDefaultUsername')) {
            _winrmDefaultUsername =
                data['winrmDefaultUsername'] as String? ?? 'FT';
          }
          if (data.containsKey('winrmDefaultPassword')) {
            _winrmDefaultPassword = unprotectSecret(
              data['winrmDefaultPassword'] as String? ?? '123',
            );
          }
          if (data.containsKey('winrmDefaultPort')) {
            _winrmDefaultPort = data['winrmDefaultPort'] as int? ?? 5985;
          }
          if (data.containsKey('winrmAutoBuzzOnConnect')) {
            _winrmAutoBuzzOnConnect =
                data['winrmAutoBuzzOnConnect'] as bool? ?? true;
          }
          if (data.containsKey('peerWinrmConfigs') &&
              data['peerWinrmConfigs'] is Map) {
            final raw = data['peerWinrmConfigs'] as Map<String, dynamic>;
            final map = <String, WinrmPeerConfig>{};
            raw.forEach((k, v) {
              if (v is Map) {
                map[k] = WinrmPeerConfig.fromJson(Map<String, dynamic>.from(v));
              }
            });
            _peerWinrmConfigs = map;
          }
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[AppPreferences] Load error: $e');
    }
  }

  Future<void> setCompactMode(bool enabled) async {
    _isCompactMode = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> setAlwaysOnTop(bool enabled) async {
    _isAlwaysOnTop = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> saveCompactGeometry({
    double? width,
    double? height,
    double? x,
    double? y,
  }) async {
    if (width != null) _compactWidth = width;
    if (height != null) _compactHeight = height;
    if (x != null) _compactPosX = x;
    if (y != null) _compactPosY = y;
    await _save();
  }

  Future<void> saveNormalGeometry({
    double? width,
    double? height,
    double? x,
    double? y,
  }) async {
    if (width != null) _normalWidth = width;
    if (height != null) _normalHeight = height;
    if (x != null) _normalPosX = x;
    if (y != null) _normalPosY = y;
    await _save();
  }

  Future<void> setChatHistoryEnabled(bool enabled) async {
    _chatHistoryEnabled = enabled;
    notifyListeners();
    await _save();
  }

  Future<void> setPeerPinned(String key, bool isPinned) async {
    if (isPinned) {
      _pinnedKeys.add(key);
    } else {
      _pinnedKeys.remove(key);
    }
    notifyListeners();
    await _save();
  }

  Future<void> setCloseBehavior(String behavior, {bool? remember}) async {
    _closeBehavior = behavior;
    if (remember != null) {
      _rememberCloseBehavior = remember;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setAiConfig({
    bool? enabled,
    String? serverUrl,
    String? selectedModel,
    bool? thinkingEnabled,
  }) async {
    if (enabled != null) _aiEnabled = enabled;
    if (serverUrl != null) _aiServerUrl = serverUrl;
    if (selectedModel != null) _aiSelectedModel = selectedModel;
    if (thinkingEnabled != null) _aiThinkingEnabled = thinkingEnabled;
    notifyListeners();
    await _save();
  }

  Future<void> clearGlassTuning() async {
    _cardBlur = null;
    _cardOpacity = null;
    _dialogBlur = null;
    _dialogOpacity = null;
    notifyListeners();
    await _save();
  }

  Future<void> setGlassTuning({
    double? cardBlur,
    double? cardOpacity,
    double? dialogBlur,
    double? dialogOpacity,
  }) async {
    if (cardBlur != null) _cardBlur = cardBlur;
    if (cardOpacity != null) _cardOpacity = cardOpacity;
    if (dialogBlur != null) _dialogBlur = dialogBlur;
    if (dialogOpacity != null) _dialogOpacity = dialogOpacity;
    notifyListeners();
    await _save();
  }

  Future<void> setCachedAiModels(List<AiModelInfo> models) async {
    _cachedDiscoveredModels = AiModelInfo.forServerSelection(models);
    AiModelInfo.updateDiscoveredModels(_cachedDiscoveredModels);
    notifyListeners();
    await _save();
  }

  Future<void> setBuzzAlertSettings({
    bool? flashScreen,
    bool? shakeWindow,
    bool? bringToFront,
  }) async {
    if (flashScreen != null) _buzzFlashScreen = flashScreen;
    if (shakeWindow != null) _buzzShakeWindow = shakeWindow;
    if (bringToFront != null) _buzzBringToFront = bringToFront;
    notifyListeners();
    await _save();
  }

  Future<void> setImeSettings({String? mode, bool? autoBypassExternal}) async {
    if (mode != null) _imeMode = mode;
    if (autoBypassExternal != null) {
      _imeAutoBypassExternal = autoBypassExternal;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setOtaSettings({
    String? source,
    String? githubRepo,
    String? githubToken,
    String? checkInterval,
    String? serverPath,
    String? username,
    String? password,
    DateTime? lastCheckTime,
    String? cachedUpdateVersion,
  }) async {
    if (source != null) _otaSource = source;
    if (githubRepo != null) _otaGithubRepo = githubRepo;
    if (githubToken != null) _otaGithubToken = githubToken;
    if (checkInterval != null) _otaCheckInterval = checkInterval;
    if (serverPath != null) _otaServerPath = serverPath;
    if (username != null) _otaUsername = username;
    if (password != null) _otaPassword = password;
    if (lastCheckTime != null) _otaLastCheckTime = lastCheckTime;
    if (cachedUpdateVersion != null) {
      _otaCachedUpdateVersion = cachedUpdateVersion.isEmpty
          ? null
          : cachedUpdateVersion;
    }
    notifyListeners();
    await _save();
  }

  Future<void> setPerfTierMode(String mode) async {
    _perfTierMode = mode;
    notifyListeners();
    await _save();
  }

  Future<void> setUserAvatar({
    String? type,
    String? preset,
    String? customPath,
    String? color,
    String? base64,
  }) async {
    if (type != null) _userAvatarType = type;
    if (preset != null) _userAvatarPreset = preset;
    if (customPath != null) _userAvatarCustomPath = customPath;
    if (color != null) _userAvatarColor = color;
    if (base64 != null) _userAvatarBase64 = base64;
    notifyListeners();
    await _save();
  }

  Future<void> setWinrmGlobalSettings({
    bool? enabled,
    String? defaultUsername,
    String? defaultPassword,
    int? defaultPort,
    bool? autoBuzzOnConnect,
  }) async {
    if (enabled != null) _winrmEnabled = enabled;
    if (defaultUsername != null) _winrmDefaultUsername = defaultUsername;
    if (defaultPassword != null) _winrmDefaultPassword = defaultPassword;
    if (defaultPort != null) _winrmDefaultPort = defaultPort;
    if (autoBuzzOnConnect != null) _winrmAutoBuzzOnConnect = autoBuzzOnConnect;
    notifyListeners();
    await _save();
  }

  Future<void> setWinrmConfigForPeer(
    String peerKey,
    WinrmPeerConfig? config,
  ) async {
    if (config == null) {
      _peerWinrmConfigs.remove(peerKey);
    } else {
      _peerWinrmConfigs[peerKey] = config;
    }
    notifyListeners();
    await _save();
  }

  Future<void> _save() async {
    _loadGeneration++;
    try {
      final file = _getPrefFile();
      Map<String, dynamic> data = {};
      if (await file.exists()) {
        try {
          final content = await file.readAsString();
          if (content.trim().isNotEmpty) {
            data = jsonDecode(content) as Map<String, dynamic>;
          }
        } catch (_) {}
      }
      data['closeBehavior'] = _closeBehavior;
      if (_localNickname != null) data['localNickname'] = _localNickname;
      data['rememberCloseBehavior'] = _rememberCloseBehavior;
      data['aiEnabled'] = _aiEnabled;
      data['aiServerUrl'] = _aiServerUrl;
      data['aiSelectedModel'] = _aiSelectedModel;
      data['aiThinkingEnabled'] = _aiThinkingEnabled;
      data['chatHistoryEnabled'] = _chatHistoryEnabled;
      data['pinnedKeys'] = _pinnedKeys.toList();
      if (_cachedDiscoveredModels.isNotEmpty) {
        data['cachedDiscoveredModels'] = AiModelInfo.forServerSelection(
          _cachedDiscoveredModels,
        ).map((m) => m.toJson()).toList();
      }
      // Remove persisted overrides when restoring the hardware defaults.
      data.remove('cardBlur');
      data.remove('cardOpacity');
      data.remove('dialogBlur');
      data.remove('dialogOpacity');
      if (_cardBlur != null) data['cardBlur'] = _cardBlur;
      if (_cardOpacity != null) data['cardOpacity'] = _cardOpacity;
      if (_dialogBlur != null) data['dialogBlur'] = _dialogBlur;
      if (_dialogOpacity != null) data['dialogOpacity'] = _dialogOpacity;
      data['isCompactMode'] = _isCompactMode;
      data['isAlwaysOnTop'] = _isAlwaysOnTop;
      if (_compactWidth != null) data['compactWidth'] = _compactWidth;
      if (_compactHeight != null) data['compactHeight'] = _compactHeight;
      if (_compactPosX != null) data['compactPosX'] = _compactPosX;
      if (_compactPosY != null) data['compactPosY'] = _compactPosY;
      if (_normalWidth != null) data['normalWidth'] = _normalWidth;
      if (_normalHeight != null) data['normalHeight'] = _normalHeight;
      if (_normalPosX != null) data['normalPosX'] = _normalPosX;
      if (_normalPosY != null) data['normalPosY'] = _normalPosY;
      data['buzzFlashScreen'] = _buzzFlashScreen;
      data['buzzShakeWindow'] = _buzzShakeWindow;
      data['buzzBringToFront'] = _buzzBringToFront;
      data['imeMode'] = _imeMode;
      data['imeAutoBypassExternal'] = _imeAutoBypassExternal;
      data['otaSource'] = _otaSource;
      data['otaGithubRepo'] = _otaGithubRepo;
      data['otaGithubToken'] = _otaGithubToken;
      data['otaCheckInterval'] = _otaCheckInterval;
      data['otaServerPath'] = _otaServerPath;
      data['otaUsername'] = _otaUsername;
      data['otaPassword'] = _otaPassword;
      data['otaLastCheckTime'] = _otaLastCheckTime?.toIso8601String();
      data['otaCachedUpdateVersion'] = _otaCachedUpdateVersion;
      data['perfTierMode'] = _perfTierMode;
      data['userAvatarType'] = _userAvatarType;
      data['userAvatarPreset'] = _userAvatarPreset;
      data['userAvatarCustomPath'] = _userAvatarCustomPath;
      data['userAvatarColor'] = _userAvatarColor;
      data['userAvatarBase64'] = _userAvatarBase64;
      data['winrmEnabled'] = _winrmEnabled;
      data['winrmDefaultUsername'] = _winrmDefaultUsername;
      data['winrmDefaultPassword'] = protectSecret(_winrmDefaultPassword);
      data['winrmDefaultPort'] = _winrmDefaultPort;
      data['winrmAutoBuzzOnConnect'] = _winrmAutoBuzzOnConnect;
      if (_peerWinrmConfigs.isNotEmpty) {
        data['peerWinrmConfigs'] = _peerWinrmConfigs.map(
          (k, v) => MapEntry(k, v.toJson()),
        );
      } else {
        data.remove('peerWinrmConfigs');
      }
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('[AppPreferences] Save error: $e');
    }
  }
}
