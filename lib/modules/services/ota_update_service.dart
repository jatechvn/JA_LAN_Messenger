import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../constants.dart';
import 'app_preferences.dart';
import 'chat_history_service.dart';

/// Quản lý phân tích và so sánh số phiên bản SemVer (Semantic Versioning)
class SemanticVersion implements Comparable<SemanticVersion> {
  final int major;
  final int minor;
  final int patch;
  final int? build;
  final String raw;
  final String? prerelease;

  const SemanticVersion({
    required this.major,
    required this.minor,
    required this.patch,
    this.build,
    required this.raw,
    this.prerelease,
  });

  /// Phân tích cú pháp chuỗi phiên bản dạng: '1.1.0', 'v1.1.0', '1.1.0+2', '1.2.0-beta'
  static SemanticVersion? tryParse(String? input) {
    if (input == null || input.trim().isEmpty) return null;
    final clean = input.trim().toLowerCase().replaceAll(RegExp(r'^[vV]'), '');
    if (!RegExp(
      r'^\d+\.\d+(?:\.\d+)?(?:-[0-9a-z.-]+)?(?:\+\d+)?$',
    ).hasMatch(clean)) {
      return null;
    }
    final pre = RegExp(r'-([^+]+)').firstMatch(clean)?.group(1);

    // Bóc tách build number nếu có dấu +
    int? buildNum;
    String versionCore = clean;
    if (clean.contains('+')) {
      final parts = clean.split('+');
      versionCore = parts[0];
      buildNum = int.tryParse(parts[1]);
    }

    // Bỏ hậu tố tiền phát hành (như -beta, -rc1)
    if (versionCore.contains('-')) {
      versionCore = versionCore.split('-')[0];
    }

    final segments = versionCore.split('.');
    if (segments.isEmpty) return null;

    final major = int.tryParse(segments[0]);
    if (major == null) return null;
    final minor = segments.length > 1 ? int.tryParse(segments[1]) : 0;
    if (minor == null) return null;
    final patch = segments.length > 2 ? int.tryParse(segments[2]) : 0;
    if (patch == null) return null;

    return SemanticVersion(
      major: major,
      minor: minor,
      patch: patch,
      build: buildNum,
      raw: input.trim(),
      prerelease: pre,
    );
  }

  @override
  int compareTo(SemanticVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    if (prerelease != other.prerelease) {
      if (prerelease == null) return 1;
      if (other.prerelease == null) return -1;
      final a = prerelease!.split('.');
      final b = other.prerelease!.split('.');
      for (var i = 0; i < a.length && i < b.length; i++) {
        final x = int.tryParse(a[i]);
        final y = int.tryParse(b[i]);
        final comparison = x != null && y != null
            ? x.compareTo(y)
            : x != null
            ? -1
            : y != null
            ? 1
            : a[i].compareTo(b[i]);
        if (comparison != 0) return comparison;
      }
      if (a.length != b.length) return a.length.compareTo(b.length);
    }
    final b1 = build ?? 0;
    final b2 = other.build ?? 0;
    return b1.compareTo(b2);
  }

  bool operator >(SemanticVersion other) => compareTo(other) > 0;
  bool operator <(SemanticVersion other) => compareTo(other) < 0;
  bool operator >=(SemanticVersion other) => compareTo(other) >= 0;
  bool operator <=(SemanticVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SemanticVersion && compareTo(other) == 0;
  }

  @override
  int get hashCode => Object.hash(major, minor, patch, build ?? 0, prerelease);

  @override
  String toString() {
    final base =
        '$major.$minor.$patch${prerelease == null ? '' : '-$prerelease'}';
    return build != null && build! > 0 ? '$base+$build' : base;
  }

  String get displayVersion => 'v$this';
}

/// Thông tin gói cập nhật phát hiện trên máy chủ hoặc GitHub
class UpdatePackageInfo {
  final SemanticVersion version;
  final String fileName;
  final String fullPath;
  final int fileSize;
  final String? releaseNotes;
  final DateTime? releaseDate;
  final String? releaseTitle;
  final String? sha256;
  final String? htmlUrl;

  const UpdatePackageInfo({
    required this.version,
    required this.fileName,
    required this.fullPath,
    required this.fileSize,
    this.releaseNotes,
    this.releaseDate,
    this.releaseTitle,
    this.sha256,
    this.htmlUrl,
  });

  bool get isRemoteUrl =>
      fullPath.startsWith('http://') || fullPath.startsWith('https://');

  String get formattedSize {
    if (fileSize <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double size = fileSize.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(i == 0 ? 0 : 2)} ${suffixes[i]}';
  }
}

/// Kết quả kiểm tra phiên bản mới
class UpdateCheckResult {
  final bool hasUpdate;
  final UpdatePackageInfo? packageInfo;
  final String currentVersion;
  final String? errorMessage;
  final bool isConnectionSuccess;

  const UpdateCheckResult({
    required this.hasUpdate,
    this.packageInfo,
    required this.currentVersion,
    this.errorMessage,
    this.isConnectionSuccess = true,
  });
}

/// Cấu hình cập nhật OTA lưu trong file JSON độc lập
class OtaUpdateConfig {
  final String source; // 'auto', 'github', 'lan'
  final String githubRepo;
  final String githubToken;
  final String serverPath;
  final String username;
  final String password;
  final String checkInterval; // 'daily', 'weekly', 'monthly', 'off'
  final bool autoDownload;

