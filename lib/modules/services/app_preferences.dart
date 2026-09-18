import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/ai_config_model.dart';

/// Manages application-wide user preferences persisted in user_preferences.json.
class AppPreferences extends ChangeNotifier {
  static final AppPreferences _instance = AppPreferences._internal();
  factory AppPreferences() => _instance;
  AppPreferences._internal() {
    load();
  }

  File? _customFile;
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

  bool isPeerPinned(String key) => _pinnedKeys.contains(key);

  int _loadGeneration = 0;

  void resetToDefaults() {
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
    _cardOpacity = null;
    _dialogBlur = null;
    _dialogOpacity = null;
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

  Future<void> load() async {
    final currentGen = ++_loadGeneration;
    try {
      final file = _getPrefFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (currentGen != _loadGeneration) return;
        if (content.trim().isNotEmpty) {
          final data = jsonDecode(content) as Map<String, dynamic>;
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
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('[AppPreferences] Load error: $e');
    }
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
      if (_cardBlur != null) data['cardBlur'] = _cardBlur;
      if (_cardOpacity != null) data['cardOpacity'] = _cardOpacity;
      if (_dialogBlur != null) data['dialogBlur'] = _dialogBlur;
      if (_dialogOpacity != null) data['dialogOpacity'] = _dialogOpacity;
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (e) {
      debugPrint('[AppPreferences] Save error: $e');
    }
  }
}
