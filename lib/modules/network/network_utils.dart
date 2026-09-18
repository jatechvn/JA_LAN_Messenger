import 'dart:io';
import 'dart:convert';

/// Chi tiết một giao diện mạng (Network Interface) trên máy
class NetworkInterfaceDetails {
  final String name;
  final String ip;
  final String subnet;
  final bool isVirtual;
  final bool isPrivateLan;
  final String? netmask;
  final int prefixLength;
  final List<String> subSlices;

  const NetworkInterfaceDetails({
    required this.name,
    required this.ip,
    required this.subnet,
    required this.isVirtual,
    required this.isPrivateLan,
    this.netmask,
    this.prefixLength = 24,
    this.subSlices = const [],
  });

  @override
  String toString() =>
      '$name: $ip ($subnet) [${isVirtual ? 'Virtual' : 'Physical LAN'}]';
}

/// Tiện ích phân tích card mạng, tính toán Subnet và Broadcast IP
class NetworkUtils {
  static int _ipNumber(String ip) {
    if (!isValidIp(ip)) throw FormatException('Invalid IPv4: $ip');
    return ip.trim().split('.').map(int.parse).fold(0, (a, b) => (a << 8) | b);
  }

  static String _ipString(int value) =>
      '${(value >> 24) & 255}.${(value >> 16) & 255}.${(value >> 8) & 255}.${value & 255}';

  static ({int first, int last}) _hostBounds(String cidr) {
    final parts = cidr.split('/');
    if (parts.length != 2) throw FormatException('Invalid CIDR: $cidr');
    final prefix = int.tryParse(parts[1]);
    if (prefix == null || prefix < 0 || prefix > 32) {
      throw FormatException('Invalid prefix: $cidr');
    }
    final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
    final network = _ipNumber(parts[0]) & mask;
    final broadcast = network | (0xffffffff ^ mask);
    return (
      first: network + (prefix < 31 ? 1 : 0),
      last: broadcast - (prefix < 31 ? 1 : 0),
    );
  }

  static int subnetHostCount(String cidr) {
    final bounds = _hostBounds(cidr);
    return bounds.last - bounds.first + 1;
  }

  static Iterable<String> subnetHosts(String cidr) sync* {
    final bounds = _hostBounds(cidr);
    for (var host = bounds.first; host <= bounds.last; host++) {
      yield _ipString(host);
    }
  }

