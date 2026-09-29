import 'package:flutter_test/flutter_test.dart';
import 'package:ja_lan_messenger/modules/localization/app_locale.dart';
import 'package:ja_lan_messenger/modules/network/lan_discovery.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  LanguageProvider.disableDiskPersistenceForTesting = true;

  group('LanguageProvider and Scan Localization Tests', () {
    late LanguageProvider lang;

    setUp(() {
      lang = LanguageProvider();
    });

    test(
      'tr formats correctly with %s and positional arguments in VI, EN, ZH',
      () {
        // VI
        lang.setLanguage(AppLanguage.vi);
        expect(
          lang.tr('scanSubnetProgress', [1323, 2300, 1323]),
          'Quét UDP + TCP: 1323/2300 địa chỉ • đã phát 1323 gói UDP',
        );
        expect(
          lang.tr('scanBroadcastingMultiNic', [2]),
          'Đang phát sóng đa tầng (2 card mạng)...',
        );
        expect(
          lang.tr('scanArpChecking', [15]),
          'Đang đối soát bảng ARP (15 thiết bị)...',
        );
        expect(lang.tr('scanPreparing'), 'Đang chuẩn bị quét mạng...');
        expect(
          lang.tr('scanIncomplete', ['Connection timeout']),
          'Quét chưa hoàn tất: Connection timeout',
        );
        expect(lang.tr('scanStopped'), 'Đã dừng quét');
        expect(lang.tr('scanNoAdaptersSelected'), 'Chưa chọn card mạng nào');
        expect(
          lang.tr('scanAdaptersUpdated'),
          'Đã cập nhật card mạng • Đang quét...',
        );
        expect(
          lang.tr('scanCompletedDetail', [2300, 2300]),
          'Đã duyệt 2300 địa chỉ • gửi 2300 gói UDP • đang lắng nghe phản hồi',
        );

        // EN
        lang.setLanguage(AppLanguage.en);
        expect(
          lang.tr('scanSubnetProgress', [1323, 2300, 1323]),
          'Scanning UDP + TCP: 1323/2300 addresses • sent 1323 UDP packets',
        );
        expect(
          lang.tr('scanBroadcastingMultiNic', [2]),
          'Multi-NIC broadcasting (2 adapters)...',
        );
        expect(
          lang.tr('scanArpChecking', [15]),
          'Checking ARP table (15 devices)...',
        );
        expect(lang.tr('scanPreparing'), 'Preparing network scan...');
        expect(
          lang.tr('scanIncomplete', ['Connection timeout']),
          'Scan incomplete: Connection timeout',
        );
        expect(lang.tr('scanStopped'), 'Scan stopped');
        expect(
          lang.tr('scanNoAdaptersSelected'),
          'No network adapter selected',
        );
        expect(
          lang.tr('scanAdaptersUpdated'),
          'Network adapters updated • Scanning...',
        );
        expect(
          lang.tr('scanCompletedDetail', [2300, 2300]),
          'Scanned 2300 addresses • sent 2300 UDP packets • listening for responses',
        );

        // ZH
        lang.setLanguage(AppLanguage.zh);
        expect(
          lang.tr('scanSubnetProgress', [1323, 2300, 1323]),
          '正在扫描 UDP + TCP：1323/2300 个地址 • 已发送 1323 个 UDP 数据包',
        );
        expect(lang.tr('scanBroadcastingMultiNic', [2]), '正在多网卡广播（2 个网卡）...');
        expect(lang.tr('scanArpChecking', [15]), '正在核对 ARP 表（15 台设备）...');
        expect(lang.tr('scanPreparing'), '正在准备扫描网络...');
        expect(
          lang.tr('scanIncomplete', ['Connection timeout']),
          '扫描未完成：Connection timeout',
        );
        expect(lang.tr('scanStopped'), '已停止扫描');
        expect(lang.tr('scanNoAdaptersSelected'), '未选择任何网卡');
        expect(lang.tr('scanAdaptersUpdated'), '网卡已更新 • 正在扫描...');
        expect(
          lang.tr('scanCompletedDetail', [2300, 2300]),
          '已扫描 2300 个地址 • 发送 2300 个 UDP 包 • 正在监听响应',
        );
      },
    );

    test('DiscoveryScanState retains metrics and copyWith correctly', () {
      const initial = DiscoveryScanState();
      expect(initial.sweepDone, 0);
      expect(initial.sweepTotal, 0);
      expect(initial.sweepSent, 0);
      expect(initial.arpCount, 0);
      expect(initial.errorMessage, isNull);

      final updated = initial.copyWith(
        isSweeping: true,
        progress: 0.5,
        activePhase: 'subnet_sweep',
        sweepDone: 50,
        sweepTotal: 100,
        sweepSent: 48,
        arpCount: 5,
        errorMessage: 'test error',
      );

      expect(updated.isSweeping, isTrue);
      expect(updated.progress, 0.5);
      expect(updated.activePhase, 'subnet_sweep');
      expect(updated.sweepDone, 50);
      expect(updated.sweepTotal, 100);
      expect(updated.sweepSent, 48);
      expect(updated.arpCount, 5);
      expect(updated.errorMessage, 'test error');
    });

    test(
      'Regex fallback correctly parses statusText when structured metrics are 0',
      () {
        const rawText =
            'Quét UDP + TCP: 1323/2300 địa chỉ • đã phát 1323 gói UDP';
        final match = RegExp(r'(\d+)\s*/\s*(\d+).*?(\d+)').firstMatch(rawText);
        expect(match, isNotNull);
        expect(int.parse(match!.group(1)!), 1323);
        expect(int.parse(match.group(2)!), 2300);
        expect(int.parse(match.group(3)!), 1323);

        lang.setLanguage(AppLanguage.en);
        final localized = lang.tr('scanSubnetProgress', [
          int.parse(match.group(1)!),
          int.parse(match.group(2)!),
          int.parse(match.group(3)!),
        ]);
        expect(
          localized,
          'Scanning UDP + TCP: 1323/2300 addresses • sent 1323 UDP packets',
        );
      },
    );
  });
}
