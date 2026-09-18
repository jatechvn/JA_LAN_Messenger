import 'dart:convert';
import 'dart:io';

/// Repository managing persistent search history queries.
/// Learned from JA_Mini_Showcase pattern.
class SearchHistoryRepository {
  static final SearchHistoryRepository _instance =
      SearchHistoryRepository._internal();
  factory SearchHistoryRepository() => _instance;
  SearchHistoryRepository._internal();

  File? _customStorageFile;
  final Map<String, List<String>> _cache = {};
  bool _isLoaded = false;
  Future<void>? _loading;
  Future<void> _pendingSave = Future.value();
  static const int maxHistory = 10;

  void setStorageFileForTesting(File? file) {
    _customStorageFile = file;
    _isLoaded = false;
    _loading = null;
    _cache.clear();
  }

  File _getStorageFile() {
    if (_customStorageFile != null) return _customStorageFile!;
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory('$appData\\JA_LAN_Messenger');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return File('${dir.path}\\search_history.json');
    }
    return File('search_history.json');
  }

  Future<void> _load() {
    if (_isLoaded) return Future.value();
    return _loading ??= _loadOnce();
  }

  Future<void> _loadOnce() async {
    try {
      final file = _getStorageFile();
      if (file.existsSync()) {
        final raw = file.readAsStringSync();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            _cache.clear();
            for (final entry in decoded.entries) {
              if (entry.value is List) {
                _cache[entry.key.toString()] = (entry.value as List)
                    .map((e) => e.toString().trim())
                    .where((s) => s.isNotEmpty)
                    .toList();
              }
            }
          } else if (decoded is List) {
            _cache['default'] = decoded
                .map((e) => e.toString().trim())
                .where((s) => s.isNotEmpty)
                .toList();
          }
        }
      }
    } catch (_) {}
    _isLoaded = true;
  }

  Future<void> _save() {
    final file = _getStorageFile();
    final snapshot = jsonEncode(_cache);
    return _pendingSave = _pendingSave.then((_) async {
      try {
        await file.writeAsString(snapshot);
      } catch (_) {}
    });
  }

  Future<List<String>> getHistory([String category = 'default']) async {
    await _load();
    return List.unmodifiable(_cache[category] ?? const []);
  }

  Future<void> addQuery(String rawQuery, [String category = 'default']) async {
    final query = rawQuery.trim();
    if (query.isEmpty) return;
    await _load();

    final list = _cache.putIfAbsent(category, () => []);
    list.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
    list.insert(0, query);
    if (list.length > maxHistory) {
      list.removeRange(maxHistory, list.length);
    }
    await _save();
  }

  Future<void> removeQuery(String query, [String category = 'default']) async {
    await _load();
    final list = _cache[category];
    if (list != null) {
      list.removeWhere((q) => q.toLowerCase() == query.toLowerCase());
      await _save();
    }
  }

  Future<void> clearHistory([String category = 'default']) async {
    await _load();
    _cache[category]?.clear();
    await _save();
  }
}
