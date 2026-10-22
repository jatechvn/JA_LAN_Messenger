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
  String? accountName;
  String? hostname;
  String? customNickname;
  String? userHash;
  int? port;
  int? avatarColorValue;
  String? avatarPreset;
  String? customAvatarBase64;

  KnownDeviceInfo({
    required this.id,
    required this.username,
    required this.lastIp,
    required this.firstDiscovered,
    required this.lastSeen,
    Set<String>? knownIps,
    this.accountName,
    this.hostname,
    this.customNickname,
    this.userHash,
    this.port,
    this.avatarColorValue,
    this.avatarPreset,
    this.customAvatarBase64,
  }) : knownIps = knownIps ?? {if (lastIp.isNotEmpty) lastIp};

  Map<String, dynamic> toJson() => {
    'id': id,
    'username': username,
    'lastIp': lastIp,
    'firstDiscovered': firstDiscovered.toIso8601String(),
    'lastSeen': lastSeen.toIso8601String(),
    'knownIps': knownIps.toList(),
    if (accountName != null && accountName!.isNotEmpty)
      'accountName': accountName,
    if (hostname != null && hostname!.isNotEmpty) 'hostname': hostname,
    if (customNickname != null && customNickname!.isNotEmpty)
      'customNickname': customNickname,
    if (userHash != null && userHash!.isNotEmpty) 'userHash': userHash,
    if (port != null && port! > 0) 'port': port,
    if (avatarColorValue != null) 'avatarColorValue': avatarColorValue,
    if (avatarPreset != null && avatarPreset!.isNotEmpty)
      'avatarPreset': avatarPreset,
    if (customAvatarBase64 != null && customAvatarBase64!.isNotEmpty)
      'customAvatarBase64': customAvatarBase64,
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
        accountName: json['accountName'] as String?,
        hostname: json['hostname'] as String?,
        customNickname: json['customNickname'] as String?,
        userHash: json['userHash'] as String?,
        port: (json['port'] as num?)?.toInt(),
        avatarColorValue: (json['avatarColorValue'] as num?)?.toInt(),
        avatarPreset: json['avatarPreset'] as String?,
        customAvatarBase64: json['customAvatarBase64'] as String?,
      );
}

class KnownDevicesRegistry {
  final String? _customFilePath;
  final Map<String, KnownDeviceInfo> _devices = {};

  KnownDevicesRegistry([this._customFilePath]) {
    load();
  }

  Map<String, KnownDeviceInfo> get devices => Map.unmodifiable(_devices);

  KnownDeviceInfo? findByIdentity(String? identityKey) {
    if (identityKey == null || identityKey.trim().isEmpty) return null;
    final raw = identityKey.trim();
    return _devices[raw] ??
        _devices[raw.toLowerCase()] ??
        _devices.entries
            .where((e) => e.key.toLowerCase() == raw.toLowerCase())
            .map((e) => e.value)
            .firstOrNull;
  }

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
    return findByIdentity(identityKey) != null;
  }

  /// Evicts [ip] from all other registered devices whose identity differs from [ownerIdentityKey].
  void evictIpFromOtherDevices(String ip, {String? ownerIdentityKey}) {
    final cleanIp = ip.trim();
    if (cleanIp.isEmpty) return;
    final normalizedOwner = ownerIdentityKey?.trim().toLowerCase();
    var changed = false;
    for (final entry in _devices.entries) {
      if (normalizedOwner != null &&
          entry.key.trim().toLowerCase() == normalizedOwner) {
        continue;
      }
      final other = entry.value;
      final removed = other.knownIps.remove(cleanIp);
      if (other.lastIp == cleanIp) {
        other.lastIp = other.knownIps.isNotEmpty ? other.knownIps.last : '';
        changed = true;
      } else if (removed) {
        changed = true;
      }
    }
    if (changed) {
      save();
    }
  }

  /// Returns `true` if this device was newly registered for the first time,
  /// or `false` if it was already known.
  bool recordDevice({
    required String identityKey,
    required String username,
    required String ip,
    String? accountName,
    String? hostname,
    String? customNickname,
    String? userHash,
    int? port,
    int? avatarColorValue,
    String? avatarPreset,
    String? customAvatarBase64,
    Set<String>? activeIps,
  }) {
    if (identityKey.isEmpty) return false;

    final now = DateTime.now();
    if (ip.isNotEmpty) {
      evictIpFromOtherDevices(ip, ownerIdentityKey: identityKey);
    }

    final existing = findByIdentity(identityKey);
    final cleanAccount =
        (accountName != null &&
            accountName.trim().isNotEmpty &&
            accountName.trim() != '???')
        ? accountName.trim()
        : null;
    final cleanHost =
        (hostname != null &&
            hostname.trim().isNotEmpty &&
            hostname.trim() != '???' &&
            hostname.trim().toLowerCase() != 'localhost')
        ? hostname.trim()
        : null;
    final cleanHash = (userHash != null && userHash.trim().isNotEmpty)
        ? userHash.trim()
        : null;

    if (existing != null) {
      if (username.trim().isNotEmpty && username.trim() != '???') {
        existing.username = username.trim();
      }
      if (ip.isNotEmpty) {
        existing.lastIp = ip;
      }
      existing.lastSeen = now;
      if (activeIps != null && activeIps.isNotEmpty) {
        existing.knownIps
          ..clear()
          ..addAll(activeIps.where((e) => e.isNotEmpty));
      }
      if (ip.isNotEmpty) {
        existing.knownIps.add(ip);
      }
      if (cleanAccount != null) existing.accountName = cleanAccount;
      if (cleanHost != null) existing.hostname = cleanHost;
      if (customNickname != null) {
        existing.customNickname = customNickname.trim().isNotEmpty
            ? customNickname.trim()
            : null;
      }
      if (cleanHash != null) existing.userHash = cleanHash;
      if (port != null && port > 0) existing.port = port;
      if (avatarColorValue != null) {
        existing.avatarColorValue = avatarColorValue;
      }
      if (avatarPreset != null) existing.avatarPreset = avatarPreset;
      if (customAvatarBase64 != null) {
        existing.customAvatarBase64 = customAvatarBase64;
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
      knownIps: {
        if (activeIps != null) ...activeIps.where((e) => e.isNotEmpty),
        if (ip.isNotEmpty) ip,
      },
      accountName: cleanAccount,
      hostname: cleanHost,
      customNickname: customNickname != null && customNickname.trim().isNotEmpty
          ? customNickname.trim()
          : null,
      userHash: cleanHash,
      port: port,
      avatarColorValue: avatarColorValue,
      avatarPreset: avatarPreset,
      customAvatarBase64: customAvatarBase64,
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
