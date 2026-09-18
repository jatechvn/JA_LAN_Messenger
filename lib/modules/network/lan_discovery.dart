import 'dart:async';
import 'package:logging/logging.dart';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../constants.dart';
import 'protocol_beebeep.dart';
import 'network_utils.dart';
import 'arp_resolver.dart';
import 'subnet_sweep.dart';

typedef OnPeerDiscoveredCallback = void Function(String ip, int port);
typedef OnScanStateChangedCallback = void Function(DiscoveryScanState state);

/// Trạng thái tiến trình quét mạng LAN theo thời gian thực
class DiscoveryScanState {
  final bool isSweeping;
  final double progress; // 0.0 -> 1.0
  final String statusText;
  final int activeAdaptersCount;
  final List<String> activeSubnets;
  final DateTime? lastSweepTime;
  final int discoveredPeersCount;
  final String
  activePhase; // 'initializing', 'broadcasting', 'arp_sweep', 'idle'

  const DiscoveryScanState({
    this.isSweeping = false,
    this.progress = 0.0,
    this.statusText = 'Đang khởi tạo dịch vụ mạng...',
    this.activeAdaptersCount = 0,
    this.activeSubnets = const [],
    this.lastSweepTime,
    this.discoveredPeersCount = 0,
    this.activePhase = 'idle',
  });

  DiscoveryScanState copyWith({
    bool? isSweeping,
    double? progress,
    String? statusText,
    int? activeAdaptersCount,
    List<String>? activeSubnets,
    DateTime? lastSweepTime,
    int? discoveredPeersCount,
    String? activePhase,
  }) {
    return DiscoveryScanState(
      isSweeping: isSweeping ?? this.isSweeping,
      progress: progress ?? this.progress,
      statusText: statusText ?? this.statusText,
      activeAdaptersCount: activeAdaptersCount ?? this.activeAdaptersCount,
      activeSubnets: activeSubnets ?? this.activeSubnets,
      lastSweepTime: lastSweepTime ?? this.lastSweepTime,
      discoveredPeersCount: discoveredPeersCount ?? this.discoveredPeersCount,
      activePhase: activePhase ?? this.activePhase,
    );
  }
}

class LanDiscoveryService {
  RawDatagramSocket? _receiverSocket;
  RawDatagramSocket? _fallbackSenderSocket;
  final Map<String, RawDatagramSocket> _interfaceSenders = {};
  List<NetworkInterfaceDetails> _availableAdapters = [];

  Timer? _broadcastTimer;
  bool _isRunning = false;
  Set<String> disabledAdapterNames = {};
  Iterable<NetworkInterfaceDetails> get _enabledAdapters =>
      _availableAdapters.where((a) => !disabledAdapterNames.contains(a.name));
  List<NetworkInterfaceDetails> get enabledAdapters =>
      _enabledAdapters.toList();
  Future<void>? _activeScan;
  SubnetSweep? _subnetSweep;
  int _scanGeneration = 0;
  int _scanRequest = 0;

  /// Cập nhật danh sách card mạng bị vô hiệu hóa ngay tức thì (0ms)
  Future<void> updateDisabledAdapters(Set<String> disabled) async {
    disabledAdapterNames = Set.of(disabled);
    final enabled = _enabledAdapters.toList();
    final enabledIps = enabled.map((a) => a.ip).toSet();
    final activeSubnets = enabled.map((a) => a.subnet).toSet().toList();

    // 1. Đóng và giải phóng ngay các socket của card bị vô hiệu hóa
    final disabledIps = _interfaceSenders.keys
        .where((ip) => !enabledIps.contains(ip))
        .toList();
    for (final ip in disabledIps) {
      try {
        _interfaceSenders.remove(ip)?.close();
      } catch (_) {}
    }

    // 2. Cập nhật scanState tức thời để UI phản hồi ngay (0ms)
    _updateScanState(
      activeAdaptersCount: enabled.length,
      activeSubnets: activeSubnets,
      isSweeping: enabled.isNotEmpty,
      progress: 0.0,
      statusText: enabled.isEmpty
          ? 'Chưa chọn card mạng nào'
          : 'Đã cập nhật card mạng • Đang quét...',
      activePhase: enabled.isNotEmpty ? 'initializing' : 'idle',
    );

    // Hủy sweep cũ ngay lập tức
    _scanGeneration++;
    _subnetSweep?.cancel();

    if (!_isRunning || enabled.isEmpty) {
      if (enabled.isEmpty) {
        _updateScanState(isSweeping: false, progress: 1.0);
      }
      return;
    }

    // 3. Khởi chạy quét mới cho riêng các card được bật (dùng cache, không gọi powershell)
    unawaited(triggerActiveScan(forceRefreshAdapters: false));
  }

