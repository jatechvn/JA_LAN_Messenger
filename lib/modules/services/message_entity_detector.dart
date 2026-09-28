import 'package:flutter/foundation.dart';

/// Loại thực thể được tự động nhận diện trong tin nhắn
enum MessageEntityType {
  url,
  phone,
  email,
  path,
}

/// Thông tin một thực thể được phát hiện trong tin nhắn
@immutable
class MessageEntity {
  final MessageEntityType type;

  /// Chuỗi gốc được tìm thấy trong tin nhắn
  final String value;

  /// Chuỗi URL dùng để thực thi hành động (https://..., mailto:..., tel:..., đường dẫn)
  final String actionUrl;

  /// Nhãn hiển thị ngắn gọn trên thanh Quick Chip
  final String label;

  const MessageEntity({
    required this.type,
    required this.value,
    required this.actionUrl,
    required this.label,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageEntity &&
          runtimeType == other.runtimeType &&
          type == other.type &&
          value == other.value;

  @override
  int get hashCode => type.hashCode ^ value.hashCode;

  @override
  String toString() => 'MessageEntity($type, $value -> $actionUrl)';
}

/// Bộ phân tích và nhận diện thông minh các thực thể trong tin nhắn
class MessageEntityDetector {
  static final RegExp _emailRegExp = RegExp(
    r'\b[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}\b',
    caseSensitive: false,
  );

  // Đường dẫn Windows: UNC (\\server\share\...) hoặc ổ đĩa (C:\Folder\...)
  static final RegExp _uncPathRegExp = RegExp(
    r'\\\\[a-zA-Z0-9_.-]+(?:\\[^\r\n\\/:*?"<>|]+)*(?:\\[^\r\n\\/:*?"<>|]+?\.[a-zA-Z0-9]{1,8}|\\[^\s\r\n\\/:*?"<>|]+)?',
    caseSensitive: false,
  );

  static final RegExp _localPathRegExp = RegExp(
    r'[a-zA-Z]:\\(?:[^\r\n\\/:*?"<>|]+\\)*(?:[^\r\n\\/:*?"<>|]+?\.[a-zA-Z0-9]{1,8}|[^\s\r\n\\/:*?"<>|]+)?',
    caseSensitive: false,
  );

  // URLs có protocol http:// hoặc https://
  static final RegExp _urlWithProtocolRegExp = RegExp(
    r'''(?:https?:\/\/[^\s<>"'()\[\]{}]+)''',
    caseSensitive: false,
  );

  // URLs bắt đầu bằng www.
  static final RegExp _urlWwwRegExp = RegExp(
    r'''(?:www\.[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}(?::\d+)?[^\s<>"'()\[\]{}]*)''',
    caseSensitive: false,
  );

  // Domain phổ biến (không bắt đầu bằng @ để tránh trùng email)
  static final RegExp _urlDomainRegExp = RegExp(
    r'''(?<![@\w])(?:[a-zA-Z0-9-]+\.)+(?:com|vn|net|org|edu|gov|io|ai|dev|co|xyz|me|info|biz|cc|tv)(?::\d+)?(?:\/[^\s<>"'()\[\]{}]*)?''',
    caseSensitive: false,
  );

  // Số điện thoại Việt Nam & Quốc tế (+84 hoặc 0...)
  static final RegExp _phoneCandidateRegExp = RegExp(
    r'(?<![\w./:\\])(?:\+84|0)(?:[\s.-]?[0-9]){8,11}(?![\w])',
  );

  /// Cắt bỏ dấu câu thừa dính ở cuối URL hoặc đường dẫn (như dấu chấm, phẩy, ngoặc)
  static String _cleanTrailingPunctuation(String input) {
    var s = input.trim();
    while (s.isNotEmpty) {
      final last = s[s.length - 1];
      if (last == '.' ||
          last == ',' ||
          last == ';' ||
          last == '!' ||
          last == '?' ||
          last == ')' ||
          last == ']' ||
          last == '}' ||
          last == '"' ||
          last == "'") {
        s = s.substring(0, s.length - 1).trim();
      } else {
        break;
      }
    }
    if (s.startsWith('"') || s.startsWith("'")) {
      s = s.substring(1).trim();
    }
    return s;
  }

  /// Trích xuất toàn bộ các thực thể duy nhất từ văn bản
  static List<MessageEntity> extractEntities(String text) {
    if (text.trim().isEmpty) return const [];

    final entities = <MessageEntity>[];
    final seenValues = <String>{};

    void addEntity(MessageEntityType type, String rawValue, String actionUrl, String label) {
      final cleanVal = rawValue.trim();
      if (cleanVal.isEmpty || seenValues.contains(cleanVal)) return;
      seenValues.add(cleanVal);
      entities.add(MessageEntity(
        type: type,
        value: cleanVal,
        actionUrl: actionUrl,
        label: label,
      ));
    }

    // 1. Emails
    for (final match in _emailRegExp.allMatches(text)) {
      final email = _cleanTrailingPunctuation(match.group(0)!);
      if (email.contains('@')) {
        addEntity(
          MessageEntityType.email,
          email,
          'mailto:$email',
          email,
        );
      }
    }

    // 2. Đường dẫn UNC & Windows Path
    for (final match in _uncPathRegExp.allMatches(text)) {
      final path = _cleanTrailingPunctuation(match.group(0)!);
      if (path.length >= 4) {
        addEntity(
          MessageEntityType.path,
          path,
          path,
          path.length > 28 ? '...${path.substring(path.length - 25)}' : path,
        );
      }
    }

    for (final match in _localPathRegExp.allMatches(text)) {
      final path = _cleanTrailingPunctuation(match.group(0)!);
      if (path.length >= 3) {
        addEntity(
          MessageEntityType.path,
          path,
          path,
          path.length > 28 ? '...${path.substring(path.length - 25)}' : path,
        );
      }
    }

    // 3. URLs
    void processUrl(String rawUrl) {
      final url = _cleanTrailingPunctuation(rawUrl);
      if (url.isEmpty || seenValues.contains(url)) return;

      // Không coi email thành URL
      if (url.contains('@') && !url.contains('://')) return;

      String actionUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        actionUrl = 'https://$url';
      }

      String displayLabel = url;
      if (displayLabel.startsWith('https://')) {
        displayLabel = displayLabel.substring(8);
      } else if (displayLabel.startsWith('http://')) {
        displayLabel = displayLabel.substring(7);
      }
      if (displayLabel.length > 30) {
        displayLabel = '${displayLabel.substring(0, 27)}...';
      }

      addEntity(MessageEntityType.url, url, actionUrl, displayLabel);
    }

    for (final match in _urlWithProtocolRegExp.allMatches(text)) {
      processUrl(match.group(0)!);
    }
    for (final match in _urlWwwRegExp.allMatches(text)) {
      processUrl(match.group(0)!);
    }
    for (final match in _urlDomainRegExp.allMatches(text)) {
      processUrl(match.group(0)!);
    }

    // 4. Số điện thoại (Phone Numbers)
    for (final match in _phoneCandidateRegExp.allMatches(text)) {
      final raw = _cleanTrailingPunctuation(match.group(0)!);
      // Loại trừ các chuỗi float như 0.5 hoặc chuỗi có quá nhiều dấu chấm (như IP 0.0.0.0)
      if (raw.contains('..') || RegExp(r'\.[0-9]{1,2}$').hasMatch(raw)) {
        continue;
      }
      final dotCount = '.'.allMatches(raw).length;
      if (dotCount > 2) {
        // Nhiều hơn 2 dấu chấm -> khả năng cao là IP hoặc chuỗi phiên bản
        continue;
      }

      // Đếm số lượng chữ số thuần túy
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 9 && digits.length <= 11) {
        // Đảm bảo là định dạng số điện thoại VN hoặc quốc tế hợp lệ
        final isValidStart = raw.startsWith('+84') ||
            raw.startsWith('03') ||
            raw.startsWith('05') ||
            raw.startsWith('07') ||
            raw.startsWith('08') ||
            raw.startsWith('09') ||
            raw.startsWith('02'); // Điện thoại bàn (024, 028...)

        if (isValidStart) {
          final telUrl = 'tel:${raw.startsWith('+') ? '+$digits' : digits}';
          addEntity(
            MessageEntityType.phone,
            raw,
            telUrl,
            raw,
          );
        }
      }
    }

    return entities;
  }
}
