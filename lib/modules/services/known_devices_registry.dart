import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';

class KnownDeviceInfo {
  final String id;
  String username;
  String lastIp;
  final DateTime firstDiscovered;
  DateTime lastSeen;
  final Set<String> knownIps;

  KnownDeviceInfo({
    required this.id,
    required this.username,
    required this.lastIp,
    required this.firstDiscovered,
    required this.lastSeen,
    Set<String>? knownIps,
  }) : knownIps = knownIps ?? {if (lastIp.isNotEmpty) lastIp};

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'lastIp': lastIp,
    'firstDiscovered': firstDiscovered.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
    'knownIps': knownIps.toList(),
  };

  factory KnownDeviceInfo.fromJson(Map<String, dynamic> json) =>
      KnownDeviceInfo(
        id: json['id'] as String? ?? '',
        username: json['username'] as String? ?? '',
        lastIp: json['lastIp'] as String? ?? '',
        firstDiscovered:
            DateTime.tryParse(json['firstDiscovered'] as String? ?? '') ??
            DateTime.now(),
        lastSeen:
            DateTime.tryParse(json['lastSeen'] as String? ?? '') ??
            DateTime.now(),
        knownIps:
            (json['knownIps'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toSet() ??
            {},
      );
}

class KnownDevicesRegistry {
  final String? _customFilePath;
  final Map<String, KnownDeviceInfo> _devices = {};

  KnownDevicesRegistry([this._customFilePath]) {
    load();
  }

  Map<String, KnownDeviceInfo> get devices => Map.unmodifiable(_devices);

  String _getRegistryFilePath() {
    final customPath = _customFilePath;
    if (customPath != null && customPath.isNotEmpty) {
      return customPath;
    }
    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory('$appData\\JA_LAN_Messenger');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return '${dir.path}\\known_devices.json';
    }
    return 'known_devices.json';
  }

  void load() {
    try {
      final file = File(_getRegistryFilePath());
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        if (content.trim().isNotEmpty) {
          final List<dynamic> list = jsonDecode(content);
          _devices.clear();
          for (final item in list) {
            if (item is Map<String, dynamic>) {
              final info = KnownDeviceInfo.fromJson(item);
              if (info.id.isNotEmpty) {
                _devices[info.id] = info;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[KnownDevicesRegistry] Load error: $e');
    }
  }

  void save() {
    try {
      final file = File(_getRegistryFilePath());
      final list = _devices.values.map((d) => d.toJson()).toList();
      file.writeAsStringSync(jsonEncode(list));
    } catch (e) {
      debugPrint('[KnownDevicesRegistry] Save error: $e');
    }
  }

  bool isDeviceKnown(String identityKey) {
    if (identityKey.isEmpty) return false;
    return _devices.containsKey(identityKey);
  }

  /// Returns `true` if this device was newly registered for the first time,
  /// or `false` if it was already known.
  bool recordDevice({
    required String identityKey,
    required String username,
    required String ip,
  }) {
    if (identityKey.isEmpty) return false;

    final now = DateTime.now();
    final existing = _devices[identityKey];

    if (existing != null) {
      if (username.trim().isNotEmpty && username.trim() != '???') {
        existing.username = username.trim();
      }
      existing.lastIp = ip;
      existing.lastSeen = now;
      if (ip.isNotEmpty) {
        existing.knownIps.add(ip);
      }
      save();
      return false; // Already known
    }

    final safeUsername =
        (username.trim().isNotEmpty && username.trim() != '???')
        ? username.trim()
        : (identityKey.contains('@') ? identityKey : ip);

    final newInfo = KnownDeviceInfo(
      id: identityKey,
      username: safeUsername,
      lastIp: ip,
      firstDiscovered: now,
      lastSeen: now,
      knownIps: {if (ip.isNotEmpty) ip},
    );
    _devices[identityKey] = newInfo;
    save();
    return true; // First time discovered
  }

  void clear() {
    _devices.clear();
    try {
      final file = File(_getRegistryFilePath());
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }
}