  final Set<String> _localIps = {};
  final Set<String> _knownArpIps = {};
  final Map<String, DateTime> _lastResponses = {};
  int _localTcpPort = defaultListenerPort;
  Future<bool> Function(String ip, int port, String sourceIp)? connectCandidate;
  OnPeerDiscoveredCallback? onPeerDiscovered;
  OnScanStateChangedCallback? onScanStateChanged;

  DiscoveryScanState _scanState = const DiscoveryScanState();

  bool get isRunning => _isRunning;
  int get localTcpPort => _localTcpPort;
  List<NetworkInterfaceDetails> get availableAdapters =>
      List.unmodifiable(_availableAdapters);
  DiscoveryScanState get scanState => _scanState;

  void _updateScanState({
    bool? isSweeping,
    double? progress,
    String? statusText,
    int? activeAdaptersCount,
    List<String>? activeSubnets,
    DateTime? lastSweepTime,
    int? discoveredPeersCount,
    String? activePhase,
  }) {
    _scanState = _scanState.copyWith(
      isSweeping: isSweeping,
      progress: progress,
      statusText: statusText,
      activeAdaptersCount: activeAdaptersCount,
      activeSubnets: activeSubnets,
      lastSweepTime: lastSweepTime,
      discoveredPeersCount: discoveredPeersCount,
      activePhase: activePhase,
    );
    onScanStateChanged?.call(_scanState);
  }

  /// Cập nhật số lượng thiết bị tìm thấy để đồng bộ lên UI
  void updateDiscoveredPeersCount(int count) {
    if (_scanState.discoveredPeersCount != count) {
      _updateScanState(discoveredPeersCount: count);
    }
  }

  /// Cập nhật cổng TCP nội bộ (khi TCP server phải đổi cổng dự phòng)
  void updateLocalTcpPort(int port) {
    if (_localTcpPort != port) {
      _localTcpPort = port;
      sendBroadcastAnnounce();
    }
  }

  /// Bắt đầu lắng nghe và phát sóng UDP
  Future<void> start({
    required int localTcpPort,
    OnPeerDiscoveredCallback? onDiscovered,
    OnScanStateChangedCallback? onScanState,
  }) async {
    if (_isRunning) return;
    _localTcpPort = localTcpPort;
    onPeerDiscovered = onDiscovered;
    onScanStateChanged = onScanState;

    _updateScanState(
      isSweeping: true,
      progress: 0.1,
      statusText: 'Đang khởi tạo các card mạng...',
      activePhase: 'initializing',
    );

    final generation = _scanGeneration;
    await _initNetworkInterfaces();
    if (generation != _scanGeneration) return;

    try {
      // 1. Tạo receiver socket lắng nghe trên cổng broadcast mặc định 36475
      _receiverSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        defaultBroadcastPort,
        reuseAddress: true,
      );

      if (generation != _scanGeneration) {
        _receiverSocket?.close();
        _receiverSocket = null;
        return;
      }
      _receiverSocket!.broadcastEnabled = true;

      // Tham gia Multicast Group BeeBEEP 224.0.64.75
      try {
        final multicastAddress = InternetAddress(defaultMulticastGroup);
        final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4,
        );
        for (final interface in interfaces) {
          try {
            _receiverSocket!.joinMulticast(multicastAddress, interface);
          } catch (e) {
            debugPrint('[Discovery] Multicast ${interface.name}: $e');
          }
        }
      } catch (e) {
        debugPrint('[Discovery] Join multicast warning: $e');
      }

