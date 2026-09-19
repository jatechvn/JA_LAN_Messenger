import 'dart:io';

class DetectedImeInfo {
  final bool isDetected;
  final String? imeName;
  final String? imeType; // 'vietnamese' hoặc 'chinese'

  const DetectedImeInfo({
    required this.isDetected,
    this.imeName,
    this.imeType,
  });

  static const DetectedImeInfo none = DetectedImeInfo(isDetected: false);
}

class ExternalImeDetector {
  static DetectedImeInfo? _cachedInfo;
  static DateTime? _lastCheckTime;
  static const Duration _cacheDuration = Duration(seconds: 6);

  // Mock override dành cho kiểm thử tự động
  static DetectedImeInfo? mockDetectedIme;

  /// Danh sách nhận diện các tiến trình bộ gõ tiếng Việt phổ biến trên Windows
  static const Map<String, String> _knownVietnameseImes = {
    'evkey64': 'EVKey',
    'evkey32': 'EVKey',
    'evkey': 'EVKey',
    'unikeynt': 'UniKey',
    'unikey': 'UniKey',
    'openkey64': 'OpenKey',
    'openkey': 'OpenKey',
    'gotiengviet': 'GõTiếngViệt',
    'vietkey': 'VietKey',
  };

  /// Danh sách nhận diện các tiến trình bộ gõ tiếng Trung phổ biến trên Windows
  static const Map<String, String> _knownChineseImes = {
    'sogoupy': 'Sogou Pinyin',
    'sogouwb': 'Sogou Wubi',
    'qqpinyin': 'QQ Pinyin',
    'baidupinyin': 'Baidu Pinyin',
  };

  /// Quét kiểm tra tiến trình bộ gõ ngoài đang chạy trên Windows
  static Future<DetectedImeInfo> checkExternalImeAsync() async {
    if (mockDetectedIme != null) {
      return mockDetectedIme!;
    }

    if (!Platform.isWindows) {
      return DetectedImeInfo.none;
    }

    // Trong môi trường kiểm thử tự động, tránh gọi subprocess và timer không cần thiết
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return DetectedImeInfo.none;
    }

    final now = DateTime.now();
    if (_cachedInfo != null &&
        _lastCheckTime != null &&
        now.difference(_lastCheckTime!) < _cacheDuration) {
      return _cachedInfo!;
    }

    try {
      final result = await Process.run(
        'tasklist',
        ['/NH', '/FO', 'CSV'],
        runInShell: true,
      ).timeout(const Duration(seconds: 2));

      if (result.exitCode == 0) {
        final stdoutLower = (result.stdout as String).toLowerCase();

        // 1. Kiểm tra bộ gõ tiếng Việt
        for (final entry in _knownVietnameseImes.entries) {
          if (stdoutLower.contains(entry.key)) {
            final info = DetectedImeInfo(
              isDetected: true,
              imeName: entry.value,
              imeType: 'vietnamese',
            );
            _cachedInfo = info;
            _lastCheckTime = now;
            return info;
          }
        }

        // 2. Kiểm tra bộ gõ tiếng Trung
        for (final entry in _knownChineseImes.entries) {
          if (stdoutLower.contains(entry.key)) {
            final info = DetectedImeInfo(
              isDetected: true,
              imeName: entry.value,
              imeType: 'chinese',
            );
            _cachedInfo = info;
            _lastCheckTime = now;
            return info;
          }
        }
      }
    } catch (_) {}

    _cachedInfo = DetectedImeInfo.none;
    _lastCheckTime = now;
    return DetectedImeInfo.none;
  }

  /// Kiểm tra nhanh heuristic xem ký tự đưa vào có phải do bộ gõ ngoài gõ hay không
  static bool hasAccentedOrChineseChars(String text) {
    for (int i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      // Hán tự: Unicode 0x4E00 - 0x9FA5
      if (code >= 0x4E00 && code <= 0x9FA5) return true;
      // Ký tự tiếng Việt có dấu ngoài bảng ASCII cơ bản (code > 127)
      if (code > 127 && _isVietnameseAccentedChar(text[i])) return true;
    }
    return false;
  }

  static bool _isVietnameseAccentedChar(String ch) {
    const accented =
        'áàảãạăắằẳẵặâấầẩẫậéèẻẽẹêếềểễệíìỉĩịóòỏõọôốồổỗộơớờởỡợúùủũụưứừửữựýỳỷỹỵ'
        'ÁÀẢÃẠĂẮẰẲẴẶÂẤẦẨẪẬÉÈẺẼẸÊẾỀỂỄỆÍÌỈĨỊÓÒỎÕỌÔỐỒỔỖỘƠỚỜỞỠỢÚÙỦŨỤƯỨỪỬỮỰÝỲỶỸỴđĐ';
    return accented.contains(ch);
  }
}
