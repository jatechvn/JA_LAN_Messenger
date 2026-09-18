import 'dart:io';

/// Phân tích bảng ARP hệ thống để lấy danh sách IP các máy đang hoạt động trong mạng LAN
class ArpResolver {
  /// Đọc bảng ARP từ hệ thống Windows và trả về `Map<String, String>` (IP -> MAC)
  static Future<Map<String, String>> getArpTable() async {
    final Map<String, String> map = {};
    try {
      final res = await Process.run('arp', ['-a'], runInShell: false);
      final out = res.stdout.toString();
      // Match: " 172.21.170.16 68-1d-ef-4e-f1-e3 dynamic"
      final regex = RegExp(
        r'(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})\s+([0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2}[-:][0-9a-fA-F]{2})',
      );

      for (final match in regex.allMatches(out)) {
        final ip = match.group(1);
        final mac = match.group(2)?.replaceAll('-', ':').toUpperCase();
        if (ip != null &&
            mac != null &&
            mac != 'FF:FF:FF:FF:FF:FF' &&
            !ip.startsWith('224.') &&
            !ip.startsWith('239.') &&
            !ip.startsWith('255.')) {
          map[ip] = mac;
        }
      }
    } catch (_) {}
    return map;
  }

  /// Lấy danh sách các IP đang hoạt động trong bảng ARP thuộc dải mạng LAN
  static Future<List<String>> getActiveLanIps({Set<String>? excludeIps}) async {
    final table = await getArpTable();
    final List<String> ips = [];
    final exclude = excludeIps ?? {};

    for (final ip in table.keys) {
      if (exclude.contains(ip)) continue;
      if (ip.startsWith('127.') || ip.startsWith('169.254.')) continue;
      ips.add(ip);
    }
    return ips;
  }
}
