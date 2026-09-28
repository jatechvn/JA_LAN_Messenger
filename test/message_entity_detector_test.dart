import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/services/message_entity_detector.dart';

void main() {
  group('MessageEntityDetector Tests', () {
    test('Extract URLs correctly', () {
      const text = 'Truy cập https://github.com/jatechvn hoặc www.google.com và check zalo.me/test.';
      final entities = MessageEntityDetector.extractEntities(text);

      final urls = entities.where((e) => e.type == MessageEntityType.url).toList();
      expect(urls.length, 3);
      expect(urls[0].value, 'https://github.com/jatechvn');
      expect(urls[0].actionUrl, 'https://github.com/jatechvn');

      expect(urls[1].value, 'www.google.com');
      expect(urls[1].actionUrl, 'https://www.google.com');

      expect(urls[2].value, 'zalo.me/test');
      expect(urls[2].actionUrl, 'https://zalo.me/test');
    });

    test('Extract Emails correctly', () {
      const text = 'Gửi phản hồi về support@jatech.vn hoặc user.name+dev@sub.domain.com!';
      final entities = MessageEntityDetector.extractEntities(text);

      final emails = entities.where((e) => e.type == MessageEntityType.email).toList();
      expect(emails.length, 2);
      expect(emails[0].value, 'support@jatech.vn');
      expect(emails[0].actionUrl, 'mailto:support@jatech.vn');

      expect(emails[1].value, 'user.name+dev@sub.domain.com');
      expect(emails[1].actionUrl, 'mailto:user.name+dev@sub.domain.com');
    });

    test('Extract Phone numbers correctly and ignore IP/Dates/Floats', () {
      const text = '''
      Liên hệ hotline: 0901234567 hoặc 098.765.4321 hoặc +84 912 345 678.
      Số bàn: 024.3768.9999.
      Server IP: 10.81.141.226 và 192.168.0.1 và 0.0.0.0.
      Ngày tạo: 2026-09-28.
      Tỉ lệ: 0.5%.
      ''';
      final entities = MessageEntityDetector.extractEntities(text);

      final phones = entities.where((e) => e.type == MessageEntityType.phone).toList();
      expect(phones.length, 4);

      expect(phones[0].value, '0901234567');
      expect(phones[0].actionUrl, 'tel:0901234567');

      expect(phones[1].value, '098.765.4321');
      expect(phones[1].actionUrl, 'tel:0987654321');

      expect(phones[2].value, '+84 912 345 678');
      expect(phones[2].actionUrl, 'tel:+84912345678');

      expect(phones[3].value, '024.3768.9999');
      expect(phones[3].actionUrl, 'tel:02437689999');

      // IPs, dates, floats must NOT be recognized as phones
      final allValues = entities.map((e) => e.value).toList();
      expect(allValues.contains('10.81.141.226'), isFalse);
      expect(allValues.contains('192.168.0.1'), isFalse);
      expect(allValues.contains('0.0.0.0'), isFalse);
      expect(allValues.contains('2026-09-28'), isFalse);
      expect(allValues.contains('0.5'), isFalse);
    });

    test('Extract UNC and Local Windows paths correctly', () {
      const text = r'Xem thư mục cập nhật tại \\10.81.141.226\temp\FBT\JA_PROJECT và file C:\Program Files\JA_LAN\app.exe.';
      final entities = MessageEntityDetector.extractEntities(text);

      final paths = entities.where((e) => e.type == MessageEntityType.path).toList();
      expect(paths.length, 2);
      expect(paths[0].value, r'\\10.81.141.226\temp\FBT\JA_PROJECT');
      expect(paths[0].actionUrl, r'\\10.81.141.226\temp\FBT\JA_PROJECT');

      expect(paths[1].value, r'C:\Program Files\JA_LAN\app.exe');
      expect(paths[1].actionUrl, r'C:\Program Files\JA_LAN\app.exe');
    });

    test('Extract Windows directory paths with spaces', () {
      const text = r'Vào thư mục C:\Program Files\Google\Chrome\ hoặc \\10.81.141.226\Shared Folder\Data\ để lấy tệp.';
      final entities = MessageEntityDetector.extractEntities(text);
      final paths = entities.where((e) => e.type == MessageEntityType.path).toList();
      expect(paths.length, 2);
      expect(paths[0].value, r'C:\Program Files\Google\Chrome\');
      expect(paths[1].value, r'\\10.81.141.226\Shared Folder\Data\');
    });

    test('Extract mixed entities in single message without conflict', () {
      const text = r'File gửi ở \\server\share\data.xlsx, cần hỗ trợ gọi 0908889999 hoặc mail admin@ja.com, xem https://ja.com/guide';
      final entities = MessageEntityDetector.extractEntities(text);

      expect(entities.length, 4);

      final emails = entities.where((e) => e.type == MessageEntityType.email).toList();
      final paths = entities.where((e) => e.type == MessageEntityType.path).toList();
      final urls = entities.where((e) => e.type == MessageEntityType.url).toList();
      final phones = entities.where((e) => e.type == MessageEntityType.phone).toList();

      expect(emails.length, 1);
      expect(emails.first.value, 'admin@ja.com');

      expect(paths.length, 1);
      expect(paths.first.value, r'\\server\share\data.xlsx');

      expect(urls.length, 1);
      expect(urls.first.value, 'https://ja.com/guide');

      expect(phones.length, 1);
      expect(phones.first.value, '0908889999');
    });

    test('Handle empty and plain text with no entities', () {
      expect(MessageEntityDetector.extractEntities(''), isEmpty);
      expect(MessageEntityDetector.extractEntities('   '), isEmpty);
      expect(MessageEntityDetector.extractEntities('Xin chào, chúc một ngày tốt lành!'), isEmpty);
    });
  });
}