  /// Parse only adjacent IPv4/mask lines; never match across adapter blocks.
  static Map<String, String> parseWindowsSubnetMasks(String text) {
    final masks = <String, String>{};
    String? candidate;
    final address = RegExp(r'(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])');
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty) {
        candidate = null;
        continue;
      }
      final matches = address
          .allMatches(line)
          .map((m) => m.group(0)!)
          .where(isValidIp)
          .toList();
      if (matches.length != 1) {
        candidate = null;
        continue;
      }
      final value = matches.single;
      if (candidate != null && value.startsWith('255.')) {
        maskToPrefixLength(value); // Reject non-contiguous masks.
        masks[candidate] = value;
        candidate = null;
      } else {
        candidate = value.startsWith('255.') ? null : value;
      }
    }
    return masks;
  }

  /// Kiểm tra xem card mạng có phải là card ảo / tunnel (Tailscale, Docker, WSL, vEthernet,...)
  static bool isVirtualAdapter(String name, String ip) {
    if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
      return true;
    }

    // Tailscale / Carrier-Grade NAT (100.64.0.0/10)
    if (ip.startsWith('100.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final secondOctet = int.tryParse(parts[1]) ?? 0;
        if (secondOctet >= 64 && secondOctet <= 127) {
          return true;
        }
      }
      return true;
    }

    final lowerName = name.toLowerCase();
    final virtualKeywords = [
      'tailscale',
      'zerotier',
      'wireguard',
      'wsl',
      'vethernet',
      'virtual',
      'docker',
      'vmware',
      'vmnet',
      'vbox',
      'tap',
      'tun',
      'pseudo',
      'teredo',
      'npcap',
      'hyper-v',
      'openvpn',
      'bluetooth',
    ];

    for (final kw in virtualKeywords) {
      if (lowerName.contains(kw)) {
        return true;
      }
    }

    return false;
  }

  /// Kiểm tra IP có thuộc dải mạng LAN riêng (RFC 1918: 10.x, 172.16-31.x, 192.168.x)
  static bool isPrivateLanIp(String ip) {
    if (ip.startsWith('192.168.') || ip.startsWith('10.')) {
      return true;
    }
    if (ip.startsWith('172.')) {
      final parts = ip.split('.');
      if (parts.length >= 2) {
        final second = int.tryParse(parts[1]) ?? 0;
        if (second >= 16 && second <= 31) {
          return true;
        }
      }
    }
    return false;
  }

  /// Chuyển Netmask dạng chuỗi (e.g. 255.255.248.0) thành prefix length (e.g. 21)
  static int maskToPrefixLength(String netmask) {
    final mask = _ipNumber(netmask);
    final inverse = 0xffffffff ^ mask;
    if ((inverse & (inverse + 1)) != 0) {
      throw FormatException('Non-contiguous subnet mask: $netmask');
    }
    return 32 - inverse.bitLength;
  }

  /// Tính toán CIDR Subnet chính xác từ IP và Subnet mask
  /// Ví dụ: 172.21.175.40 với mask 255.255.248.0 -> 172.21.168.0/21
  static String calculateCidrSubnet(String ip, [String? netmask]) {
    final cleanIp = ip.trim();
    final ipOctets = cleanIp
        .split('.')
        .map((e) => int.tryParse(e) ?? -1)
        .toList();
    if (ipOctets.length != 4 || ipOctets.any((o) => o < 0 || o > 255)) {
      return '$cleanIp/24';
    }

    if (netmask == null || netmask.trim().isEmpty) {
      return '${ipOctets[0]}.${ipOctets[1]}.${ipOctets[2]}.0/24';
    }

    final maskOctets = netmask
        .trim()
        .split('.')
        .map((e) => int.tryParse(e) ?? -1)
        .toList();
    if (maskOctets.length != 4 || maskOctets.any((o) => o < 0 || o > 255)) {
      return '${ipOctets[0]}.${ipOctets[1]}.${ipOctets[2]}.0/24';
    }

    final ipInt =
        (ipOctets[0] << 24) |
        (ipOctets[1] << 16) |
        (ipOctets[2] << 8) |
        ipOctets[3];
    final maskInt =
        (maskOctets[0] << 24) |
        (maskOctets[1] << 16) |
        (maskOctets[2] << 8) |
        maskOctets[3];
    final prefixLen = maskToPrefixLength(netmask);

    final networkInt = ipInt & maskInt;
    final o1 = (networkInt >> 24) & 0xFF;
    final o2 = (networkInt >> 16) & 0xFF;
    final o3 = (networkInt >> 8) & 0xFF;
    final o4 = networkInt & 0xFF;

    return '$o1.$o2.$o3.$o4/$prefixLen';
  }

  /// Đối với supernet có prefix < 24 (như 172.21.168.0/21),
  /// phân rã thành danh sách các subnet /24 cấu thành.
  /// Ví dụ: 172.21.168.0/21 -> [172.21.168.0/24, ..., 172.21.175.0/24]
  static List<String> getSubnetSlices(String cidr) {
    final clean = cidr.trim();
    if (!clean.contains('/')) return [clean];
    final parts = clean.split('/');
    final ip = parts[0].trim();
    final prefix = int.tryParse(parts[1].trim()) ?? 24;

    if (prefix >= 24) {
      return [clean];
    }
    if (prefix < 16) {
      return [clean];
    }

    final octets = ip.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    if (octets.length != 4) return [clean];

    final ipInt =
        (octets[0] << 24) | (octets[1] << 16) | (octets[2] << 8) | octets[3];
    final mask = prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFFFFFF;
    final networkInt = ipInt & mask;
    final numSlices = 1 << (24 - prefix); // e.g. /21 -> 1 << 3 = 8 slices

    final List<String> slices = [];
    for (int i = 0; i < numSlices; i++) {
      final sliceNetworkInt = networkInt + (i << 8);
      final o1 = (sliceNetworkInt >> 24) & 0xFF;
      final o2 = (sliceNetworkInt >> 16) & 0xFF;
      final o3 = (sliceNetworkInt >> 8) & 0xFF;
      slices.add('$o1.$o2.$o3.0/24');
    }
    return slices;
  }

  /// Đọc Subnet Mask thực tế trên Windows thông qua lệnh ipconfig
  static List<NetworkInterfaceDetails>? _cachedAdapters;
  static DateTime? _cachedAdaptersTime;
  static Map<String, String>? _cachedNetmasks;
  static DateTime? _cachedNetmasksTime;

  /// Xóa cache để ép buộc làm mới lại danh sách card mạng khi cần
  static void invalidateAdapterCache() {
    _cachedAdapters = null;
    _cachedAdaptersTime = null;
    _cachedNetmasks = null;
    _cachedNetmasksTime = null;
  }

  static Future<Map<String, String>> _getWindowsSubnetMasks({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedNetmasks != null &&
        _cachedNetmasksTime != null &&
        now.difference(_cachedNetmasksTime!).inSeconds < 60) {
      return Map.of(_cachedNetmasks!);
    }

    final Map<String, String> map = {};
    if (!Platform.isWindows) return map;

    try {
      // .NET returns address/mask pairs without depending on ipconfig language.
      final result = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        r"[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new(); @([System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() | ForEach-Object { $_.GetIPProperties().UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' } | ForEach-Object { @{ip=$_.Address.ToString(); mask=$_.IPv4Mask.ToString()} }) | ConvertTo-Json -Compress",
      ]).timeout(const Duration(seconds: 5));
      if (result.exitCode == 0) {
        final decoded = jsonDecode(result.stdout.toString());
        final entries = decoded is List ? decoded : [decoded];
        for (final entry in entries) {
          final ip = entry['ip'] as String, mask = entry['mask'] as String;
          maskToPrefixLength(mask);
          if (isValidIp(ip)) map[ip] = mask;
        }
      }
    } catch (_) {
      /* Fall back to ipconfig below. */
    }
    if (map.isEmpty) {
      try {
        final result = await Process.run(
          'ipconfig',
          [],
          runInShell: false,
        ).timeout(const Duration(seconds: 5));
        if (result.exitCode == 0) {
          map.addAll(parseWindowsSubnetMasks(result.stdout.toString()));
        }
      } catch (_) {}
    }

    if (map.isNotEmpty) {
      _cachedNetmasks = Map.of(map);
      _cachedNetmasksTime = now;
    }
    return map;
  }

  /// Lấy danh sách các card mạng vật lý đang hoạt động (kèm cache TTL 60s)
  static Future<List<NetworkInterfaceDetails>> getAvailableAdapters({
    bool forceRefresh = false,
  }) async {
    final now = DateTime.now();
    if (!forceRefresh &&
        _cachedAdapters != null &&
        _cachedAdaptersTime != null &&
        now.difference(_cachedAdaptersTime!).inSeconds < 60) {
      return List.of(_cachedAdapters!);
    }

    final List<NetworkInterfaceDetails> list = [];
    try {
      final netmasks = await _getWindowsSubnetMasks(forceRefresh: forceRefresh);
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );

      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.startsWith('127.') || ip.startsWith('169.254.')) {
            continue;
          }

          final isVirtual = isVirtualAdapter(iface.name, ip);
          final isLan = isPrivateLanIp(ip);
          final mask = netmasks[ip];
          final subnet = calculateCidrSubnet(ip, mask);
          final prefix = mask != null ? maskToPrefixLength(mask) : 24;
          final slices = getSubnetSlices(subnet);

          list.add(
            NetworkInterfaceDetails(
              name: iface.name,
              ip: ip,
              subnet: subnet,
              isVirtual: isVirtual,
              isPrivateLan: isLan,
              netmask: mask,
              prefixLength: prefix,
              subSlices: slices,
            ),
          );
        }
      }

      // Ưu tiên: LAN vật lý lên đầu, card khác thứ hai, card ảo xuống cuối
      list.sort((a, b) {
        if (!a.isVirtual && b.isVirtual) return -1;
        if (a.isVirtual && !b.isVirtual) return 1;
        if (a.isPrivateLan && !b.isPrivateLan) return -1;
        if (!a.isPrivateLan && b.isPrivateLan) return 1;
        return a.name.compareTo(b.name);
      });

      if (list.isNotEmpty) {
        _cachedAdapters = List.of(list);
        _cachedAdaptersTime = now;
      }
    } catch (_) {}

    return list;
  }

  /// Tính địa chỉ Directed Broadcast cho một IP hoặc CIDR
  /// Ví dụ: 192.168.1.0/24 -> 192.168.1.255, 172.21.170.0/24 -> 172.21.170.255
  static String getBroadcastIp(String ipOrCidr) {
    try {
      final cidr = ipOrCidr.contains('/') ? ipOrCidr : '$ipOrCidr/24';
      final parts = cidr.split('/');
      final prefix = int.parse(parts[1]);
      _hostBounds(cidr);
      final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
      return _ipString((_ipNumber(parts[0]) & mask) | (0xffffffff ^ mask));
    } on FormatException {
      return '255.255.255.255';
    }
  }

  /// Tính địa chỉ broadcast chính xác của một CIDR supernet
  /// Ví dụ: 172.21.168.0/21 -> 172.21.175.255
  static String getSupernetBroadcastIp(String ip, String? netmask) {
    final cleanIp = ip.trim();
    final ipOctets = cleanIp
        .split('.')
        .map((e) => int.tryParse(e) ?? -1)
        .toList();
    if (ipOctets.length != 4 || ipOctets.any((o) => o < 0 || o > 255)) {
      return '255.255.255.255';
    }

    if (netmask == null || netmask.trim().isEmpty) {
      return '${ipOctets[0]}.${ipOctets[1]}.${ipOctets[2]}.255';
    }

    final maskOctets = netmask
        .trim()
        .split('.')
        .map((e) => int.tryParse(e) ?? -1)
        .toList();
    if (maskOctets.length != 4 || maskOctets.any((o) => o < 0 || o > 255)) {
      return '${ipOctets[0]}.${ipOctets[1]}.${ipOctets[2]}.255';
    }

    final ipInt =
        (ipOctets[0] << 24) |
        (ipOctets[1] << 16) |
        (ipOctets[2] << 8) |
        ipOctets[3];
    final maskInt =
        (maskOctets[0] << 24) |
        (maskOctets[1] << 16) |
        (maskOctets[2] << 8) |
        maskOctets[3];

    final networkInt = ipInt & maskInt;
    final broadcastInt = networkInt | (~maskInt & 0xFFFFFFFF);

    final o1 = (broadcastInt >> 24) & 0xFF;
    final o2 = (broadcastInt >> 16) & 0xFF;
    final o3 = (broadcastInt >> 8) & 0xFF;
    final o4 = broadcastInt & 0xFF;

    return '$o1.$o2.$o3.$o4';
  }

  /// Trả về tất cả các IP gán cho máy (bao gồm cả card ảo và loopback)
  static Future<Set<String>> getHostDeviceIps() async {
    final Set<String> ips = {'127.0.0.1', 'localhost'};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: true,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          ips.add(addr.address);
        }
      }
    } catch (_) {}
    return ips;
  }

  /// Kiểm tra xem remoteIp có nằm trong dải subnet của adapter không
  static bool isIpInSubnet(String remoteIp, String subnetCidr) {
    if (!remoteIp.contains('.') || !subnetCidr.contains('/')) return false;
    final parts = subnetCidr.split('/');
    final netIp = parts[0];
    final prefix = int.tryParse(parts[1]) ?? 24;

    final rOctets = remoteIp
        .split('.')
        .map((e) => int.tryParse(e) ?? -1)
        .toList();
    final nOctets = netIp.split('.').map((e) => int.tryParse(e) ?? -1).toList();
    if (rOctets.length != 4 || nOctets.length != 4) return false;

    final rInt =
        (rOctets[0] << 24) |
        (rOctets[1] << 16) |
        (rOctets[2] << 8) |
        rOctets[3];
    final nInt =
        (nOctets[0] << 24) |
        (nOctets[1] << 16) |
        (nOctets[2] << 8) |
        nOctets[3];
    final mask = prefix == 0 ? 0 : (~0 << (32 - prefix)) & 0xFFFFFFFF;

    return (rInt & mask) == (nInt & mask);
  }

  /// Tìm IP của card mạng cục bộ có dải mạng tương thích với remoteIp
  /// Giúp gán sourceAddress khi kết nối TCP hoặc gửi UDP unicast
  static String? findMatchingLocalIp(
    String remoteIp,
    List<NetworkInterfaceDetails> adapters,
  ) {
    // 1. Kiểm tra dải subnet chính xác (ví dụ /21 hoặc /24)
    for (final a in adapters) {
      if (isIpInSubnet(remoteIp, a.subnet)) {
        return a.ip;
      }
    }

    // 2. Kiểm tra cùng class C (/24) cơ bản
    final remoteParts = remoteIp.split('.');
    if (remoteParts.length == 4) {
      final classC = '${remoteParts[0]}.${remoteParts[1]}.${remoteParts[2]}.';
      for (final a in adapters) {
        if (a.ip.startsWith(classC)) {
          return a.ip;
        }
      }
    }

    // 3. Fallback: card vật lý đầu tiên
    for (final a in adapters) {
      if (!a.isVirtual && a.isPrivateLan) {
        return a.ip;
      }
    }

    if (adapters.isNotEmpty) {
      return adapters.first.ip;
    }
    return null;
  }

  /// Kiểm tra định dạng IPv4 hợp lệ
  static bool isValidIp(String ip) {
    final reg = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$');
    final match = reg.firstMatch(ip.trim());
    if (match == null) return false;
    for (int i = 1; i <= 4; i++) {
      final octet = int.tryParse(match.group(i)!) ?? -1;
      if (octet < 0 || octet > 255) return false;
    }
    return true;
  }

  /// So sánh hai địa chỉ IPv4 theo giá trị số học
  static int compareIps(String ipA, String ipB) {
    final aParts = ipA.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final bParts = ipB.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    if (aParts.length == 4 && bParts.length == 4) {
      for (var i = 0; i < 4; i++) {
        final diff = aParts[i].compareTo(bParts[i]);
        if (diff != 0) return diff;
      }
    }
    return ipA.compareTo(ipB);
  }
}