  const OtaUpdateConfig({
    this.source = 'auto',
    this.githubRepo = 'jatechvn/JA_LAN_Messenger',
    this.githubToken = '',
    required this.serverPath,
    required this.username,
    required this.password,
    this.checkInterval = 'daily',
    this.autoDownload = false,
  });

  factory OtaUpdateConfig.defaults() => const OtaUpdateConfig(
    source: 'auto',
    githubRepo: 'jatechvn/JA_LAN_Messenger',
    githubToken: '',
    serverPath:
        r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger',
    username: 'user',
    password: 'user',
    checkInterval: 'daily',
    autoDownload: false,
  );

  factory OtaUpdateConfig.fromJson(Map<String, dynamic> json) {
    return OtaUpdateConfig(
      source: json['source'] as String? ?? 'auto',
      githubRepo: json['githubRepo'] as String? ?? 'jatechvn/JA_LAN_Messenger',
      githubToken: json['githubToken'] as String? ?? '',
      serverPath:
          json['serverPath'] as String? ??
          r'\\10.81.141.226\temp\FBT\JA_PROJECT\JA_Update\JA_LAN_Messenger',
      username: json['username'] as String? ?? 'user',
      password: json['password'] as String? ?? 'user',
      checkInterval: json['checkInterval'] as String? ?? 'daily',
      autoDownload: json['autoDownload'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'source': source,
    'githubRepo': githubRepo,
    'githubToken': githubToken,
    'serverPath': serverPath,
    'username': username,
    'password': password,
    'checkInterval': checkInterval,
    'autoDownload': autoDownload,
  };
}

/// Dịch vụ quản lý kiểm tra và thực hiện cập nhật OTA
class OtaUpdateService {
  static bool isValidPackageName(String name) =>
      RegExp(
        r'^JA_LAN_Messenger_[a-zA-Z0-9_.+-]+\.zip$',
        caseSensitive: false,
      ).hasMatch(name) &&
      !name.contains('..');

  static String _psLiteral(String value) => "'${value.replaceAll("'", "''")}'";

  static Future<ProcessResult> _runPowerShell(String script) {
    final encoded = base64Encode(
      script.codeUnits.expand((c) => [c & 255, c >> 8]).toList(),
    );
    return Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-EncodedCommand',
      encoded,
    ]);
  }

  bool _applying = false;
  static final OtaUpdateService _instance = OtaUpdateService._internal();
  factory OtaUpdateService() => _instance;
  OtaUpdateService._internal();

  File? _customConfigFileForTesting;
  Directory? _customServerDirForTesting;
  Map<String, dynamic>? _mockGitHubReleaseJsonForTesting;

  @visibleForTesting
  void setCustomConfigFileForTesting(File? file) {
    _customConfigFileForTesting = file;
  }

  @visibleForTesting
  void setCustomServerDirForTesting(Directory? dir) {
    _customServerDirForTesting = dir;
  }

  @visibleForTesting
  void setMockGitHubReleaseJsonForTesting(Map<String, dynamic>? json) {
    _mockGitHubReleaseJsonForTesting = json;
  }