      _receiverSocket!.listen(_handleIncomingDatagram);

      // 2. Tạo fallback sender socket
      try {
        _fallbackSenderSocket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        _fallbackSenderSocket?.broadcastEnabled = true;
      } catch (e) {
        debugPrint('[Discovery] Fallback sender socket bind error: $e');
      }

      if (generation != _scanGeneration) {
        stop();
        return;
      }
      _isRunning = true;

      // 3. Gửi broadcast & subnet sweep ngay lập tức
      unawaited(triggerActiveScan());

      // 4. Định kỳ phát sóng mỗi 3 giây và quét ARP mỗi 2 chu kỳ (6s) để phát hiện tức thì thiết bị mới
      _broadcastTimer = Timer.periodic(const Duration(seconds: 3), (_) {
        if (_activeScan != null) return;
        sendBroadcastAnnounce();
      });

      debugPrint(
        '[Discovery] Started Multi-NIC UDP discovery on port $defaultBroadcastPort (${_interfaceSenders.length} adapters bound)',
      );
    } catch (e) {
      debugPrint('[Discovery] Failed to start UDP discovery: $e');
      stop();
    }
  }

  /// Khởi tạo và liên kết sockets với từng card mạng vật lý
  Future<void> _initNetworkInterfaces({bool forceRefresh = false}) async {
    final generation = _scanGeneration;
    _localIps.clear();
    _localIps.add('127.0.0.1');

    try {
      final hostIps = await NetworkUtils.getHostDeviceIps();
      if (generation != _scanGeneration) return;
      _localIps.addAll(hostIps);

      final adapters = await NetworkUtils.getAvailableAdapters(
        forceRefresh: forceRefresh,
      );
      if (generation != _scanGeneration) return;
      _availableAdapters = adapters;
      final activeSubnets = _enabledAdapters
          .map((a) => a.subnet)
          .toSet()
          .toList();

      final enabledIps = _enabledAdapters.map((a) => a.ip).toSet();

      // Đóng các sender socket của adapter bị tắt hoặc không còn tồn tại
      final toRemove = _interfaceSenders.keys
          .where((ip) => !enabledIps.contains(ip))
          .toList();
      for (final ip in toRemove) {
        try {
          _interfaceSenders.remove(ip)?.close();
        } catch (_) {}
      }

      // Tạo socket chuyên biệt cho từng card mạng được kích hoạt (tránh bind lại nếu đã có)
      for (final adapter in _enabledAdapters) {
        if (_interfaceSenders.containsKey(adapter.ip)) continue;
        try {
          final s = await RawDatagramSocket.bind(
            InternetAddress(adapter.ip),
            0,
            reuseAddress: true,
          );
          if (generation != _scanGeneration) {
            s.close();
            return;
          }
          s.broadcastEnabled = true;
          _interfaceSenders[adapter.ip] = s;
          debugPrint(
            '[Discovery] Bound sender socket to ${adapter.name} (${adapter.ip})',
          );
        } catch (e) {
          debugPrint(
            '[Discovery] Cannot bind sender socket to ${adapter.ip}: $e',
          );
        }
      }

      _updateScanState(
        activeAdaptersCount: _interfaceSenders.length,
        activeSubnets: activeSubnets,
      );
    } catch (e) {
      debugPrint('[Discovery] Error initializing network interfaces: $e');
    }
  }

  /// Kích hoạt quét mạng chủ động tức thì (khi người dùng bấm nút Quét lại)
  Future<void> triggerActiveScan({
    Set<String>? adapterIps,
    bool forceRefreshAdapters = false,
  }) async {
    final request = ++_scanRequest;
    if (_activeScan != null) {
      _scanGeneration++;
      _subnetSweep?.cancel();
      await _activeScan;
    }
    if (!_isRunning || request != _scanRequest) return;
    return _activeScan ??= _performActiveScan(
      adapterIps: adapterIps,
      forceRefreshAdapters: forceRefreshAdapters,
    ).whenComplete(() => _activeScan = null);
  }

  Future<void> _performActiveScan({
    Set<String>? adapterIps,
    bool forceRefreshAdapters = false,
  }) async {
    final elapsed = Stopwatch()..start();
    Logger('Diagnostics').info('scan_started');
    final generation = _scanGeneration;
    final currentEnabled = _enabledAdapters.toList();
    _updateScanState(
      isSweeping: true,
      progress: 0,
      statusText: 'Đang chuẩn bị quét mạng...',
      activePhase: 'initializing',
      activeAdaptersCount: currentEnabled.length,
      activeSubnets: currentEnabled.map((a) => a.subnet).toSet().toList(),
    );
    await _initNetworkInterfaces(forceRefresh: forceRefreshAdapters);
    if (!_isRunning || generation != _scanGeneration) return;
    await sendBroadcastAnnounce(adapterIps: adapterIps);
    final adapters = _enabledAdapters
        .where(
          (a) =>
              _interfaceSenders.containsKey(a.ip) &&
              (adapterIps == null || adapterIps.contains(a.ip)),
        )
        .toList();
    _updateScanState(
      activeAdaptersCount: adapters.length,
      activeSubnets: adapters.map((a) => a.subnet).toList(),
    );
    final sweep = SubnetSweep();
    _subnetSweep = sweep;
    try {
      final result = await sweep.run(
        adapters: adapters,
        localIps: _localIps,
        send: (adapter, ip) async {
          if (!_isRunning || generation != _scanGeneration) return false;
          final packet = ProtocolBeebeep.buildBroadcastPacket(
            localTcpPort: _localTcpPort,
            targetHostAddress: ip,
          );
          var sent = false;
          try {
            sent =
                _interfaceSenders[adapter.ip]?.send(
                  packet,
                  InternetAddress(ip),
                  defaultBroadcastPort,
                ) ==
                packet.length;
          } catch (_) {}
          await connectCandidate?.call(ip, defaultListenerPort, adapter.ip);
          return sent;
        },
        onProgress: (done, total, sent) {
          if (!_isRunning || generation != _scanGeneration) return;
          _updateScanState(
            isSweeping: true,
            progress: total == 0 ? 0 : done / total,
            statusText:
                'Quét UDP + TCP: $done/$total địa chỉ • đã phát $sent gói UDP',
            activePhase: 'subnet_sweep',
          );
        },
      );
      if (!_isRunning || generation != _scanGeneration || result.cancelled) {
        return;
      }
      _finishSweep();
      final localCount = adapters.fold<int>(
        0,
        (sum, a) =>
            sum +
            _localIps
                .where((ip) => NetworkUtils.isIpInSubnet(ip, a.subnet))
                .length,
      );
      final failures = result.attempted - localCount - result.sent;
      _updateScanState(
        statusText:
            'Đã duyệt ${result.attempted} địa chỉ • gửi ${result.sent} gói UDP • $failures gói chưa gửi • đang lắng nghe phản hồi',
      );
    } catch (e) {
      if (_isRunning && generation == _scanGeneration) {
        _updateScanState(
          isSweeping: false,
          activePhase: 'idle',
          statusText: 'Quét chưa hoàn tất: $e',
        );
      }
    } finally {
      Logger('Diagnostics').info(
        'scan_finished elapsed_ms=${elapsed.elapsedMilliseconds} cancelled=${generation != _scanGeneration}',
      );
      if (identical(_subnetSweep, sweep)) _subnetSweep = null;
    }
  }

  /// Gửi gói tin thông báo tồn tại qua Multi-NIC Broadcast, Subnet Slices, Multicast & ARP Unicast
  Future<void> sendBroadcastAnnounce({
    bool sweepArp = false,
    Set<String>? adapterIps,
  }) async {
    if (!_isRunning || (sweepArp && _activeScan != null)) return;

    try {
      if (sweepArp) {
        _updateScanState(
          isSweeping: true,
          progress: 0.35,
          statusText:
              'Đang phát sóng đa tầng (${_interfaceSenders.length} card mạng)...',
          activePhase: 'broadcasting',
        );
      }

      // 1. Phát trên từng card mạng hiện hữu cụ thể (ngăn Windows lệch định tuyến)
      for (final adapter in _enabledAdapters) {
        if (adapterIps != null && !adapterIps.contains(adapter.ip)) continue;
        final sender = _interfaceSenders[adapter.ip] ?? _fallbackSenderSocket;
        if (sender == null) continue;

        List<int> packetFor(String destination) =>
            ProtocolBeebeep.buildBroadcastPacket(
              localTcpPort: _localTcpPort,
              targetHostAddress: destination,
            );

        // a) Global Broadcast 255.255.255.255
        try {
          sender.send(
            packetFor(defaultBroadcastAddress),
            InternetAddress(defaultBroadcastAddress),
            defaultBroadcastPort,
          );
        } catch (_) {}

        // b) Supernet / Adapter Directed Broadcast (e.g. 172.21.175.255)
        try {
          final supernetBcast = NetworkUtils.getSupernetBroadcastIp(
            adapter.ip,
            adapter.netmask,
          );
          sender.send(
            packetFor(supernetBcast),
            InternetAddress(supernetBcast),
            defaultBroadcastPort,
          );
        } catch (_) {}

        // c) Constituent Subnet Slices (/24 broadcasts cho các supernet /21, /22, /23)
        // Đảm bảo các máy ở các slice lân cận (e.g. 172.21.170.x vs 172.21.175.x) nhận được
        for (final slice in adapter.subSlices) {
          try {
            final sliceBcast = NetworkUtils.getBroadcastIp(slice);
            sender.send(
              packetFor(sliceBcast),
              InternetAddress(sliceBcast),
              defaultBroadcastPort,
            );
          } catch (_) {}
        }

        // d) Multicast 224.0.64.75
        try {
          sender.send(
            packetFor(defaultMulticastGroup),
            InternetAddress(defaultMulticastGroup),
            defaultBroadcastPort,
          );
        } catch (_) {}
      }

      // 2. Gửi qua fallback sender socket
      if (_fallbackSenderSocket != null &&
          adapterIps == null &&
          disabledAdapterNames.isEmpty) {
        final fallbackPacket = ProtocolBeebeep.buildBroadcastPacket(
          localTcpPort: _localTcpPort,
          targetHostAddress: defaultBroadcastAddress,
        );
        try {
          _fallbackSenderSocket!.send(
            fallbackPacket,
            InternetAddress(defaultBroadcastAddress),
            defaultBroadcastPort,
          );
        } catch (_) {}
      }

      // 3. Quét chủ động Unicast tới các IP trong bảng ARP hệ thống
      if (sweepArp) {
        await _sweepArpCache();
      }
    } catch (e) {
      debugPrint('[Discovery] Broadcast send error: $e');
      if (sweepArp) {
        _finishSweep();
      }
    }
  }

  /// Quét bảng ARP và gửi UDP Unicast trực tiếp (vượt qua các switch chặn UDP Broadcast)
  Future<void> _sweepArpCache() async {
    try {
      final ips = await ArpResolver.getActiveLanIps(excludeIps: _localIps);
      if (!_isRunning || _activeScan != null) return;
      if (ips.isEmpty) {
        _finishSweep();
        return;
      }

      // Tự động phát hiện IP mới xuất hiện trong bảng ARP
      final newIps = ips.where((ip) => !_knownArpIps.contains(ip)).toList();
      if (newIps.isNotEmpty) {
        debugPrint('[Discovery] New ARP devices discovered: $newIps');
        _knownArpIps.addAll(newIps);
      }

      _updateScanState(
        isSweeping: true,
        progress: 0.7,
        statusText: 'Đang đối soát bảng ARP (${ips.length} thiết bị)...',
        activePhase: 'arp_sweep',
      );

      for (final targetIp in ips) {
        // Tìm sender socket khớp với dải mạng của targetIp
        final localIp = NetworkUtils.findMatchingLocalIp(
          targetIp,
          _enabledAdapters.toList(),
        );
        final sender =
            (localIp != null ? _interfaceSenders[localIp] : null) ??
            _fallbackSenderSocket;
        if (sender == null) continue;

        try {
          final packetBytes = ProtocolBeebeep.buildBroadcastPacket(
            localTcpPort: _localTcpPort,
            targetHostAddress: targetIp,
          );
          sender.send(
            packetBytes,
            InternetAddress(targetIp),
            defaultBroadcastPort,
          );
        } catch (_) {}
      }

      _finishSweep();
    } catch (_) {
      _finishSweep();
    }
  }

  void _finishSweep() {
    if (!_isRunning) return;
    final subnetSummary = _scanState.activeSubnets.isNotEmpty
        ? _scanState.activeSubnets.join(', ')
        : 'LAN';
    _updateScanState(
      isSweeping: false,
      progress: 1.0,
      statusText: 'Lắng nghe thời gian thực • $subnetSummary',
      lastSweepTime: DateTime.now(),
      activePhase: 'idle',
    );
  }

  /// Gửi gói tin UDP Unicast đáp lễ ngay lập tức tới máy vừa gửi tín hiệu
  void _sendReactiveUnicastResponse(String targetIp) {
    if (!_isRunning) return;
    final localIp = NetworkUtils.findMatchingLocalIp(
      targetIp,
      _enabledAdapters.toList(),
    );
    final sender =
        (localIp != null ? _interfaceSenders[localIp] : null) ??
        _fallbackSenderSocket;
    if (sender == null) return;

    try {
      final packetBytes = ProtocolBeebeep.buildBroadcastPacket(
        localTcpPort: _localTcpPort,
        targetHostAddress: targetIp,
      );
      sender.send(packetBytes, InternetAddress(targetIp), defaultBroadcastPort);
    } catch (_) {}
  }

  /// Xử lý datagram nhận được từ mạng LAN
  void _handleIncomingDatagram(RawSocketEvent event) {
    if (event != RawSocketEvent.read || _receiverSocket == null) return;

    final datagram = _receiverSocket!.receive();
    if (datagram == null) return;

    final senderIp = datagram.address.address;
    if (disabledAdapterNames.isNotEmpty &&
        !_enabledAdapters.any(
          (a) => NetworkUtils.isIpInSubnet(senderIp, a.subnet),
        )) {
      return;
    }

    try {
      final payload = utf8.decode(datagram.data, allowMalformed: true);
      final remotePort = ProtocolBeebeep.parseBroadcastPacket(payload);
      if (remotePort != null) {
        if (isOwnEndpoint(senderIp, remotePort, _localIps, _localTcpPort)) {
          return;
        }
        debugPrint('[Discovery] Discovered peer at $senderIp:$remotePort');
        // Rate limit replies: two ported clients must not echo UDP forever.
        final now = DateTime.now();
        _lastResponses.removeWhere(
          (_, time) => now.difference(time).inSeconds >= 10,
        );
        final endpoint = '$senderIp:$remotePort';
        if (!_lastResponses.containsKey(endpoint)) {
          _lastResponses[endpoint] = now;
          _sendReactiveUnicastResponse(senderIp);
        }

        // 2. Báo cho Coordinator thiết lập handshake
        onPeerDiscovered?.call(senderIp, remotePort);
      }
    } catch (e) {
      debugPrint('[Discovery] Decode datagram error from $senderIp: $e');
    }
  }

  @visibleForTesting
  static bool isOwnEndpoint(
    String ip,
    int port,
    Set<String> localIps,
    int localPort,
  ) => localIps.contains(ip) && port == localPort;

  /// Dừng dịch vụ phát hiện
  void stop() {
    _scanRequest++;
    _scanGeneration++;
    _subnetSweep?.cancel();
    _updateScanState(
      isSweeping: false,
      activePhase: 'idle',
      statusText: 'Đã dừng quét',
    );
    _broadcastTimer?.cancel();
    _broadcastTimer = null;
    _receiverSocket?.close();
    _receiverSocket = null;

    for (final s in _interfaceSenders.values) {
      try {
        s.close();
      } catch (_) {}
    }
    _interfaceSenders.clear();

    _fallbackSenderSocket?.close();
    _fallbackSenderSocket = null;

    _isRunning = false;
    _lastResponses.clear();
    debugPrint('[Discovery] Stopped UDP discovery');
  }
}