  /// Lấy vị trí file update_config.json:
  /// 1. Cạnh file thực thi .exe nếu tồn tại (tiện lợi cho deploy portable / LAN)
  /// 2. Thư mục AppData (%APPDATA%\JA_LAN_Messenger\update_config.json)
  File getConfigFile() {
    if (_customConfigFileForTesting != null) {
      return _customConfigFileForTesting!;
    }

    try {
      final exeDir = File(Platform.resolvedExecutable).parent;
      final exeConfig = File(
        '${exeDir.path}${Platform.pathSeparator}update_config.json',
      );
      if (exeConfig.existsSync()) {
        return exeConfig;
      }
    } catch (_) {}

    final appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final dir = Directory('$appData\\JA_LAN_Messenger');
      if (!dir.existsSync()) {
        try {
          dir.createSync(recursive: true);
        } catch (_) {}
      }
      return File('${dir.path}\\update_config.json');
    }
    return File('update_config.json');
  }

  /// Nạp cấu hình từ update_config.json nếu có
  Future<OtaUpdateConfig?> loadExternalConfigFile() async {
    try {
      final file = getConfigFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.trim().isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;
          return OtaUpdateConfig.fromJson(json);
        }
      }
    } catch (e) {
      debugPrint('[OtaUpdateService] Load config error: $e');
    }
    return null;
  }

  /// Lưu cấu hình ra file update_config.json
  Future<void> saveExternalConfigFile(OtaUpdateConfig config) async {
    try {
      final file = getConfigFile();
      final encoder = const JsonEncoder.withIndent('  ');
      await file.writeAsString(encoder.convert(config.toJson()), flush: true);
    } catch (e) {
      debugPrint('[OtaUpdateService] Save config error: $e');
    }
  }

  /// Đồng bộ cấu hình từ file JSON ngoài vào AppPreferences khi khởi động
  Future<void> syncExternalConfigToPreferences() async {
    final externalConfig = await loadExternalConfigFile();
    if (externalConfig != null) {
      final prefs = AppPreferences();
      await prefs.setOtaSettings(
        source: externalConfig.source,
        githubRepo: externalConfig.githubRepo,
        githubToken: externalConfig.githubToken,
        checkInterval: externalConfig.checkInterval,
        serverPath: externalConfig.serverPath,
        username: externalConfig.username,
        password: externalConfig.password,
      );
    }
  }

  /// Kiểm tra xem đã đến thời điểm cần kiểm tra cập nhật tự động chưa
  bool shouldCheckForUpdates({
    required String interval,
    DateTime? lastCheckTime,
    DateTime? now,
  }) {
    if (interval == 'off') return false;
    if (lastCheckTime == null) return true;

    final currentTime = now ?? DateTime.now();
    final elapsed = currentTime.difference(lastCheckTime);

    switch (interval) {
      case 'daily':
        return elapsed.inHours >= 24;
      case 'weekly':
        return elapsed.inDays >= 7;
      case 'monthly':
        return elapsed.inDays >= 30;
      default:
        return elapsed.inHours >= 24;
    }
  }

  /// Trích xuất thư mục gốc chia sẻ SMB từ đường dẫn UNC (ví dụ: '\\10.81.141.226\temp')
  static String? extractSmbShareRoot(String uncPath) {
    final normalized = uncPath.replaceAll('/', '\\');
    if (!normalized.startsWith(r'\\')) return null;

    final parts = normalized.substring(2).split('\\');
    if (parts.length < 2) return null;
    return '\\\\${parts[0]}\\${parts[1]}';
  }

  /// Kết nối tới máy chủ chia sẻ mạng nội bộ SMB/UNC qua `net use` nếu cần
  Future<bool> connectSmbShare({
    String? path,
    String? username,
    String? password,
  }) async {
    if (_customServerDirForTesting != null) {
      return await _customServerDirForTesting!.exists();
    }

    final prefs = AppPreferences();
    final targetPath = path ?? prefs.otaServerPath;
    final user = username ?? prefs.otaUsername;
    final pass = password ?? prefs.otaPassword;

    // Nếu là thư mục thông thường (local hoặc mapped drive), kiểm tra trực tiếp
    try {
      final normalized = targetPath.replaceAll('/', '\\');
      if (!normalized.startsWith(r'\\')) {
        return await Directory(targetPath).exists();
      }

      // 1. Thử truy cập trực tiếp (nếu đã kết nối hoặc không yêu cầu mật khẩu)
      try {
        if (await Directory(targetPath).exists()) {
          return true;
        }
      } catch (_) {}

      // 2. Chạy 'net use' cho thư mục gốc của share
      final shareRoot = extractSmbShareRoot(targetPath);
      if (shareRoot != null && Platform.isWindows) {
        try {
          final result = await Process.run('net', [
            'use',
            shareRoot,
            pass,
            '/user:$user',
          ]);
          if (result.exitCode == 0) {
            return await Directory(targetPath).exists();
          }
          // Mã 1219 nghĩa là đã có kết nối trước đó với cùng server
          final out = '${result.stdout} ${result.stderr}';
          if (out.contains('1219')) {
            return await Directory(targetPath).exists();
          }
        } catch (e) {
          debugPrint('[OtaUpdateService] net use error: $e');
        }
      }

      return await Directory(targetPath).exists();
    } catch (_) {
      return false;
    }
  }

  /// Kiểm tra cập nhật qua GitHub Releases (Internet)
  Future<UpdateCheckResult> checkGitHubUpdates({
    String? repo,
    String? token,
    String? overrideCurrentVersion,
  }) async {
    final prefs = AppPreferences();
    final targetRepo = (repo ?? prefs.otaGithubRepo)
        .trim()
        .replaceAll(RegExp(r'^https?://github\.com/'), '')
        .replaceAll(RegExp(r'/$'), '');
    final targetToken = (token ?? prefs.otaGithubToken).trim();
    final currentVerStr = overrideCurrentVersion ?? appVersion;
    final currentSemVer =
        SemanticVersion.tryParse(currentVerStr) ??
        const SemanticVersion(major: 1, minor: 0, patch: 0, raw: '1.0.0');

    if (targetRepo.isEmpty || !targetRepo.contains('/')) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVerStr,
        isConnectionSuccess: false,
        errorMessage: 'Repository GitHub không hợp lệ (định dạng: owner/repo)',
      );
    }

    Map<String, dynamic>? releaseJson;

    if (_mockGitHubReleaseJsonForTesting != null) {
      releaseJson = _mockGitHubReleaseJsonForTesting;
    } else {
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      try {
        final uri = Uri.parse(
          'https://api.github.com/repos/$targetRepo/releases/latest',
        );
        final request = await client.getUrl(uri);
        request.headers.set(
          HttpHeaders.acceptHeader,
          'application/vnd.github.v3+json',
        );
        request.headers.set(
          HttpHeaders.userAgentHeader,
          'JA-LAN-Messenger-OTA',
        );
        if (targetToken.isNotEmpty) {
          request.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $targetToken',
          );
        }

        final response = await request.close();
        if (response.statusCode == 404) {
          return UpdateCheckResult(
            hasUpdate: false,
            currentVersion: currentVerStr,
            isConnectionSuccess: false,
            errorMessage:
                'Không tìm thấy bản phát hành nào trên repository $targetRepo (hoặc repo Private cần điền GitHub Token)',
          );
        } else if (response.statusCode == 401 || response.statusCode == 403) {
          return UpdateCheckResult(
            hasUpdate: false,
            currentVersion: currentVerStr,
            isConnectionSuccess: false,
            errorMessage:
                'Lỗi xác thực GitHub API (${response.statusCode}): Vui lòng kiểm tra lại GitHub Token hoặc hạn ngạch truy cập.',
          );
        } else if (response.statusCode != 200) {
          return UpdateCheckResult(
            hasUpdate: false,
            currentVersion: currentVerStr,
            isConnectionSuccess: false,
            errorMessage:
                'Lỗi kết nối GitHub (${response.statusCode}): ${response.reasonPhrase}',
          );
        }

        final bodyStr = await response.transform(utf8.decoder).join();
        releaseJson = jsonDecode(bodyStr) as Map<String, dynamic>;
      } catch (e) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVerStr,
          isConnectionSuccess: false,
          errorMessage: 'Lỗi khi kết nối GitHub Releases: $e',
        );
      } finally {
        client.close();
      }
    }

    if (releaseJson == null) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVerStr,
        isConnectionSuccess: false,
        errorMessage: 'Dữ liệu bản phát hành GitHub trống hoặc không hợp lệ',
      );
    }

    final targetJson = releaseJson;

    try {
      final tagName = targetJson['tag_name'] as String? ?? '';
      final releaseName = targetJson['name'] as String? ?? tagName;
      final releaseBody = targetJson['body'] as String? ?? '';
      final publishedAt = targetJson['published_at'] as String?;
      final htmlUrl = targetJson['html_url'] as String?;
      final releaseSemVer = SemanticVersion.tryParse(tagName);

      if (releaseSemVer == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVerStr,
          errorMessage:
              'Không thể phân tích phiên bản từ tag phát hành: $tagName',
        );
      }

      final assets = (targetJson['assets'] as List<dynamic>? ?? []);
      Map<String, dynamic>? zipAsset;
      Map<String, dynamic>? shaAsset;

      for (final a in assets) {
        if (a is Map<String, dynamic>) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          if (name.endsWith('.zip') &&
              (name.contains('lan_messenger') || name.contains('windows'))) {
            zipAsset = a;
          } else if (zipAsset == null && name.endsWith('.zip')) {
            zipAsset = a;
          }
          if (name.contains('sha256') || name.endsWith('.txt')) {
            shaAsset = a;
          }
        }
      }

      if (zipAsset == null) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVerStr,
          errorMessage: 'Bản phát hành $tagName không có file .zip cho Windows',
        );
      }

      final zipFileName = zipAsset['name'] as String;
      final zipFileSize = zipAsset['size'] as int? ?? 0;
      final browserDownloadUrl =
          zipAsset['browser_download_url'] as String? ?? '';
      final apiUrl = zipAsset['url'] as String?;
      final downloadUrl = (targetToken.isNotEmpty && apiUrl != null)
          ? apiUrl
          : browserDownloadUrl;

      String? foundSha256;
      if (shaAsset != null && _mockGitHubReleaseJsonForTesting == null) {
        try {
          final shaUrl = (targetToken.isNotEmpty && shaAsset['url'] != null)
              ? shaAsset['url'] as String
              : shaAsset['browser_download_url'] as String? ?? '';
          if (shaUrl.isNotEmpty) {
            foundSha256 = await _fetchSha256FromUrl(
              url: shaUrl,
              targetZipName: zipFileName,
              token: targetToken,
            );
          }
        } catch (e) {
          debugPrint('[OtaUpdateService] Fetch SHA256 error: $e');
        }
      }

      final hasUpdate = releaseSemVer > currentSemVer;
      final pkg = UpdatePackageInfo(
        version: releaseSemVer,
        fileName: zipFileName,
        fullPath: downloadUrl,
        fileSize: zipFileSize,
        releaseNotes: releaseBody.trim().isNotEmpty ? releaseBody : null,
        releaseDate: publishedAt != null
            ? DateTime.tryParse(publishedAt)
            : null,
        releaseTitle: releaseName,
        sha256: foundSha256,
        htmlUrl: htmlUrl,
      );

      if (hasUpdate) {
        await prefs.setOtaSettings(
          cachedUpdateVersion: releaseSemVer.toString(),
          lastCheckTime: DateTime.now(),
        );
      }

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        packageInfo: pkg,
        currentVersion: currentVerStr,
        isConnectionSuccess: true,
      );
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVerStr,
        isConnectionSuccess: false,
        errorMessage: 'Lỗi khi phân tích bản phát hành GitHub: $e',
      );
    }
  }

  /// Tải nội dung file SHA256SUMS.txt từ URL và trích xuất hash tương ứng với tệp zip
  Future<String?> _fetchSha256FromUrl({
    required String url,
    required String targetZipName,
    String? token,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      var currentUri = Uri.parse(url);
      var req = await client.getUrl(currentUri);
      req.headers.set(HttpHeaders.userAgentHeader, 'JA-LAN-Messenger-OTA');
      if (token != null &&
          token.isNotEmpty &&
          !url.contains('objects.githubusercontent.com') &&
          !url.contains('s3.amazonaws.com')) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      }

      var resp = await req.close();
      var redirects = 0;
      while (resp.isRedirect && redirects < 5) {
        redirects++;
        final loc = resp.headers.value(HttpHeaders.locationHeader);
        if (loc == null) break;
        currentUri = currentUri.resolve(loc);
        req = await client.getUrl(currentUri);
        req.headers.set(HttpHeaders.userAgentHeader, 'JA-LAN-Messenger-OTA');
        if (token != null &&
            token.isNotEmpty &&
            !currentUri.host.contains('objects.githubusercontent.com') &&
            !currentUri.host.contains('s3.amazonaws.com')) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
        }
        resp = await req.close();
      }

      if (resp.statusCode == 200) {
        final text = await resp.transform(utf8.decoder).join();
        for (final line in text.split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          final parts = trimmed.split(RegExp(r'\s+'));
          if (parts.length >= 2) {
            final hash = parts[0].trim();
            final file = parts[1].replaceAll('*', '').trim();
            if (file.toLowerCase() == targetZipName.toLowerCase() ||
                parts.any(
                  (p) => p.toLowerCase().contains(targetZipName.toLowerCase()),
                )) {
              return hash.toLowerCase();
            }
          }
        }
      }
    } catch (_) {
    } finally {
      client.close();
    }
    return null;
  }

  /// Kiểm tra kết nối nhanh tới GitHub Releases
  Future<Map<String, dynamic>> testGitHubConnection({
    String? repo,
    String? token,
  }) async {
    final prefs = AppPreferences();
    final targetRepo = (repo ?? prefs.otaGithubRepo)
        .trim()
        .replaceAll(RegExp(r'^https?://github\.com/'), '')
        .replaceAll(RegExp(r'/$'), '');
    final targetToken = (token ?? prefs.otaGithubToken).trim();

    if (targetRepo.isEmpty || !targetRepo.contains('/')) {
      return {
        'success': false,
        'message': 'Repository GitHub không hợp lệ (định dạng: owner/repo)',
      };
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 12);
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/$targetRepo/releases/latest',
      );
      final request = await client.getUrl(uri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github.v3+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'JA-LAN-Messenger-OTA');
      if (targetToken.isNotEmpty) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $targetToken',
        );
      }
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(utf8.decoder).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        final tag = json['tag_name'] as String? ?? 'N/A';
        return {
          'success': true,
          'message': 'Kết nối GitHub thành công! Tag mới nhất: $tag',
          'latestTag': tag,
          'json': json,
        };
      } else if (response.statusCode == 404) {
        return {
          'success': false,
          'message':
              'Không tìm thấy repository hoặc release ($targetRepo). Nếu là repo Private, vui lòng điền GitHub Token.',
        };
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        return {
          'success': false,
          'message':
              'Lỗi quyền truy cập GitHub (${response.statusCode}): Vui lòng kiểm tra lại GitHub Token.',
        };
      } else {
        return {
          'success': false,
          'message':
              'Lỗi GitHub HTTP ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
    } catch (e) {
      return {'success': false, 'message': 'Lỗi kết nối tới GitHub: $e'};
    } finally {
      client.close();
    }
  }

  /// Kiểm tra cập nhật qua thư mục mạng nội bộ (SMB/UNC)
  Future<UpdateCheckResult> _checkLanUpdates({
    String? overrideServerPath,
    String? overrideCurrentVersion,
    bool isManual = false,
  }) async {
    final prefs = AppPreferences();
    final serverPath = overrideServerPath ?? prefs.otaServerPath;
    final currentVerStr = overrideCurrentVersion ?? appVersion;
    final currentSemVer =
        SemanticVersion.tryParse(currentVerStr) ??
        const SemanticVersion(major: 1, minor: 0, patch: 0, raw: '1.0.0');

    // 1. Kết nối máy chủ
    final connected = await connectSmbShare(path: serverPath);
    if (!connected) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVerStr,
        isConnectionSuccess: false,
        errorMessage:
            'Không thể kết nối hoặc truy cập thư mục máy chủ: $serverPath',
      );
    }

    // Cập nhật thời điểm kiểm tra cuối
    await prefs.setOtaSettings(lastCheckTime: DateTime.now());

    final Directory dir = _customServerDirForTesting ?? Directory(serverPath);
    if (!await dir.exists()) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVerStr,
        isConnectionSuccess: false,
        errorMessage: 'Thư mục máy chủ không tồn tại: $serverPath',
      );
    }

    // 2. Kiểm tra file version.json trước nếu có
    final versionJsonFile = File(
      '${dir.path}${Platform.pathSeparator}version.json',
    );
    if (await versionJsonFile.exists()) {
      try {
        final content = await versionJsonFile.readAsString();
        final json = jsonDecode(content) as Map<String, dynamic>;
        final verStr = json['version'] as String?;
        final fileName = json['fileName'] as String? ?? json['file'] as String?;
        final notes =
            json['releaseNotes'] as String? ?? json['changelog'] as String?;
        final dateStr = json['releaseDate'] as String?;
        final expectedSha = json['sha256'] as String?;

        final serverSemVer = SemanticVersion.tryParse(verStr);
        if (serverSemVer != null &&
            fileName != null &&
            isValidPackageName(fileName)) {
          final zipFile = File('${dir.path}${Platform.pathSeparator}$fileName');
          if (await zipFile.exists()) {
            final hasUpdate = serverSemVer > currentSemVer;
            final pkg = UpdatePackageInfo(
              version: serverSemVer,
              fileName: fileName,
              fullPath: zipFile.path,
              fileSize: await zipFile.length(),
              releaseNotes: notes,
              releaseDate: dateStr != null ? DateTime.tryParse(dateStr) : null,
              sha256: expectedSha,
            );
            if (hasUpdate) {
              await prefs.setOtaSettings(
                cachedUpdateVersion: serverSemVer.toString(),
              );
            }
            return UpdateCheckResult(
              hasUpdate: hasUpdate,
              packageInfo: pkg,
              currentVersion: currentVerStr,
            );
          }
        }
      } catch (e) {
        debugPrint('[OtaUpdateService] Parse version.json error: $e');
      }
    }

    // 3. Tự động quét các file .zip trong thư mục máy chủ
    try {
      final List<FileSystemEntity> entries = await dir
          .list(followLinks: false)
          .toList();
      final List<UpdatePackageInfo> candidates = [];

      final verRegex = RegExp(
        r'^JA_LAN_Messenger_[vV](\d+\.\d+(?:\.\d+)?(?:-[a-zA-Z0-9.-]+)?(?:\+\d+)?)(?:_[a-zA-Z0-9_]+)?\.zip$',
        caseSensitive: false,
      );

      for (final entity in entries) {
        if (entity is File && entity.path.toLowerCase().endsWith('.zip')) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          final match = isValidPackageName(fileName)
              ? verRegex.firstMatch(fileName)
              : null;
          if (match != null) {
            final verStr = match.group(1);
            final semVer = SemanticVersion.tryParse(verStr);
            if (semVer != null) {
              int size = 0;
              try {
                size = await entity.length();
              } catch (_) {}
              candidates.add(
                UpdatePackageInfo(
                  version: semVer,
                  fileName: fileName,
                  fullPath: entity.path,
                  fileSize: size,
                ),
              );
            }
          }
        }
      }

      if (candidates.isEmpty) {
        return UpdateCheckResult(
          hasUpdate: false,
          currentVersion: currentVerStr,
          errorMessage: 'Không tìm thấy gói cập nhật .zip nào trên máy chủ',
        );
      }

      // Sắp xếp giảm dần, lấy phiên bản cao nhất
      candidates.sort((a, b) => b.version.compareTo(a.version));
      final latestPkg = candidates.first;
      final hasUpdate = latestPkg.version > currentSemVer;

      if (hasUpdate) {
        await prefs.setOtaSettings(
          cachedUpdateVersion: latestPkg.version.toString(),
        );
      }

      return UpdateCheckResult(
        hasUpdate: hasUpdate,
        packageInfo: latestPkg,
        currentVersion: currentVerStr,
      );
    } catch (e) {
      return UpdateCheckResult(
        hasUpdate: false,
        currentVersion: currentVerStr,
        isConnectionSuccess: false,
        errorMessage: 'Lỗi khi quét tệp trên máy chủ: $e',
      );
    }
  }

  /// Kiểm tra cập nhật (Hỗ trợ Kênh: 'auto', 'github', 'lan')
  Future<UpdateCheckResult> checkForUpdates({
    String? overrideServerPath,
    String? overrideCurrentVersion,
    String? overrideSource,
    String? overrideRepo,
    String? overrideToken,
    bool isManual = false,
  }) async {
    final prefs = AppPreferences();
    final source = overrideSource ?? prefs.otaSource;
    final currentVerStr = overrideCurrentVersion ?? appVersion;

    if (source == 'github') {
      return await checkGitHubUpdates(
        repo: overrideRepo,
        token: overrideToken,
        overrideCurrentVersion: currentVerStr,
      );
    } else if (source == 'lan') {
      return await _checkLanUpdates(
        overrideServerPath: overrideServerPath,
        overrideCurrentVersion: currentVerStr,
        isManual: isManual,
      );
    } else {
      // 'auto' mode: Thử LAN trước nếu khả dụng
      final lanResult = await _checkLanUpdates(
        overrideServerPath: overrideServerPath,
        overrideCurrentVersion: currentVerStr,
        isManual: isManual,
      );
      if (lanResult.hasUpdate) {
        return lanResult;
      }

      // Nếu LAN không có bản cập nhật mới hoặc không kết nối được -> chuyển sang kiểm tra GitHub Releases
      try {
        final ghResult = await checkGitHubUpdates(
          repo: overrideRepo,
          token: overrideToken,
          overrideCurrentVersion: currentVerStr,
        );
        if (ghResult.hasUpdate || ghResult.isConnectionSuccess) {
          return ghResult;
        }
      } catch (e) {
        debugPrint('[OtaUpdateService] Auto fallback to GitHub error: $e');
      }
      return lanResult;
    }
  }

  /// Tải tệp zip từ Internet với cơ chế stream chunk và theo dõi chuyển hướng (Redirects)
  Future<void> _downloadRemoteZip({
    required String url,
    required File destinationFile,
    required int expectedSize,
    String? token,
    void Function(double progress, String status)? onProgress,
  }) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    try {
      var currentUri = Uri.parse(url);
      var req = await client.getUrl(currentUri);
      req.headers.set(HttpHeaders.userAgentHeader, 'JA-LAN-Messenger-OTA');
      if (token != null &&
          token.isNotEmpty &&
          !url.contains('objects.githubusercontent.com') &&
          !url.contains('s3.amazonaws.com')) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
        req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      }

      var resp = await req.close();
      var redirects = 0;
      while (resp.isRedirect && redirects < 5) {
        redirects++;
        final location = resp.headers.value(HttpHeaders.locationHeader);
        if (location == null) break;
        currentUri = currentUri.resolve(location);
        req = await client.getUrl(currentUri);
        req.headers.set(HttpHeaders.userAgentHeader, 'JA-LAN-Messenger-OTA');
        if (token != null &&
            token.isNotEmpty &&
            !currentUri.host.contains('objects.githubusercontent.com') &&
            !currentUri.host.contains('s3.amazonaws.com')) {
          req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
        }
        resp = await req.close();
      }

      if (resp.statusCode != 200) {
        throw StateError(
          'Tải tệp thất bại (HTTP ${resp.statusCode}): ${resp.reasonPhrase}',
        );
      }

      final contentLength = resp.contentLength > 0
          ? resp.contentLength
          : expectedSize;
      final sink = destinationFile.openWrite();
      var downloaded = 0;

      await for (final chunk in resp) {
        sink.add(chunk);
        downloaded += chunk.length;
        final ratio = contentLength > 0 ? (downloaded / contentLength) : 0.5;
        final mbDownloaded = (downloaded / (1024 * 1024)).toStringAsFixed(1);
        final mbTotal = contentLength > 0
            ? '${(contentLength / (1024 * 1024)).toStringAsFixed(1)} MB'
            : '...';
        onProgress?.call(
          (0.1 + ratio * 0.5).clamp(0.1, 0.6),
          'Đang tải gói cập nhật ($mbDownloaded / $mbTotal)...',
        );
      }
      await sink.flush();
      await sink.close();

      if (contentLength > 0 && downloaded != contentLength) {
        throw StateError(
          'Tệp tải về không trọn vẹn ($downloaded / $contentLength bytes)',
        );
      }
    } finally {
      client.close();
    }
  }

  /// Tính mã băm SHA-256 của tệp
  Future<String> _calculateSha256(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }

  /// Thực hiện tải gói cập nhật, giải nén và kích hoạt script cập nhật
  Future<void> performUpdate(
    UpdatePackageInfo packageInfo, {
    void Function(double progress, String status)? onProgress,
  }) async {
    if (!Platform.isWindows) throw UnsupportedError('OTA requires Windows');
    if (_applying) throw StateError('An update is already running');
    _applying = true;
    try {
      await _performUpdate(packageInfo, onProgress: onProgress);
    } finally {
      _applying = false;
    }
  }

  Future<Directory> _performUpdate(
    UpdatePackageInfo packageInfo, {
    void Function(double progress, String status)? onProgress,
    bool prepareOnly = false,
  }) async {
    onProgress?.call(0.05, 'Khởi tạo thư mục tạm...');

    final tempBase = await Directory.systemTemp.createTemp(
      'JA_LAN_Messenger_Update_',
    );
    final localZipFile = File('${tempBase.path}/update.zip');

    if (packageInfo.isRemoteUrl) {
      final prefs = AppPreferences();
      await _downloadRemoteZip(
        url: packageInfo.fullPath,
        destinationFile: localZipFile,
        expectedSize: packageInfo.fileSize,
        token: prefs.otaGithubToken,
        onProgress: onProgress,
      );
    } else {
      final sourceZip = File(packageInfo.fullPath);
      final totalBytes = await sourceZip.length();
      if (totalBytes == 0 ||
          (packageInfo.fileSize > 0 && totalBytes != packageInfo.fileSize)) {
        throw StateError(
          'Update package size changed; check for updates again',
        );
      }
      final writer = localZipFile.openWrite();
      var copied = 0;
      try {
        await for (final chunk in sourceZip.openRead()) {
          writer.add(chunk);
          copied += chunk.length;
          onProgress?.call(
            (0.1 + copied / totalBytes * 0.5).clamp(0.1, 0.6),
            'Downloading update...',
          );
        }
        await writer.flush();
      } finally {
        await writer.close();
      }
      if (copied != totalBytes) throw StateError('Incomplete update package');
    }

    // Xác thực mã băm SHA-256 nếu có
    if (packageInfo.sha256 != null && packageInfo.sha256!.trim().isNotEmpty) {
      onProgress?.call(0.62, 'Đang xác thực mã băm SHA256...');
      final actualHash = await _calculateSha256(localZipFile);
      if (actualHash.toLowerCase() !=
          packageInfo.sha256!.trim().toLowerCase()) {
        throw StateError(
          'Mã băm SHA256 không khớp!\nKỳ vọng: ${packageInfo.sha256}\nThực tế: $actualHash',
        );
      }
    }

    // 2. Giải nén gói cập nhật
    onProgress?.call(0.65, 'Đang giải nén gói cập nhật...');
    final extractDir = Directory('${tempBase.path}\\extracted');
    extractDir.createSync(recursive: true);

    final validation = await _runPowerShell("""
\$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
\$zip = [IO.Compression.ZipFile]::OpenRead(${_psLiteral(localZipFile.path)})
try {
  foreach (\$entry in \$zip.Entries) {
    \$parts = \$entry.FullName.Replace('\\', '/').Split('/')
    if (\$entry.FullName -match '^[\\/]' -or \$entry.FullName.Contains(':') -or \$parts -contains '..' -or ((\$entry.ExternalAttributes -shr 16) -band 61440) -eq 40960) { throw 'Unsafe archive entry' }
  }
  [IO.Compression.ZipFileExtensions]::ExtractToDirectory(\$zip, ${_psLiteral(extractDir.path)})
} finally { \$zip.Dispose() }
""");
    if (validation.exitCode != 0) {
      throw StateError('Invalid or unsafe update archive');
    }

    // 3. Tìm thư mục nguồn chứa tệp thực thi sau khi giải nén
    onProgress?.call(0.85, 'Đang chuẩn bị bàn giao cập nhật...');
    Directory payloadDir = extractDir;

    // Nếu zip đóng gói lồng 1 thư mục gốc (vd: JA_LAN_Messenger_v1.1.0_Windows_x64)
    final subDirs = extractDir.listSync().whereType<Directory>().toList();
    if (subDirs.length == 1) {
      final testExe = File('${subDirs.first.path}\\ja_lan_messenger.exe');
      if (testExe.existsSync()) {
        payloadDir = subDirs.first;
      }
    }

    for (final name in [
      'ja_lan_messenger.exe',
      'flutter_windows.dll',
      'data',
    ]) {
      if (!await FileSystemEntity.isFile('${payloadDir.path}/$name') &&
          !await FileSystemEntity.isDirectory('${payloadDir.path}/$name')) {
        throw StateError('Incomplete Flutter update package: $name');
      }
    }

    if (prepareOnly) return payloadDir;
    // 4. Xác định thư mục ứng dụng hiện tại đang chạy
    final currentExe = File(Platform.resolvedExecutable);
    final targetAppDir = currentExe.parent;
    final currentPid = pid;

    // 5. Sinh script apply_update.bat độc lập
    final batFile = File('${tempBase.path}\\apply_update.bat');
    final batContent = generateApplyUpdateScript(
      oldPid: currentPid,
      sourceDir: payloadDir.path,
      targetDir: targetAppDir.path,
      exeName: currentExe.path.split(Platform.pathSeparator).last,
    );
    batFile.writeAsStringSync(batContent);

    onProgress?.call(1.0, 'Sẵn sàng áp dụng cập nhật! Khởi động lại ngay...');
    await Future.delayed(const Duration(milliseconds: 600));

    // 6. Kích hoạt apply_update.bat ở chế độ Detached và thoát tiến trình hiện tại
    if (Platform.isWindows) {
      await ChatHistoryService().flush();
      final launch = await _runPowerShell(
        "Start-Process -FilePath 'cmd.exe' -ArgumentList ${_psLiteral('/c ""${batFile.path}""')} -WindowStyle Hidden",
      );
      if (launch.exitCode != 0) {
        throw StateError('Cannot start update installer');
      }
      exit(0);
    }
    return payloadDir;
  }

  /// Tạo nội dung script bàn giao cập nhật trên Windows
  @visibleForTesting
  Future<Directory> validatePackageForTesting(UpdatePackageInfo package) =>
      _performUpdate(package, prepareOnly: true);

  static String generateApplyUpdateScript({
    required int oldPid,
    required String sourceDir,
    required String targetDir,
    required String exeName,
  }) {
    for (final value in [sourceDir, targetDir, exeName]) {
      if (value.contains(RegExp(r'["%\r\n]'))) {
        throw ArgumentError('Unsupported updater path');
      }
    }
    if (oldPid <= 0 || exeName.contains(RegExp(r'[\\/]'))) {
      throw ArgumentError('Invalid updater target');
    }
    return '''@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 >nul
title JA LAN Messenger - Dang Cap Nhat Phien Ban Moi...

set "OLD_PID=$oldPid"
set "SRC_DIR=$sourceDir"
set "DST_DIR=$targetDir"
set "EXE_NAME=$exeName"
set "BACKUP_DIR=%~dp0backup"
if not exist "%SRC_DIR%\\%EXE_NAME%" exit /b 10
if not exist "%DST_DIR%\\%EXE_NAME%" exit /b 11
set /a WAIT_COUNT=0

echo ========================================================
echo   JA LAN MESSENGER - DANG TIEN HANH CAP NHAT
echo ========================================================
echo.
echo [1/3] Dang cho tien trinh cu (PID %OLD_PID%) dong han...

:wait_loop
set /a WAIT_COUNT+=1
if %WAIT_COUNT% GEQ 60 exit /b 12
timeout /t 1 /nobreak >nul
tasklist /fi "PID eq %OLD_PID%" 2>nul | findstr /i "%OLD_PID%" >nul
if not errorlevel 1 goto wait_loop

:: Cho them 1s de Windows giai phong toan bo handle file
timeout /t 1 /nobreak >nul

echo [2/3] Dang ghi de tep ung dung moi...
robocopy "%DST_DIR%" "%BACKUP_DIR%" /E /NP /R:2 /W:1 /XD logs conversations backups /XF user_preferences.json update_config.json known_devices.json >"%~dp0backup.log"
if errorlevel 8 exit /b 13
robocopy "%SRC_DIR%" "%DST_DIR%" /E /IS /IT /NP /R:5 /W:2 /XD logs conversations backups /XF user_preferences.json update_config.json known_devices.json >"%~dp0apply.log"
if errorlevel 8 goto rollback

echo [3/3] Khoi chay ung dung moi...
start "" "%DST_DIR%\\%EXE_NAME%"

:: Cho 2s roi dong cua so
timeout /t 2 /nobreak >nul
exit /b 0

:rollback
robocopy "%BACKUP_DIR%" "%DST_DIR%" /E /IS /IT /NP /R:2 /W:1 >"%~dp0rollback.log"
if errorlevel 8 exit /b 14
start "" "%DST_DIR%\\%EXE_NAME%"
exit /b 15
''';
  }
}
